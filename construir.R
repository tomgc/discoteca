# ============================================================================
# construir.R — Generar catálogo final desde el caché
# Proyecto Discoteca | tomgc
# ============================================================================
#
# QUÉ HACE:
#   1. Lee music_cache.json con datos de las 3 fuentes
#   2. Re-importa ediciones web si existen (categoria, notas, tags)
#   3. Aplana → catalogo.json (para la web) + catalogo_musica.csv (Excel/R)
#
# CUÁNDO CORRER: después de spotify.R, lastfm.R, musicbrainz.R,
#   o después de importar ediciones desde la web.
#
# PAQUETES: install.packages(c("jsonlite", "cli", "here"))
# ============================================================================

source(here::here("utils.R"))

# --- Funciones propias de construir.R ---------------------------------------

# Migración: rating/favorito → categoria (P11 — lógica centralizada)
# Si el álbum ya tiene categoria, no se toca.
# Si tiene rating/favorito del formato viejo, se convierte.
migrar_a_categoria <- function(personal) {
  if (!is.null(personal$categoria)) return(personal)

  if (isTRUE(personal$favorito)) {
    personal$categoria <- "masterpiece"
  } else if (!is.null(personal$rating) && personal$rating >= 4) {
    personal$categoria <- "great"
  } else if (!is.null(personal$rating) && personal$rating >= 2) {
    personal$categoria <- "good"
  } else {
    personal$categoria <- NULL
  }

  # Limpiar campos viejos
  personal$rating <- NULL
  personal$favorito <- NULL

  personal
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

    # Formato nuevo: categoria
    if (!is.null(entry$categoria)) {
      cache$albumes[[id]]$personal$categoria <- entry$categoria
    }
    # Formato viejo: rating/favorito (migrar)
    if (!is.null(entry$rating)) {
      cache$albumes[[id]]$personal$rating <- entry$rating
    }
    if (!is.null(entry$favorito)) {
      cache$albumes[[id]]$personal$favorito <- entry$favorito
    }
    # Campos compartidos entre ambos formatos
    if (!is.null(entry$notas)) {
      cache$albumes[[id]]$personal$notas <- entry$notas
    }
    if (!is.null(entry$tags_propios)) {
      cache$albumes[[id]]$personal$tags_propios <- entry$tags_propios
    }
    n <- n + 1
  }
  cli_alert_success("{n} ediciones importadas")
  cache
}

aplanar_album <- function(key, entry) {
  tryCatch(
    {
      # Migrar rating/favorito → categoria si corresponde
      personal <- migrar_a_categoria(entry$personal %||% list())

      spotify_id <- entry$id_spotify %||% sub("^spotify:", "", key)
      spotify_url <- if (nchar(spotify_id) > 0) {
        paste0("https://open.spotify.com/album/", spotify_id)
      } else {
        ""
      }

      list(
        id                 = key,
        artista            = entry$artista %||% "",
        album              = entry$album %||% "",
        anio               = entry$anio %||% 0L,
        fecha_lanzamiento  = entry$fecha_lanzamiento %||% "",
        fecha_precision    = entry$fecha_precision %||% "year",
        sello              = entry$musicbrainz$sello %||% "",
        pais               = entry$musicbrainz$pais %||% "",
        num_tracks         = entry$num_tracks %||% 0L,
        duracion_total_min = entry$duracion_total_min %||% 0,
        artwork_url        = entry$artwork_url %||% "",
        spotify_url        = spotify_url,
        generos            = entry$generos %||% list(),
        scrobbles          = entry$lastfm$scrobbles_totales %||% 0L,
        primer_scrobble    = entry$lastfm$primer_scrobble %||% "",
        tags_lastfm        = entry$lastfm$tags_lastfm %||% list(),
        categoria          = personal$categoria,
        notas              = personal$notas %||% "",
        tags_propios       = personal$tags_propios %||% list(),
        wikipedia_extract  = entry$wikipedia$extract %||% "",
        wikipedia_url      = entry$wikipedia$url %||% "",
        fecha_agregado     = personal$fecha_agregado %||%
                             entry$personal$fecha_agregado %||%
                             format(Sys.Date())
      )
    },
    error = function(e) {
      cli_alert_warning("Error aplanando {key}: {e$message}")
      NULL
    }
  )
}

# --- Main -------------------------------------------------------------------

