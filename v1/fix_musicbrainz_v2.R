# ============================================================================
# fix_musicbrainz_v2.R — Fix completo de MusicBrainz
# ============================================================================
#
# 3 pases:
#   1. No encontrados → limpiar títulos + re-buscar
#   2. Tipo no-Album → re-buscar filtrando por type=Album
#   3. Sello NA → probar más releases (hasta 6)
#
# ============================================================================

source(here::here("utils.R"))
library(httr2)

cache <- leer_cache()

# ── HTTP MusicBrainz ───────────────────────────────────────────────────────

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

# Búsqueda con filtro opcional de tipo
buscar_rg <- function(artista, album, tipo_filtro = NULL) {
  query <- paste0('releasegroup:"', album, '" AND artist:"', artista, '"')
  if (!is.null(tipo_filtro)) {
    query <- paste0(query, ' AND primarytype:"', tipo_filtro, '"')
  }
  data <- mb_get("release-group", params = list(query = query, limit = "10"))
  Sys.sleep(MB_PAUSE)
  if (is.null(data) || length(data$`release-groups` %||% list()) == 0) return(NULL)

  # Si tenemos filtro, tomar el primero. Si no, preferir Album sobre otros
  if (!is.null(tipo_filtro)) {
    mejor <- data$`release-groups`[[1]]
  } else {
    # Preferir Album si hay uno
    albums <- Filter(\(rg) identical(rg$`primary-type`, "Album"), data$`release-groups`)
    mejor <- if (length(albums) > 0) albums[[1]] else data$`release-groups`[[1]]
  }

  list(mbid = mejor$id, tipo = mejor$`primary-type` %||% "Unknown")
}

