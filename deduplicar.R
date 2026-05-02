# ============================================================================
# deduplicar.R — Detectar y marcar álbumes duplicados en el caché
# Proyecto Discoteca | tomgc
# ============================================================================
#
# QUÉ HACE:
#   1. Agrupa álbumes por artista + nombre (case-insensitive)
#   2. Si hay duplicados, conserva el que tiene más scrobbles
#   3. Los demás se marcan con _duplicado_de = {id_ganador}
#      y categoria = "descartado" (no se borran del caché — P1)
#
# CUÁNDO CORRER: una vez, o después de agregar muchos discos nuevos.
#   Después correr construir.R para regenerar el catálogo.
#
# MODO: por defecto corre en modo diagnóstico (solo reporta).
#   Cambiar APLICAR_CAMBIOS a TRUE para marcar los duplicados.
#
# PAQUETES: install.packages(c("jsonlite", "cli", "here"))
# ============================================================================

library(jsonlite)
library(cli)
library(here)

# --- Configuración -----------------------------------------------------------

RUTA_CACHE <- here("datos", "music_cache.json")

# Cambiar a TRUE para aplicar los cambios al caché
APLICAR_CAMBIOS <- TRUE

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

# Clave de agrupación: artista + album en minúsculas, sin espacios extra
clave_album <- function(entry) {
  artista <- trimws(tolower(entry$artista %||% ""))
  album   <- trimws(tolower(entry$album %||% ""))
  paste(artista, album, sep = " — ")
}

# Scrobbles del álbum (para decidir cuál conservar)
get_scrobbles <- function(entry) {
  entry$lastfm$scrobbles_totales %||% 0L
}

# --- Main --------------------------------------------------------------------

main <- function() {
  cli_h1("Discoteca — Deduplicar álbumes")

  cache <- leer_cache(RUTA_CACHE)
  keys <- names(cache$albumes)
  cli_alert_info("Álbumes en caché: {length(keys)}")

  # Excluir los que ya están marcados como duplicados
  ya_marcados <- sum(vapply(keys, \(k) {
    !is.null(cache$albumes[[k]]$`_duplicado_de`)
  }, logical(1)))
  if (ya_marcados > 0) {
    cli_alert_info("Ya marcados como duplicados: {ya_marcados}")
  }

  # Agrupar por clave
  grupos <- list()
  for (k in keys) {
    entry <- cache$albumes[[k]]
    # Saltar los que ya están marcados
    if (!is.null(entry$`_duplicado_de`)) next
    cl <- clave_album(entry)
    if (is.null(grupos[[cl]])) grupos[[cl]] <- list()
    grupos[[cl]] <- c(grupos[[cl]], list(list(key = k, entry = entry)))
  }

  # Filtrar solo los que tienen más de 1 entrada
  duplicados <- Filter(\(g) length(g) > 1, grupos)

  if (length(duplicados) == 0) {
    cli_alert_success("No se encontraron duplicados nuevos")
    return(invisible(NULL))
  }

  cli_alert_warning("Grupos con duplicados: {length(duplicados)}")
  cli_text("")

  # Procesar cada grupo
  total_a_marcar <- 0
  decisiones <- list()  # lista de list(ganar = key, descartar = c(keys))

  for (cl in names(duplicados)) {
    grupo <- duplicados[[cl]]

    # Ordenar por scrobbles descendente — el primero gana
    scrobbles <- vapply(grupo, \(g) get_scrobbles(g$entry), numeric(1))
    orden <- order(scrobbles, decreasing = TRUE)
    grupo <- grupo[orden]
    scrobbles <- scrobbles[orden]

    ganador <- grupo[[1]]
    perdedores <- grupo[-1]

    # Reportar
    cli_text(cli::col_cyan(cl))
    cli_text("  {cli::col_green('✓')} {ganador$key} ({scrobbles[1]} scrobbles) — conservar")
    for (i in seq_along(perdedores)) {
      p <- perdedores[[i]]
      s <- scrobbles[i + 1]
      anio_g <- ganador$entry$anio %||% "?"
      anio_p <- p$entry$anio %||% "?"
      tracks_g <- ganador$entry$num_tracks %||% "?"
      tracks_p <- p$entry$num_tracks %||% "?"

      diferencias <- c()
      if (anio_g != anio_p) diferencias <- c(diferencias, paste0("año: ", anio_p, " vs ", anio_g))
      if (tracks_g != tracks_p) diferencias <- c(diferencias, paste0("tracks: ", tracks_p, " vs ", tracks_g))
      dif_str <- if (length(diferencias) > 0) paste0(" [", paste(diferencias, collapse = ", "), "]") else ""

      cli_text("  {cli::col_red('×')} {p$key} ({s} scrobbles){dif_str} — descartar")
    }

    decisiones <- c(decisiones, list(list(
      ganador = ganador$key,
      descartar = vapply(perdedores, \(p) p$key, character(1))
    )))
    total_a_marcar <- total_a_marcar + length(perdedores)
  }

  cli_text("")
  cli_alert_info("Total a marcar como duplicado: {total_a_marcar}")

  # Aplicar cambios si está habilitado
  if (!APLICAR_CAMBIOS) {
    cli_alert_info("Modo diagnóstico — no se aplicaron cambios")
    cli_alert_info("Cambia APLICAR_CAMBIOS <- TRUE y vuelve a correr para aplicar")
    return(invisible(NULL))
  }

  cli_h2("Aplicando cambios")
  n_marcados <- 0

  for (dec in decisiones) {
    for (k in dec$descartar) {
      cache$albumes[[k]]$`_duplicado_de` <- dec$ganador
      # Marcar como descartado (se oculta en modo Collection)
      if (is.null(cache$albumes[[k]]$personal)) {
        cache$albumes[[k]]$personal <- list()
      }
      cache$albumes[[k]]$personal$categoria <- "descartado"
      n_marcados <- n_marcados + 1
    }
  }

  # Guardar caché (P4 — escritura atómica)
  cache$`_meta`$ultima_actualizacion <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  escribir_json_atomico(cache, RUTA_CACHE, pretty = TRUE, auto_unbox = TRUE)

  cli_alert_success("{n_marcados} álbumes marcados como duplicados")
  cli_alert_info("Corre construir.R para regenerar el catálogo")
}

main()
