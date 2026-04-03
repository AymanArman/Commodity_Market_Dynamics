library(testthat)
library(dplyr)

source(here::here("R/utils_data.R"))
source(here::here("R/mod_analysis_returns.R"))

dflong <- RTL::dflong

# --- Log return formula ---

test_that("compute_returns produces correct log return on known series", {
  fake <- tibble::tibble(
    date   = as.Date(c("2020-01-01", "2020-01-02", "2020-01-03")),
    series = rep("XX01", 3),
    value  = c(100, 110, 99),
    tenor  = rep(1L, 3)
  )
  result   <- compute_returns(fake)
  expected <- log(110 / 100)
  expect_equal(result[["XX01"]][1], expected, tolerance = 1e-10)
})

test_that("compute_returns second row return is correct", {
  fake <- tibble::tibble(
    date   = as.Date(c("2020-01-01", "2020-01-02", "2020-01-03")),
    series = rep("XX01", 3),
    value  = c(100, 110, 99),
    tenor  = rep(1L, 3)
  )
  result   <- compute_returns(fake)
  expected <- log(99 / 110)
  expect_equal(result[["XX01"]][2], expected, tolerance = 1e-10)
})

test_that("compute_returns drops first row — no NA from missing lag", {
  fake <- tibble::tibble(
    date   = as.Date(c("2020-01-01", "2020-01-02", "2020-01-03")),
    series = rep("XX01", 3),
    value  = c(100, 110, 99),
    tenor  = rep(1L, 3)
  )
  result <- compute_returns(fake)
  expect_equal(nrow(result), 2)
  expect_false(any(is.na(result[["XX01"]])))
})

# --- Returns matrix dimensions per ticker ---

test_that("compute_returns for CL produces 36 tenor columns", {
  result     <- compute_returns(get_ticker(dflong, "CL"))
  tenor_cols <- setdiff(names(result), "date")
  expect_equal(length(tenor_cols), 36)
})

test_that("compute_returns for HO produces 18 tenor columns", {
  result     <- compute_returns(get_ticker(dflong, "HO"))
  tenor_cols <- setdiff(names(result), "date")
  expect_equal(length(tenor_cols), 18)
})

test_that("compute_returns for HTT produces 12 tenor columns", {
  result     <- compute_returns(get_ticker(dflong, "HTT"))
  tenor_cols <- setdiff(names(result), "date")
  expect_equal(length(tenor_cols), 12)
})

test_that("compute_returns result has a date column", {
  result <- compute_returns(get_ticker(dflong, "CL"))
  expect_true("date" %in% names(result))
})

# --- Correlation matrix properties ---

test_that("correlation matrix is symmetric", {
  rw         <- compute_returns(get_ticker(dflong, "CL"))
  tenor_cols <- setdiff(names(rw), "date")
  corr_mat   <- cor(rw[, tenor_cols], use = "pairwise.complete.obs")
  expect_true(isSymmetric(corr_mat))
})

test_that("correlation matrix diagonal equals 1", {
  rw         <- compute_returns(get_ticker(dflong, "CL"))
  tenor_cols <- setdiff(names(rw), "date")
  corr_mat   <- cor(rw[, tenor_cols], use = "pairwise.complete.obs")
  expect_true(all(abs(diag(corr_mat) - 1) < 1e-10))
})

test_that("all correlation values are in [-1, 1]", {
  rw         <- compute_returns(get_ticker(dflong, "CL"))
  tenor_cols <- setdiff(names(rw), "date")
  corr_mat   <- cor(rw[, tenor_cols], use = "pairwise.complete.obs")
  expect_true(all(corr_mat >= -1 - 1e-10 & corr_mat <= 1 + 1e-10))
})

# --- Determinism (proxy for cache correctness) ---

test_that("compute_returns is deterministic across two calls", {
  tkr_data <- get_ticker(dflong, "BRN")
  r1 <- compute_returns(tkr_data)
  r2 <- compute_returns(tkr_data)
  expect_equal(r1, r2)
})
