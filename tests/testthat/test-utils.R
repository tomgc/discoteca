# Tests para utils.R
# Correr desde la raíz del proyecto:  Rscript tests/testthat.R

library(testthat)
library(here)
source(here("utils.R"))


# ── safe_str ────────────────────────────────────────────────────────────────

test_that("safe_str maneja NULL", {
  expect_identical(safe_str(NULL), "")
})

test_that("safe_str maneja NA — regresión del bug v5", {
  expect_identical(safe_str(NA), "")
  expect_identical(safe_str(NA_character_), "")
  expect_identical(safe_str(NA_integer_), "")
})

test_that("safe_str maneja character(0)", {
  expect_identical(safe_str(character(0)), "")
  expect_identical(safe_str(list()), "")
})

test_that("safe_str pasa por escalares normales", {
  expect_identical(safe_str("hola"), "hola")
  expect_identical(safe_str(42), "42")
  expect_identical(safe_str(TRUE), "TRUE")
})

test_that("safe_str toma el primer elemento de vectores", {
  expect_identical(safe_str(c("a", "b", "c")), "a")
  expect_identical(safe_str(list("x", "y")), "x")
})


# ── safe_num ────────────────────────────────────────────────────────────────

test_that("safe_num maneja NULL con default", {
  expect_identical(safe_num(NULL), 0)
  expect_identical(safe_num(NULL, default = -1), -1)
})

test_that("safe_num maneja NA", {
  expect_identical(safe_num(NA), 0)
  expect_identical(safe_num(NA_real_), 0)
  expect_identical(safe_num(NA, default = 999), 999)
})

test_that("safe_num maneja character(0)", {
  expect_identical(safe_num(numeric(0)), 0)
  expect_identical(safe_num(list()), 0)
})

test_that("safe_num convierte numéricos correctamente", {
  expect_identical(safe_num(42), 42)
  expect_identical(safe_num(3.14), 3.14)
  expect_identical(safe_num("7"), 7)
})

test_that("safe_num toma el primer elemento de vectores", {
  expect_identical(safe_num(c(1, 2, 3)), 1)
})


# ── colapsar ────────────────────────────────────────────────────────────────

test_that("colapsar maneja NULL y vacíos", {
  expect_identical(colapsar(NULL), "")
  expect_identical(colapsar(character(0)), "")
  expect_identical(colapsar(list()), "")
})

test_that("colapsar une con '; '", {
  expect_identical(colapsar(c("rock", "indie")), "rock; indie")
  expect_identical(colapsar(list("a", "b", "c")), "a; b; c")
})

test_that("colapsar maneja un solo elemento", {
  expect_identical(colapsar("rock"), "rock")
})


# ── Constantes ──────────────────────────────────────────────────────────────

test_that("constantes de categorías están definidas y son consistentes", {
  expect_true(all(CATEGORIAS_VISIBLES %in% CATEGORIAS_VALIDAS))
  expect_true("descartado" %in% CATEGORIAS_VALIDAS)
  expect_false("descartado" %in% CATEGORIAS_VISIBLES)
})

test_that("rutas son absolutas vía here::here", {
  expect_true(startsWith(RUTA_CACHE, "/") || grepl(":", RUTA_CACHE))
  expect_true(endsWith(RUTA_CACHE, "music_cache.json"))
  expect_true(endsWith(RUTA_CATALOGO, "catalogo.json"))
  expect_true(endsWith(RUTA_CSV, "catalogo_musica.csv"))
})

test_that("rate limits respetan políticas de las APIs", {
  expect_gte(MB_PAUSE, 1)
  expect_gt(LASTFM_PAUSE, 0)
  expect_gte(SPOTIFY_PAGE_SIZE, 1)
  expect_lte(SPOTIFY_PAGE_SIZE, 50)
})


# ── validar_cache ───────────────────────────────────────────────────────────

test_that("validar_cache detecta estructura faltante", {
  expect_false(validar_cache(list()))
  expect_false(validar_cache(list(albumes = list())))
})

test_that("validar_cache acepta caché vacío con _meta", {
  cache_vacio <- list(`_meta` = list(version = "test"), albumes = list())
  expect_true(validar_cache(cache_vacio))
})

test_that("validar_cache acepta álbum con todos los campos requeridos", {
  cache_ok <- list(
    `_meta` = list(version = "test"),
    albumes = list(
      "spotify:abc" = list(
        artista     = "Test",
        album       = "Disco Test",
        anio        = 2020L,
        artwork_url = "http://x/y.jpg"
      )
    )
  )
  expect_true(validar_cache(cache_ok))
})


# ── Round-trip de I/O ───────────────────────────────────────────────────────

