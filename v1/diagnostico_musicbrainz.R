# diagnostico_musicbrainz.R — Listar problemas pendientes de MusicBrainz

source(here::here("utils.R"))

cache <- leer_cache()

# 1. No encontrados
no_enc <- names(Filter(
  \(a) !is.null(a$musicbrainz$nota) && grepl("No encontrado", a$musicbrainz$nota),
  cache$albumes
))

# 2. Sello NA
sello_na <- names(Filter(
  \(a) !is.null(a$musicbrainz$fecha_consulta) &&
       (is.null(a$musicbrainz$sello) || is.na(a$musicbrainz$sello)),
  cache$albumes
))

# 3. Tipo != Album
no_album <- names(Filter(
  \(a) !is.null(a$musicbrainz$tipo) &&
       !is.na(a$musicbrainz$tipo) &&
       !(a$musicbrainz$tipo %in% c("Album")),
  cache$albumes
))

cli_h2("No encontrados")
for (k in no_enc) cli_alert_warning("{cache$albumes[[k]]$artista} — {cache$albumes[[k]]$album}")
cli_alert_info("Total: {length(no_enc)}")

cli_h2("Sello NA")
for (k in sello_na) {
  a <- cache$albumes[[k]]
  cli_alert_warning("{a$artista} — {a$album} | tipo: {a$musicbrainz$tipo %||% '?'}")
}
cli_alert_info("Total: {length(sello_na)}")

cli_h2("Tipo no-Album")
for (k in no_album) {
  a <- cache$albumes[[k]]
  cli_alert_warning("{a$artista} — {a$album} | tipo: {a$musicbrainz$tipo}")
}
cli_alert_info("Total: {length(no_album)}")
