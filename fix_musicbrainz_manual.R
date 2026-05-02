# ============================================================================
# fix_musicbrainz_manual.R — Correcciones manuales + tipo + sello
# ============================================================================

source(here::here("utils.R"))
library(httr2)

cache <- leer_cache()

# Leer correcciones con encoding UTF-8
txt_json <- readLines(here("datos", "correcciones_mb.json"), encoding = "UTF-8", warn = FALSE)
correcciones <- fromJSON(paste(txt_json, collapse = "\n"), simplifyVector = FALSE)$correcciones

# ── HTTP MusicBrainz ───────────────────────────────────────────────────────

mb_get <- function(endpoint, params = list()) {
  url <- paste0(MB_BASE, "/", endpoint)
  for (intento in seq_len(HTTP_MAX_RETRIES)) {
    resp <- tryCatch({
      req <- request(url) |>
        req_headers(`User-Agent` = MB_USER_AGENT) |>
        req_url_query(fmt = "json") |>
        req_error(is_error = \(r) FALSE)
      for (nm in names(params)) req <- req |> req_url_query(!!nm := params[[nm]])
      req |> req_perform()
    }, error = function(e) NULL)
    if (is.null(resp)) { Sys.sleep(2^intento); next }
    status <- resp_status(resp)
    if (status == 200) return(resp_body_json(resp, simplifyVector = FALSE))
    if (status %in% c(429, 503)) { Sys.sleep(5); next }
    return(NULL)
  }
  NULL
}

#' Escapa caracteres especiales de Lucene usando fixed=TRUE (no regex)
escapar_lucene <- function(s) {
  chars <- c("\\", "+", "-", "!", "(", ")", "{", "}", "[", "]",
             "^", "\"", "~", "*", "?", ":", "/")
  for (ch in chars) {
    s <- gsub(ch, paste0("\\", ch), s, fixed = TRUE)
  }
  s
}

buscar_rg <- function(artista, album, tipo_filtro = NULL) {
  album_esc <- escapar_lucene(album)
  artista_esc <- escapar_lucene(artista)
  query <- paste0('releasegroup:"', album_esc, '" AND artist:"', artista_esc, '"')
  if (!is.null(tipo_filtro)) query <- paste0(query, ' AND primarytype:"', tipo_filtro, '"')

  data <- mb_get("release-group", params = list(query = query, limit = "10"))
  Sys.sleep(MB_PAUSE)
  if (is.null(data) || length(data$`release-groups` %||% list()) == 0) return(NULL)

  if (!is.null(tipo_filtro)) {
    mejor <- data$`release-groups`[[1]]
  } else {
    albums <- Filter(\(rg) identical(rg$`primary-type`, "Album"), data$`release-groups`)
    mejor <- if (length(albums) > 0) albums[[1]] else data$`release-groups`[[1]]
  }
  list(mbid = mejor$id, tipo = mejor$`primary-type` %||% "Unknown")
}

buscar_release <- function(mbid, max_rel = 8L) {
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
      if (!is.null(lbl)) {
        s <- lbl$name %||% NA_character_
        if (!is.na(s) && s != "[no label]") sello <- s
      }
    }
    if (!is.na(sello)) return(list(sello = sello, pais = pais))
  }
  list(sello = NA_character_, pais = NA_character_)
}

guardar_mb <- function(key, mbid, sello, pais, tipo, nota_extra = NULL) {
  entry <- list(mbid = mbid, sello = sello, pais = pais,
                tipo = tipo, fecha_consulta = format(Sys.Date()))
  if (!is.null(nota_extra)) entry$titulo_buscado <- nota_extra
  cache$albumes[[key]]$musicbrainz <<- entry
  guardar_cache(cache)
}

# ══════════════════════════════════════════════════════════════════════════
# PASE 1: Correcciones manuales
# ══════════════════════════════════════════════════════════════════════════

cli_h1("Pase 1: Correcciones manuales ({length(correcciones)})")
p1_ok <- 0

for (i in seq_along(correcciones)) {
  corr <- correcciones[[i]]
  artista_sp <- corr$artista
  album_sp   <- corr$album_spotify
  buscar_a   <- corr$buscar_album
  buscar_art <- corr$buscar_artista %||% artista_sp

  # Encontrar la key en el caché
  key <- NULL
  for (k in names(cache$albumes)) {
    a <- cache$albumes[[k]]
    if (identical(a$artista, artista_sp) && identical(a$album, album_sp)) {
      key <- k
      break
    }
  }
  if (is.null(key)) next

  # Verificar si ya tiene datos buenos
  mb <- cache$albumes[[key]]$musicbrainz
  sello_actual <- mb$sello
  if (is.null(sello_actual) || length(sello_actual) == 0) sello_actual <- NA_character_
  tipo_actual <- mb$tipo
  if (is.null(tipo_actual) || length(tipo_actual) == 0) tipo_actual <- NA_character_

  tiene_sello <- !is.na(sello_actual) && sello_actual != "" && sello_actual != "[no label]"
  es_album <- !is.na(tipo_actual) && tipo_actual == "Album"
  if (tiene_sello && es_album) next

  cli_alert("  [{i}/{length(correcciones)}] {buscar_art} — {buscar_a}")

  resultado <- tryCatch({
    rg <- buscar_rg(buscar_art, buscar_a)
    if (is.null(rg)) {
      cli_alert_warning("    No encontrado")
      "no"
    } else {
      info <- buscar_release(rg$mbid)
      guardar_mb(key, rg$mbid, info$sello, info$pais, rg$tipo, buscar_a)
      cli_alert_success("    {rg$tipo} | {info$sello %||% '?'} | {info$pais %||% '?'}")
      p1_ok <<- p1_ok + 1
      "ok"
    }
  }, error = function(e) { cli_alert_danger("    Error: {e$message}"); "error" })
}