test_that("guardar_json + leer producen el mismo dato", {
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp))

  datos <- list(
    list(id = "a", nombre = "uno", valor = 1L),
    list(id = "b", nombre = "dos", valor = 2L)
  )
  guardar_json(datos, tmp, auto_unbox = TRUE)

  expect_true(file.exists(tmp))
  leido <- jsonlite::fromJSON(tmp, simplifyVector = FALSE)
  expect_length(leido, 2)
  expect_identical(leido[[1]]$id, "a")
  expect_identical(leido[[2]]$valor, 2L)
})

test_that("escritura atómica no deja archivos .tmp residuales", {
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(c(tmp, paste0(tmp, ".tmp"))))

  guardar_json(list(x = 1), tmp, auto_unbox = TRUE)
  expect_true(file.exists(tmp))
  expect_false(file.exists(paste0(tmp, ".tmp")))
})


# ── ordenar_keys (C.10) ────────────────────────────────────────────────────

test_that("ordenar_keys ordena alfabéticamente las claves de un objeto", {
  entrada <- list(zebra = 1, alpha = 2, mike = 3)
  resultado <- ordenar_keys(entrada)
  expect_identical(names(resultado), c("alpha", "mike", "zebra"))
})

test_that("ordenar_keys es recursivo en objetos anidados", {
  entrada <- list(
    z = list(y = 1, a = 2),
    a = list(c = 3, b = 4)
  )
  resultado <- ordenar_keys(entrada)
  expect_identical(names(resultado), c("a", "z"))
  expect_identical(names(resultado$a), c("b", "c"))
  expect_identical(names(resultado$z), c("a", "y"))
})

test_that("ordenar_keys preserva orden de arrays (listas sin nombres)", {
  entrada <- list(
    items = list(
      list(b = 1, a = 2),
      list(b = 3, a = 4)
    )
  )
  resultado <- ordenar_keys(entrada)
  # El array preserva orden
  expect_length(resultado$items, 2)
  # Pero cada elemento del array tiene sus keys ordenadas
  expect_identical(names(resultado$items[[1]]), c("a", "b"))
  expect_identical(names(resultado$items[[2]]), c("a", "b"))
})

test_that("ordenar_keys es idempotente sobre escalares y vectores", {
  expect_identical(ordenar_keys(42), 42)
  expect_identical(ordenar_keys("hola"), "hola")
  expect_identical(ordenar_keys(c(3, 1, 2)), c(3, 1, 2))
})


# ── validar_catalogo (C.8) ─────────────────────────────────────────────────

test_that("validar_catalogo no encuentra problemas en catálogo válido", {
  cat <- list(
    list(id = "spotify:1", artista = "A", album = "X", anio = 2020L, categoria = "good"),
    list(id = "spotify:2", artista = "B", album = "Y", anio = 1975L, categoria = NULL)
  )
  res <- suppressMessages(validar_catalogo(cat))
  expect_length(res$problemas, 0)
  expect_identical(res$total, 2L)
})

test_that("validar_catalogo detecta campos vacíos", {
  cat <- list(list(id = "", artista = "", album = "X"))
  res <- suppressMessages(validar_catalogo(cat))
  expect_gte(length(res$problemas), 2)  # id y artista vacíos
})

test_that("validar_catalogo detecta categoría inválida", {
  cat <- list(list(id = "1", artista = "A", album = "X", categoria = "epic"))
  res <- suppressMessages(validar_catalogo(cat))
  expect_true(any(grepl("epic", res$problemas, fixed = TRUE)))
})

test_that("validar_catalogo detecta IDs duplicados", {
  cat <- list(
    list(id = "spotify:1", artista = "A", album = "X"),
    list(id = "spotify:1", artista = "B", album = "Y")
  )
  res <- suppressMessages(validar_catalogo(cat))
  expect_true(any(grepl("duplicados", res$problemas)))
})

test_that("validar_catalogo detecta año fuera de rango", {
  cat <- list(list(id = "1", artista = "A", album = "X", anio = 1800L))
  res <- suppressMessages(validar_catalogo(cat))
  expect_true(any(grepl("fuera de rango", res$problemas)))
})

test_that("validar_catalogo no es fatal — devuelve siempre lista", {
  cat <- list(list(id = ""))
  expect_silent(suppressMessages(validar_catalogo(cat)))
})

test_that("validar_catalogo tolera NA y list() en cualquier campo (jsonlite)", {
  cat <- list(
    list(id = "1", artista = NA,         album = "X"),                # NA en string
    list(id = "2", artista = "B",         album = "Y", categoria = NA), # NA en categoría
    list(id = "3", artista = "C",         album = "Z", anio = NA),     # NA en año
    list(id = "4", artista = "D",         album = "W", categoria = list()),  # list vacía
    list(id = "5", artista = "E",         album = "Q", anio  = list())       # list vacía
  )
  # No debe explotar — solo warnings warning-level.
  expect_no_error(suppressMessages(validar_catalogo(cat)))
})
