# ============================================================================
# lastfm.R — Enriquecer con datos de escucha desde Last.fm
# Proyecto Discoteca | tomgc
# ============================================================================
#
# QUÉ HACE:
#   1. Lee álbumes del caché que no tienen datos de Last.fm
#   2. Para cada uno busca scrobbles, tags, y primer scrobble
#   3. Guarda cada álbum al caché INMEDIATAMENTE
#
# NOTAS:
#   - Last.fm permite ~4 req/s. Usamos Sys.sleep(0.25) entre llamadas.
#   - Si se interrumpe, el progreso queda guardado.
#   - Errores individuales se registran en el caché con nota.
#
# PAQUETES: install.packages(c("httr2", "jsonlite", "cli"))
# ============================================================================

library(httr2)
library(jsonlite)
library(cli)

# --- Configuración ----------------------------------------------------------

RUTA_CACHE  <- file.path("datos", "music_cache.json")
LASTFM_BASE <- "https://ws.audioscrobbler.com/2.0/"

# --- Funciones de caché -----------------------------------------------------

leer_cache <- function(ruta) {
  if (!file.exists(ruta)) cli_abort("Caché no encontrado en {ruta}. Corre spotify.R primero.")
  fromJSON(ruta, simplifyVector = FALSE)
}

guardar_cache <- function(cache, ruta) {
  cache$`_meta`$ultima_actualizacion <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  write_json(cache, ruta, pretty = TRUE, auto_unbox = TRUE)
}

# --- HTTP -------------------------------------------------------------------

lastfm_get <- function(method, params, api_key, max_reintentos = 3) {
  params_full <- c(list(method = method, api_key = api_key, format = "json"), params)

  for (intento in seq_len(max_reintentos)) {
    resp <- tryCatch(
      {
        req <- request(LASTFM_BASE)
        for (nm in names(params_full)) req <- req |> req_url_query(!!nm := params_full[[nm]])
        req |> req_error(is_error = \(resp) FALSE) |> req_perform()
      },
      error = function(e) { cli_alert_danger("Red: {e$message}"); NULL }
    )

    if (is.null(resp)) { Sys.sleep(2^intento); next }

    status <- resp_status(resp)
    if (status == 200) {
      data <- resp_body_json(resp, simplifyVector = FALSE)
      if (!is.null(data$error)) { cli_alert_warning("Last.fm error {data$error}: {data$message %||% '?'}"); return(NULL) }
      return(data)
    }
    if (status == 429) { cli_alert_warning("Rate limit Last.fm — 10s"); Sys.sleep(10); next }
    cli_alert_danger("HTTP {status}"); return(NULL)
  }
  NULL
}

# --- Extraer tags de forma segura -------------------------------------------

extraer_tags <- function(info) {
  tryCatch(
    {
      if (is.null(info$tags) || !is.list(info$tags)) return(list())
      tag_data <- info$tags$tag
      if (is.null(tag_data) || !is.list(tag_data)) return(list())
      lapply(tag_data, \(t) if (is.list(t) && !is.null(t$name)) t$name else if (is.character(t)) t else NULL)
    },
    error = function(e) list()
  )
}

# --- Buscar álbum -----------------------------------------------------------

buscar_album_lastfm <- function(artista, album, api_key, usuario) {
  data <- lastfm_get("album.getInfo",
    params = list(artist = artista, album = album, username = usuario, autocorrect = "1"),
    api_key = api_key
  )

  if (is.null(data) || is.null(data$album)) return(NULL)
  info <- data$album

  list(
    scrobbles_totales = as.integer(info$userplaycount %||% "0"),
    tags_lastfm       = extraer_tags(info),
    nombre_corregido  = info$name,
    artista_corregido = info$artist
  )
}

# --- Buscar primer scrobble -------------------------------------------------

