# ============================================================================
# utils.R — Funciones compartidas del proyecto Discoteca
# ============================================================================
#
# Este módulo centraliza:
#   - Lectura/escritura de caché con escritura atómica (P4)
#   - Constantes de configuración parametrizadas (P11)
#   - Funciones de validación de integridad (P8)
#   - Helpers compartidos (safe_str, safe_num, colapsar, etc.)
#
# Todos los scripts lo cargan con source(here::here("utils.R"))
# ============================================================================

# C.12 — Verificación de dependencias: instala lo que falte antes de library().
# Llamado tanto al cargar utils.R como por scripts que necesiten paquetes extra.
instalar_si_falta <- function(paquetes) {
  faltantes <- paquetes[
    !vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(faltantes) > 0) {
    message("Instalando paquetes faltantes: ", paste(faltantes, collapse = ", "))
    install.packages(faltantes)
  }
}

instalar_si_falta(c("jsonlite", "cli", "here"))

library(jsonlite)
library(cli)
library(here)

# ── Constantes de configuración (P11: sin números mágicos) ──────────────────

# Rutas (P7: portabilidad con here::here)
RUTA_CACHE         <- here("datos", "music_cache.json")
RUTA_CATALOGO      <- here("datos", "catalogo.json")
RUTA_CSV           <- here("datos", "catalogo_musica.csv")
RUTA_WEB_EDIT      <- here("datos", "ediciones_web.json")
RUTA_CORRECCIONES  <- here("datos", "correcciones_mb.json")

# Spotify
SPOTIFY_BASE               <- "https://api.spotify.com/v1"
SPOTIFY_PAGE_SIZE          <- 50L
SPOTIFY_REDIRECT           <- "http://127.0.0.1:1410/"
SPOTIFY_RATE_LIMIT_MAX_WAIT <- 300  # Segundos. Si pide más, abortar.

# Last.fm
LASTFM_BASE  <- "https://ws.audioscrobbler.com/2.0/"
LASTFM_PAUSE <- 0.25  # Segundos entre requests (~4 req/s)

# MusicBrainz
MB_BASE          <- "https://musicbrainz.org/ws/2"
MB_CAA_BASE      <- "https://coverartarchive.org"
MB_USER_AGENT    <- "Discoteca/1.0 (https://github.com/tomgc/discoteca)"
MB_PAUSE         <- 1     # MusicBrainz exige mínimo 1s entre requests
MB_MAX_RELEASES  <- 3L    # Máximo de releases a probar para sello/país

# Reintentos HTTP
HTTP_MAX_RETRIES <- 3L

# Versión del caché
CACHE_VERSION <- "2.1"

# Categorías de la colección (P11: parametrizadas)
# null / NA = sin clasificar, "descartado" = fuera de la colección
CATEGORIAS_VALIDAS  <- c("good", "great", "masterpiece", "descartado")
CATEGORIAS_VISIBLES <- c("good", "great", "masterpiece")  # Las que se muestran por defecto


# ── Caché: lectura ──────────────────────────────────────────────────────────

#' Lee el caché existente o crea uno vacío.
#' @param ruta Ruta al archivo JSON del caché.
#' @return Lista con estructura del caché.
leer_cache <- function(ruta = RUTA_CACHE) {
  if (file.exists(ruta)) {
    cache <- fromJSON(ruta, simplifyVector = FALSE)
    n <- length(cache$albumes)
    cli_alert_info("Caché cargado: {n} álbumes")
    return(cache)
  }

  cli_alert_warning("Caché no encontrado, creando uno nuevo")
  list(
    `_meta` = list(
      version              = CACHE_VERSION,
      descripcion          = "Caché permanente — solo se agregan datos, nunca se borran",
      ultima_actualizacion = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
      fuentes              = list("spotify", "lastfm", "musicbrainz")
    ),
    albumes = list()
  )
}


# ── Caché: escritura atómica (P4) ──────────────────────────────────────────

