# ============================================================================
# restaurar_cache.R — Recuperar music_cache.json desde el último backup
# ============================================================================
#
# El pipeline programado sube music_cache.json comprimido como artifact
# del workflow (retención 90 días). Este script lo descarga y restaura.
#
# REQUIERE: gh CLI autenticado (gh auth status)
#
# USO:
#   Rscript restaurar_cache.R                   # descarga el más reciente
#   Rscript restaurar_cache.R --run-id 123456   # de una corrida específica
#
# Si tienes BACKUP_GIST_ID configurado, alternativamente:
#   gh gist view $BACKUP_GIST_ID --files music_cache.json.gz.b64 \
#     | base64 -d > music_cache.json.gz && gunzip music_cache.json.gz
# ============================================================================

suppressPackageStartupMessages({
  library(cli)
  library(here)
})

args   <- commandArgs(trailingOnly = TRUE)
run_id <- NULL
i <- 1
while (i <= length(args)) {
  if (args[[i]] == "--run-id" && i < length(args)) {
    run_id <- args[[i + 1]]; i <- i + 2
  } else { i <- i + 1 }
}

destino <- here("datos", "music_cache.json")

if (file.exists(destino)) {
  msg <- sprintf("Ya existe %s. ¿Sobrescribir? (s/N): ", destino)
  resp <- tolower(trimws(readline(msg)))
  if (!resp %in% c("s", "si", "y", "yes")) {
    cli_alert_info("Cancelado.")
    quit(status = 0)
  }
  backup <- paste0(destino, ".bak.", format(Sys.time(), "%Y%m%d-%H%M%S"))
  file.copy(destino, backup)
  cli_alert_info("Backup local: {basename(backup)}")
}

# Buscar el último artifact si no se especificó run-id
if (is.null(run_id)) {
  cli_alert_info("Buscando última corrida exitosa de Pipeline...")
  out <- system2("gh", c("run", "list",
                         "-R", "tomgc/discoteca",
                         "-w", "Pipeline (scheduled)",
                         "-s", "success",
                         "-L", "1",
                         "--json", "databaseId",
                         "-q", ".[0].databaseId"),
                 stdout = TRUE)
  if (length(out) == 0 || out == "") {
    cli_alert_danger("No se encontró ninguna corrida exitosa.")
    quit(status = 1)
  }
  run_id <- out
  cli_alert_info("Run ID: {run_id}")
}

tmpdir <- tempfile("cache-restore-")
dir.create(tmpdir)
on.exit(unlink(tmpdir, recursive = TRUE))

cli_alert_info("Descargando artifact...")
status <- system2("gh", c("run", "download", run_id,
                          "-R", "tomgc/discoteca",
                          "-D", tmpdir))
if (status != 0) {
  cli_alert_danger("Fallo al descargar artifact.")
  quit(status = 1)
}

gz <- list.files(tmpdir, pattern = "\\.gz$", recursive = TRUE, full.names = TRUE)
if (length(gz) == 0) {
  cli_alert_danger("No se encontró music_cache.json.gz en el artifact.")
  quit(status = 1)
}

cli_alert_info("Descomprimiendo {basename(gz[[1]])}...")
con  <- gzfile(gz[[1]], "rb")
data <- readBin(con, raw(), file.info(gz[[1]])$size * 20)
close(con)
writeBin(data, destino)

cli_alert_success("Cache restaurado en {destino}")
cli_alert_info("Tamaño: {round(file.info(destino)$size / 1024 / 1024, 1)} MB")
