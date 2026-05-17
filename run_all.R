# ============================================================================
# run_all.R — Entrada única del pipeline Discoteca
# ============================================================================
#
# USO desde R:
#   source("run_all.R")
#   run_all()
#   run_all(skip = c("spotify", "musicbrainz"))   # solo Last.fm + construir
#   run_all(only = "wikipedia")                   # solo Wikipedia + construir
#
# USO desde shell:
#   Rscript run_all.R                              # corre todo
#   Rscript run_all.R --skip spotify,musicbrainz   # salta etapas
#   Rscript run_all.R --only wikipedia             # solo una etapa (+construir)
#   Rscript run_all.R --dedup                      # incluye deduplicar.R
#
# Etapas (en orden):
#   spotify → lastfm → musicbrainz → wikipedia → [dedup] → construir
#
# Siempre carga .Renviron si existe.
# ============================================================================

ETAPAS_DEFAULT <- c("spotify", "lastfm", "musicbrainz", "wikipedia", "construir")

#' Calcula qué etapas correr a partir de los flags. Función pura, testeable.
#' - only > skip > defaults
#' - "construir" se garantiza al final si --only se usa (se necesita para
#'   regenerar el catálogo después de cualquier enrichment).
#' - dedup se inserta justo antes de "construir" (después de wikipedia
#'   si existe; si no, justo antes de "construir").
calcular_etapas <- function(skip = character(0), only = NULL, dedup = FALSE,
                            defaults = ETAPAS_DEFAULT) {
  etapas <- if (!is.null(only)) {
    unique(c(only, "construir"))
  } else {
    setdiff(defaults, skip)
  }

  if (isTRUE(dedup)) {
    etapas <- append(etapas, "deduplicar",
                     after = match("wikipedia", etapas, nomatch = length(etapas) - 1))
  }

  etapas
}

run_all <- function(skip = character(0), only = NULL, dedup = FALSE) {
  if (file.exists(".Renviron")) readRenviron(".Renviron")

  library(cli)

  etapas <- calcular_etapas(skip = skip, only = only, dedup = dedup)

  cli_h1("Discoteca — Pipeline completo")
  cli_alert_info("Etapas: {paste(etapas, collapse = ' → ')}")
  inicio <- Sys.time()

  for (etapa in etapas) {
    archivo <- paste0(etapa, ".R")
    if (!file.exists(archivo)) {
      cli_alert_warning("Etapa '{etapa}' omitida: {archivo} no existe")
      next
    }
    cli_h2(toupper(etapa))
    t0 <- Sys.time()
    tryCatch(
      source(archivo, local = new.env()),
      error = function(e) {
        cli_alert_danger("Etapa '{etapa}' falló: {e$message}")
        stop(e)
      }
    )
    elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
    cli_alert_success("Etapa '{etapa}' OK ({round(elapsed, 1)} min)")
  }

  total <- as.numeric(difftime(Sys.time(), inicio, units = "mins"))
  cli_h1("Pipeline completado en {round(total, 1)} min")
  invisible(TRUE)
}


# ── CLI: parseo de argumentos para Rscript ─────────────────────────────────

#' Parsea args de commandArgs. Función pura — devuelve lista de flags o
#' aborta con clase de condición. Permite tests sin invocar quit().
#'
#' @return list(skip, only, dedup, help) — o stop() con clase "discoteca_cli_error"
parsear_args <- function(args) {
  skip  <- character(0)
  only  <- NULL
  dedup <- FALSE
  help  <- FALSE

  i <- 1
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--skip" && i < length(args)) {
      skip <- strsplit(args[[i + 1]], ",", fixed = TRUE)[[1]]
      i <- i + 2
    } else if (a == "--only" && i < length(args)) {
      only <- args[[i + 1]]
      i <- i + 2
    } else if (a == "--dedup") {
      dedup <- TRUE
      i <- i + 1
    } else if (a %in% c("-h", "--help")) {
      help <- TRUE
      i <- i + 1
    } else {
      stop(structure(
        class    = c("discoteca_cli_error", "error", "condition"),
        list(message = paste("Argumento desconocido:", a), call = sys.call())
      ))
    }
  }

  list(skip = skip, only = only, dedup = dedup, help = help)
}

if (!interactive() && sys.nframe() == 0L) {
  parsed <- tryCatch(
    parsear_args(commandArgs(trailingOnly = TRUE)),
    discoteca_cli_error = function(e) {
      message(conditionMessage(e))
      quit(status = 1)
    }
  )

  if (isTRUE(parsed$help)) {
    cat("Uso: Rscript run_all.R [--skip a,b,c] [--only etapa] [--dedup]\n")
    cat("Etapas: spotify, lastfm, musicbrainz, wikipedia, construir\n")
    quit(status = 0)
  }

  run_all(skip = parsed$skip, only = parsed$only, dedup = parsed$dedup)
}