buscar_primer_scrobble <- function(artista, album, api_key, usuario) {
  data <- lastfm_get("user.getRecentTracks",
    params = list(user = usuario, artist = artista, limit = "200", page = "1"),
    api_key = api_key
  )

  if (is.null(data) || is.null(data$recenttracks) || is.null(data$recenttracks$track)) {
    return(NA_character_)
  }

  album_lower <- tolower(album)
  fechas <- c()

  for (track in data$recenttracks$track) {
    # Protección: track puede no tener $album o $date
    track_album <- tryCatch(tolower(track$album$`#text` %||% ""), error = \(e) "")
    if (track_album == album_lower && !is.null(track$date) && !is.null(track$date$uts)) {
      fechas <- c(fechas, track$date$uts)
    }
  }

  if (length(fechas) == 0) return(NA_character_)
  format(as.POSIXct(min(as.numeric(fechas)), origin = "1970-01-01"), "%Y-%m-%d")
}

# --- Main -------------------------------------------------------------------

main <- function() {
  cli_h1("Discoteca — Enriquecer desde Last.fm")

  api_key <- Sys.getenv("LASTFM_API_KEY")
  usuario <- Sys.getenv("LASTFM_USER")
  if (api_key == "" || usuario == "") {
    cli_abort("Credenciales Last.fm no encontradas. Agrega LASTFM_API_KEY y LASTFM_USER a .Renviron")
  }

  cache <- leer_cache(RUTA_CACHE)
  todas <- names(cache$albumes)

  sin_lastfm <- Filter(
    \(k) length(cache$albumes[[k]]$lastfm) == 0 || is.null(cache$albumes[[k]]$lastfm$fecha_consulta),
    todas
  )

  cli_alert_info("En caché: {length(todas)} | Sin Last.fm: {length(sin_lastfm)}")
  if (length(sin_lastfm) == 0) { cli_alert_success("Todos completos"); return(invisible(NULL)) }

  enriquecidos <- 0; no_encontrados <- 0; errores <- 0

  for (i in seq_along(sin_lastfm)) {
    key <- sin_lastfm[i]
    a   <- cache$albumes[[key]]

    cli_alert("  [{i}/{length(sin_lastfm)}] {a$artista} — {a$album}")

    resultado <- tryCatch(
      {
        info <- buscar_album_lastfm(a$artista, a$album, api_key, usuario)
        Sys.sleep(0.25)

        if (is.null(info)) {
          cache$albumes[[key]]$lastfm <- list(
            scrobbles_totales = 0L, primer_scrobble = NA, tags_lastfm = list(),
            fecha_consulta = format(Sys.Date()), nota = "No encontrado en Last.fm"
          )
          guardar_cache(cache, RUTA_CACHE)
          "no_encontrado"
        } else {
          primer <- NA_character_
          if (info$scrobbles_totales > 0) {
            primer <- tryCatch(buscar_primer_scrobble(a$artista, a$album, api_key, usuario), error = \(e) NA_character_)
            Sys.sleep(0.25)
          }
          cache$albumes[[key]]$lastfm <- list(
            scrobbles_totales = info$scrobbles_totales, primer_scrobble = primer,
            tags_lastfm = info$tags_lastfm, fecha_consulta = format(Sys.Date())
          )
          guardar_cache(cache, RUTA_CACHE)
          cli_alert_success("    {info$scrobbles_totales} scrobbles")
          "ok"
        }
      },
      error = function(e) {
        cli_alert_danger("    Error: {e$message}")
        cache$albumes[[key]]$lastfm <<- list(
          scrobbles_totales = 0L, primer_scrobble = NA, tags_lastfm = list(),
          fecha_consulta = format(Sys.Date()), nota = paste0("Error: ", e$message)
        )
        guardar_cache(cache, RUTA_CACHE)
        "error"
      }
    )

    if (resultado == "ok") enriquecidos <- enriquecidos + 1
    if (resultado == "no_encontrado") no_encontrados <- no_encontrados + 1
    if (resultado == "error") errores <- errores + 1
  }

  cli_h2("Resumen")
  cli_alert_info("Enriquecidos: {enriquecidos} | No encontrados: {no_encontrados} | Errores: {errores}")
}

main()
