# Tests para construir.R
# Verifica el aplanado del caché → catálogo + la migración rating→categoria.

library(testthat)
library(here)
source(here("utils.R"))

# Carga construir.R sin ejecutar main()
withr::local_options(discoteca.load_only = TRUE)
source(here("construir.R"))


# ── migrar_a_categoria ─────────────────────────────────────────────────────

test_that("migrar_a_categoria preserva categoria si ya existe", {
  res <- migrar_a_categoria(list(categoria = "great"))
  expect_identical(res$categoria, "great")
})

test_that("migrar_a_categoria: favorito=TRUE → masterpiece", {
  res <- migrar_a_categoria(list(favorito = TRUE, rating = 5))
  expect_identical(res$categoria, "masterpiece")
  expect_null(res$favorito)
  expect_null(res$rating)
})

test_that("migrar_a_categoria: rating >=4 sin favorito → great", {
  res <- migrar_a_categoria(list(rating = 4))
  expect_identical(res$categoria, "great")
})

test_that("migrar_a_categoria: rating 2-3 → good", {
  res <- migrar_a_categoria(list(rating = 3))
  expect_identical(res$categoria, "good")
  res2 <- migrar_a_categoria(list(rating = 2))
  expect_identical(res2$categoria, "good")
})

test_that("migrar_a_categoria: rating <2 sin favorito → NULL", {
  res <- migrar_a_categoria(list(rating = 1))
  expect_null(res$categoria)
})

test_that("migrar_a_categoria: sin rating ni favorito → NULL", {
  res <- migrar_a_categoria(list())
  expect_null(res$categoria)
})


# ── aplanar_album ──────────────────────────────────────────────────────────

entry_minimo <- function(...) {
  defaults <- list(
    artista = "Test Artist", album = "Test Album", anio = 2020L,
    id_spotify = "abc123", num_tracks = 10L
  )
  modifyList(defaults, list(...))
}

test_that("aplanar_album produce los campos esperados", {
  res <- aplanar_album("spotify:abc123", entry_minimo())
  expect_true(all(c("id", "artista", "album", "anio", "spotify_url",
                     "generos", "tags_lastfm", "tags_propios", "fecha_agregado")
                   %in% names(res)))
  expect_identical(res$artista, "Test Artist")
  expect_identical(res$spotify_url, "https://open.spotify.com/album/abc123")
})

test_that("aplanar_album construye spotify_url desde la key si no hay id_spotify", {
  entry <- entry_minimo()
  entry$id_spotify <- NULL
  res <- aplanar_album("spotify:fromkey", entry)
  expect_identical(res$spotify_url, "https://open.spotify.com/album/fromkey")
})

test_that("aplanar_album: campos opcionales como list() vacía → string vacío (no '{}'')", {
  # Este caso reproduce el bug que detectamos en CI: jsonlite a veces
  # serializa campos opcionales como list() vacía. aplanar_album debería
  # normalizarlos a "" para que el JSON sea limpio.
  entry <- entry_minimo()
  entry$artista <- list()
  entry$album <- list()
  entry$primer_scrobble <- list()

  res <- aplanar_album("spotify:abc", entry)
  expect_identical(res$artista, "")
  expect_identical(res$album, "")
  expect_identical(res$primer_scrobble, "")
})

test_that("aplanar_album: NA en campos numéricos → default 0", {
  entry <- entry_minimo(anio = NA, num_tracks = NA, duracion_total_min = NA)
  res <- aplanar_album("spotify:abc", entry)
  expect_identical(res$anio, 0L)
  expect_identical(res$num_tracks, 0L)
})

test_that("aplanar_album: ediciones personales migran rating→categoria", {
  entry <- entry_minimo()
  entry$personal <- list(rating = 5, favorito = TRUE, notas = "Excelente")
  res <- aplanar_album("spotify:abc", entry)
  expect_identical(res$categoria, "masterpiece")
  expect_identical(res$notas, "Excelente")
})

test_that("aplanar_album: fecha_precision tiene default 'year'", {
  entry <- entry_minimo()
  entry$fecha_precision <- NULL
  res <- aplanar_album("spotify:abc", entry)
  expect_identical(res$fecha_precision, "year")
})
