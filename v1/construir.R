# ============================================================================
# construir.R — Generar catálogo final desde el caché
# Proyecto Discoteca | tomgc
# ============================================================================
#
# QUÉ HACE:
#   1. Lee music_cache.json con datos de las 3 fuentes
#   2. Re-importa ediciones web si existen (rating, notas, tags)
#   3. Aplana → catalogo.json (para la web) + catalogo_musica.csv (Excel/R)
#
# CUÁNDO CORRER: después de spotify.R, lastfm.R, musicbrainz.R,
#   o después de importar ediciones desde la web.
#
# PAQUETES: install.packages(c("jsonlite", "cli"))
# ============================================================================

library(jsonlite)
library(cli)

# --- Configuración ----------------------------------------------------------

RUTA_CACHE    <- file.path("datos", "music_cache.json")
RUTA_CATALOGO <- file.path("datos", "catalogo.json")
RUTA_CSV      <- file.path("datos", "catalogo_musica.csv")
RUTA_WEB_EDIT <- file.path("datos", "ediciones_web.json")

# --- Funciones --------------------------------------------------------------

leer_cache <- function(ruta) {
  if (!file.exists(ruta)) cli_abort("Caché no encontrado en {ruta}")
  fromJSON(ruta, simplifyVector = FALSE)
}

importar_ediciones_web <- function(cache, ruta) {
  if (!file.exists(ruta)) return(cache)

  cli_alert_info("Importando ediciones web: {ruta}")
  ediciones <- tryCatch(fromJSON(ruta, simplifyVector = FALSE), error = function(e) {
    cli_alert_warning("No se pudo leer: {e$message}"); NULL
  })
  if (is.null(ediciones)) return(cache)

  n <- 0
  for (entry in ediciones) {
    id <- entry$id
    if (is.null(id) || !(id %in% names(cache$albumes))) next
    if (!is.null(entry$rating))       cache$albumes[[id]]$personal$rating       <- entry$rating
    if (!is.null(entry$favorito))     cache$albumes[[id]]$personal$favorito     <- entry$favorito
    if (!is.null(entry$notas))        cache$albumes[[id]]$personal$notas        <- entry$notas
    if (!is.null(entry$tags_propios)) cache$albumes[[id]]$personal$tags_propios <- entry$tags_propios
    n <- n + 1
  }
  cli_alert_success("{n} ediciones importadas")
  cache
}

aplanar_album <- function(key, entry) {
  tryCatch(
    list(
      id                 = key,
      artista            = entry$artista %||% "",
      album              = entry$album %||% "",
      anio               = entry$anio %||% 0L,
      fecha_lanzamiento  = entry$fecha_lanzamiento %||% "",
      fecha_precision    = entry$fecha_precision %||% "year",
      sello              = entry$musicbrainz$sello %||% NA,
      pais               = entry$musicbrainz$pais %||% NA,
      num_tracks         = entry$num_tracks %||% 0L,
      duracion_total_min = entry$duracion_total_min %||% 0,
      artwork_url        = entry$artwork_url %||% "",
      generos            = entry$generos %||% list(),
      scrobbles          = entry$lastfm$scrobbles_totales %||% 0L,
      primer_scrobble    = entry$lastfm$primer_scrobble %||% NA,
      tags_lastfm        = entry$lastfm$tags_lastfm %||% list(),
      rating             = entry$personal$rating %||% 0L,
      favorito           = entry$personal$favorito %||% FALSE,
      notas              = entry$personal$notas %||% "",
      tags_propios       = entry$personal$tags_propios %||% list(),
      fecha_agregado     = entry$personal$fecha_agregado %||% format(Sys.Date())
    ),
    error = function(e) {
      cli_alert_warning("Error aplanando {key}: {e$message}")
      NULL
    }
  )
}

colapsar <- function(x) {
  if (is.null(x) || length(x) == 0) return("")
  paste(unlist(x), collapse = "; ")
}

# Extracción segura para sapply — devuelve "" si falla
safe_get <- function(x, field, default = "") {
  tryCatch(x[[field]] %||% default, error = function(e) default)
}

