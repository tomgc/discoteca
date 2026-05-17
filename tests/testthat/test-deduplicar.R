# Tests para deduplicar.R
# Verifica la normalización de nombres y la clave de agrupación.

library(testthat)
library(here)
source(here("utils.R"))

withr::local_options(discoteca.load_only = TRUE)
source(here("deduplicar.R"))


# ── normalizar_nombre ──────────────────────────────────────────────────────

test_that("normalizar_nombre quita sufijos de re-issue / remaster", {
  expect_identical(
    normalizar_nombre("No Control (Re-Issue)"),
    normalizar_nombre("No Control")
  )
  expect_identical(
    normalizar_nombre("OK Computer (Remastered)"),
    normalizar_nombre("OK Computer")
  )
})

test_that("normalizar_nombre quita Deluxe Edition", {
  expect_identical(
    normalizar_nombre("Random Access Memories (Deluxe Edition)"),
    normalizar_nombre("Random Access Memories")
  )
})

test_that("normalizar_nombre es case-insensitive", {
  expect_identical(normalizar_nombre("Title"), normalizar_nombre("TITLE"))
})


# ── clave_album ────────────────────────────────────────────────────────────

test_that("clave_album genera misma key para variantes", {
  k1 <- clave_album(list(artista = "Bad Religion", album = "No Control"))
  k2 <- clave_album(list(artista = "Bad Religion", album = "No Control (Re-Issue)"))
  expect_identical(k1, k2)
})

test_that("clave_album tolera list() vacía en artista/album", {
  # Regresión del bug del refactor safe_str — trimws/tolower fallaban con list()
  expect_no_error(clave_album(list(artista = list(), album = list())))
  expect_no_error(clave_album(list(artista = NA, album = NA)))
  expect_no_error(clave_album(list()))
})

test_that("clave_album es case-insensitive en el artista", {
  k1 <- clave_album(list(artista = "Radiohead", album = "OK Computer"))
  k2 <- clave_album(list(artista = "RADIOHEAD", album = "OK Computer"))
  expect_identical(k1, k2)
})


# ── get_scrobbles ──────────────────────────────────────────────────────────

test_that("get_scrobbles retorna 0 cuando no hay datos de Last.fm", {
  # safe_num retorna el default tal cual (0L integer). Cualquier valor
  # real pasa por as.numeric (double). Inconsistencia menor pero
  # documentada: el contrato real es "número escalar".
  for (entry in list(
    list(),
    list(lastfm = list()),
    list(lastfm = list(scrobbles_totales = NULL))
  )) {
    res <- get_scrobbles(entry)
    expect_true(is.numeric(res), info = "número escalar")
    expect_equal(res, 0)
  }
})

test_that("get_scrobbles maneja list() vacía sin romper vapply downstream", {
  # Regresión: get_scrobbles se usa en vapply(..., numeric(1)). Si retorna
  # list() en vez de numeric, vapply explota.
  res <- get_scrobbles(list(lastfm = list(scrobbles_totales = list())))
  expect_true(is.numeric(res))
  expect_length(res, 1)
})

test_that("get_scrobbles convierte string numérico a número", {
  res <- get_scrobbles(list(lastfm = list(scrobbles_totales = "42")))
  expect_equal(res, 42)
})

test_that("get_scrobbles retorna el valor cuando existe", {
  res <- get_scrobbles(list(lastfm = list(scrobbles_totales = 100L)))
  expect_equal(res, 100)
})
