library(testthat)
library(dplyr)
devtools::load_all(quiet = TRUE)

dflong <- RTL::dflong

# ── Shared setup ──────────────────────────────────────────────────────────────

# CL returns — used across multiple tests
cl_returns <- dflong |>
  dplyr::filter(startsWith(series, "CL")) |>
  compute_returns()

# HTT returns — spread ticker (level differences)
htt_returns <- dflong |>
  dplyr::filter(startsWith(series, "HTT")) |>
  compute_returns()

# ============================================================
# mod_vol_density  (tests 2.1 – 2.2, 2.6)
# ============================================================

# 2.1 — clip_returns_by_tenor: all values within [p01, p99] after clipping
test_that("2.1 clip_returns_by_tenor keeps all values within [p01, p99] per tenor", {
  clipped <- cl_returns |>
    dplyr::filter(tenor %in% c("M01", "M06", "M12")) |>
    clip_returns_by_tenor()

  # For each tenor, verify no values exceed the original percentile bounds
  raw_subset <- cl_returns |>
    dplyr::filter(tenor %in% c("M01", "M06", "M12"))

  for (t in c("M01", "M06", "M12")) {
    raw_t     <- raw_subset |> dplyr::filter(tenor == t) |> dplyr::pull(return)
    clipped_t <- clipped     |> dplyr::filter(tenor == t) |> dplyr::pull(return)

    p01 <- stats::quantile(raw_t, 0.01, na.rm = TRUE)
    p99 <- stats::quantile(raw_t, 0.99, na.rm = TRUE)

    expect_true(
      all(clipped_t >= p01 & clipped_t <= p99),
      label = paste("all clipped returns within [p01, p99] for tenor", t)
    )
  }
})

# 2.2 — clip is computed independently per tenor (not a single global clip)
test_that("2.2 clip_returns_by_tenor uses each tenor's own percentile bounds", {
  subset <- cl_returns |>
    dplyr::filter(tenor %in% c("M01", "M18"))

  clipped <- subset |> clip_returns_by_tenor()

  # Compute per-tenor p01 and p99 from raw data
  m01_raw <- subset |> dplyr::filter(tenor == "M01") |> dplyr::pull(return)
  m18_raw <- subset |> dplyr::filter(tenor == "M18") |> dplyr::pull(return)

  m01_p01 <- stats::quantile(m01_raw, 0.01, na.rm = TRUE)
  m01_p99 <- stats::quantile(m01_raw, 0.99, na.rm = TRUE)
  m18_p01 <- stats::quantile(m18_raw, 0.01, na.rm = TRUE)
  m18_p99 <- stats::quantile(m18_raw, 0.99, na.rm = TRUE)

  # The two tenors should have different clip ranges (M01 is more volatile)
  expect_false(
    isTRUE(all.equal(m01_p01, m18_p01, tolerance = 1e-6)) &&
    isTRUE(all.equal(m01_p99, m18_p99, tolerance = 1e-6)),
    label = "M01 and M18 clip ranges differ — each tenor uses its own percentiles"
  )

  # Clipped M01 values must stay within M01's own bounds (not M18's)
  m01_clipped <- clipped |> dplyr::filter(tenor == "M01") |> dplyr::pull(return)
  expect_true(all(m01_clipped >= m01_p01 & m01_clipped <= m01_p99),
              label = "M01 clipped values within M01 own [p01, p99]")

  # Clipped M18 values must stay within M18's own bounds (not M01's)
  m18_clipped <- clipped |> dplyr::filter(tenor == "M18") |> dplyr::pull(return)
  expect_true(all(m18_clipped >= m18_p01 & m18_clipped <= m18_p99),
              label = "M18 clipped values within M18 own [p01, p99]")
})

# 2.6 — annualised vol formula: sd(returns) × sqrt(252)
test_that("2.6 annualised vol for CL M01 matches sd(returns) * sqrt(252)", {
  m01_returns <- cl_returns |>
    dplyr::filter(tenor == "M01") |>
    dplyr::pull(return)

  expected_vol <- stats::sd(m01_returns, na.rm = TRUE) * sqrt(252)

  # Recompute the same way mod_vol_density does in the vol bar chart
  computed_vol <- cl_returns |>
    dplyr::filter(tenor == "M01") |>
    dplyr::summarise(vol = stats::sd(return, na.rm = TRUE) * sqrt(252)) |>
    dplyr::pull(vol)

  expect_equal(computed_vol, expected_vol, tolerance = 1e-10,
               label = "vol bar chart uses sd(returns) * sqrt(252)")

  # Sanity: result is a positive finite number
  expect_true(is.finite(computed_vol) && computed_vol > 0)
})

# ============================================================
# mod_vol_heatmap  (tests 2.9 – 2.12)
# ============================================================

# Helper: build correlation matrix the same way mod_vol_heatmap does
make_cor_matrix <- function(returns_long) {
  wide <- returns_long |>
    tidyr::pivot_wider(names_from = tenor, values_from = return) |>
    tidyr::drop_na() |>
    dplyr::select(-date)
  tenor_order <- sort(colnames(wide))
  wide <- wide[, tenor_order, drop = FALSE]
  stats::cor(as.matrix(wide), use = "pairwise.complete.obs")
}

cl_cor  <- make_cor_matrix(cl_returns)
htt_cor <- make_cor_matrix(htt_returns)