# --- Main -------------------------------------------------------------------

main <- function() {
  cli_h1("Discoteca — Construir catálogo")

  cache <- leer_cache(RUTA_CACHE)
  cli_alert_info("Álbumes en caché: {length(cache$albumes)}")

  cache <- importar_ediciones_web(cache, RUTA_WEB_EDIT)

  # Aplanar (filtra NULLs de álbumes con estructura corrupta)
  catalogo <- Filter(Negate(is.null), lapply(names(cache$albumes), function(key) {
    aplanar_album(key, cache$albumes[[key]])
  }))

  # Ordenar por artista, luego año
  catalogo <- catalogo[order(
    sapply(catalogo, \(x) tolower(x$artista)),
    sapply(catalogo, \(x) x$anio)
  )]

  cli_alert_info("Álbumes en catálogo: {length(catalogo)}")

  # JSON para la web
  write_json(catalogo, RUTA_CATALOGO, pretty = TRUE, auto_unbox = TRUE)
  cli_alert_success("catalogo.json → {length(catalogo)} álbumes")

  # CSV para Excel/R
  tryCatch(
    {
      df <- data.frame(
        id                 = sapply(catalogo, \(x) x$id),
        artista            = sapply(catalogo, \(x) x$artista),
        album              = sapply(catalogo, \(x) x$album),
        anio               = sapply(catalogo, \(x) x$anio),
        fecha_lanzamiento  = sapply(catalogo, \(x) x$fecha_lanzamiento %||% ""),
        fecha_precision    = sapply(catalogo, \(x) x$fecha_precision %||% "year"),
        sello              = sapply(catalogo, \(x) x$sello %||% ""),
        pais               = sapply(catalogo, \(x) x$pais %||% ""),
        num_tracks         = sapply(catalogo, \(x) x$num_tracks),
        duracion_total_min = sapply(catalogo, \(x) x$duracion_total_min),
        scrobbles          = sapply(catalogo, \(x) x$scrobbles),
        primer_scrobble    = sapply(catalogo, \(x) x$primer_scrobble %||% ""),
        rating             = sapply(catalogo, \(x) x$rating),
        favorito           = sapply(catalogo, \(x) x$favorito),
        generos            = sapply(catalogo, \(x) colapsar(x$generos)),
        tags_lastfm        = sapply(catalogo, \(x) colapsar(x$tags_lastfm)),
        tags_propios       = sapply(catalogo, \(x) colapsar(x$tags_propios)),
        notas              = sapply(catalogo, \(x) x$notas),
        fecha_agregado     = sapply(catalogo, \(x) x$fecha_agregado),
        stringsAsFactors   = FALSE
      )
      write.csv(df, RUTA_CSV, row.names = FALSE, fileEncoding = "UTF-8")
      cli_alert_success("catalogo_musica.csv generado")
    },
    error = function(e) {
      cli_alert_danger("Error generando CSV: {e$message}")
      cli_alert_info("El catalogo.json se generó correctamente — el CSV falló.")
    }
  )

  # Guardar caché actualizado
  cache$`_meta`$ultima_actualizacion <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  write_json(cache, RUTA_CACHE, pretty = TRUE, auto_unbox = TRUE)

  # Reporte
  cli_h2("Resumen")
  n_scrobbles <- sum(sapply(catalogo, \(x) x$scrobbles > 0))
  n_sello     <- sum(sapply(catalogo, \(x) !is.na(x$sello) && x$sello != ""))
  n_fecha     <- sum(sapply(catalogo, \(x) x$fecha_precision == "day"))
  n_fav       <- sum(sapply(catalogo, \(x) isTRUE(x$favorito)))
  n_rating    <- sum(sapply(catalogo, \(x) x$rating > 0))

  cli_alert_info("Con scrobbles: {n_scrobbles} | Con sello: {n_sello} | Con fecha exacta: {n_fecha}")
  cli_alert_info("Con rating: {n_rating} | Favoritos: {n_fav}")
}

main()
