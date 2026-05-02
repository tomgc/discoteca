# ============================================================================
# fix_lastfm_errors.R — Re-procesar álbumes que fallaron en Last.fm
# ============================================================================
# Busca álbumes cuyo bloque lastfm tiene una nota de error,
# limpia su fecha_consulta para que lastfm.R los re-intente,
# y corre lastfm.R automáticamente.
# ============================================================================

library(jsonlite)
library(cli)

cache <- fromJSON("datos/music_cache.json", simplifyVector = FALSE)

# Encontrar los que tienen nota de error
con_error <- names(Filter(
  \(a) grepl("Error:", a$lastfm$nota %||% "", fixed = TRUE),
  cache$albumes
))

cli_alert_info("Álbumes con error: {length(con_error)}")

if (length(con_error) == 0) {
  cli_alert_success("No hay errores que corregir")
} else {
  # Limpiar su bloque lastfm para que lastfm.R los re-intente
  for (key in con_error) {
    cli_alert("  Limpiando: {cache$albumes[[key]]$artista} — {cache$albumes[[key]]$album}")
    cache$albumes[[key]]$lastfm <- list()
  }

  write_json(cache, "datos/music_cache.json", pretty = TRUE, auto_unbox = TRUE)
  cli_alert_success("Listos para re-procesar")

  # Correr lastfm.R
  cli_h2("Re-procesando con Last.fm...")
  source("lastfm.R")
}
