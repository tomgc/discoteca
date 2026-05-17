# Tests para run_all.R
# Cubre el cálculo de etapas y el parser CLI — pura sin side effects.

library(testthat)
library(here)
source(here("utils.R"))

# run_all.R tiene guard 'if (!interactive() && sys.nframe()==0L)' para el CLI
source(here("run_all.R"))


# ── calcular_etapas ────────────────────────────────────────────────────────

test_that("calcular_etapas: defaults completo", {
  expect_identical(
    calcular_etapas(),
    c("spotify", "lastfm", "musicbrainz", "wikipedia", "construir")
  )
})

test_that("calcular_etapas: --skip excluye etapas", {
  res <- calcular_etapas(skip = c("spotify", "lastfm"))
  expect_false("spotify" %in% res)
  expect_false("lastfm" %in% res)
  expect_true("construir" %in% res)
})

test_that("calcular_etapas: --only fuerza una etapa + construir", {
  res <- calcular_etapas(only = "wikipedia")
  expect_identical(res, c("wikipedia", "construir"))
})

test_that("calcular_etapas: --only construir devuelve solo construir (sin duplicar)", {
  res <- calcular_etapas(only = "construir")
  expect_identical(res, "construir")
})

test_that("calcular_etapas: --only ignora --skip", {
  res <- calcular_etapas(only = "lastfm", skip = c("lastfm", "construir"))
  expect_true("lastfm" %in% res)
  expect_true("construir" %in% res)
})

test_that("calcular_etapas: --dedup inserta deduplicar antes de construir", {
  res <- calcular_etapas(dedup = TRUE)
  idx_dedup <- match("deduplicar", res)
  idx_construir <- match("construir", res)
  expect_true(!is.na(idx_dedup) && !is.na(idx_construir))
  expect_lt(idx_dedup, idx_construir)
})

test_that("calcular_etapas: --dedup respeta --only", {
  res <- calcular_etapas(only = "musicbrainz", dedup = TRUE)
  expect_true("deduplicar" %in% res)
  expect_true("musicbrainz" %in% res)
  expect_true("construir" %in% res)
})


# ── parsear_args ───────────────────────────────────────────────────────────

test_that("parsear_args: sin argumentos → defaults", {
  res <- parsear_args(character(0))
  expect_identical(res$skip,  character(0))
  expect_null(res$only)
  expect_false(res$dedup)
  expect_false(res$help)
})

test_that("parsear_args: --skip parsea lista separada por comas", {
  res <- parsear_args(c("--skip", "spotify,lastfm,musicbrainz"))
  expect_identical(res$skip, c("spotify", "lastfm", "musicbrainz"))
})

test_that("parsear_args: --only", {
  res <- parsear_args(c("--only", "wikipedia"))
  expect_identical(res$only, "wikipedia")
})

test_that("parsear_args: --dedup es bandera (no toma valor)", {
  res <- parsear_args(c("--dedup"))
  expect_true(res$dedup)
})

test_that("parsear_args: --help / -h", {
  expect_true(parsear_args("--help")$help)
  expect_true(parsear_args("-h")$help)
})

test_that("parsear_args: combinación de flags", {
  res <- parsear_args(c("--skip", "spotify", "--dedup", "--only", "lastfm"))
  expect_identical(res$skip, "spotify")
  expect_identical(res$only, "lastfm")
  expect_true(res$dedup)
})

test_that("parsear_args: argumento desconocido lanza condición tipada", {
  expect_error(
    parsear_args(c("--invento")),
    class = "discoteca_cli_error"
  )
})
