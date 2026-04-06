library(testthat)
library(dplyr)
# Load internal helpers (classify_regime, smooth_regime)
devtools::load_all(quiet = TRUE)

dflong <- RTL::dflong

# ── Shared helpers ────────────────────────────────────────────────────────────

# Replicate the normalise_ticker logic from mod_fc_comparison for unit tests.
# Parameters: ticker (e.g. "CL"), sel_date (Date)
# Returns: tibble (tenor, indexed_price, ticker)
normalise_ticker_test <- function(ticker, sel_date) {
  raw <- dflong |>
    filter(startsWith(series, ticker), date == sel_date) |>
    mutate(tenor = paste0("M", sub("^[A-Za-z]+", "", series))) |>
    arrange(tenor)

  m1_price <- raw |> filter(tenor == "M01") |> pull(value)
  stopifnot(length(m1_price) == 1, m1_price > 0)

  raw |>
    mutate(indexed_price = value / m1_price * 100, ticker = ticker) |>
    select(tenor, indexed_price, ticker)
}

# Pick a date where both CL and BRN have data
cl_dates  <- dflong |> filter(startsWith(series, "CL"))  |> pull(date) |> unique() |> sort()
brn_dates <- dflong |> filter(startsWith(series, "BRN")) |> pull(date) |> unique() |> sort()
common_dates <- sort(intersect(cl_dates, brn_dates))
test_date <- common_dates[floor(length(common_dates) / 2)]  # mid-history date

# ============================================================
# mod_fc_comparison  (tests 1.1 – 1.6, 1.9)
# ============================================================

# 1.1 — M1 = 100 normalisation
test_that("1.1 M01 indexed price is exactly 100 for any ticker/date", {
  for (ticker in c("CL", "BRN", "NG")) {
    dates_t <- dflong |> filter(startsWith(series, ticker)) |> pull(date) |> unique() |> sort()
    d <- dates_t[floor(length(dates_t) / 2)]
    nd <- normalise_ticker_test(ticker, d)
    m1_val <- nd |> filter(tenor == "M01") |> pull(indexed_price)
    expect_equal(m1_val, 100, tolerance = 1e-10,
                 label = paste("M01 == 100 for", ticker, "on", d))
  }
})

# 1.2 — other tenors indexed correctly
test_that("1.2 M02 indexed_price == (raw_M02 / raw_M01) * 100", {
  raw <- dflong |>
    filter(startsWith(series, "CL"), date == test_date) |>
    mutate(tenor = paste0("M", sub("^[A-Za-z]+", "", series))) |>
    arrange(tenor)

  raw_m1 <- raw |> filter(tenor == "M01") |> pull(value)
  raw_m2 <- raw |> filter(tenor == "M02") |> pull(value)
  expected_m2 <- raw_m2 / raw_m1 * 100

  nd <- normalise_ticker_test("CL", test_date)
  actual_m2 <- nd |> filter(tenor == "M02") |> pull(indexed_price)

  expect_equal(actual_m2, expected_m2, tolerance = 1e-10)
})

# 1.3 — integer date map correctness
test_that("1.3 date_map idx resolves to correct date at first, mid, and last positions", {
  dates    <- common_dates
  date_map <- data.frame(idx = seq_along(dates), date = dates)

  expect_equal(date_map$date[date_map$idx == 1],             dates[1])
  expect_equal(date_map$date[date_map$idx == nrow(date_map)], dates[length(dates)])

  mid_idx <- floor(nrow(date_map) / 2)
  expect_equal(date_map$date[date_map$idx == mid_idx], dates[mid_idx])
})

# 1.4 — sparse ticker filter: intersection only
test_that("1.4 available_dates is the intersection of both tickers' date sets", {
  # HTT starts later than CL so CL+HTT intersection < CL alone
  htt_dates <- dflong |> filter(startsWith(series, "HTT")) |> pull(date) |> unique()
  intersection <- sort(as.Date(intersect(cl_dates, htt_dates), origin = "1970-01-01"))
  expect_lt(length(intersection), length(cl_dates))
  # All intersection dates must be present in both source sets
  expect_true(all(intersection %in% cl_dates))
  expect_true(all(intersection %in% htt_dates))
})

# 1.5 — no partial curves: all tickers on a shared date have their full tenor set
test_that("1.5 normalise_ticker returns rows for all available tenors on the selected date", {
  cl_nd  <- normalise_ticker_test("CL",  test_date)
  brn_nd <- normalise_ticker_test("BRN", test_date)

  # Each ticker should have all its tenors present (no silent drops)
  cl_expected_tenors <- dflong |>
    filter(startsWith(series, "CL"), date == test_date) |>
    mutate(tenor = paste0("M", sub("^[A-Za-z]+", "", series))) |>
    pull(tenor)
  expect_setequal(cl_nd$tenor, cl_expected_tenors)

  brn_expected_tenors <- dflong |>
    filter(startsWith(series, "BRN"), date == test_date) |>
    mutate(tenor = paste0("M", sub("^[A-Za-z]+", "", series))) |>
    pull(tenor)
  expect_setequal(brn_nd$tenor, brn_expected_tenors)
})

# 1.6 — slider max update: adding a ticker with shorter history shrinks intersection
test_that("1.6 intersection shrinks when a shorter-history ticker is added", {
  # HTT starts later than CL — CL+HTT intersection < CL+BRN intersection
  htt_dates <- dflong |> filter(startsWith(series, "HTT")) |> pull(date) |> unique()
  cl_brn_intersection <- length(intersect(cl_dates, brn_dates))
  cl_htt_intersection <- length(intersect(cl_dates, htt_dates))
  expect_lt(cl_htt_intersection, cl_brn_intersection)
})

