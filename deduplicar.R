# ============================================================================
# deduplicar.R — Detectar y marcar álbumes duplicados en el caché
# Proyecto Discoteca | tomgc
# ============================================================================
#
# QUÉ HACE:
#   1. Agrupa álbumes por artista + nombre normalizado (case-insensitive)
#   2. Si hay duplicados, conserva el que tiene más scrobbles
#   3. Los demás se marcan con _duplicado_de = {id_ganador}
#      y categoria = "descartado" (no se borran del caché — P1)
#
# MATCHING FUZZY (v5):
#   El nombre del álbum se normaliza eliminando sufijos comunes que indican
#   variantes del mismo disco: (Re-Issue), (Remaster), (Remastered),
#   (Deluxe), (Deluxe Edition), (Expanded Edition), (Anniversary Edition),
#   (Special Edition), (Bonus Track Version), etc.
#   Así "No Control" y "No Control (Re-Issue)" se agrupan juntos.
#
# CUÁNDO CORRER: una vez, o después de agregar muchos discos nuevos.
#   Después correr construir.R para regenerar el catálogo.
#
# MODO: por defecto corre en modo diagnóstico (solo reporta).
#   Cambiar APLICAR_CAMBIOS a TRUE para marcar los duplicados.
#
# PAQUETES: install.packages(c("jsonlite", "cli", "here"))
# ============================================================================

source(here::here("utils.R"))

# --- Configuración -----------------------------------------------------------

# Cambiar a TRUE para aplicar los cambios al caché
APLICAR_CAMBIOS <- TRUE

# Sufijos que se eliminan del nombre del álbum para agrupar variantes.
# El orden no importa; se aplican todos.
# Cada patrón se prueba entre paréntesis, corchetes o sin delimitadores al final.
# Ejemplo: "No Control (Re-Issue)" → "No Control"
#          "OK Computer OKNOTOK 1997 2017" no matchea (no tiene sufijo conocido)
SUFIJOS_VARIANTE <- c(
  "re-issue", "reissue", "re issue",
  "remaster", "remastered",
  "deluxe", "deluxe edition", "deluxe version",
  "expanded edition", "expanded",
  "special edition", "special",
  "anniversary edition",
  "\\d+th anniversary edition",   # 20th Anniversary Edition, etc.
  "\\d+th anniversary",
  "bonus track version", "bonus tracks version", "bonus tracks",
  "super deluxe", "super deluxe edition",
  "complete edition",
  "legacy edition",
  "collector'?s edition",
  "international version",
  "explicit"
)

# --- Funciones ---------------------------------------------------------------

#' Normaliza el nombre de un álbum para comparación.
#' Elimina sufijos de variantes (entre paréntesis, corchetes o sueltos al final),
#' convierte a minúsculas, y limpia espacios.
#'
#' Analogía: es como quitar las etiquetas de "edición especial" de la carátula
#' para ver si debajo es el mismo disco.
#'
#' @param nombre Nombre del álbum (character).
#' @return Nombre normalizado (character).
normalizar_nombre <- function(nombre) {
  n <- trimws(tolower(nombre))

  # Construir patrón regex: matchea cada sufijo entre (), [] o suelto al final
  # Ejemplo: "(Re-Issue)" o "[Remastered]" o " - Remastered" o "Remastered"
  for (sufijo in SUFIJOS_VARIANTE) {
    # Entre paréntesis: "Album (Re-Issue)"
    n <- gsub(paste0("\\s*\\(\\s*", sufijo, "\\s*\\)"), "", n, perl = TRUE)
    # Entre corchetes: "Album [Remastered]"
    n <- gsub(paste0("\\s*\\[\\s*", sufijo, "\\s*\\]"), "", n, perl = TRUE)
    # Con guión: "Album - Remastered"
    n <- gsub(paste0("\\s*-\\s*", sufijo, "\\s*$"), "", n, perl = TRUE)
  }

  # Limpiar espacios múltiples y trailing
  trimws(gsub("\\s+", " ", n))
}

#' Clave de agrupación: artista + album normalizado.
#' safe_str maneja NULL, NA, list() vacía y character(0) → escalar character.
clave_album <- function(entry) {
  artista <- trimws(tolower(safe_str(entry$artista)))
  album   <- normalizar_nombre(safe_str(entry$album))
  paste(artista, album, sep = " — ")
}

#' Scrobbles del álbum (para decidir cuál conservar).
#' safe_num garantiza escalar numérico — el get_scrobbles se usa en
#' vapply(..., numeric(1)) que falla si recibe list().
get_scrobbles <- function(entry) {
  safe_num(entry$lastfm$scrobbles_totales, 0L)
}

# --- Main --------------------------------------------------------------------

