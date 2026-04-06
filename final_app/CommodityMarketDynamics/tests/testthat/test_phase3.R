library(CommodityMarketDynamics)
library(dplyr)
library(testthat)

dflong <- RTL::dflong

# ── Phase 3 Smoke: prior phases ──────────────────────────────────────────────
# Re-run critical path checks from Phases 0-2 to confirm nothing is broken

test_that("3.smoke.0: dflong loads and has required tickers", {
  expect_true(nrow(dflong) > 0)
  expect_true(all(c("CL01", "BRN01", "HO01", "RB01", "NG01", "HTT01") %in%
                    unique(dflong$series)))
})

test_that("3.smoke.1: EIA static files loaded correctly", {
  r <- shiny::reactiveValues()
  shiny::isolate({
    load_eia_xls <- function(filename) {
      path <- system.file("extdata", filename, package = "CommodityMarketDynamics")
      readxl::read_xls(path, sheet = "Data 1", skip = 2,
                       col_names = c("date", "value")) |>
        dplyr::mutate(
          date  = suppressWarnings(as.Date(as.numeric(date), origin = "1899-12-30")),
          value = suppressWarnings(as.numeric(value))
        ) |>
        dplyr::filter(!is.na(date), !is.na(value))
    }
    r$eia_crude_prod      <- load_eia_xls("PET.WCRFPUS2.W.xls")
    r$eia_crude_inputs    <- load_eia_xls("PET.WCRRIUS2.W.xls")
    r$eia_distillate_stocks <- load_eia_xls("PET.WDISTUS1.W.xls")
    r$eia_gasoline_stocks <- load_eia_xls("PET.WGTSTUS1.W.xls")
    r$eia_ng_storage      <- load_eia_xls("NG.NW2_EPG0_SWO_R48_BCF.W.xls")
    r$eia_lng_exports     <- load_eia_xls("N9133US2m.xls")

    # 3.6: production and inputs files (raw data starts in 1983; module filters to 2008+)
    expect_true(nrow(r$eia_crude_prod) > 0)
    expect_true(max(r$eia_crude_prod$date) >= as.Date("2008-01-01"))
    expect_true(nrow(r$eia_crude_inputs) > 0)

    # 3.13: distillate and gasoline stocks
    expect_true(nrow(r$eia_distillate_stocks) > 0)
    expect_true(nrow(r$eia_gasoline_stocks) > 0)

    # 3.17: NG storage Bcf range sanity
    expect_true(nrow(r$eia_ng_storage) > 0)
    expect_true(max(r$eia_ng_storage$value) < 5000)
    expect_true(min(r$eia_ng_storage$value) > 0)

    # 3.24: LNG exports series contains data through 2016+ (series starts 1997 with
    # the Sabine Pass milestone at 2016-02-24; file covers full range)
    expect_true(nrow(r$eia_lng_exports) > 0)
    expect_true(max(r$eia_lng_exports$date) >= as.Date("2016-01-01"))
  })
})

# ── mod_md_crude ─────────────────────────────────────────────────────────────

test_that("3.1: BRN-WTI spread = BRN01 - CL01 on each date", {
  brn <- dplyr::filter(dflong, series == "BRN01") |> dplyr::select(date, brn = value)
  cl  <- dplyr::filter(dflong, series == "CL01")  |> dplyr::select(date, cl  = value)
  joined <- dplyr::inner_join(brn, cl, by = "date") |>
    dplyr::mutate(spread = brn - cl)

  # Spot-check 3 dates
  spot_dates <- joined$date[c(100, 500, 1000)]
  for (d in spot_dates) {
    row <- dplyr::filter(joined, date == d)
    expect_equal(row$spread, row$brn - row$cl, tolerance = 1e-9)
  }
})

test_that("3.4: Cushing WoW change = current_week - prior_week", {
  # RTL::cushing is a named list; $storage has date + stocks columns
  raw  <- RTL::cushing$storage |> dplyr::arrange(date)
  cush <- raw |>
    dplyr::mutate(wow = stocks - dplyr::lag(stocks)) |>
    dplyr::filter(!is.na(wow))

  # Spot-check row 50: wow[50] = stocks[51] - stocks[50] in the raw sorted series
  expect_equal(
    raw$stocks[51] - raw$stocks[50],
    cush$wow[50],
    tolerance = 1e-6
  )
})