#' Guarda el caché a disco con escritura atómica.
#'
#' Patrón: escribe a archivo temporal → renombra al definitivo.
#' Si R se cae a mitad de write_json, el archivo original queda intacto.
#'
#' @param cache Lista del caché.
#' @param ruta Ruta destino.
guardar_cache <- function(cache, ruta = RUTA_CACHE) {
  cache$`_meta`$ultima_actualizacion <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  dir.create(dirname(ruta), showWarnings = FALSE, recursive = TRUE)

  # Escritura atómica: temp → rename (P4)
  ruta_tmp <- paste0(ruta, ".tmp")
  write_json(cache, ruta_tmp, pretty = TRUE, auto_unbox = TRUE)
  file.rename(ruta_tmp, ruta)
}

#' Guarda cualquier JSON con escritura atómica (P4).
#' Usado por construir.R para catalogo.json y por deduplicar.R.
#' @param data Datos a serializar.
#' @param ruta Ruta destino.
#' @param ... Argumentos adicionales para write_json.
guardar_json <- function(data, ruta, ...) {
  dir.create(dirname(ruta), showWarnings = FALSE, recursive = TRUE)
  ruta_tmp <- paste0(ruta, ".tmp")
  write_json(data, ruta_tmp, ...)
  file.rename(ruta_tmp, ruta)
}

#' Valida invariantes del catálogo aplanado antes de publicar (C.8, B.4).
#'
#' Checks (todos warning-level, NO detienen ejecución — C.8):
#'   - Cada álbum tiene id, artista, album no vacíos
#'   - Las categorías están en CATEGORIAS_VALIDAS (o NULL)
#'   - El año, si existe, está en rango plausible (1900..año actual + 2)
#'   - No hay IDs duplicados
#'
#' @param catalogo Lista de álbumes aplanados (output de construir.R).
#' @return Lista con: total, problemas (vector de mensajes). Imprime warnings.
validar_catalogo <- function(catalogo) {
  problemas <- character(0)
  anio_max  <- as.integer(format(Sys.Date(), "%Y")) + 2L

  for (i in seq_along(catalogo)) {
    a <- catalogo[[i]]
    contexto <- sprintf("[%d] %s — %s", i, a$artista %||% "?", a$album %||% "?")

    if (!nzchar(a$id %||% ""))      problemas <- c(problemas, paste(contexto, "→ id vacío"))
    if (!nzchar(a$artista %||% "")) problemas <- c(problemas, paste(contexto, "→ artista vacío"))
    if (!nzchar(a$album %||% ""))   problemas <- c(problemas, paste(contexto, "→ album vacío"))

    cat <- a$categoria
    if (!is.null(cat) && !(cat %in% CATEGORIAS_VALIDAS)) {
      problemas <- c(problemas, paste(contexto, "→ categoría inválida:", cat))
    }

    anio <- a$anio
    if (!is.null(anio) && length(anio) == 1 && !is.na(anio) && anio > 0) {
      if (anio < 1900 || anio > anio_max) {
        problemas <- c(problemas, paste(contexto, "→ año fuera de rango:", anio))
      }
    }
  }

  ids <- vapply(catalogo, \(a) a$id %||% "", character(1))
  dups <- unique(ids[duplicated(ids) & nzchar(ids)])
  if (length(dups) > 0) {
    problemas <- c(problemas, paste("IDs duplicados:", paste(head(dups, 5), collapse = ", ")))
  }

  for (msg in problemas) cli_alert_warning(msg)

  if (length(problemas) == 0) {
    cli_alert_success("Validación del catálogo: {length(catalogo)} álbumes, sin problemas")
  } else {
    cli_alert_warning("Validación: {length(problemas)} problemas (no fatales)")
  }

  list(total = length(catalogo), problemas = problemas)
}