cli_alert_info("Pase 1: {p1_ok} corregidos")

# ══════════════════════════════════════════════════════════════════════════
# PASE 2: Tipo no-Album -> re-buscar filtrando por Album
# ══════════════════════════════════════════════════════════════════════════

cache <- leer_cache()

no_album_keys <- c()
for (k in names(cache$albumes)) {
  mb <- cache$albumes[[k]]$musicbrainz
  if (is.null(mb) || length(mb) == 0) next
  tipo <- mb$tipo
  if (is.null(tipo) || length(tipo) == 0 || is.na(tipo)) next
  if (tipo != "Album") no_album_keys <- c(no_album_keys, k)
}

cli_h1("Pase 2: Tipo no-Album ({length(no_album_keys)})")
p2_ok <- 0

for (i in seq_along(no_album_keys)) {
  key <- no_album_keys[i]
  a   <- cache$albumes[[key]]

  cli_alert("  [{i}/{length(no_album_keys)}] {a$artista} — {a$album} (era: {a$musicbrainz$tipo})")

  resultado <- tryCatch({
    rg <- buscar_rg(a$artista, a$album, tipo_filtro = "Album")
    if (is.null(rg)) {
      cli_alert("    No existe como Album en MB")
      "no"
    } else {
      info <- buscar_release(rg$mbid)
      guardar_mb(key, rg$mbid, info$sello, info$pais, rg$tipo)
      cli_alert_success("    {rg$tipo} | {info$sello %||% '?'} | {info$pais %||% '?'}")
      p2_ok <<- p2_ok + 1
      "ok"
    }
  }, error = function(e) { cli_alert_danger("    Error: {e$message}"); "error" })
}

cli_alert_info("Pase 2: {p2_ok} corregidos")

# ══════════════════════════════════════════════════════════════════════════
# PASE 3: Sello NA o [no label] -> probar más releases
# ══════════════════════════════════════════════════════════════════════════

cache <- leer_cache()

sello_malo_keys <- c()
for (k in names(cache$albumes)) {
  mb <- cache$albumes[[k]]$musicbrainz
  if (is.null(mb) || length(mb) == 0) next
  mbid <- mb$mbid
  if (is.null(mbid) || length(mbid) == 0 || is.na(mbid)) next
  sello <- mb$sello
  if (is.null(sello) || length(sello) == 0) sello <- NA_character_
  if (is.na(sello) || sello == "" || sello == "[no label]") {
    sello_malo_keys <- c(sello_malo_keys, k)
  }
}

cli_h1("Pase 3: Sello NA/[no label] ({length(sello_malo_keys)})")
p3_ok <- 0

for (i in seq_along(sello_malo_keys)) {
  key  <- sello_malo_keys[i]
  a    <- cache$albumes[[key]]
  mbid <- a$musicbrainz$mbid

  cli_alert("  [{i}/{length(sello_malo_keys)}] {a$artista} — {a$album}")

  resultado <- tryCatch({
    info <- buscar_release(mbid, max_rel = 8L)
    if (!is.na(info$sello) && info$sello != "[no label]") {
      cache$albumes[[key]]$musicbrainz$sello <- info$sello
      if (!is.na(info$pais)) cache$albumes[[key]]$musicbrainz$pais <- info$pais
      guardar_cache(cache)
      cli_alert_success("    {info$sello} | {info$pais %||% '?'}")
      p3_ok <<- p3_ok + 1
      "ok"
    } else {
      cli_alert_warning("    Sello no disponible")
      "no"
    }
  }, error = function(e) { cli_alert_danger("    Error: {e$message}"); "error" })
}

cli_alert_info("Pase 3: {p3_ok} sellos encontrados")

# ══════════════════════════════════════════════════════════════════════════
cli_h1("Resumen")
cli_alert_info("Pase 1 (correcciones manuales): {p1_ok}")
cli_alert_info("Pase 2 (tipo no-Album): {p2_ok}")
cli_alert_info("Pase 3 (sello NA/[no label]): {p3_ok}")
cli_alert_info("Corre diagnostico_musicbrainz_v2.R para ver el estado actual")