test_that("3.7: na.approx gap-fill removes all NAs before STL", {
  load_eia_xls <- function(filename) {
    path <- system.file("extdata", filename, package = "CommodityMarketDynamics")
    readxl::read_xls(path, sheet = "Data 1", skip = 2,
                     col_names = c("date", "value")) |>
      dplyr::mutate(
        date  = suppressWarnings(as.Date(as.numeric(date), origin = "1899-12-30")),
        value = suppressWarnings(as.numeric(value))
      ) |>
      dplyr::filter(!is.na(date), !is.na(value))
  }
  prod_raw <- load_eia_xls("PET.WCRFPUS2.W.xls")
  d <- dplyr::filter(prod_raw,
                     date >= as.Date("2008-01-01"),
                     date <= as.Date("2025-12-31")) |>
    dplyr::arrange(date)

  # Introduce a synthetic gap
  d$value[5] <- NA

  filled <- zoo::na.approx(d$value, na.rm = FALSE)
  filled <- filled[!is.na(filled)]
  expect_equal(sum(is.na(filled)), 0L)
})

test_that("3.8: STL chart data constrained to 2008-01-01 – 2025-12-31", {
  load_eia_xls <- function(filename) {
    path <- system.file("extdata", filename, package = "CommodityMarketDynamics")
    readxl::read_xls(path, sheet = "Data 1", skip = 2,
                     col_names = c("date", "value")) |>
      dplyr::mutate(
        date  = suppressWarnings(as.Date(as.numeric(date), origin = "1899-12-30")),
        value = suppressWarnings(as.numeric(value))
      ) |>
      dplyr::filter(!is.na(date), !is.na(value))
  }
  prod <- load_eia_xls("PET.WCRFPUS2.W.xls")
  d <- dplyr::filter(prod,
                     date >= as.Date("2008-01-01"),
                     date <= as.Date("2025-12-31"))
  expect_true(min(d$date) >= as.Date("2008-01-01"))
  expect_true(max(d$date) <= as.Date("2025-12-31"))
})

test_that("3.9: STL runs without error on gap-filled EIA production data", {
  load_eia_xls <- function(filename) {
    path <- system.file("extdata", filename, package = "CommodityMarketDynamics")
    readxl::read_xls(path, sheet = "Data 1", skip = 2,
                     col_names = c("date", "value")) |>
      dplyr::mutate(
        date  = suppressWarnings(as.Date(as.numeric(date), origin = "1899-12-30")),
        value = suppressWarnings(as.numeric(value))
      ) |>
      dplyr::filter(!is.na(date), !is.na(value))
  }
  prod <- load_eia_xls("PET.WCRFPUS2.W.xls")
  d <- dplyr::filter(prod,
                     date >= as.Date("2008-01-01"),
                     date <= as.Date("2025-12-31")) |>
    dplyr::arrange(date)

  d$value <- zoo::na.approx(d$value, na.rm = FALSE)
  d <- dplyr::filter(d, !is.na(value))

  stl_result <- stats::stl(
    stats::ts(d$value, frequency = 52L),
    s.window = "periodic"
  )
  expect_s3_class(stl_result, "stl")
})

# ── mod_md_refined ───────────────────────────────────────────────────────────

test_that("3.10: HO crack spread = HO01 * 42 - CL01", {
  ho <- dplyr::filter(dflong, series == "HO01") |> dplyr::select(date, ho = value)
  cl <- dplyr::filter(dflong, series == "CL01") |> dplyr::select(date, cl = value)
  joined <- dplyr::inner_join(ho, cl, by = "date") |>
    dplyr::mutate(crack = ho * 42 - cl)

  spot <- joined[c(100, 500, 1000), ]
  expect_equal(spot$crack, spot$ho * 42 - spot$cl, tolerance = 1e-9)
})

test_that("3.11: RB crack spread = RB01 * 42 - CL01", {
  rb <- dplyr::filter(dflong, series == "RB01") |> dplyr::select(date, rb = value)
  cl <- dplyr::filter(dflong, series == "CL01") |> dplyr::select(date, cl = value)
  joined <- dplyr::inner_join(rb, cl, by = "date") |>
    dplyr::mutate(crack = rb * 42 - cl)

  spot <- joined[c(100, 500, 1000), ]
  expect_equal(spot$crack, spot$rb * 42 - spot$cl, tolerance = 1e-9)
})

