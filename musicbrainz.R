# ============================================================================
# musicbrainz.R — Enriquecer con metadatos de MusicBrainz
# Proyecto Discoteca | tomgc
# ============================================================================
#
# QUÉ HACE:
#   1. Para cada álbum sin datos de MusicBrainz, busca sello, país, tipo
#   2. Respaldo de artwork vía Cover Art Archive si falta
#   3. Guarda cada álbum al caché INMEDIATAMENTE
#
# NOTAS:
#   - MusicBrainz exige máximo 1 req/s y User-Agent obligatorio.
#   - No requiere autenticación (API pública).
#   - ~3 requests por álbum = ~60 min para 1375 álbumes.
#   - Si se interrumpe, el progreso queda guardado.
#
# REFACTOR v5:
#   - leer_cache() y guardar_cache() ahora vienen de utils.R
#   - Constantes (RUTA_CACHE, MB_BASE, etc.) vienen de utils.R
#   - guardar_cache() ahora usa escritura atómica (P4) — antes no la tenía
#
# PAQUETES: install.packages(c("httr2", "jsonlite", "cli", "here"))
# ============================================================================

library(httr2)
source(here::here("utils.R"))

# --- HTTP -------------------------------------------------------------------

mb_get <- function(endpoint, params = list(), max_reintentos = HTTP_MAX_RETRIES) {
  url <- paste0(MB_BASE, "/", endpoint)

  for (intento in seq_len(max_reintentos)) {
    resp <- tryCatch(
      {
        req <- request(url) |>
          req_headers(`User-Agent` = MB_USER_AGENT) |>
          req_url_query(fmt = "json") |>
          req_error(is_error = \(resp) FALSE)
        for (nm in names(params)) req <- req |> req_url_query(!!nm := params[[nm]])
        req |> req_perform()
      },
      error = function(e) { cli_alert_danger("Red: {e$message}"); NULL }
    )

    if (is.null(resp)) { Sys.sleep(2^intento); next }

    status <- resp_status(resp)
    if (status == 200) return(resp_body_json(resp, simplifyVector = FALSE))
    if (status == 503) { cli_alert_warning("MusicBrainz 503 — 5s"); Sys.sleep(5); next }
    if (status == 429) { cli_alert_warning("Rate limit MB — 3s"); Sys.sleep(3); next }
    cli_alert_danger("HTTP {status}"); return(NULL)
  }
  NULL
}

# --- Búsquedas --------------------------------------------------------------

buscar_release_group <- function(artista, album) {
  query <- paste0('releasegroup:"', album, '" AND artist:"', artista, '"')
  data <- mb_get("release-group", params = list(query = query, limit = "5"))
  Sys.sleep(MB_PAUSE)

  if (is.null(data) || is.null(data$`release-groups`) || length(data$`release-groups`) == 0) return(NULL)
  mejor <- data$`release-groups`[[1]]
  list(mbid = mejor$id, tipo = mejor$`primary-type` %||% "Unknown")
}

buscar_release_info <- function(release_group_mbid) {
  data <- mb_get(paste0("release-group/", release_group_mbid), params = list(inc = "releases"))
  Sys.sleep(MB_PAUSE)

  if (is.null(data) || is.null(data$releases) || length(data$releases) == 0) {
    return(list(sello = NA_character_, pais = NA_character_))
  }

  # Probar máximo MB_MAX_RELEASES para no hacer demasiadas llamadas
  n <- min(length(data$releases), MB_MAX_RELEASES)

  for (i in seq_len(n)) {
    release <- data$releases[[i]]
    pais <- release$country %||% NA_character_

    detail <- mb_get(paste0("release/", release$id), params = list(inc = "labels"))
    Sys.sleep(MB_PAUSE)

    sello <- NA_character_
    if (!is.null(detail) && !is.null(detail$`label-info`) && length(detail$`label-info`) > 0) {
      label <- detail$`label-info`[[1]]$label
      if (!is.null(label)) sello <- label$name %||% NA_character_
    }

    if (!is.na(sello) || !is.na(pais)) return(list(sello = sello, pais = pais))
  }

  list(sello = NA_character_, pais = NA_character_)
}

