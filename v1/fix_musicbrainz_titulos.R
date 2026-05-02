# ============================================================================
# fix_musicbrainz_titulos.R — Re-intentar álbumes no encontrados en MusicBrainz
# ============================================================================
#
# Problema: Spotify agrega sufijos como "(Deluxe Edition)", "(Remastered)",
#   "(Live)", "(Explicit)" que MusicBrainz no reconoce.
# Solución: Limpiar el título y re-buscar con el nombre base.
#
# ============================================================================

source(here::here("utils.R"))
library(httr2)

cache <- leer_cache()

# ── Identificar no encontrados ─────────────────────────────────────────────

no_encontrados <- names(Filter(
  \(a) !is.null(a$musicbrainz$nota) && grepl("No encontrado", a$musicbrainz$nota),
  cache$albumes
))

cli_alert_info("Álbumes no encontrados en MusicBrainz: {length(no_encontrados)}")

if (length(no_encontrados) == 0) {
  cli_alert_success("Nada que corregir")
  quit(save = "no")
}

# ── Patrones a limpiar (P11: parametrizados) ────────────────────────────────

# Orden importa: los más específicos primero
PATRONES_LIMPIAR <- c(
  # Paréntesis con contenido conocido
  "\\s*\\(\\d{4}\\s+Remaster(ed)?\\)",          # (2007 Remaster)
  "\\s*\\(\\d{4}\\s+Stereo Mix\\)",              # (2007 Stereo Mix)
  "\\s*\\(\\d{4}\\s+Mix\\)",                     # (2025 Mix)
  "\\s*\\(\\d{4}\\s+Remix\\)",                   # (2018 Remix)
  "\\s*\\(Remaster(ed)?\\s*\\d*\\)",             # (Remastered) o (Remastered 2016)
  "\\s*\\(Super Deluxe[^)]*\\)",                 # (Super Deluxe)
  "\\s*\\(Deluxe\\s*(Edition|Version)?[^)]*\\)", # (Deluxe Edition), (Deluxe Version)
  "\\s*\\(Expanded\\s*(Edition)?[^)]*\\)",       # (Expanded Edition)
  "\\s*\\(Special\\s*Edition[^)]*\\)",           # (Special Edition)
  "\\s*\\(Anniversary[^)]*\\)",                  # (Anniversary Edition)
  "\\s*\\(\\d+th Anniversary[^)]*\\)",           # (30th Anniversary Edition)
  "\\s*\\(\\d+th Anniversary\\)",                # (20th Anniversary)
  "\\s*\\(Live[^)]*\\)",                         # (Live), (Live at...)
  "\\s*\\(Explicit[^)]*\\)",                     # (Explicit Version)
  "\\s*\\(Non EU\\)",                            # (Non EU)
  "\\s*\\(Trophy Edition\\)",                    # (Trophy Edition)
  "\\s*\\(Band Edition[^)]*\\)",                 # (Band Edition Remastered)
  "\\s*\\[Explicit[^\\]]*\\]",                   # [Explicit Version]
  "\\s*\\[Live[^\\]]*\\]",                       # [Live]
  # Sufijos sin paréntesis
  "\\s*-\\s*Remaster(ed)?\\s*$",                 # - Remastered
  "\\s*-\\s*Best Of.*$",                         # - Best Of
  "\\s*-\\s*Remixes\\s*$",                       # - Remixes
  # Genéricos al final (más agresivos, van últimos)
  "\\s*\\(\\d{4}\\s+Remaster[^)]*\\)",           # Cualquier (YYYY Remaster...)
  "\\s*\\(\\d{4}\\s+Re[^)]*\\)"                  # Cualquier (YYYY Re...)
)

#' Limpia sufijos de un título de álbum
limpiar_titulo <- function(titulo) {
  limpio <- titulo
  for (patron in PATRONES_LIMPIAR) {
    limpio <- gsub(patron, "", limpio, perl = TRUE, ignore.case = TRUE)
  }
  trimws(limpio)
}

# ── Analizar patrones ──────────────────────────────────────────────────────

cli_h2("Análisis de títulos")

titulos_info <- lapply(no_encontrados, function(key) {
  a <- cache$albumes[[key]]
  original <- a$album
  limpio   <- limpiar_titulo(original)
  cambio   <- original != limpio
  list(key = key, artista = a$artista, original = original, limpio = limpio, cambio = cambio)
})

con_cambio <- Filter(\(x) x$cambio, titulos_info)
sin_cambio <- Filter(\(x) !x$cambio, titulos_info)

cli_alert_info("Con sufijos detectados (se re-intentarán): {length(con_cambio)}")
cli_alert_info("Sin sufijos (título ya limpio, no se re-intenta): {length(sin_cambio)}")