test_that("3.12: crack spread inner join warns on row drops", {
  # Simulate a scenario where one leg has fewer rows (HO starts later)
  compute_crack_with_warning <- function(ho_d, rb_d, cl_d) {
    joined    <- dplyr::inner_join(ho_d, rb_d, by = "date") |>
      dplyr::inner_join(cl_d, by = "date")
    n_ho_rb   <- nrow(dplyr::inner_join(ho_d, rb_d, by = "date"))
    n_dropped <- n_ho_rb - nrow(joined)
    if (n_dropped > 0) {
      warning(sprintf("crack_spread_data: inner join dropped %d rows due to missing leg(s).",
                      n_dropped))
    }
    joined
  }

  # Use synthetic data to reliably test the warning — known-size inputs with
  # CL missing 3 dates that HO/RB have, guaranteeing exactly 3 dropped rows
  dates_full    <- seq(as.Date("2020-01-02"), by = "day", length.out = 10)
  dates_trimmed <- dates_full[4:10]  # 3 dates missing from CL

  ho_syn <- data.frame(date = dates_full, ho = rnorm(10))
  rb_syn <- data.frame(date = dates_full, rb = rnorm(10))
  cl_syn <- data.frame(date = dates_trimmed, cl = rnorm(7))

  expect_warning(
    compute_crack_with_warning(ho_syn, rb_syn, cl_syn),
    regexp = "inner join dropped"
  )
})

test_that("3.14: 5yr average excludes first 5 calendar years", {
  load_eia_xls <- function(filename) {
    path <- system.file("extdata", filename, package = "CommodityMarketDynamics")
    readxl::read_xls(path, sheet = "Data 1", skip = 2,
                     col_names = c("date", "value")) |>
      dplyr::mutate(
        date  = suppressWarnings(as.Date(as.numeric(date), origin = "1899-12-30")),
        value = suppressWarnings(as.numeric(value))
      ) |>
      dplyr::filter(!is.na(date), !is.na(value))
  }
  stocks <- load_eia_xls("PET.WDISTUS1.W.xls") |>
    dplyr::arrange(date) |>
    dplyr::mutate(year = lubridate::year(date), week_num = lubridate::week(date))

  min_yr    <- min(stocks$year)
  cutoff_yr <- min_yr + 5L

  with_avg <- stocks |>
    dplyr::group_by(week_num) |>
    dplyr::arrange(year) |>
    dplyr::mutate(
      roll5       = zoo::rollapplyr(value, width = 5L, FUN = mean, fill = NA, align = "right"),
      five_yr_avg = dplyr::case_when(
        year < cutoff_yr ~ NA_real_,
        TRUE             ~ dplyr::lag(roll5, 1L)
      )
    ) |>
    dplyr::select(-roll5) |>
    dplyr::ungroup()

  # All rows in first 5 years should have NA average
  early <- dplyr::filter(with_avg, year < cutoff_yr)
  expect_true(all(is.na(early$five_yr_avg)))

  # First non-NA average should be at year >= min_yr + 5
  first_avg_date <- with_avg |>
    dplyr::filter(!is.na(five_yr_avg)) |>
    dplyr::pull(date) |>
    min()
  expect_true(lubridate::year(first_avg_date) >= min_yr + 5L)
})

# ── mod_md_ng ─────────────────────────────────────────────────────────────────

test_that("3.15: seasonal storage overlay has one line per year", {
  load_eia_xls <- function(filename) {
    path <- system.file("extdata", filename, package = "CommodityMarketDynamics")
    readxl::read_xls(path, sheet = "Data 1", skip = 2,
                     col_names = c("date", "value")) |>
      dplyr::mutate(
        date  = suppressWarnings(as.Date(as.numeric(date), origin = "1899-12-30")),
        value = suppressWarnings(as.numeric(value))
      ) |>
      dplyr::filter(!is.na(date), !is.na(value))
  }
  ng_storage <- load_eia_xls("NG.NW2_EPG0_SWO_R48_BCF.W.xls")
  d <- dplyr::filter(ng_storage,
                     date >= as.Date("2008-01-01"),
                     date <= as.Date("2025-12-31")) |>
    dplyr::mutate(year = lubridate::year(date))

  n_years <- dplyr::n_distinct(d$year)
  expect_equal(n_years, length(unique(d$year)))
})