buscar_artwork_caa <- function(release_group_mbid) {
  url <- paste0(MB_CAA_BASE, "/release-group/", release_group_mbid)
  resp <- tryCatch(
    request(url) |> req_headers(`User-Agent` = MB_USER_AGENT) |>
      req_error(is_error = \(resp) FALSE) |> req_perform(),
    error = function(e) NULL
  )

  if (is.null(resp) || resp_status(resp) != 200) return(NA_character_)
  data <- resp_body_json(resp, simplifyVector = FALSE)

  if (!is.null(data$images) && length(data$images) > 0) {
    for (img in data$images) {
      if (isTRUE(img$front)) return(img$thumbnails$`500` %||% img$image %||% NA_character_)
    }
    return(data$images[[1]]$thumbnails$`500` %||% data$images[[1]]$image %||% NA_character_)
  }
  NA_character_
}

# --- Main -------------------------------------------------------------------

main <- function() {
  cli_h1("Discoteca — Enriquecer desde MusicBrainz")

  cache <- leer_cache()
  todas <- names(cache$albumes)

  sin_mb <- Filter(
    \(k) length(cache$albumes[[k]]$musicbrainz) == 0 || is.null(cache$albumes[[k]]$musicbrainz$fecha_consulta),
    todas
  )

  cli_alert_info("En caché: {length(todas)} | Sin MusicBrainz: {length(sin_mb)}")
  if (length(sin_mb) == 0) { cli_alert_success("Todos completos"); return(invisible(NULL)) }

  mins <- round(length(sin_mb) * 3 / 60)
  cli_alert_warning("~{mins} minutos estimados (1 req/s por política de MusicBrainz)")

  inicio <- Sys.time()
  enriquecidos <- 0; no_encontrados <- 0; errores <- 0

  for (i in seq_along(sin_mb)) {
    key <- sin_mb[i]
    a   <- cache$albumes[[key]]

    cli_alert("  [{i}/{length(sin_mb)}] {a$artista} — {a$album}")

    resultado <- tryCatch(
      {
        rg <- buscar_release_group(a$artista, a$album)

        if (is.null(rg)) {
          cache$albumes[[key]]$musicbrainz <- list(
            mbid = NA, sello = NA, pais = NA, tipo = NA,
            fecha_consulta = format(Sys.Date()), nota = "No encontrado en MusicBrainz"
          )
          guardar_cache(cache)
          cli_alert_warning("    No encontrado")
          "no_encontrado"
        } else {
          info <- buscar_release_info(rg$mbid)

          # Artwork respaldo
          if (is.null(a$artwork_url) || a$artwork_url == "") {
            artwork <- tryCatch(buscar_artwork_caa(rg$mbid), error = \(e) NA_character_)
            Sys.sleep(MB_PAUSE)
            if (!is.na(artwork)) {
              cache$albumes[[key]]$artwork_url <- artwork
              cli_alert_success("    Artwork encontrado")
            }
          }

          cache$albumes[[key]]$musicbrainz <- list(
            mbid = rg$mbid, sello = info$sello, pais = info$pais,
            tipo = rg$tipo, fecha_consulta = format(Sys.Date())
          )
          guardar_cache(cache)
          cli_alert_success("    {rg$tipo} | {info$sello %||% '?'} | {info$pais %||% '?'}")
          "ok"
        }
      },
      error = function(e) {
        cli_alert_danger("    Error: {e$message}")
        cache$albumes[[key]]$musicbrainz <<- list(
          mbid = NA, sello = NA, pais = NA, tipo = NA,
          fecha_consulta = format(Sys.Date()), nota = paste0("Error: ", e$message)
        )
        guardar_cache(cache)
        "error"
      }
    )

    if (resultado == "ok") enriquecidos <- enriquecidos + 1
    if (resultado == "no_encontrado") no_encontrados <- no_encontrados + 1
    if (resultado == "error") errores <- errores + 1
  }

  cli_h2("Resumen")
  cli_alert_info("Enriquecidos: {enriquecidos} | No encontrados: {no_encontrados} | Errores: {errores}")
  reportar_tiempo(inicio)
}

main()
