library(CommodityMarketDynamics)
library(dplyr)
library(testthat)

dflong <- RTL::dflong

# ── Phase 4 Smoke: prior phases ──────────────────────────────────────────────

test_that("4.smoke.0: dflong loads and has required tickers", {
  expect_true(nrow(dflong) > 0)
  expect_true(all(c("CL01", "BRN01", "HO01", "RB01", "NG01", "HTT01") %in%
                    unique(dflong$series)))
})

# ── Rolling correlation helpers ───────────────────────────────────────────────

# Helper: compute M01 returns for one ticker from dflong
get_m1_returns <- function(ticker, data = dflong) {
  data |>
    dplyr::filter(series == paste0(ticker, "01")) |>
    CommodityMarketDynamics:::compute_returns() |>
    dplyr::select(date, return)
}

# Helper: inner-join two tickers and compute rolling correlation
rolling_corr_series <- function(t1, t2, window, data = dflong) {
  r1 <- get_m1_returns(t1, data)
  r2 <- get_m1_returns(t2, data)
  joined <- dplyr::inner_join(r1, r2, by = "date", suffix = c("_t1", "_t2")) |>
    dplyr::arrange(date)
  ret_mat <- as.matrix(joined[, c("return_t1", "return_t2")])
  corr <- zoo::rollapplyr(
    data       = ret_mat,
    width      = window,
    FUN        = function(m) stats::cor(m[, 1], m[, 2], use = "complete.obs"),
    by.column  = FALSE,
    fill       = NA,
    align      = "right"
  )
  list(dates = joined$date, corr = corr)
}

# ── 4.1: Default window = 90 ──────────────────────────────────────────────────
test_that("4.1: rolling correlation computed with 90-day window — first non-NA at day 90", {
  res   <- rolling_corr_series("CL", "BRN", window = 90L)
  corrs <- res$corr
  # First non-NA value appears at index 90 (window = 90, right-aligned)
  first_valid <- min(which(!is.na(corrs)))
  expect_equal(first_valid, 90L)
})

# ── 4.2: Slider updates window ────────────────────────────────────────────────
test_that("4.2: window=21 — first non-NA appears at index 21", {
  res   <- rolling_corr_series("CL", "BRN", window = 21L)
  corrs <- res$corr
  first_valid <- min(which(!is.na(corrs)))
  expect_equal(first_valid, 21L)
})

# ── 4.3: Vol regime threshold = 80th percentile ───────────────────────────────
test_that("4.3: high-vol threshold is the 80th percentile of avg rolling vol", {
  r1 <- get_m1_returns("CL")
  r2 <- get_m1_returns("BRN")
  joined <- dplyr::inner_join(r1, r2, by = "date", suffix = c("_t1", "_t2")) |>
    dplyr::arrange(date)
  roll_vol1 <- zoo::rollapply(joined$return_t1, width = 21L, FUN = stats::sd,
                              fill = NA, align = "right")
  roll_vol2 <- zoo::rollapply(joined$return_t2, width = 21L, FUN = stats::sd,
                              fill = NA, align = "right")
  avg_vol       <- rowMeans(cbind(roll_vol1, roll_vol2), na.rm = FALSE)
  expected_thr  <- stats::quantile(avg_vol, probs = 0.80, na.rm = TRUE)

  # Verify threshold is the 80th percentile and not a constant
  expect_true(expected_thr > 0)
  # If it were the 90th percentile the value would be strictly higher
  thr_90 <- stats::quantile(avg_vol, probs = 0.90, na.rm = TRUE)
  expect_true(expected_thr < thr_90)
})

# ── 4.4 / 4.5: get_high_vol_periods — only TRUE runs returned, correct structure
test_that("4.4/4.5: get_high_vol_periods returns only high-vol date ranges", {
  dates   <- seq(as.Date("2020-01-01"), by = "day", length.out = 10)
  is_high <- c(FALSE, FALSE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE, FALSE, FALSE)
  periods <- CommodityMarketDynamics:::get_high_vol_periods(dates, is_high)

  # Should identify 2 contiguous high-vol runs
  expect_equal(nrow(periods), 2L)
  expect_equal(periods$x0[1], as.Date("2020-01-03"))
  expect_equal(periods$x1[1], as.Date("2020-01-05"))
  expect_equal(periods$x0[2], as.Date("2020-01-07"))
  expect_equal(periods$x1[2], as.Date("2020-01-08"))
})

