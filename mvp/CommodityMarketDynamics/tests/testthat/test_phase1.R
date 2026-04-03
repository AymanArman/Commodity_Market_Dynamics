library(testthat)
library(dplyr)
library(zoo)

source(here::here("R/utils_data.R"))
source(here::here("R/mod_analysis_regime.R"))

dflong <- RTL::dflong

# --- Tenor extraction ---

test_that("tenor extracted correctly from series string", {
  result <- get_ticker(dflong, "CL")
  expect_true(3L  %in% result$tenor)
  expect_true(36L %in% result$tenor)
  expect_false(any(is.na(result$tenor)))
})

test_that("tenor extracted correctly for HTT", {
  result <- get_ticker(dflong, "HTT")
  expect_true(all(result$tenor >= 1 & result$tenor <= 12))
})

# --- Regime classification ---

test_that("compute_regime returns date and regime columns", {
  regime <- compute_regime(get_ticker(dflong, "CL"))
  expect_true(all(c("date", "regime") %in% names(regime)))
})

test_that("compute_regime only produces valid labels", {
  regime <- compute_regime(get_ticker(dflong, "CL"))
  expect_true(all(regime$regime %in% c("contango", "backwardation", "neutral")))
})

test_that("compute_regime on known contango input returns contango", {
  # Construct a synthetic 3-tenor curve where front < back (contango)
  fake <- tibble::tibble(
    date  = rep(as.Date("2020-01-01"), 3),
    series = c("XX01", "XX02", "XX03"),
    value  = c(50, 55, 60),
    tenor  = c(1L, 2L, 3L)
  )
  regime <- compute_regime(fake)
  expect_equal(regime$regime[1], "contango")
})

test_that("compute_regime on known backwardation input returns backwardation", {
  fake <- tibble::tibble(
    date  = rep(as.Date("2020-01-01"), 3),
    series = c("XX01", "XX02", "XX03"),
    value  = c(60, 55, 50),
    tenor  = c(1L, 2L, 3L)
  )
  regime <- compute_regime(fake)
  expect_equal(regime$regime[1], "backwardation")
})

test_that("regime smoothing suppresses single-day flip within 5-day window", {
  # 4 contango days, 1 backwardation day in the middle, then 4 contango days
  dates <- seq(as.Date("2020-01-01"), by = "day", length.out = 9)
  make_day <- function(d, front, back, tenor_n = 3) {
    tibble::tibble(
      date   = rep(d, tenor_n),
      series = paste0("XX0", seq_len(tenor_n)),
      value  = seq(front, back, length.out = tenor_n),
      tenor  = seq_len(tenor_n)
    )
  }
  rows <- dplyr::bind_rows(
    lapply(dates[1:4], make_day, front = 50, back = 60),  # contango
    make_day(dates[5], front = 60, back = 50),             # backwardation (flip)
    lapply(dates[6:9], make_day, front = 50, back = 60)   # contango
  )
  regime <- compute_regime(rows)
  # The single flip day (position 5) should be smoothed to contango
  flipped <- regime |> dplyr::filter(date == dates[5]) |> dplyr::pull(regime)
  expect_equal(flipped, "contango")
})

# --- Regime caching ---

test_that("compute_regime produces same result on second call (deterministic)", {
  tkr_data <- get_ticker(dflong, "BRN")
  r1 <- compute_regime(tkr_data)
  r2 <- compute_regime(tkr_data)
  expect_equal(r1, r2)
})

# --- Normalization ---

test_that("min-max normalization produces values in [0, 1]", {
  vals <- c(10, 20, 30, 40, 50)
  mn <- min(vals); mx <- max(vals)
  norm <- (vals - mn) / (mx - mn)
  expect_true(all(norm >= 0 & norm <= 1))
  expect_equal(min(norm), 0)
  expect_equal(max(norm), 1)
})