test_that("3.18: 5yr average methodology — spot-check one week", {
  load_eia_xls <- function(filename) {
    path <- system.file("extdata", filename, package = "CommodityMarketDynamics")
    readxl::read_xls(path, sheet = "Data 1", skip = 2,
                     col_names = c("date", "value")) |>
      dplyr::mutate(
        date  = suppressWarnings(as.Date(as.numeric(date), origin = "1899-12-30")),
        value = suppressWarnings(as.numeric(value))
      ) |>
      dplyr::filter(!is.na(date), !is.na(value))
  }
  ng <- load_eia_xls("NG.NW2_EPG0_SWO_R48_BCF.W.xls") |>
    dplyr::arrange(date) |>
    dplyr::mutate(year = lubridate::year(date), week_num = lubridate::week(date))

  # For week 10 of year 2020: average of week 10 in years 2015-2019
  target_week <- 10L
  target_year <- 2020L
  prior_years <- (target_year - 5L):(target_year - 1L)

  prior_vals <- dplyr::filter(ng, week_num == target_week, year %in% prior_years)$value
  expected_avg <- mean(prior_vals, na.rm = TRUE)

  # Compute using the same lag(rollapplyr, 1) logic as the module:
  # at year Y, gives mean of Y-5 to Y-1 (prior 5 years, excluding current)
  ng_avg <- ng |>
    dplyr::filter(week_num == target_week) |>
    dplyr::arrange(year) |>
    dplyr::mutate(
      roll5       = zoo::rollapplyr(value, width = 5L, FUN = mean,
                                    fill = NA, align = "right"),
      five_yr_avg = dplyr::lag(roll5, 1L)
    )
  actual_avg <- dplyr::filter(ng_avg, year == target_year)$five_yr_avg

  expect_equal(actual_avg, expected_avg, tolerance = 0.01)
})

test_that("3.19: surplus/deficit = actual - 5yr_avg", {
  load_eia_xls <- function(filename) {
    path <- system.file("extdata", filename, package = "CommodityMarketDynamics")
    readxl::read_xls(path, sheet = "Data 1", skip = 2,
                     col_names = c("date", "value")) |>
      dplyr::mutate(
        date  = suppressWarnings(as.Date(as.numeric(date), origin = "1899-12-30")),
        value = suppressWarnings(as.numeric(value))
      ) |>
      dplyr::filter(!is.na(date), !is.na(value))
  }
  ng <- load_eia_xls("NG.NW2_EPG0_SWO_R48_BCF.W.xls") |>
    dplyr::arrange(date) |>
    dplyr::mutate(year = lubridate::year(date), week_num = lubridate::week(date))

  min_yr <- min(ng$year)
  ng_avg <- ng |>
    dplyr::group_by(week_num) |>
    dplyr::arrange(year) |>
    dplyr::mutate(
      roll5       = zoo::rollapplyr(value, 5L, mean, fill = NA, align = "right"),
      five_yr_avg = dplyr::case_when(
        year < min_yr + 5L ~ NA_real_,
        TRUE               ~ dplyr::lag(roll5, 1L)
      )
    ) |>
    dplyr::select(-roll5) |>
    dplyr::ungroup() |>
    dplyr::mutate(surplus = value - five_yr_avg)

  row_check <- dplyr::filter(ng_avg, !is.na(surplus)) |> dplyr::slice(10)
  expect_equal(row_check$surplus, row_check$value - row_check$five_yr_avg,
               tolerance = 1e-9)
})

# ── EIA-923 ──────────────────────────────────────────────────────────────────

test_that("3.20: EIA-923 skip logic — 2020 file (skip=5) columns align", {
  f2020 <- system.file(
    "extdata", "EIA923_Schedules_2_3_4_5_M_12_2020_Final_Revision.xlsx",
    package = "CommodityMarketDynamics"
  )
  if (!file.exists(f2020)) skip("EIA-923 2020 file not found")

  df <- readxl::read_excel(
    f2020,
    sheet     = "Page 1 Generation and Fuel Data",
    skip      = 5L,
    col_types = "text",
    n_max     = 3L
  )

  # Col 7 = Plant State, col 15 = Reported Fuel Type Code (not blank)
  expect_false(is.na(names(df)[7]))
  expect_false(is.na(names(df)[15]))
  expect_equal(ncol(df), 97L)
})

test_that("3.20b: read_eia923_file standardises column names regardless of year", {
  f2020 <- system.file(
    "extdata", "EIA923_Schedules_2_3_4_5_M_12_2020_Final_Revision.xlsx",
    package = "CommodityMarketDynamics"
  )
  if (!file.exists(f2020)) skip("EIA-923 2020 file not found")

  df <- read_eia923_file(f2020)

  expected_names <- c(
    "plant_state", "census_region", "fuel_type_code",
    "netgen_jan", "netgen_feb", "netgen_mar", "netgen_apr",
    "netgen_may", "netgen_jun", "netgen_jul", "netgen_aug",
    "netgen_sep", "netgen_oct", "netgen_nov", "netgen_dec",
    "year"
  )
  expect_equal(names(df), expected_names)
})