main <- function() {
  cli_h1("Discoteca — Deduplicar álbumes")

  cache <- leer_cache()
  keys <- names(cache$albumes)
  cli_alert_info("Álbumes en caché: {length(keys)}")

  # Excluir los que ya están marcados como duplicados
  ya_marcados <- sum(vapply(keys, \(k) {
    !is.null(cache$albumes[[k]]$`_duplicado_de`)
  }, logical(1)))
  if (ya_marcados > 0) {
    cli_alert_info("Ya marcados como duplicados: {ya_marcados}")
  }

  # Agrupar por clave (con normalización fuzzy)
  grupos <- list()
  for (k in keys) {
    entry <- cache$albumes[[k]]
    # Saltar los que ya están marcados
    if (!is.null(entry$`_duplicado_de`)) next
    cl <- clave_album(entry)
    if (is.null(grupos[[cl]])) grupos[[cl]] <- list()
    grupos[[cl]] <- c(grupos[[cl]], list(list(key = k, entry = entry)))
  }

  # Filtrar solo los que tienen más de 1 entrada
  duplicados <- Filter(\(g) length(g) > 1, grupos)

  if (length(duplicados) == 0) {
    cli_alert_success("No se encontraron duplicados nuevos")
    return(invisible(NULL))
  }

  cli_alert_warning("Grupos con duplicados: {length(duplicados)}")
  cli_text("")

  # Procesar cada grupo
  total_a_marcar <- 0
  decisiones <- list()  # lista de list(ganar = key, descartar = c(keys))

  for (cl in names(duplicados)) {
    grupo <- duplicados[[cl]]

    # Ordenar por scrobbles descendente — el primero gana
    scrobbles <- vapply(grupo, \(g) get_scrobbles(g$entry), numeric(1))
    orden <- order(scrobbles, decreasing = TRUE)
    grupo <- grupo[orden]
    scrobbles <- scrobbles[orden]

    ganador <- grupo[[1]]
    perdedores <- grupo[-1]

    # Reportar
    cli_text(cli::col_cyan(cl))
    cli_text("  {cli::col_green('\u2713')} {ganador$entry$album} [{ganador$key}] ({scrobbles[1]} scrobbles) — conservar")
    for (i in seq_along(perdedores)) {
      p <- perdedores[[i]]
      s <- scrobbles[i + 1]
      anio_g <- ganador$entry$anio %||% "?"
      anio_p <- p$entry$anio %||% "?"
      tracks_g <- ganador$entry$num_tracks %||% "?"
      tracks_p <- p$entry$num_tracks %||% "?"

      diferencias <- c()
      if (anio_g != anio_p) diferencias <- c(diferencias, paste0("año: ", anio_p, " vs ", anio_g))
      if (tracks_g != tracks_p) diferencias <- c(diferencias, paste0("tracks: ", tracks_p, " vs ", tracks_g))
      # Mostrar el nombre original si difiere del ganador (útil para ver qué sufijo se normalizó)
      if (tolower(p$entry$album) != tolower(ganador$entry$album)) {
        diferencias <- c(diferencias, paste0("nombre: \"", p$entry$album, "\""))
      }
      dif_str <- if (length(diferencias) > 0) paste0(" [", paste(diferencias, collapse = ", "), "]") else ""

      cli_text("  {cli::col_red('\u00d7')} {p$entry$album} [{p$key}] ({s} scrobbles){dif_str} — descartar")
    }

    decisiones <- c(decisiones, list(list(
      ganador = ganador$key,
      descartar = vapply(perdedores, \(p) p$key, character(1))
    )))
    total_a_marcar <- total_a_marcar + length(perdedores)
  }

  cli_text("")
  cli_alert_info("Total a marcar como duplicado: {total_a_marcar}")

  # Aplicar cambios si está habilitado
  if (!APLICAR_CAMBIOS) {
    cli_alert_info("Modo diagnóstico — no se aplicaron cambios")
    cli_alert_info("Cambia APLICAR_CAMBIOS <- TRUE y vuelve a correr para aplicar")
    return(invisible(NULL))
  }

  cli_h2("Aplicando cambios")
  n_marcados <- 0

  for (dec in decisiones) {
    for (k in dec$descartar) {
      cache$albumes[[k]]$`_duplicado_de` <- dec$ganador
      # Marcar como descartado (se oculta en modo Collection)
      if (is.null(cache$albumes[[k]]$personal)) {
        cache$albumes[[k]]$personal <- list()
      }
      cache$albumes[[k]]$personal$categoria <- "descartado"
      n_marcados <- n_marcados + 1
    }
  }

  # Guardar caché (P4 — escritura atómica vía utils.R)
  guardar_cache(cache)

  cli_alert_success("{n_marcados} álbumes marcados como duplicados")
  cli_alert_info("Corre construir.R para regenerar el catálogo")
}

# Guard: ver construir.R para explicación.
if (!isTRUE(getOption("discoteca.load_only"))) main()
