# ============================================================================
# importar_ediciones.R — Importar ediciones exportadas desde el navegador
# ============================================================================
#
# QUÉ HACE:
#   1. Busca el archivo de ediciones más reciente en ~/Downloads
#      (patrón configurable, por defecto: "discoteca-ediciones*.json")
#   2. Lo valida (estructura, ids únicos, categorías legales)
#   3. Hace backup del datos/ediciones_web.json actual
#   4. Mueve el archivo a datos/ediciones_web.json
#   5. Sugiere correr construir.R
#
# USO:
#   Rscript importar_ediciones.R                     # busca y mueve
#   Rscript importar_ediciones.R --archivo ~/x.json  # archivo específico
#   Rscript importar_ediciones.R --dry-run           # solo validar
#
# ============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(cli)
  library(here)
})

source(here("utils.R"))

PATRON_DEFAULT <- "discoteca.*ediciones.*\\.json$"
DIR_DOWNLOADS  <- path.expand("~/Downloads")


buscar_archivo_mas_reciente <- function(dir = DIR_DOWNLOADS, patron = PATRON_DEFAULT) {
  archivos <- list.files(dir, pattern = patron, full.names = TRUE, ignore.case = TRUE)
  if (length(archivos) == 0) return(NULL)
  archivos[order(file.info(archivos)$mtime, decreasing = TRUE)][[1]]
}

validar_ediciones <- function(ediciones) {
  if (!is.list(ediciones) || length(ediciones) == 0) {
    cli_alert_danger("Estructura inválida: no es lista o está vacía")
    return(FALSE)
  }

  ids <- vapply(ediciones, \(e) e$id %||% NA_character_, character(1))
  if (anyNA(ids)) {
    cli_alert_danger("Hay entradas sin 'id'")
    return(FALSE)
  }
  if (anyDuplicated(ids)) {
    duplicados <- unique(ids[duplicated(ids)])
    cli_alert_danger("IDs duplicados: {paste(head(duplicados, 5), collapse = ', ')}")
    return(FALSE)
  }

  cats <- unique(unlist(lapply(ediciones, \(e) e$categoria)))
  cats <- cats[!is.null(cats)]
  ilegales <- setdiff(cats, CATEGORIAS_VALIDAS)
  if (length(ilegales) > 0) {
    cli_alert_danger("Categorías inválidas: {paste(ilegales, collapse = ', ')}")
    return(FALSE)
  }

  cli_alert_success("Validación OK: {length(ediciones)} entradas, {length(cats)} categorías distintas")
  TRUE
}

importar <- function(origen, dry_run = FALSE) {
  if (!file.exists(origen)) {
    cli_alert_danger("Archivo no existe: {origen}")
    return(invisible(FALSE))
  }

  cli_alert_info("Origen: {origen}")
  ediciones <- tryCatch(
    fromJSON(origen, simplifyVector = FALSE),
    error = function(e) {
      cli_alert_danger("JSON inválido: {e$message}")
      NULL
    }
  )
  if (is.null(ediciones)) return(invisible(FALSE))

  if (!validar_ediciones(ediciones)) {
    return(invisible(FALSE))
  }

  if (dry_run) {
    cli_alert_info("--dry-run: no se modifica nada")
    return(invisible(TRUE))
  }

  destino <- RUTA_WEB_EDIT
  if (file.exists(destino)) {
    backup <- paste0(destino, ".bak.", format(Sys.time(), "%Y%m%d-%H%M%S"))
    file.copy(destino, backup)
    cli_alert_info("Backup: {basename(backup)}")
  }

  # Escritura atómica vía utils.R (preserva el archivo original si write_json falla)
  guardar_json(ediciones, destino, pretty = TRUE, auto_unbox = TRUE)
  cli_alert_success("Importado a: {destino}")
  cli_alert_info("Siguiente paso: source('construir.R') para regenerar catalogo.json")
  invisible(TRUE)
}


# ── CLI ─────────────────────────────────────────────────────────────────────

if (!interactive() && sys.nframe() == 0L) {
  args    <- commandArgs(trailingOnly = TRUE)
  archivo <- NULL
  dry_run <- FALSE

  i <- 1
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--archivo" && i < length(args)) {
      archivo <- args[[i + 1]]; i <- i + 2
    } else if (a == "--dry-run") {
      dry_run <- TRUE; i <- i + 1
    } else if (a %in% c("-h", "--help")) {
      cat("Uso: Rscript importar_ediciones.R [--archivo path] [--dry-run]\n")
      quit(status = 0)
    } else {
      message("Argumento desconocido: ", a); quit(status = 1)
    }
  }

  if (is.null(archivo)) {
    archivo <- buscar_archivo_mas_reciente()
    if (is.null(archivo)) {
      cli_alert_danger("No se encontró archivo en {DIR_DOWNLOADS} (patrón: {PATRON_DEFAULT})")
      quit(status = 1)
    }
  }

  ok <- importar(archivo, dry_run = dry_run)
  quit(status = if (isTRUE(ok)) 0 else 1)
}