#' Ordena recursivamente las claves de un objeto JSON-like (C.10).
#' Listas con names() son objetos JSON y se ordenan alfabéticamente.
#' Listas sin names son arrays y se preservan en orden.
#' Esto produce diffs git limpios cuando una fuente cambia el orden de keys.
ordenar_keys <- function(x) {
  if (is.list(x) && !is.null(names(x)) && all(nzchar(names(x)))) {
    x <- x[sort(names(x))]
    x <- lapply(x, ordenar_keys)
  } else if (is.list(x)) {
    x <- lapply(x, ordenar_keys)
  }
  x
}

#' Guarda CSV con escritura atómica y codificación UTF-8 explícita (P7).
#' @param df Data frame.
#' @param ruta Ruta destino.
guardar_csv <- function(df, ruta) {
  dir.create(dirname(ruta), showWarnings = FALSE, recursive = TRUE)
  ruta_tmp <- paste0(ruta, ".tmp")
  write.csv(df, ruta_tmp, row.names = FALSE, fileEncoding = "UTF-8")
  file.rename(ruta_tmp, ruta)
}


# ── Validación de integridad (P8) ──────────────────────────────────────────

#' Valida la estructura básica del caché.
#' @param cache Lista del caché.
#' @return TRUE si es válido, FALSE con warnings si no.
validar_cache <- function(cache) {
  ok <- TRUE

  if (is.null(cache$`_meta`)) {
    cli_alert_warning("Validación: falta bloque _meta")
    ok <- FALSE
  }

  if (is.null(cache$albumes)) {
    cli_alert_warning("Validación: falta bloque albumes")
    ok <- FALSE
  }

  n <- length(cache$albumes)
  if (n == 0) {
    cli_alert_warning("Validación: caché vacío")
    return(ok)
  }

  # Verificar campos mínimos en una muestra
  muestra <- cache$albumes[[1]]
  campos_requeridos <- c("artista", "album", "anio", "artwork_url")
  faltantes <- setdiff(campos_requeridos, names(muestra))
  if (length(faltantes) > 0) {
    cli_alert_warning("Validación: campos faltantes en primer álbum: {paste(faltantes, collapse = ', ')}")
    ok <- FALSE
  }

  # Contar álbumes con datos de cada fuente
  n_spotify <- sum(vapply(cache$albumes, \(a) !is.null(a$spotify$fecha_consulta), logical(1)))
  n_lastfm  <- sum(vapply(cache$albumes, \(a) !is.null(a$lastfm$fecha_consulta), logical(1)))
  n_mb      <- sum(vapply(cache$albumes, \(a) !is.null(a$musicbrainz$fecha_consulta), logical(1)))

  cli_alert_info("Cobertura: Spotify {n_spotify}/{n} | Last.fm {n_lastfm}/{n} | MusicBrainz {n_mb}/{n}")

  ok
}


# ── Helpers: extracción segura ─────────────────────────────────────────────

#' Extracción segura de texto — siempre devuelve un escalar character.
#' Maneja NULL, NA, character(0) y vectores.
safe_str <- function(x) {
  if (is.null(x) || length(x) == 0) return("")
  val <- x[[1]]
  if (is.na(val)) return("")
  as.character(val)
}

#' Extracción segura de número — siempre devuelve un escalar numérico.
safe_num <- function(x, default = 0) {
  if (is.null(x) || length(x) == 0) return(default)
  val <- x[[1]]
  if (is.na(val)) return(default)
  as.numeric(val)
}

#' Colapsa una lista a string separado por "; " para CSV.
#' Tolerante a NULL, NA, character(0).
colapsar <- function(x) {
  if (is.null(x) || length(x) == 0) return("")
  vals <- unlist(x)
  if (length(vals) == 0) return("")
  paste(vals, collapse = "; ")
}


# ── Helpers: varios ────────────────────────────────────────────────────────

#' Reporte de tiempo transcurrido.
reportar_tiempo <- function(inicio) {
  elapsed <- as.numeric(difftime(Sys.time(), inicio, units = "mins"))
  if (elapsed < 1) {
    cli_alert_info("Tiempo: {round(elapsed * 60)}s")
  } else {
    cli_alert_info("Tiempo: {round(elapsed, 1)} min")
  }
}
