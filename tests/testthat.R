source(here::here("utils.R"))
instalar_si_falta("testthat")

library(testthat)
library(here)

test_dir(here("tests", "testthat"), reporter = "summary")
