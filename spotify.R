# ============================================================================
# spotify.R — Importar álbumes guardados desde Spotify
# Proyecto Discoteca | tomgc
# ============================================================================
#
# QUÉ HACE:
#   1. Se autentica con la API de Spotify (OAuth 2.0)
#   2. Descarga todos tus álbumes guardados (paginados de 50 en 50)
#   3. Guarda cada álbum nuevo al caché INMEDIATAMENTE
#
# NOTAS:
#   - No busca géneros (Spotify cobra rate limit). Se obtienen vía Last.fm.
#   - No usa spotifyr (endpoints deprecados en feb 2026). Usa httr2 directo.
#   - Si se interrumpe, el progreso queda guardado en disco.
#   - Redirect URI: http://127.0.0.1:1410/
#
# REFACTOR v5:
#   - leer_cache() y guardar_cache() ahora vienen de utils.R
#   - Constantes (RUTA_CACHE, SPOTIFY_BASE, PAGE_SIZE) vienen de utils.R
#   - guardar_cache() ahora usa escritura atómica (P4) — antes no la tenía
#
# PAQUETES: install.packages(c("httr2", "jsonlite", "cli", "here"))
# ============================================================================

library(httr2)
source(here::here("utils.R"))

# --- Autenticación ----------------------------------------------------------

obtener_token_spotify <- function() {
  client_id     <- Sys.getenv("SPOTIFY_CLIENT_ID")
  client_secret <- Sys.getenv("SPOTIFY_CLIENT_SECRET")

  if (client_id == "" || client_secret == "") {
    cli_abort(c(
      "No se encontraron credenciales de Spotify en .Renviron",
      "i" = "Agrega SPOTIFY_CLIENT_ID y SPOTIFY_CLIENT_SECRET a tu .Renviron",
      "i" = "Luego reinicia R o corre readRenviron('.Renviron')"
    ))
  }

  cliente <- oauth_client(
    id = client_id, secret = client_secret,
    token_url = "https://accounts.spotify.com/api/token",
    name = "discoteca"
  )

  token <- oauth_flow_auth_code(
    client = cliente,
    auth_url = "https://accounts.spotify.com/authorize",
    scope = "user-library-read",
    redirect_uri = SPOTIFY_REDIRECT
  )

  cli_alert_success("Autenticación exitosa con Spotify")
  token
}

# --- HTTP -------------------------------------------------------------------

spotify_get <- function(url, token, max_reintentos = HTTP_MAX_RETRIES) {
  for (intento in seq_len(max_reintentos)) {
    resp <- tryCatch(
      request(url) |>
        req_auth_bearer_token(token$access_token) |>
        req_error(is_error = \(resp) FALSE) |>
        req_perform(),
      error = function(e) {
        cli_alert_danger("Error de red: {e$message}")
        NULL
      }
    )

    if (is.null(resp)) { Sys.sleep(2^intento); next }

    status <- resp_status(resp)

    if (status == 200) return(resp_body_json(resp, simplifyVector = FALSE))

    if (status == 429) {
      espera <- as.numeric(resp_header(resp, "Retry-After") %||% "5")
      if (espera > SPOTIFY_RATE_LIMIT_MAX_WAIT) {
        cli_alert_danger("Rate limit severo: Spotify pide esperar {round(espera/3600, 1)} horas")
        cli_alert_info("Progreso guardado. Corre el script de nuevo más tarde.")
        return("RATE_LIMITED")
      }
      cli_alert_warning("Rate limit — esperando {espera}s (intento {intento})")
      Sys.sleep(espera + 1)
      next
    }

    if (status == 401) {
      cli_abort("Token expirado (401). Corre el script de nuevo para re-autenticarte.")
    }

    cli_alert_danger("Error HTTP {status}")
    return(NULL)
  }

  cli_alert_danger("Falló después de {max_reintentos} reintentos")
  NULL
}

# --- Descarga paginada ------------------------------------------------------

