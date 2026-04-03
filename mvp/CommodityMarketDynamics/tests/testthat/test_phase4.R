library(testthat)
library(dplyr)
library(zoo)

source(here::here("R/utils_data.R"))
source(here::here("R/mod_analysis_var.R"))
source(here::here("R/mod_cross_market.R"))

dflong <- RTL::dflong

# Fit a VAR once for all tests that need it (p=2 to avoid lag selection overhead)
var_mat <- build_var_matrix(dflong)
var_fit <- vars::VAR(var_mat, p = 2, type = "const")

# --- build_var_matrix ---

test_that("build_var_matrix returns a data.frame", {
  expect_s3_class(var_mat, "data.frame")
})

test_that("build_var_matrix has exactly 6 columns: CL, BRN, NG, HO, RB, HTT", {
  expect_equal(sort(names(var_mat)), sort(c("CL", "BRN", "NG", "HO", "RB", "HTT")))
})

test_that("build_var_matrix contains no NA values", {
  expect_false(any(is.na(var_mat)))
})

test_that("build_var_matrix returns only numeric columns", {
  expect_true(all(sapply(var_mat, is.numeric)))
})

# --- select_var_lag ---

test_that("select_var_lag returns a single integer", {
  vs     <- vars::VARselect(var_mat, lag.max = 5, type = "const")
  result <- select_var_lag(vs)
  expect_length(result, 1)
  expect_true(is.integer(result) || is.numeric(result))
})

test_that("select_var_lag picks majority vote lag", {
  # Synthetic: AIC=3, HQ=3, SC=2, FPE=3 → majority is 3
  fake <- list(selection = c("AIC(n)" = 3L, "HQ(n)" = 3L, "SC(n)" = 2L, "FPE(n)" = 3L))
  expect_equal(select_var_lag(fake), 3L)
})

test_that("select_var_lag breaks ties by choosing the lower lag", {
  # AIC=5, HQ=5, SC=2, FPE=2 → tie between 2 and 5 → choose 2
  fake <- list(selection = c("AIC(n)" = 5L, "HQ(n)" = 5L, "SC(n)" = 2L, "FPE(n)" = 2L))
  expect_equal(select_var_lag(fake), 2L)
})

test_that("select_var_lag handles all criteria agreeing on one lag", {
  fake <- list(selection = c("AIC(n)" = 4L, "HQ(n)" = 4L, "SC(n)" = 4L, "FPE(n)" = 4L))
  expect_equal(select_var_lag(fake), 4L)
})

# --- VAR fit ---

test_that("VAR fits on actual 6-ticker return matrix without error", {
  expect_s3_class(var_fit, "varest")
})

test_that("VAR variable names match the 6 tickers", {
  expect_equal(sort(colnames(var_fit$y)), sort(c("CL", "BRN", "NG", "HO", "RB", "HTT")))
})

# --- IRF structure (boot = FALSE for test speed) ---

test_that("IRF object is returned without error (boot = FALSE)", {
  irf_obj <- vars::irf(var_fit, impulse = "CL", n.ahead = 20, boot = FALSE)
  expect_s3_class(irf_obj, "varirf")
})

test_that("IRF point estimates have 21 steps (horizon 0 to 20)", {
  # vars::irf indexes by shock ticker: irf_obj$irf$CL is the response matrix
  irf_obj <- vars::irf(var_fit, impulse = "CL", n.ahead = 20, boot = FALSE)
  expect_equal(nrow(irf_obj$irf$CL), 21L)
})

test_that("IRF response matrix for CL shock has columns for all 6 tickers", {
  irf_obj <- vars::irf(var_fit, impulse = "CL", n.ahead = 20, boot = FALSE)
  expect_true(all(c("CL", "BRN", "NG", "HO", "RB", "HTT") %in% colnames(irf_obj$irf$CL)))
})

test_that("IRF bootstrap CI bounds are non-null (boot = TRUE, 5 runs)", {
  irf_obj <- vars::irf(var_fit, impulse = "CL", n.ahead = 20,
                       boot = TRUE, ci = 0.95, runs = 5, ortho = TRUE)
  expect_false(is.null(irf_obj$Lower))
  expect_false(is.null(irf_obj$Upper))
})

# --- irf_is_significant ---


# --- vol_regime_shapes ---

