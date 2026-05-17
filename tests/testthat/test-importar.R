# Tests para importar_ediciones.R
# Verifica la validación de ediciones exportadas desde el navegador y
# el round-trip (importar → catálogo).

library(testthat)
library(here)
source(here("utils.R"))

# importar_ediciones.R tiene guard 'if (!interactive() && sys.nframe()==0L)'
# para el CLI — sys.nframe() > 0 al sourcear desde tests, así que safe.
source(here("importar_ediciones.R"))


# ── validar_ediciones ──────────────────────────────────────────────────────

test_that("validar_ediciones rechaza estructura no-lista", {
  expect_false(suppressMessages(validar_ediciones(NULL)))
  expect_false(suppressMessages(validar_ediciones("not a list")))
  expect_false(suppressMessages(validar_ediciones(42)))
})

test_that("validar_ediciones rechaza lista vacía", {
  expect_false(suppressMessages(validar_ediciones(list())))
})

test_that("validar_ediciones rechaza entrada sin id", {
  ediciones <- list(
    list(id = "spotify:1", categoria = "good"),
    list(categoria = "great")  # sin id
  )
  expect_false(suppressMessages(validar_ediciones(ediciones)))
})

test_that("validar_ediciones rechaza IDs duplicados", {
  ediciones <- list(
    list(id = "spotify:1", categoria = "good"),
    list(id = "spotify:1", categoria = "great")
  )
  expect_false(suppressMessages(validar_ediciones(ediciones)))
})

test_that("validar_ediciones rechaza categoría inválida", {
  ediciones <- list(
    list(id = "spotify:1", categoria = "epic")
  )
  expect_false(suppressMessages(validar_ediciones(ediciones)))
})

test_that("validar_ediciones acepta entradas válidas", {
  ediciones <- list(
    list(id = "spotify:1", categoria = "good",        notas = "", tags_propios = list()),
    list(id = "spotify:2", categoria = "great",       notas = "x"),
    list(id = "spotify:3", categoria = "masterpiece"),
    list(id = "spotify:4", categoria = "descartado"),
    list(id = "spotify:5")  # sin categoría también es legal
  )
  expect_true(suppressMessages(validar_ediciones(ediciones)))
})

test_that("validar_ediciones acepta entradas reales del repo", {
  # Si el archivo existe en el repo, validar que el formato sigue siendo
  # legal (defensa contra cambios accidentales del schema).
  ruta <- here("datos", "ediciones_web.json")
  skip_if_not(file.exists(ruta), "ediciones_web.json no presente")

  ediciones <- jsonlite::fromJSON(ruta, simplifyVector = FALSE)
  expect_true(suppressMessages(validar_ediciones(ediciones)))
})


# ── buscar_archivo_mas_reciente ────────────────────────────────────────────

test_that("buscar_archivo_mas_reciente devuelve NULL en directorio sin match", {
  tmp <- tempfile("downloads-test-"); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  expect_null(buscar_archivo_mas_reciente(dir = tmp))
})

test_that("buscar_archivo_mas_reciente prefiere el archivo más reciente", {
  tmp <- tempfile("downloads-test-"); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  viejo <- file.path(tmp, "discoteca-ediciones-2025.json")
  nuevo <- file.path(tmp, "discoteca-ediciones-2026.json")
  writeLines("[]", viejo); writeLines("[]", nuevo)
  Sys.setFileTime(viejo, Sys.time() - 3600)  # 1h atrás
  Sys.setFileTime(nuevo, Sys.time())

  resultado <- buscar_archivo_mas_reciente(dir = tmp)
  expect_identical(basename(resultado), basename(nuevo))
})

test_that("buscar_archivo_mas_reciente ignora archivos que no matchean patrón", {
  tmp <- tempfile("downloads-test-"); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  writeLines("[]", file.path(tmp, "otra-cosa.json"))
  writeLines("[]", file.path(tmp, "no-es-json.txt"))

  expect_null(buscar_archivo_mas_reciente(dir = tmp))
})


# ── importar (round-trip) ──────────────────────────────────────────────────

test_that("importar dry_run no toca el destino", {
  tmp <- tempfile(fileext = ".json")
  writeLines('[{"id":"spotify:abc","categoria":"good"}]', tmp)
  on.exit(unlink(tmp))

  destino_original_existe <- file.exists(RUTA_WEB_EDIT)

  resultado <- suppressMessages(importar(tmp, dry_run = TRUE))
  expect_true(resultado)

  # No debe haber tocado el destino real (su existencia no cambia)
  expect_identical(file.exists(RUTA_WEB_EDIT), destino_original_existe)
})

test_that("importar rechaza JSON malformado", {
  tmp <- tempfile(fileext = ".json")
  writeLines("not json at all {", tmp)
  on.exit(unlink(tmp))

  expect_false(suppressMessages(importar(tmp, dry_run = TRUE)))
})

test_that("importar rechaza archivo inexistente", {
  expect_false(suppressMessages(importar("/no/existe.json", dry_run = TRUE)))
})