main <- function() {
  cli_h1("Discoteca — Construir catálogo")

  cache <- leer_cache()
  cli_alert_info("Álbumes en caché: {length(cache$albumes)}")

  cache <- importar_ediciones_web(cache, RUTA_WEB_EDIT)

  # Aplanar (filtra NULLs de álbumes con estructura corrupta)
  catalogo <- Filter(Negate(is.null), lapply(names(cache$albumes), function(key) {
    aplanar_album(key, cache$albumes[[key]])
  }))

  # Ordenar por artista, luego año
  catalogo <- catalogo[order(
    vapply(catalogo, \(x) tolower(x$artista), character(1)),
    vapply(catalogo, \(x) safe_num(x$anio, 0L), numeric(1))
  )]

  cli_alert_info("Álbumes en catálogo: {length(catalogo)}")

  # --- JSON para la web (P4 — escritura atómica, P10 — auto_unbox) -----------
  guardar_json(catalogo, RUTA_CATALOGO, pretty = TRUE, auto_unbox = TRUE)
  cli_alert_success("catalogo.json → {length(catalogo)} álbumes")

  # --- CSV para Excel/R (vapply con tipo fijo para evitar sapply bugs) --------
  tryCatch(
    {
      df <- data.frame(
        id                 = vapply(catalogo, \(x) safe_str(x$id),                 character(1)),
        artista            = vapply(catalogo, \(x) safe_str(x$artista),             character(1)),
        album              = vapply(catalogo, \(x) safe_str(x$album),               character(1)),
        anio               = vapply(catalogo, \(x) safe_num(x$anio, 0L),            numeric(1)),
        fecha_lanzamiento  = vapply(catalogo, \(x) safe_str(x$fecha_lanzamiento),   character(1)),
        fecha_precision    = vapply(catalogo, \(x) safe_str(x$fecha_precision),      character(1)),
        sello              = vapply(catalogo, \(x) safe_str(x$sello),               character(1)),
        pais               = vapply(catalogo, \(x) safe_str(x$pais),                character(1)),
        num_tracks         = vapply(catalogo, \(x) safe_num(x$num_tracks, 0L),      numeric(1)),
        duracion_total_min = vapply(catalogo, \(x) safe_num(x$duracion_total_min),  numeric(1)),
        spotify_url        = vapply(catalogo, \(x) safe_str(x$spotify_url),         character(1)),
        scrobbles          = vapply(catalogo, \(x) safe_num(x$scrobbles, 0L),       numeric(1)),
        primer_scrobble    = vapply(catalogo, \(x) safe_str(x$primer_scrobble),     character(1)),
        categoria          = vapply(catalogo, \(x) safe_str(x$categoria),           character(1)),
        generos            = vapply(catalogo, \(x) colapsar(x$generos),             character(1)),
        tags_lastfm        = vapply(catalogo, \(x) colapsar(x$tags_lastfm),         character(1)),
        tags_propios       = vapply(catalogo, \(x) colapsar(x$tags_propios),        character(1)),
        notas              = vapply(catalogo, \(x) safe_str(x$notas),               character(1)),
        fecha_agregado     = vapply(catalogo, \(x) safe_str(x$fecha_agregado),      character(1)),
        stringsAsFactors   = FALSE
      )
      guardar_csv(df, RUTA_CSV)
      cli_alert_success("catalogo_musica.csv → {nrow(df)} filas")
    },
    error = function(e) {
      cli_alert_danger("Error generando CSV: {e$message}")
      cli_alert_info("El catalogo.json se generó correctamente — el CSV falló.")
    }
  )

  # Guardar caché actualizado (P4 — escritura atómica)
  guardar_cache(cache)

  # --- Reporte ---------------------------------------------------------------
  cli_h2("Resumen")
  n_scrobbles  <- sum(vapply(catalogo, \(x) safe_num(x$scrobbles) > 0, logical(1)))
  n_sello      <- sum(vapply(catalogo, \(x) safe_str(x$sello) != "", logical(1)))
  n_fecha      <- sum(vapply(catalogo, \(x) identical(x$fecha_precision, "day"), logical(1)))
  n_cat        <- sum(vapply(catalogo, \(x) !is.null(x$categoria), logical(1)))
  n_master     <- sum(vapply(catalogo, \(x) identical(x$categoria, "masterpiece"), logical(1)))
  n_great      <- sum(vapply(catalogo, \(x) identical(x$categoria, "great"), logical(1)))
  n_good       <- sum(vapply(catalogo, \(x) identical(x$categoria, "good"), logical(1)))
  n_descartado <- sum(vapply(catalogo, \(x) identical(x$categoria, "descartado"), logical(1)))
  n_spotify    <- sum(vapply(catalogo, \(x) safe_str(x$spotify_url) != "", logical(1)))

  cli_alert_info("Scrobbles: {n_scrobbles} | Sello: {n_sello} | Fecha exacta: {n_fecha} | Spotify URL: {n_spotify}")
  cli_alert_info("Clasificados: {n_cat} (masterpiece: {n_master}, great: {n_great}, good: {n_good}, descartado: {n_descartado})")
}

main()