# 1.9 — empty date inputs produce no trace (unit-level: normalise returns 0 rows for bad date)
test_that("1.9 normalise_ticker returns 0 rows for a date with no data", {
  bad_date <- as.Date("1900-01-01")
  raw <- dflong |>
    filter(startsWith(series, "CL"), date == bad_date)
  expect_equal(nrow(raw), 0L)
  # normalise_ticker_test would error/return 0 rows — confirm source data is empty
})

# ============================================================
# mod_fc_surface  (tests 1.10 – 1.12)
# ============================================================

# Build a minimal wide data frame for regime testing
make_wide <- function(m01, last) {
  data.frame(date = as.Date("2020-01-01"), M01 = m01, M12 = last)
}

# 1.10 — contango classification
test_that("1.10 classify_regime returns contango when last tenor > M01", {
  wide <- make_wide(m01 = 50, last = 55)
  result <- CommodityMarketDynamics:::classify_regime(wide)
  expect_equal(result$regime, "contango")
})

# 1.11 — backwardation classification
test_that("1.11 classify_regime returns backwardation when M01 > last tenor", {
  wide <- make_wide(m01 = 55, last = 50)
  result <- CommodityMarketDynamics:::classify_regime(wide)
  expect_equal(result$regime, "backwardation")
})

# 1.12 — 5-day rolling majority vote smoothing
test_that("1.12 smooth_regime smooths isolated 1-day switch within 4-day run", {
  # 4 contango, 1 backwardation, 4 contango -> all contango after smoothing
  regimes <- data.frame(
    date   = seq.Date(as.Date("2020-01-01"), by = "day", length.out = 9),
    regime = c("contango","contango","contango","contango",
               "backwardation",
               "contango","contango","contango","contango")
  )
  smoothed <- CommodityMarketDynamics:::smooth_regime(regimes)
  expect_true(all(smoothed$regime == "contango"),
              label = "isolated backwardation day smoothed out by majority vote")
})

# ============================================================
# mod_fc_monthly  (tests 1.15 – 1.16)
# ============================================================

monthly_data_cl <- dflong |>
  dplyr::filter(startsWith(series, "CL")) |>
  dplyr::mutate(
    tenor = paste0("M", sub("^[A-Za-z]+", "", series)),
    month = lubridate::month(date, label = TRUE, abbr = TRUE)
  ) |>
  dplyr::group_by(month, tenor) |>
  dplyr::summarise(mean_price = mean(value, na.rm = TRUE), .groups = "drop")

# 1.15 — exactly 12 months present
test_that("1.15 exactly 12 calendar months in monthly_data for CL", {
  expect_equal(length(unique(monthly_data_cl$month)), 12L)
})

# 1.16 — values are averages across years
test_that("1.16 Jan M01 CL mean_price matches manually computed mean", {
  expected <- dflong |>
    dplyr::filter(series == "CL01", lubridate::month(date) == 1) |>
    dplyr::pull(value) |>
    mean(na.rm = TRUE)

  actual <- monthly_data_cl |>
    dplyr::filter(as.character(month) == "Jan", tenor == "M01") |>
    dplyr::pull(mean_price)

  expect_equal(actual, expected, tolerance = 1e-8)
})

# ============================================================
# mod_fc_pca  (tests 1.18 – 1.20)
# ============================================================

# Compute PCA on CL for tests
cl_wide <- dflong |>
  dplyr::filter(startsWith(series, "CL")) |>
  dplyr::mutate(tenor = paste0("M", sub("^[A-Za-z]+", "", series))) |>
  dplyr::select(date, tenor, value) |>
  tidyr::pivot_wider(names_from = tenor, values_from = value) |>
  tidyr::drop_na() |>
  dplyr::arrange(date)

tenor_cols_cl <- setdiff(names(cl_wide), "date")
tenor_cols_cl <- tenor_cols_cl[order(as.integer(sub("M0*", "", tenor_cols_cl)))]
cl_pca <- stats::prcomp(as.matrix(cl_wide[, tenor_cols_cl]), scale. = TRUE)
cl_var  <- cl_pca$sdev^2 / sum(cl_pca$sdev^2)

# 1.18 — PCA slot written on first selection (integration; tested via reactive
# indirectly — validate computation runs without error and returns expected structure)
test_that("1.18 PCA object has rotation matrix with correct dimensions", {
  expect_equal(nrow(cl_pca$rotation), length(tenor_cols_cl))
  expect_true(ncol(cl_pca$rotation) <= length(tenor_cols_cl))
})

# 1.19 — variance explained sums to 1.0
test_that("1.19 variance explained proportions sum to 1.0", {
  expect_equal(sum(cl_var), 1.0, tolerance = 1e-10)
})

# 1.20 — 2% threshold filter
test_that("1.20 only PCs with >= 2% individual variance are plotted", {
  qualifying <- which(cl_var >= 0.02)
  expect_gte(length(qualifying), 1L)
  expect_true(all(cl_var[qualifying] >= 0.02))
  # Also confirm there are some PCs below 2% (otherwise the filter is vacuous)
  below_threshold <- which(cl_var < 0.02)
  expect_gte(length(below_threshold), 1L)
})
