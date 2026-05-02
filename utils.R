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
#
# CHANGELOG v4 → v5:
#   - Todos los scripts ahora usan este módulo (antes cada uno definía
#     sus propias versiones de leer_cache y guardar_cache)
#   - safe_str() y safe_num() movidos desde construir.R; corregido bug
#     donde as.character(NA) producía el string "NA" en el CSV
#   - Agregada escribir_json_atomico() (antes duplicada en construir.R
#     y deduplicar.R)
#   - reportar_tiempo() para medir duración de procesos largos
#
# ============================================================================

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
#' FIX v5: as.character(NA) producía "NA" (el string). Ahora devuelve "".
safe_str <- function(x) {
  if (is.null(x) || length(x) == 0) return("")
  val <- x[[1]]
  if (is.na(val)) return("")
  as.character(val)
}

#' Extracción segura de número — siempre devuelve un escalar numérico.
#' FIX v5: is.na() check agregado para consistencia con safe_str.
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