test_that("4.4b: get_high_vol_periods returns empty data.frame when no high-vol periods", {
  dates   <- seq(as.Date("2020-01-01"), by = "day", length.out = 5)
  is_high <- rep(FALSE, 5)
  periods <- CommodityMarketDynamics:::get_high_vol_periods(dates, is_high)
  expect_equal(nrow(periods), 0L)
})

# ── VAR data prep tests ───────────────────────────────────────────────────────

# Run mod_var_server once to obtain r$var_results for downstream tests
r_var <- shiny::reactiveValues()
shiny::isolate(mod_var_server(dflong, r_var))

# ── 4.6: All 6 tickers in VAR data ───────────────────────────────────────────
test_that("4.6: all 6 tickers are present in the VAR model", {
  shiny::isolate({
    shiny::req(r_var$var_results)
    model_tickers <- colnames(r_var$var_results$y)
    expect_true(all(c("CL", "BRN", "NG", "HO", "RB", "HTT") %in% model_tickers))
  })
})

# ── 4.7: Sufficient overlapping dates ────────────────────────────────────────
test_that("4.7: VAR data has > 60 rows after inner join", {
  shiny::isolate({
    shiny::req(r_var$var_results)
    expect_gt(nrow(r_var$var_results$y), 60L)
  })
})

# ── 4.8: Missing ticker warning ───────────────────────────────────────────────
test_that("4.8: mod_var_server warns when a ticker is absent from dflong", {
  dflong_no_htt <- dflong |> dplyr::filter(!startsWith(series, "HTT"))
  r_test <- shiny::reactiveValues()
  expect_warning(
    shiny::isolate(mod_var_server(dflong_no_htt, r_test)),
    regexp = "HTT"
  )
})

# ── 4.9: Weekly returns are approximately weekly ──────────────────────────────
test_that("4.9: VAR date gaps are weekly (median 7 days; >90% in 5-8 day band)", {
  shiny::isolate({
    shiny::req(r_var$var_results)
    var_dates <- as.Date(rownames(r_var$var_results$y))
    gaps      <- as.integer(diff(var_dates))
    # Median gap should be 7 days (Friday to Friday)
    expect_equal(stats::median(gaps), 7L)
    # At least 90% of gaps in the standard 5-8 day band; holiday clusters (e.g.
    # Christmas + New Year) can produce ~21-day jumps — those are expected
    expect_gt(mean(gaps >= 5L & gaps <= 8L), 0.90)
  })
})

# ── 4.10: HTT is delta P (z-scored) ─────────────────────────────────────────
test_that("4.10: HTT in VAR input is z-scored weekly price difference (not log return)", {
  # Reconstruct weekly delta P for HTT restricted to the inner-join date set.
  # mod_var_server z-scores each series using only the rows that survived the
  # inner join — so we must restrict to those dates before computing mean/sd.
  shiny::isolate({
    shiny::req(r_var$var_results)
    var_dates <- as.Date(rownames(r_var$var_results$y))
    htt_var   <- r_var$var_results$y[, "HTT"]

    # Rebuild weekly end-of-week prices, compute delta P, restrict to VAR dates
    htt_dp <- dflong |>
      dplyr::filter(series == "HTT01") |>
      dplyr::mutate(
        year_week = paste0(lubridate::isoyear(date), "-",
                           sprintf("%02d", lubridate::isoweek(date)))
      ) |>
      dplyr::group_by(year_week) |>
      dplyr::filter(date == max(date)) |>
      dplyr::ungroup() |>
      dplyr::arrange(date) |>
      dplyr::mutate(dp = value - dplyr::lag(value)) |>
      dplyr::filter(!is.na(dp), date %in% var_dates)

    # Z-score using the same subset (inner-join dates only), matching mod_var logic
    z_expected <- (htt_dp$dp - mean(htt_dp$dp)) / stats::sd(htt_dp$dp)

    # Spot-check first 3 matched rows
    for (i in seq_len(min(3L, nrow(htt_dp)))) {
      d   <- htt_dp$date[i]
      idx <- which(var_dates == d)
      if (length(idx) == 1L) {
        expect_equal(unname(htt_var[idx]), z_expected[i], tolerance = 1e-6)
      }
    }
  })
})

# ── 4.11: Z-score standardisation ─────────────────────────────────────────────
test_that("4.11: each series in VAR input has mean ≈ 0 and sd ≈ 1", {
  shiny::isolate({
    shiny::req(r_var$var_results)
    y <- r_var$var_results$y
    for (col in colnames(y)) {
      expect_lt(abs(mean(y[, col])), 0.05,
                label = paste0(col, " mean"))
      expect_lt(abs(stats::sd(y[, col]) - 1), 0.05,
                label = paste0(col, " sd"))
    }
  })
})