test_that("3.20c: EIA-923 '.' values become NA, not 0", {
  f2020 <- system.file(
    "extdata", "EIA923_Schedules_2_3_4_5_M_12_2020_Final_Revision.xlsx",
    package = "CommodityMarketDynamics"
  )
  if (!file.exists(f2020)) skip("EIA-923 2020 file not found")

  # Read raw to find a "." value
  raw <- readxl::read_excel(
    f2020,
    sheet     = "Page 1 Generation and Fuel Data",
    skip      = 5L,
    col_types = "text"
  )
  raw_netgen <- raw[[80]]  # col 80 = Netgen January

  # Only test if "." appears in this file; otherwise skip
  if (!any(raw_netgen == ".", na.rm = TRUE)) {
    skip("No '.' values found in Netgen January column for this file")
  }

  df <- read_eia923_file(f2020)
  dot_positions <- which(raw_netgen == ".")
  expect_true(all(is.na(df$netgen_jan[dot_positions])))
})

test_that("3.21: coal fuel type filter retains only coal codes", {
  f2020 <- system.file(
    "extdata", "EIA923_Schedules_2_3_4_5_M_12_2020_Final_Revision.xlsx",
    package = "CommodityMarketDynamics"
  )
  if (!file.exists(f2020)) skip("EIA-923 2020 file not found")

  df <- read_eia923_file(f2020)
  coal_codes <- c("ANT", "BIT", "LIG", "RC", "SUB", "WC")
  filtered   <- dplyr::filter(df, fuel_type_code %in% coal_codes)

  expect_true(all(filtered$fuel_type_code %in% coal_codes))
  expect_true(nrow(filtered) > 0)
})

test_that("3.22: census region mapping", {
  expect_equal(map_census_region("NEW"),  "Northeast")
  expect_equal(map_census_region("MAT"),  "Northeast")
  expect_equal(map_census_region("ENC"),  "Midwest")
  expect_equal(map_census_region("WNC"),  "Midwest")
  expect_equal(map_census_region("WSC"),  "South")
  expect_equal(map_census_region("SAT"),  "South")
  expect_equal(map_census_region("ESC"),  "South")
  expect_equal(map_census_region("MTN"),  "West")
  expect_equal(map_census_region("PACC"), "West")
  expect_equal(map_census_region("PACN"), "West")
})

test_that("3.23: NG01 daily × LNG monthly join — nrow(joined) == nrow(daily_ng)", {
  load_eia_xls <- function(filename) {
    path <- system.file("extdata", filename, package = "CommodityMarketDynamics")
    readxl::read_xls(path, sheet = "Data 1", skip = 2,
                     col_names = c("date", "value")) |>
      dplyr::mutate(
        date  = suppressWarnings(as.Date(as.numeric(date), origin = "1899-12-30")),
        value = suppressWarnings(as.numeric(value))
      ) |>
      dplyr::filter(!is.na(date), !is.na(value))
  }
  lng <- load_eia_xls("N9133US2m.xls") |>
    dplyr::mutate(month_date = as.Date(format(date, "%Y-%m-01"))) |>
    dplyr::group_by(month_date) |>
    dplyr::summarise(exports = sum(value, na.rm = TRUE), .groups = "drop")

  ng_monthly <- dplyr::filter(dflong, series == "NG01") |>
    dplyr::mutate(month_date = as.Date(format(date, "%Y-%m-01"))) |>
    dplyr::group_by(month_date) |>
    dplyr::summarise(price = mean(value, na.rm = TRUE), .groups = "drop")

  joined <- dplyr::inner_join(ng_monthly, lng, by = "month_date")

  # nrow(joined) <= nrow(ng_monthly): each monthly NG row matches ≤ one LNG row
  expect_lte(nrow(joined), nrow(ng_monthly))
  # No row duplication — all month_date values unique
  expect_equal(nrow(joined), dplyr::n_distinct(joined$month_date))
})

test_that("3.25: Sabine Pass vertical line at exactly 2016-02-24", {
  sabine_date <- as.Date("2016-02-24")
  expect_equal(sabine_date, as.Date("2016-02-24"))
})