descargar_albumes_guardados <- function(token) {
  albumes <- list()
  offset  <- 0
  total   <- NA

  cli_alert_info("Descargando álbumes guardados de Spotify...")

  repeat {
    url  <- paste0(SPOTIFY_BASE, "/me/albums?limit=", SPOTIFY_PAGE_SIZE, "&offset=", offset)
    data <- spotify_get(url, token)

    if (identical(data, "RATE_LIMITED")) {
      cli_alert_warning("Descarga interrumpida. Se obtuvieron {length(albumes)} álbumes parciales.")
      break
    }
    if (is.null(data)) break

    if (is.na(total)) {
      total <- data$total
      cli_alert_info("Total en tu biblioteca: {total}")
    }

    if (length(data$items) == 0) break

    albumes <- c(albumes, data$items)
    offset  <- offset + SPOTIFY_PAGE_SIZE
    cli_alert("  Descargados: {length(albumes)} / {total}")

    if (is.null(data$`next`)) break
    Sys.sleep(0.3)
  }

  if (length(albumes) > 0) cli_alert_success("Descarga: {length(albumes)} álbumes obtenidos")
  albumes
}

# --- Procesamiento de un álbum ----------------------------------------------

procesar_album <- function(item) {
  album      <- item$album
  artista    <- album$artists[[1]]
  fecha_raw  <- album$release_date %||% ""
  fecha_prec <- album$release_date_precision %||% "year"

  # Artwork: primera imagen (la más grande)
  artwork <- ""
  if (length(album$images) > 0) artwork <- album$images[[1]]$url

  # Duración total en minutos
  duracion_ms <- 0
  if (!is.null(album$tracks) && !is.null(album$tracks$items)) {
    duracion_ms <- sum(vapply(album$tracks$items, \(t) t$duration_ms %||% 0, numeric(1)))
  }

  list(
    id_spotify         = album$id,
    artista            = artista$name %||% "Desconocido",
    album              = album$name %||% "Sin título",
    anio               = as.integer(substr(fecha_raw, 1, 4)),
    fecha_lanzamiento  = fecha_raw,
    fecha_precision    = fecha_prec,
    num_tracks         = album$total_tracks %||% 0L,
    duracion_total_min = round(duracion_ms / 60000, 1),
    artwork_url        = artwork,
    generos            = list(),
    spotify            = list(artist_id = artista$id, fecha_consulta = format(Sys.Date())),
    lastfm             = list(),
    musicbrainz        = list(),
    personal           = list(
      categoria = NULL, notas = "",
      tags_propios = list(), fecha_agregado = format(Sys.Date())
    )
  )
}

# --- Main -------------------------------------------------------------------

main <- function() {
  cli_h1("Discoteca — Importar desde Spotify")

  cache <- leer_cache()
  ids_existentes <- names(cache$albumes)
  token <- obtener_token_spotify()
  items <- descargar_albumes_guardados(token)

  if (length(items) == 0) {
    cli_alert_warning("No se encontraron álbumes")
    return(invisible(NULL))
  }

  inicio <- Sys.time()
  nuevos <- 0; saltados <- 0; errores <- 0

  for (item in items) {
    cache_key <- paste0("spotify:", item$album$id %||% "unknown")

    if (cache_key %in% ids_existentes) { saltados <- saltados + 1; next }

    resultado <- tryCatch(procesar_album(item), error = function(e) {
      cli_alert_danger("  Error: {e$message}")
      NULL
    })

    if (is.null(resultado)) { errores <- errores + 1; next }

    cache$albumes[[cache_key]] <- resultado
    ids_existentes <- c(ids_existentes, cache_key)
    nuevos <- nuevos + 1
    guardar_cache(cache)
    cli_alert_success("  [{nuevos}] {resultado$artista} — {resultado$album} ({resultado$anio})")
  }

  cli_h2("Resumen")
  cli_alert_info("Nuevos: {nuevos} | Saltados: {saltados} | Errores: {errores} | Total: {length(cache$albumes)}")
  reportar_tiempo(inicio)
}

main()