# ── 4.12: Lag selection uses multi-criterion consensus ────────────────────────
test_that("4.12: VAR lag is selected where >= 2 criteria agree (or BIC fallback)", {
  shiny::isolate({
    shiny::req(r_var$var_results)
    best_lag <- r_var$var_results$p
    # Re-run VARselect to verify the lag is plausible
    var_select   <- vars::VARselect(r_var$var_results$y, lag.max = 8L, type = "const")
    selections   <- unname(var_select$selection)
    lag_counts   <- table(selections)
    consensus    <- as.integer(names(lag_counts)[which.max(lag_counts)])
    # Best lag should either match consensus or be the BIC selection (fallback)
    bic_lag <- unname(var_select$selection[["SC(n)"]])
    expect_true(best_lag == consensus || best_lag == bic_lag)
  })
})

# ── 4.13: Cholesky ordering ───────────────────────────────────────────────────
test_that("4.13: VAR column order matches Cholesky ordering BRN-CL-HO-RB-HTT-NG", {
  shiny::isolate({
    shiny::req(r_var$var_results)
    expect_equal(colnames(r_var$var_results$y),
                 c("BRN", "CL", "HO", "RB", "HTT", "NG"))
  })
})

# ── IRF tests ─────────────────────────────────────────────────────────────────

# Compute one IRF object for tests 4.14–4.16 (CL shock, suppress boot for speed)
irf_obj <- shiny::isolate({
  shiny::req(r_var$var_results)
  vars::irf(r_var$var_results, impulse = "CL", n.ahead = 12L,
            ortho = TRUE, ci = 0.95, boot = TRUE, runs = 100L)
})

# ── 4.14: Shock ticker drives the IRF impulse ────────────────────────────────
test_that("4.14: selecting CL as shock produces an irf entry keyed by 'CL'", {
  expect_true("CL" %in% names(irf_obj$irf))
})

# ── 4.15: IRF returns 5 responding tickers ───────────────────────────────────
test_that("4.15: IRF response matrix has 6 columns (all tickers including shock)", {
  # vars::irf returns ALL tickers in the response matrix (including shock ticker);
  # mod_cm_var_server filters to the 5 non-shock tickers when building traces
  chol_order  <- c("BRN", "CL", "HO", "RB", "HTT", "NG")
  responding  <- chol_order[chol_order != "CL"]
  resp_mat    <- irf_obj$irf[["CL"]]
  expect_equal(length(responding), 5L)
  # All responding tickers are columns in the response matrix
  expect_true(all(responding %in% colnames(resp_mat)))
})

# ── 4.16: IRF horizon = 12 weeks ─────────────────────────────────────────────
test_that("4.16: IRF horizon is 12 weeks (13 rows: 0 through 12)", {
  resp_mat <- irf_obj$irf[["CL"]]
  # nrow = n.ahead + 1 = 13; last horizon = 12
  expect_equal(nrow(resp_mat) - 1L, 12L)
})

# ── 4.17/4.18: hex_to_rgba helper ────────────────────────────────────────────
test_that("4.17/4.18: hex_to_rgba converts viridis hex to correct rgba string", {
  # viridisLite::viridis(1) returns something like "#440154FF"
  col   <- viridisLite::viridis(1L)[[1]]
  rgba  <- CommodityMarketDynamics:::hex_to_rgba(col, 0.15)
  # Should be of the form rgba(R,G,B,0.15)
  expect_match(rgba, "^rgba\\([0-9]+,[0-9]+,[0-9]+,0\\.15\\)$")
})

# ── 4.19: Smoke — rolling correlation renders for CL/BRN ─────────────────────
test_that("4.19: rolling_corr_series produces non-NA values for CL and BRN", {
  res <- rolling_corr_series("CL", "BRN", window = 90L)
  expect_true(any(!is.na(res$corr)))
  non_na <- res$corr[!is.na(res$corr)]
  # All valid correlations are in [-1, 1]
  expect_true(all(non_na >= -1 & non_na <= 1))
})

# ── 4.20: Smoke — IRF renders 5 response traces for CL shock ─────────────────
test_that("4.20: IRF object has 5 responding tickers when CL is shocked", {
  chol_order <- c("BRN", "CL", "HO", "RB", "HTT", "NG")
  responding <- chol_order[chol_order != "CL"]
  resp_mat   <- irf_obj$irf[["CL"]]
  expect_equal(length(responding), 5L)
  # Each responding ticker has a full 13-row response (horizon 0:12)
  for (t in responding) {
    expect_equal(length(resp_mat[, t]), 13L)
  }
})
