# diagnostico_musicbrainz_v2.R — Estado actual de MusicBrainz

source(here::here("utils.R"))

cache <- leer_cache()
todas <- names(cache$albumes)

no_enc <- c(); sello_na <- c(); no_label <- c(); no_album <- c()

for (k in todas) {
  mb <- cache$albumes[[k]]$musicbrainz
  if (is.null(mb) || length(mb) == 0) next
  nota <- mb$nota %||% ""
  sello <- mb$sello
  if (is.null(sello) || length(sello) == 0) sello <- NA_character_
  tipo <- mb$tipo
  if (is.null(tipo) || length(tipo) == 0) tipo <- NA_character_

  if (grepl("No encontrado", nota)) {
    no_enc <- c(no_enc, k)
  } else {
    if (is.na(sello) || sello == "") sello_na <- c(sello_na, k)
    if (!is.na(sello) && sello == "[no label]") no_label <- c(no_label, k)
    if (!is.na(tipo) && tipo != "Album") no_album <- c(no_album, k)
  }
}

cli_h1("Diagnóstico MusicBrainz")
cli_alert_info("Total: {length(todas)}")
cli_alert_info("No encontrados: {length(no_enc)}")
cli_alert_info("Sello NA/vacío: {length(sello_na)}")
cli_alert_info("Sello [no label]: {length(no_label)}")
cli_alert_info("Tipo no-Album: {length(no_album)}")

if (length(no_enc) > 0) {
  cli_h2("No encontrados")
  for (k in no_enc) cli_alert_warning("{cache$albumes[[k]]$artista} — {cache$albumes[[k]]$album}")
}
if (length(sello_na) > 0) {
  cli_h2("Sello NA/vacío")
  for (k in sello_na) {
    a <- cache$albumes[[k]]
    cli_alert_warning("{a$artista} — {a$album} | tipo: {a$musicbrainz$tipo %||% '?'}")
  }
}
if (length(no_label) > 0) {
  cli_h2("Sello [no label]")
  for (k in no_label) cli_alert_warning("{cache$albumes[[k]]$artista} — {cache$albumes[[k]]$album}")
}
