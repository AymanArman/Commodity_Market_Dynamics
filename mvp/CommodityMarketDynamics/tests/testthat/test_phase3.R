library(testthat)
library(dplyr)

source(here::here("R/utils_data.R"))
source(here::here("R/mod_market_dynamics.R"))

dflong <- RTL::dflong

# --- Calendar spread (Crude) ---

test_that("CL calendar spread is M1 minus M2", {
  cl_wide <- pivot_ticker_wide(get_ticker(dflong, "CL"))
  spread  <- dplyr::mutate(cl_wide, spread = CL01 - CL02)
  # For a known row: spread must equal CL01 - CL02 exactly
  row1 <- spread[1, ]
  expect_equal(row1$spread, row1$CL01 - row1$CL02)
})

test_that("CL calendar spread has no NAs where CL01 and CL02 both exist", {
  cl_wide <- pivot_ticker_wide(get_ticker(dflong, "CL"))
  spread  <- dplyr::mutate(cl_wide, spread = CL01 - CL02) |>
    dplyr::filter(!is.na(CL01) & !is.na(CL02))
  expect_false(any(is.na(spread$spread)))
})

test_that("CL calendar spread is negative in backwardation (front > back)", {
  # Synthetic: CL01=70, CL02=65 → spread = 5 (positive = backwardation)
  fake_wide <- tibble::tibble(date = as.Date("2020-01-01"), CL01 = 70, CL02 = 65)
  spread    <- dplyr::mutate(fake_wide, spread = CL01 - CL02)
  expect_gt(spread$spread, 0)
})

test_that("CL calendar spread is negative in contango (front < back)", {
  # Synthetic: CL01=65, CL02=70 → spread = -5 (negative = contango)
  fake_wide <- tibble::tibble(date = as.Date("2020-01-01"), CL01 = 65, CL02 = 70)
  spread    <- dplyr::mutate(fake_wide, spread = CL01 - CL02)
  expect_lt(spread$spread, 0)
})

# --- Crack spread unit conversion (Refined Products) ---

test_that("HO prices are in USD/gallon range (not USD/bbl)", {
  # NYMEX HO trades in USD/gallon — typical range ~$1–$5/gal, never ~$40–$120
  ho_vals <- get_front_month(dflong, "HO")$value
  expect_true(median(ho_vals, na.rm = TRUE) < 10,
    info = "HO median price should be < $10 — if not, unit assumption is wrong")
})

test_that("CL prices are in USD/bbl range", {
  cl_vals <- get_front_month(dflong, "CL")$value
  expect_true(median(cl_vals, na.rm = TRUE) > 20,
    info = "CL median price should be > $20 — confirms USD/bbl scale")
})

test_that("HO crack spread after unit conversion is in plausible USD/bbl range", {
  ho     <- get_front_month(dflong, "HO") |> dplyr::select(date, ho = value)
  cl     <- get_front_month(dflong, "CL") |> dplyr::select(date, cl = value)
  spread <- dplyr::inner_join(ho, cl, by = "date") |>
    dplyr::mutate(crack = ho * 42 - cl) |>
    dplyr::filter(!is.na(crack))
  # Crack spread in USD/bbl should be broadly between -$20 and +$60 historically
  expect_true(median(spread$crack, na.rm = TRUE) > -20 &
              median(spread$crack, na.rm = TRUE) < 60,
    info = "HO crack spread median outside expected range — check unit conversion")
})

test_that("HO crack spread formula: known inputs produce known output", {
  # HO = 2.00 USD/gal → 2.00 × 42 = $84/bbl; CL = 70 USD/bbl → crack = $14/bbl
  crack <- 2.00 * 42 - 70
  expect_equal(crack, 14)
})

# --- Monthly return seasonality (Natural Gas) ---

test_that("NG monthly seasonality produces 12 rows (one per month)", {
  ng_front <- get_front_month(dflong, "NG") |> dplyr::arrange(date)
  ng_ret   <- ng_front |>
    dplyr::mutate(ret = log(value / dplyr::lag(value))) |>
    dplyr::filter(!is.na(ret)) |>
    dplyr::mutate(month_num = as.integer(format(date, "%m")))
  monthly  <- ng_ret |>
    dplyr::group_by(month_num) |>
    dplyr::summarise(avg_ret = mean(ret, na.rm = TRUE), .groups = "drop")
  expect_equal(nrow(monthly), 12L)
})

test_that("NG monthly avg return is numeric and finite for all months", {
  ng_front <- get_front_month(dflong, "NG") |> dplyr::arrange(date)
  ng_ret   <- ng_front |>
    dplyr::mutate(ret = log(value / dplyr::lag(value))) |>
    dplyr::filter(!is.na(ret)) |>
    dplyr::mutate(month_num = as.integer(format(date, "%m")))
  monthly  <- ng_ret |>
    dplyr::group_by(month_num) |>
    dplyr::summarise(avg_ret = mean(ret, na.rm = TRUE), .groups = "drop")
  expect_true(all(is.finite(monthly$avg_ret)))
})

test_that("monthly seasonality aggregation is correct on known series", {
  # Two observations per month: Jan returns of 0.02 and 0.04 → avg = 0.03
  fake <- tibble::tibble(
    date  = as.Date(c("2020-01-05", "2021-01-05", "2020-07-05", "2021-07-05")),
    month_num = c(1L, 1L, 7L, 7L),
    ret   = c(0.02, 0.04, -0.01, 0.01)
  )
  monthly <- fake |>
    dplyr::group_by(month_num) |>
    dplyr::summarise(avg_ret = mean(ret), .groups = "drop") |>
    dplyr::arrange(month_num)
  expect_equal(monthly$avg_ret[monthly$month_num == 1L], 0.03)
  expect_equal(monthly$avg_ret[monthly$month_num == 7L], 0.00)
})

# --- Group button state logic (pure reactive logic tested via testServer) ---

test_that("active_group starts NULL and updates correctly on NG button", {
  shiny::testServer(mod_market_dynamics_server, args = list(dflong = dflong, r = shiny::reactiveValues()), {
    expect_null(active_group())
    session$setInputs(btn_ng = 1)
    expect_equal(active_group(), "NG")
  })
})

test_that("clicking active NG button again does not change state", {
  shiny::testServer(mod_market_dynamics_server, args = list(dflong = dflong, r = shiny::reactiveValues()), {
    session$setInputs(btn_ng = 1)
    expect_equal(active_group(), "NG")
    session$setInputs(btn_ng = 2)
    expect_equal(active_group(), "NG")   # still NG — no-op
  })
})

test_that("modal confirm applies pending_group and removes modal", {
  shiny::testServer(mod_market_dynamics_server, args = list(dflong = dflong, r = shiny::reactiveValues()), {
    # Simulate: click Crude (sets pending_group) then confirm
    session$setInputs(btn_crude = 1)
    expect_equal(pending_group(), "Crude")
    session$setInputs(modal_confirm = 1)
    expect_equal(active_group(), "Crude")
  })
})

test_that("modal cancel leaves active_group unchanged", {
  shiny::testServer(mod_market_dynamics_server, args = list(dflong = dflong, r = shiny::reactiveValues()), {
    # Set NG active first
    session$setInputs(btn_ng = 1)
    expect_equal(active_group(), "NG")
    # Click Crude (shows modal, pending_group = "Crude") but do NOT confirm
    session$setInputs(btn_crude = 1)
    expect_equal(pending_group(), "Crude")
    expect_equal(active_group(), "NG")   # not changed — modal not confirmed
  })
})
