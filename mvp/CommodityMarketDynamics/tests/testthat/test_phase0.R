library(testthat)
library(dplyr)

# Source utils so tests can run without loading the full package
source(here::here("R/utils_data.R"))

# --- dflong structure ---

test_that("dflong loads with expected columns", {
  df <- RTL::dflong
  expect_true(all(c("date", "series", "value") %in% names(df)))
})

test_that("dflong has rows", {
  df <- RTL::dflong
  expect_gt(nrow(df), 100000)
})

# --- get_ticker ---

test_that("get_ticker returns only matching ticker prefix", {
  df <- RTL::dflong
  result <- get_ticker(df, "CL")
  expect_true(all(startsWith(result$series, "CL")))
  expect_false(any(startsWith(result$series, "BRN")))
})

test_that("get_ticker adds tenor column as integer", {
  df <- RTL::dflong
  result <- get_ticker(df, "CL")
  expect_type(result$tenor, "integer")
  expect_true(all(result$tenor >= 1))
})

test_that("get_ticker works for all 6 tickers", {
  df <- RTL::dflong
  for (ticker in TICKERS) {
    result <- get_ticker(df, ticker)
    expect_gt(nrow(result), 0, label = paste("ticker", ticker, "returned rows"))
  }
})

# --- get_front_month ---

test_that("get_front_month returns only M01 series", {
  df <- RTL::dflong
  result <- get_front_month(df, "CL")
  expect_true(all(result$series == "CL01"))
})

# --- pivot_ticker_wide ---

test_that("pivot_ticker_wide produces a date column and tenor columns", {
  df <- RTL::dflong
  long <- get_ticker(df, "HO")
  wide <- pivot_ticker_wide(long)
  expect_true("date" %in% names(wide))
  expect_true("HO01" %in% names(wide))
  expect_true(nrow(wide) > 0)
})