if (length(con_cambio) > 0) {
  cli_h3("Ejemplos de limpieza:")
  n_mostrar <- min(15, length(con_cambio))
  for (i in seq_len(n_mostrar)) {
    x <- con_cambio[[i]]
    cli_alert("  {x$artista}: \"{x$original}\" → \"{x$limpio}\"")
  }
}

if (length(sin_cambio) > 0) {
  cli_h3("Sin cambios (probablemente artistas o álbumes desconocidos en MusicBrainz):")
  n_mostrar <- min(10, length(sin_cambio))
  for (i in seq_len(n_mostrar)) {
    x <- sin_cambio[[i]]
    cli_alert_warning("  {x$artista} — {x$original}")
  }
}

# ── Re-intentar con títulos limpios ─────────────────────────────────────────

if (length(con_cambio) == 0) {
  cli_alert_info("No hay títulos que limpiar")
  quit(save = "no")
}

cli_h2("Re-buscando {length(con_cambio)} álbumes con títulos limpios")

# Funciones de MusicBrainz (reutilizadas de musicbrainz.R)
mb_get <- function(endpoint, params = list()) {
  url <- paste0(MB_BASE, "/", endpoint)
  for (intento in seq_len(HTTP_MAX_RETRIES)) {
    resp <- tryCatch(
      {
        req <- request(url) |>
          req_headers(`User-Agent` = MB_USER_AGENT) |>
          req_url_query(fmt = "json") |>
          req_error(is_error = \(r) FALSE)
        for (nm in names(params)) req <- req |> req_url_query(!!nm := params[[nm]])
        req |> req_perform()
      },
      error = function(e) NULL
    )
    if (is.null(resp)) { Sys.sleep(2^intento); next }
    status <- resp_status(resp)
    if (status == 200) return(resp_body_json(resp, simplifyVector = FALSE))
    if (status %in% c(429, 503)) { Sys.sleep(5); next }
    return(NULL)
  }
  NULL
}

buscar_rg <- function(artista, album) {
  query <- paste0('releasegroup:"', album, '" AND artist:"', artista, '"')
  data <- mb_get("release-group", params = list(query = query, limit = "5"))
  Sys.sleep(MB_PAUSE)
  if (is.null(data) || length(data$`release-groups` %||% list()) == 0) return(NULL)
  mejor <- data$`release-groups`[[1]]
  list(mbid = mejor$id, tipo = mejor$`primary-type` %||% "Unknown")
}

buscar_release <- function(mbid) {
  data <- mb_get(paste0("release-group/", mbid), params = list(inc = "releases"))
  Sys.sleep(MB_PAUSE)
  if (is.null(data) || length(data$releases %||% list()) == 0) {
    return(list(sello = NA_character_, pais = NA_character_))
  }
  n <- min(length(data$releases), MB_MAX_RELEASES)
  for (i in seq_len(n)) {
    rel <- data$releases[[i]]
    pais <- rel$country %||% NA_character_
    det <- mb_get(paste0("release/", rel$id), params = list(inc = "labels"))
    Sys.sleep(MB_PAUSE)
    sello <- NA_character_
    if (!is.null(det$`label-info`) && length(det$`label-info`) > 0) {
      lbl <- det$`label-info`[[1]]$label
      if (!is.null(lbl)) sello <- lbl$name %||% NA_character_
    }
    if (!is.na(sello) || !is.na(pais)) return(list(sello = sello, pais = pais))
  }
  list(sello = NA_character_, pais = NA_character_)
}

encontrados <- 0

for (i in seq_along(con_cambio)) {
  x <- con_cambio[[i]]
  cli_alert("  [{i}/{length(con_cambio)}] {x$artista} — {x$limpio}")

  resultado <- tryCatch(
    {
      rg <- buscar_rg(x$artista, x$limpio)
      if (is.null(rg)) {
        cli_alert_warning("    Sigue sin encontrarse")
        "no"
      } else {
        info <- buscar_release(rg$mbid)
        cache$albumes[[x$key]]$musicbrainz <- list(
          mbid = rg$mbid, sello = info$sello, pais = info$pais,
          tipo = rg$tipo, fecha_consulta = format(Sys.Date()),
          titulo_buscado = x$limpio  # Registrar qué título funcionó (P11)
        )
        guardar_cache(cache)
        cli_alert_success("    {rg$tipo} | {info$sello %||% '?'} | {info$pais %||% '?'}")
        encontrados <- encontrados + 1
        "ok"
      }
    },
    error = function(e) {
      cli_alert_danger("    Error: {e$message}")
      "error"
    }
  )
}

cli_h2("Resumen")
cli_alert_info("Re-intentados: {length(con_cambio)}")
cli_alert_info("Encontrados ahora: {encontrados}")
cli_alert_info("Sin cambio posible: {length(sin_cambio)}")

total_no_encontrados <- length(no_encontrados) - encontrados
cli_alert_info("Total sin datos de MusicBrainz: {total_no_encontrados}")
