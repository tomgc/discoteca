# ============================================================================
# wikipedia.R — Enriquecer masterpieces con información de Wikipedia
# Proyecto Discoteca | tomgc
# ============================================================================
#
# QUÉ HACE:
#   1. Lee music_cache.json
#   2. Filtra álbumes con categoria = "masterpiece"
#   3. Busca en Wikipedia (inglés) el artículo del álbum
#   4. Extrae resumen (extracto) y URL
#   5. Guarda en el caché bajo $wikipedia
#
# IDEMPOTENCIA: si un álbum ya tiene datos de Wikipedia, se salta.
#   Para forzar re-consulta, borrar $wikipedia del álbum en el caché.
#
# RATE LIMIT: Wikipedia permite ~200 req/s, pero usamos 0.5s entre
#   requests por cortesía. No requiere API key.
#
# PAQUETES: install.packages(c("jsonlite", "cli", "here", "httr2"))
# ============================================================================

source(here::here("utils.R"))
instalar_si_falta("httr2")
library(httr2)

# --- Configuración (P11) ----------------------------------------------------

RUTA_CACHE <- here("datos", "music_cache.json")

# Wikipedia API endpoint (inglés)
WIKI_API <- "https://en.wikipedia.org/w/api.php"

# Pausa entre requests (cortesía, no obligatorio)
WIKI_DELAY <- 0.5

# Largo máximo del extracto en caracteres
WIKI_MAX_CHARS <- 1500

# User-Agent (P9 — buenas prácticas de API)
WIKI_USER_AGENT <- "Discoteca/1.0 (https://github.com/tomgc/discoteca; personal music catalog)"

# --- Funciones ---------------------------------------------------------------

leer_cache <- function(ruta) {
  if (!file.exists(ruta)) cli_abort("Caché no encontrado en {ruta}")
  fromJSON(ruta, simplifyVector = FALSE)
}

escribir_json_atomico <- function(data, ruta, ...) {
  tmp <- paste0(ruta, ".tmp")
  write_json(data, tmp, ...)
  file.rename(tmp, ruta)
}

# Buscar artículo de Wikipedia para un álbum
# Estrategia de búsqueda:
#   1. "{Album} (album)" — formato estándar de Wikipedia para álbumes
#   2. "{Album} {Artist} album" — fallback si el primero no encuentra
buscar_wikipedia <- function(album, artista) {
  queries <- c(
    paste0(album, " (album)"),
    paste0(album, " ", artista, " album")
  )

  for (query in queries) {
    result <- tryCatch(
      {
        resp <- request(WIKI_API) |>
          req_url_query(
            action   = "query",
            titles   = query,
            prop     = "extracts|info",
            exintro  = "true",          # solo la intro del artículo
            explaintext = "true",       # texto plano, no HTML
            exchars  = WIKI_MAX_CHARS,
            inprop   = "url",
            format   = "json",
            redirects = 1               # seguir redirects de Wikipedia
          ) |>
          req_headers(`User-Agent` = WIKI_USER_AGENT) |>
          req_perform()

        data <- resp_body_json(resp)
        pages <- data$query$pages

        # Wikipedia devuelve pages como lista con el page ID como key
        # Si el ID es "-1", no se encontró
        page <- pages[[1]]
        if (is.null(page) || identical(page$pageid, -1L) || page$missing == "") {
          next
        }

        extract <- page$extract %||% ""
        if (nchar(extract) < 50) next  # extracto muy corto = artículo irrelevante

        list(
          extract    = extract,
          url        = page$fullurl %||% "",
          title      = page$title %||% "",
          consulta   = format(Sys.Date())
        )
      },
      error = function(e) {
        NULL
      }
    )

    if (!is.null(result)) return(result)
    Sys.sleep(WIKI_DELAY)
  }

  # No encontrado con ninguna estrategia
  NULL
}

# --- Main --------------------------------------------------------------------

main <- function() {
  cli_h1("Discoteca — Wikipedia para Masterpieces")

  cache <- leer_cache(RUTA_CACHE)
  keys <- names(cache$albumes)

  # Filtrar masterpieces sin datos de Wikipedia
  pendientes <- list()
  ya_tiene <- 0
  total_master <- 0

  for (k in keys) {
    entry <- cache$albumes[[k]]
    cat <- entry$personal$categoria %||% ""
    if (cat != "masterpiece") next
    total_master <- total_master + 1

    if (!is.null(entry$wikipedia$extract) && nchar(entry$wikipedia$extract) > 0) {
      ya_tiene <- ya_tiene + 1
      next
    }
    pendientes[[k]] <- entry
  }

  cli_alert_info("Masterpieces en caché: {total_master}")
  cli_alert_info("Ya con Wikipedia: {ya_tiene}")
  cli_alert_info("Pendientes: {length(pendientes)}")

  if (length(pendientes) == 0) {
    cli_alert_success("Todos los masterpieces ya tienen datos de Wikipedia")
    return(invisible(NULL))
  }

  # Procesar pendientes
  ok <- 0
  no_encontrado <- 0
  errores <- 0

  for (i in seq_along(pendientes)) {
    k <- names(pendientes)[i]
    entry <- pendientes[[k]]
    artista <- entry$artista %||% ""
    album <- entry$album %||% ""

    cli_text("[{i}/{length(pendientes)}] {artista} — {album}")

    result <- tryCatch(
      buscar_wikipedia(album, artista),
      error = function(e) {
        cli_alert_warning("  Error: {e$message}")
        errores <<- errores + 1
        NULL
      }
    )

    if (!is.null(result)) {
      cache$albumes[[k]]$wikipedia <- result
      cli_alert_success("  ✓ {nchar(result$extract)} chars")
      ok <- ok + 1
    } else {
      # Marcar como no encontrado para no reintentar
      cache$albumes[[k]]$wikipedia <- list(
        extract  = "",
        url      = "",
        nota     = "No encontrado en Wikipedia",
        consulta = format(Sys.Date())
      )
      cli_alert_warning("  ✗ No encontrado")
      no_encontrado <- no_encontrado + 1
    }

    Sys.sleep(WIKI_DELAY)

    # Guardar progreso cada 10 álbumes (P3 — checkpointing)
    if (i %% 10 == 0) {
      cache$`_meta`$ultima_actualizacion <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
      escribir_json_atomico(cache, RUTA_CACHE, pretty = TRUE, auto_unbox = TRUE)
    }
  }

  # Guardar final (P4 — escritura atómica)
  cache$`_meta`$ultima_actualizacion <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  escribir_json_atomico(cache, RUTA_CACHE, pretty = TRUE, auto_unbox = TRUE)

  # Resumen (P13)
  cli_h2("Resumen")
  cli_alert_info("Encontrados: {ok} | No encontrados: {no_encontrado} | Errores: {errores}")
  cli_alert_info("Corre construir.R para incluir los datos en el catálogo")
}

main()