test_that("vol_regime_shapes returns a list", {
  dates    <- seq(as.Date("2020-01-01"), by = "day", length.out = 10)
  high_vol <- c(FALSE, FALSE, TRUE, TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, FALSE)
  shapes   <- vol_regime_shapes(dates, high_vol)
  expect_type(shapes, "list")
})

test_that("vol_regime_shapes produces one rect per contiguous high-vol segment", {
  # Two separate high-vol segments: [3,5] and [8]
  dates    <- seq(as.Date("2020-01-01"), by = "day", length.out = 10)
  high_vol <- c(FALSE, FALSE, TRUE, TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, FALSE)
  shapes   <- vol_regime_shapes(dates, high_vol)
  expect_equal(length(shapes), 2L)
})

test_that("vol_regime_shapes handles all-FALSE high_vol (no shapes)", {
  dates    <- seq(as.Date("2020-01-01"), by = "day", length.out = 5)
  high_vol <- rep(FALSE, 5)
  shapes   <- vol_regime_shapes(dates, high_vol)
  expect_equal(length(shapes), 0L)
})

test_that("vol_regime_shapes handles segment running to end of series", {
  dates    <- seq(as.Date("2020-01-01"), by = "day", length.out = 5)
  high_vol <- c(FALSE, FALSE, TRUE, TRUE, TRUE)
  shapes   <- vol_regime_shapes(dates, high_vol)
  expect_equal(length(shapes), 1L)
})

# --- Rolling correlation ---

test_that("rolling correlation of two identical series equals 1", {
  set.seed(42)
  vals   <- cumsum(rnorm(200))
  dates  <- seq(as.Date("2020-01-01"), by = "day", length.out = 200)
  ret_mat <- zoo::zoo(cbind(vals, vals), dates)
  roll_cor <- zoo::rollapply(
    ret_mat, width = 60,
    FUN = function(x) stats::cor(x[, 1], x[, 2], use = "complete.obs"),
    by.column = FALSE, align = "right", fill = NA
  )
  # All non-NA values should be 1
  non_na <- as.numeric(roll_cor)[!is.na(as.numeric(roll_cor))]
  expect_true(all(abs(non_na - 1) < 1e-10))
})

test_that("rolling correlation of perfectly anti-correlated series equals -1", {
  set.seed(42)
  vals   <- rnorm(200)
  dates  <- seq(as.Date("2020-01-01"), by = "day", length.out = 200)
  ret_mat <- zoo::zoo(cbind(vals, -vals), dates)
  roll_cor <- zoo::rollapply(
    ret_mat, width = 60,
    FUN = function(x) stats::cor(x[, 1], x[, 2], use = "complete.obs"),
    by.column = FALSE, align = "right", fill = NA
  )
  non_na <- as.numeric(roll_cor)[!is.na(as.numeric(roll_cor))]
  expect_true(all(abs(non_na + 1) < 1e-10))
})

# --- Vol regime threshold ---

test_that("rolling SD values above 75th percentile are flagged as high vol", {
  set.seed(7)
  roll_sd <- c(0.01, 0.02, 0.05, 0.08, 0.10, 0.12, 0.03, 0.04, 0.09, 0.20)
  vol_thr <- stats::quantile(roll_sd, 0.75, na.rm = TRUE)
  high_vol <- roll_sd > vol_thr
  n_high <- sum(high_vol)
  # 75th percentile → ~25% of values above it
  expect_true(n_high >= 1 && n_high < length(roll_sd))
  expect_true(all(roll_sd[high_vol] > vol_thr))
  expect_true(all(roll_sd[!high_vol] <= vol_thr))
})

# --- r$var_results written on module init ---

test_that("r$var_results is non-NULL after mod_analysis_var_server initializes", {
  r <- shiny::reactiveValues()
  shiny::testServer(
    mod_analysis_var_server,
    args = list(dflong = dflong, r = r),
    {
      expect_false(is.null(r$var_results))
    }
  )
})

test_that("r$var_results contains expected keys", {
  r <- shiny::reactiveValues()
  shiny::testServer(
    mod_analysis_var_server,
    args = list(dflong = dflong, r = r),
    {
      expect_true(all(c("var_fit", "lag_n", "lag_label", "granger", "irfs", "tickers")
                      %in% names(r$var_results)))
    }
  )
})