# Buscar sello/país con más releases
buscar_release <- function(mbid, max_rel = 6L) {
  data <- mb_get(paste0("release-group/", mbid), params = list(inc = "releases"))
  Sys.sleep(MB_PAUSE)
  if (is.null(data) || length(data$releases %||% list()) == 0) {
    return(list(sello = NA_character_, pais = NA_character_))
  }
  n <- min(length(data$releases), max_rel)
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

# Guardar resultado al caché
guardar_mb <- function(key, mbid, sello, pais, tipo, nota_extra = NULL) {
  entry <- list(
    mbid = mbid, sello = sello, pais = pais,
    tipo = tipo, fecha_consulta = format(Sys.Date())
  )
  if (!is.null(nota_extra)) entry$titulo_buscado <- nota_extra
  cache$albumes[[key]]$musicbrainz <<- entry
  guardar_cache(cache)
}

# ── Patrones de limpieza de título (extendidos) ─────────────────────────────

PATRONES <- c(
  # Versiones regionales
  "\\s*\\(U\\.?S\\.?\\s*Version\\)",
  "\\s*\\(International\\s*Version\\)",
  "\\s*\\(Non\\s*EU\\s*Version\\)",
  "\\s*\\(Non EU\\)",
  "\\s*\\(non\\s+EU[^)]*\\)",
  "\\s*\\(Eastwest\\s*Release\\)",
  "\\s*\\(Version\\s*\\d+\\)",
  # Remasters y ediciones
  "\\s*\\(\\d{4}\\s*-?\\s*Remaster(ed)?[^)]*\\)",
  "\\s*\\(Remaster(ed)?\\s*\\d*[^)]*\\)",
  "\\s*\\(Super Deluxe[^)]*\\)",
  "\\s*\\(Deluxe[^)]*\\)",
  "\\s*\\(Expanded[^)]*\\)",
  "\\s*\\(Special\\s*(Edition|Reissue)[^)]*\\)",
  "\\s*\\(\\d+th Anniversary[^)]*\\)",
  "\\s*\\(Anniversary[^)]*\\)",
  "\\s*\\(Collector'?s\\s*Edition[^)]*\\)",
  "\\s*\\(Enhanced\\s*Reissue[^)]*\\)",
  "\\s*\\(\\d{4}\\s*(Extended)?\\s*Re(edition|issue)[^)]*\\)",
  # Live y unplugged
  "\\s*\\(Live[^)]*\\)",
  "\\s*\\(MTV Unplugged[^)]*\\)",
  "\\s*\\(Unplugged[^)]*\\)",
  "\\s*\\(En Directo[^)]*\\)",
  "\\s*\\(In Concert[^)]*\\)",
  # Explicit
  "\\s*\\(Explicit[^)]*\\)",
  "\\s*\\[Explicit[^\\]]*\\]",
  # Ediciones con año
  "\\s*\\(\\d{4}\\s+Remix[^)]*\\)",
  "\\s*\\(\\d{4}\\s+Mix[^)]*\\)",
  "\\s*\\(\\d{4}\\s+Stereo[^)]*\\)",
  # Corchetes
  "\\s*\\[\\d{4}\\s+Master[^\\]]*\\]",
  "\\s*\\[Remastered[^\\]]*\\]",
  "\\s*\\[Live[^\\]]*\\]",
  # Edited, Redux, etc.
  "\\s*\\(Edited\\s*Version\\)",
  "\\s*\\(Versión[^)]*\\)",
  "\\s*\\(Red\\s*Edition\\)",
  "\\s*\\(Legacy\\s*Edition[^)]*\\)",
  # Sufijos con guión
  "\\s*-\\s*Remaster(ed)?.*$",
  "\\s*-\\s*Best Of.*$",
  "\\s*-\\s*Remixes\\s*$",
  "\\s*-\\s*Deluxe\\s*Edition\\s*$",
  # Trophy, Redux
  "\\s*\\(Trophy\\s*Edition\\)",
  "\\s*Redux\\s*$",
  # XX Anniversary
  "\\s*\\(XX\\s*Anniversary[^)]*\\)"
)

limpiar_titulo <- function(titulo) {
  limpio <- titulo
  for (p in PATRONES) limpio <- gsub(p, "", limpio, perl = TRUE, ignore.case = TRUE)
  trimws(limpio)
}

# ══════════════════════════════════════════════════════════════════════════
# PASE 1: No encontrados → limpiar título + re-buscar (preferir Album)
# ══════════════════════════════════════════════════════════════════════════

no_enc <- names(Filter(
  \(a) !is.null(a$musicbrainz$nota) && grepl("No encontrado", a$musicbrainz$nota),
  cache$albumes
))

cli_h1("Pase 1: No encontrados ({length(no_enc)})")

p1_ok <- 0

for (i in seq_along(no_enc)) {
  key <- no_enc[i]
  a   <- cache$albumes[[key]]
  titulo_limpio <- limpiar_titulo(a$album)

  cli_alert("  [{i}/{length(no_enc)}] {a$artista} — {titulo_limpio}")

  resultado <- tryCatch({
    # Intentar con título limpio, preferir Album
    rg <- buscar_rg(a$artista, titulo_limpio)

    if (is.null(rg)) {
      cli_alert_warning("    Sigue sin encontrarse")
      "no"
    } else {
      info <- buscar_release(rg$mbid)
      guardar_mb(key, rg$mbid, info$sello, info$pais, rg$tipo, titulo_limpio)
      cli_alert_success("    {rg$tipo} | {info$sello %||% '?'} | {info$pais %||% '?'}")
      p1_ok <<- p1_ok + 1
      "ok"
    }
  }, error = function(e) { cli_alert_danger("    Error: {e$message}"); "error" })
}

cli_alert_info("Pase 1: {p1_ok} encontrados de {length(no_enc)}")

# ══════════════════════════════════════════════════════════════════════════
# PASE 2: Tipo no-Album → re-buscar con filtro type=Album
# ══════════════════════════════════════════════════════════════════════════

# Re-leer caché (fue modificado en pase 1)
cache <- leer_cache()

no_album <- names(Filter(
  \(a) !is.null(a$musicbrainz$tipo) && !is.na(a$musicbrainz$tipo) &&
       a$musicbrainz$tipo != "Album",
  cache$albumes
))

cli_h1("Pase 2: Tipo no-Album ({length(no_album)})")

p2_ok <- 0

for (i in seq_along(no_album)) {
  key <- no_album[i]
  a   <- cache$albumes[[key]]
  titulo_limpio <- limpiar_titulo(a$album)

  cli_alert("  [{i}/{length(no_album)}] {a$artista} — {titulo_limpio} (era: {a$musicbrainz$tipo})")

  resultado <- tryCatch({
    # Buscar explícitamente con type=Album
    rg <- buscar_rg(a$artista, titulo_limpio, tipo_filtro = "Album")

    if (is.null(rg)) {
      # Puede que realmente sea un EP/single, no forzar
      cli_alert("    No hay álbum con ese nombre — manteniendo {a$musicbrainz$tipo}")
      "no"
    } else {
      info <- buscar_release(rg$mbid)
      guardar_mb(key, rg$mbid, info$sello, info$pais, rg$tipo, titulo_limpio)
      cli_alert_success("    {rg$tipo} | {info$sello %||% '?'} | {info$pais %||% '?'}")
      p2_ok <<- p2_ok + 1
      "ok"
    }
  }, error = function(e) { cli_alert_danger("    Error: {e$message}"); "error" })
}

cli_alert_info("Pase 2: {p2_ok} corregidos de {length(no_album)}")

# ══════════════════════════════════════════════════════════════════════════
# PASE 3: Sello NA → probar más releases (hasta 6)
# ══════════════════════════════════════════════════════════════════════════

cache <- leer_cache()

sello_na <- names(Filter(
  \(a) !is.null(a$musicbrainz$fecha_consulta) &&
       !is.null(a$musicbrainz$mbid) && !is.na(a$musicbrainz$mbid) &&
       (is.null(a$musicbrainz$sello) || is.na(a$musicbrainz$sello)),
  cache$albumes
))

cli_h1("Pase 3: Sello NA ({length(sello_na)})")

p3_ok <- 0

for (i in seq_along(sello_na)) {
  key <- sello_na[i]
  a   <- cache$albumes[[key]]
  mbid <- a$musicbrainz$mbid

  cli_alert("  [{i}/{length(sello_na)}] {a$artista} — {a$album}")

  resultado <- tryCatch({
    info <- buscar_release(mbid, max_rel = 6L)
    if (!is.na(info$sello)) {
      cache$albumes[[key]]$musicbrainz$sello <- info$sello
      cache$albumes[[key]]$musicbrainz$pais  <- info$pais %||% cache$albumes[[key]]$musicbrainz$pais
      guardar_cache(cache)
      cli_alert_success("    {info$sello} | {info$pais %||% '?'}")
      p3_ok <<- p3_ok + 1
      "ok"
    } else {
      cli_alert_warning("    Sello sigue sin encontrarse")
      "no"
    }
  }, error = function(e) { cli_alert_danger("    Error: {e$message}"); "error" })
}

cli_alert_info("Pase 3: {p3_ok} sellos encontrados de {length(sello_na)}")

# ══════════════════════════════════════════════════════════════════════════
# RESUMEN FINAL
# ══════════════════════════════════════════════════════════════════════════

cache <- leer_cache()
todas <- names(cache$albumes)

final_no_enc <- sum(sapply(cache$albumes, \(a) !is.null(a$musicbrainz$nota) && grepl("No encontrado", a$musicbrainz$nota)))
final_sello_na <- sum(sapply(cache$albumes, \(a) !is.null(a$musicbrainz$fecha_consulta) && (is.null(a$musicbrainz$sello) || is.na(a$musicbrainz$sello))))
final_no_album <- sum(sapply(cache$albumes, \(a) !is.null(a$musicbrainz$tipo) && !is.na(a$musicbrainz$tipo) && a$musicbrainz$tipo != "Album"))

cli_h1("Resumen final")
cli_alert_info("Total álbumes: {length(todas)}")
cli_alert_info("Aún no encontrados: {final_no_enc}")
cli_alert_info("Aún sin sello: {final_sello_na}")
cli_alert_info("Aún tipo no-Album: {final_no_album} (pueden ser EPs/singles legítimos)")