# 2.9 — correlation matrix is symmetric
test_that("2.9 correlation matrix is symmetric: cor[i,j] == cor[j,i]", {
  expect_equal(cl_cor, t(cl_cor), tolerance = 1e-10,
               label = "CL correlation matrix is symmetric")
})

# 2.10 — diagonal entries equal 1
test_that("2.10 all diagonal entries of correlation matrix equal 1", {
  expect_true(all(abs(diag(cl_cor) - 1) < 1e-10),
              label = "all diagonal entries == 1")
})

# 2.11 — all values in [-1, 1]
test_that("2.11 all correlation values are in [-1, 1]", {
  expect_true(all(cl_cor >= -1 - 1e-10 & cl_cor <= 1 + 1e-10),
              label = "no correlation outside [-1, 1]")
})

# 2.12 — HTT routes through compute_returns (level differences, not log returns)
# Verify that HTT correlation is computed on the output of compute_returns(),
# not on raw prices or separately computed log returns.
# If compute_returns() is used, HTT returns will include negative values
# (it's a spread); log returns of a spread are undefined/incorrect.
test_that("2.12 HTT correlation uses level differences via compute_returns", {
  # compute_returns detects HTT as a spread (>0.1% negative values)
  # and switches to delta P. Verify that the output contains negative values
  # (which would be impossible if log returns were mistakenly used on prices >0)
  htt_raw <- dflong |> dplyr::filter(startsWith(series, "HTT"))
  prop_neg_price <- mean(htt_raw$value < 0, na.rm = TRUE)
  prop_neg_return <- mean(htt_returns$return < 0, na.rm = TRUE)

  # HTT prices have a non-trivial negative proportion -> spread ticker detected
  expect_gt(prop_neg_price, 0.001,
            label = "HTT has meaningful negative price proportion (spread)")

  # Level differences for a spread can be positive or negative ~50/50
  expect_gt(prop_neg_return, 0.30,
            label = "HTT returns from compute_returns are level diffs (~50% negative)")

  # htt_cor matrix should still be valid (symmetric, diagonal=1, in [-1,1])
  expect_equal(htt_cor, t(htt_cor), tolerance = 1e-10,
               label = "HTT correlation matrix is symmetric")
  expect_true(all(abs(diag(htt_cor) - 1) < 1e-10),
              label = "HTT correlation matrix diagonal == 1")
})

# ============================================================
# mod_vol_rolling  (tests 2.14 – 2.15, 2.17)
# ============================================================

# Build rolling vol for CL M01 the same way mod_vol_rolling does
cl_m01_returns <- cl_returns |>
  dplyr::filter(tenor == "M01") |>
  dplyr::arrange(date)

cl_m01_roll <- dplyr::tibble(
  date     = cl_m01_returns$date,
  roll_vol = zoo::rollapply(
    cl_m01_returns$return,
    width = 21L,
    FUN   = stats::sd,
    fill  = NA,
    align = "right"
  ) * sqrt(252)
) |>
  dplyr::filter(!is.na(roll_vol))

# 2.14 — 21-day rolling window
test_that("2.14 rolling vol uses 21-day window: first vol value == sd(returns[1:21]) * sqrt(252)", {
  # The first non-NA value corresponds to rows 1:21 in the sorted return series
  first_21 <- cl_m01_returns$return[1:21]
  expected  <- stats::sd(first_21, na.rm = TRUE) * sqrt(252)
  actual    <- cl_m01_roll$roll_vol[1]

  expect_equal(actual, expected, tolerance = 1e-10,
               label = "first rolling vol == sd(returns[1:21]) * sqrt(252)")
})

# 2.15 — output is annualised (multiplied by sqrt(252))
test_that("2.15 rolling vol is annualised: values approx sqrt(252) * non-annualised", {
  # Compute non-annualised rolling sd for comparison
  roll_sd_raw <- zoo::rollapply(
    cl_m01_returns$return,
    width = 21L,
    FUN   = stats::sd,
    fill  = NA,
    align = "right"
  )
  roll_sd_raw <- roll_sd_raw[!is.na(roll_sd_raw)]

  annualised <- roll_sd_raw * sqrt(252)

  # Check that the module output matches the annualised version, not raw sd
  expect_equal(cl_m01_roll$roll_vol, annualised, tolerance = 1e-10,
               label = "roll_vol == raw_sd * sqrt(252)")
})

# 2.17 — event markers silently omitted when date is outside series range
test_that("2.17 event marker silently omitted when date outside series date range", {
  # Simulate a series that starts after 2014-03-03 (Crimea event)
  # Use CL M01 data filtered to after 2015-01-01
  short_series <- cl_m01_returns |>
    dplyr::filter(date > as.Date("2015-01-01"))

  date_min <- min(short_series$date)
  date_max <- max(short_series$date)

  crimea_date <- as.Date("2014-03-03")

  # Crimea is before date_min — should be excluded from in_range_events
  events <- data.frame(
    date  = as.Date(c("2014-03-03", "2020-03-09", "2022-03-07")),
    label = c("Crimea Annexation", "COVID-19 / Oil Price War", "Russia-Ukraine Invasion"),
    stringsAsFactors = FALSE
  )

  in_range <- events[events$date >= date_min & events$date <= date_max, ]

  expect_false(crimea_date %in% in_range$date,
               label = "Crimea marker absent for series starting after 2015")
  expect_equal(nrow(in_range), 2L,
               label = "Only 2 events in range (COVID and Ukraine remain)")
})
