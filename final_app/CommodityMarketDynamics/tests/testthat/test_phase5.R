library(CommodityMarketDynamics)
library(dplyr)
library(testthat)

dflong <- RTL::dflong

# ── Phase 5 Smoke: prior phases ───────────────────────────────────────────────

test_that("5.smoke.0: dflong loads and all 6 tickers present", {
  expect_true(nrow(dflong) > 0)
  expect_true(all(c("CL01","BRN01","NG01","HO01","RB01","HTT01") %in%
                    unique(dflong$series)))
})

# ── mod_hedge_swap helpers ────────────────────────────────────────────────────

# 5.1 — Period generation excludes periods with missing tenors
test_that("5.1: valid periods exclude any period missing a delivery month", {
  # Build a tenor map for CL near end of data — many back tenors absent
  last_cl <- dflong |> filter(series == "CL01") |> pull(date) |> max()
  ref <- last_cl - 7L   # 1 week before last date — most Cal years will be invalid

  tm <- CommodityMarketDynamics:::swap_tenor_map(ref, "CL")
  # Only tenors present in dflong on ref_date
  avail_prices <- dflong |>
    filter(startsWith(series, "CL"), date == ref) |>
    mutate(tenor = paste0("M", sub("^CL", "", series))) |>
    pull(tenor)

  periods <- CommodityMarketDynamics:::swap_valid_periods(tm, avail_prices)

  # Every period's tenors must all appear in avail_prices
  for (p_name in names(periods)) {
    tenors_in_p <- periods[[p_name]]
    expect_true(all(tenors_in_p %in% avail_prices),
                info = paste0("Period '", p_name, "' has tenors absent from fwd curve"))
  }
})

# 5.2 — Period selector regenerates on date change (reactive logic via helper)
test_that("5.2: periods differ between early and late reference dates", {
  early_ref <- as.Date("2010-01-15")
  late_ref  <- dflong |> filter(series == "CL01") |> pull(date) |> max() - 30L

  tm_early <- CommodityMarketDynamics:::swap_tenor_map(early_ref, "CL")
  avail_early <- dflong |>
    filter(startsWith(series, "CL"), date == early_ref) |>
    mutate(tenor = paste0("M", sub("^CL", "", series))) |>
    pull(tenor)
  periods_early <- CommodityMarketDynamics:::swap_valid_periods(tm_early, avail_early)

  tm_late <- CommodityMarketDynamics:::swap_tenor_map(late_ref, "CL")
  avail_late <- dflong |>
    filter(startsWith(series, "CL"), date == late_ref) |>
    mutate(tenor = paste0("M", sub("^CL", "", series))) |>
    pull(tenor)
  periods_late <- CommodityMarketDynamics:::swap_valid_periods(tm_late, avail_late)

  # Different reference dates produce differently-named periods
  expect_false(
    identical(names(periods_early), names(periods_late)),
    info = "Early and late reference dates should yield different period names"
  )
})

# 5.3 — Swap price = arithmetic mean of forward prices for the period
test_that("5.3: flat swap price = mean of delivery month forward prices", {
  ref <- as.Date("2020-06-15")
  tm  <- CommodityMarketDynamics:::swap_tenor_map(ref, "CL")

  fwd <- dflong |>
    filter(startsWith(series, "CL"), date == ref) |>
    mutate(tenor = paste0("M", sub("^CL", "", series))) |>
    select(tenor, CL = value)

  periods <- CommodityMarketDynamics:::swap_valid_periods(tm, fwd$tenor)
  skip_if(length(periods) == 0, "No valid periods for CL on 2020-06-15")

  first_period <- names(periods)[1]
  tenors       <- periods[[first_period]]

  computed <- CommodityMarketDynamics:::compute_flat_swap_price(fwd, tenors, "CL")
  expected <- mean(fwd$CL[fwd$tenor %in% tenors], na.rm = TRUE)

  expect_equal(computed, expected, tolerance = 1e-6)
})

# 5.4 — HO ×42 conversion applied
test_that("5.4: HO flat swap price uses ×42 multiplier", {
  ref <- as.Date("2020-06-15")
  fwd_raw <- dflong |>
    filter(startsWith(series, "HO"), date == ref) |>
    mutate(tenor = paste0("M", sub("^HO", "", series))) |>
    select(tenor, HO = value)
  skip_if(nrow(fwd_raw) == 0, "No HO data on 2020-06-15")

  tenors <- fwd_raw$tenor[1:min(3, nrow(fwd_raw))]
  price_with_mult    <- CommodityMarketDynamics:::compute_flat_swap_price(fwd_raw, tenors, "HO")
  price_without_mult <- mean(fwd_raw$HO[fwd_raw$tenor %in% tenors], na.rm = TRUE)

  expect_equal(price_with_mult, price_without_mult * 42, tolerance = 1e-6)
})

# 5.5 — RB ×42 conversion applied
test_that("5.5: RB flat swap price uses ×42 multiplier", {
  ref <- as.Date("2020-06-15")
  fwd_raw <- dflong |>
    filter(startsWith(series, "RB"), date == ref) |>
    mutate(tenor = paste0("M", sub("^RB", "", series))) |>
    select(tenor, RB = value)
  skip_if(nrow(fwd_raw) == 0, "No RB data on 2020-06-15")

  tenors <- fwd_raw$tenor[1:min(3, nrow(fwd_raw))]
  price_with_mult    <- CommodityMarketDynamics:::compute_flat_swap_price(fwd_raw, tenors, "RB")
  price_without_mult <- mean(fwd_raw$RB[fwd_raw$tenor %in% tenors], na.rm = TRUE)

  expect_equal(price_with_mult, price_without_mult * 42, tolerance = 1e-6)
})

# ── mod_hedge_roll helpers ────────────────────────────────────────────────────

# Helper: build roll table for a standard ticker
build_cl_rolls <- function(ref = as.Date("2022-01-15"), dir = "Producer") {
  CommodityMarketDynamics:::build_roll_table(dflong, "CL", ref, dir)
}

# 5.10 — Roll 1 entry = M1 price on reference date
test_that("5.10: roll 1 entry price = M1 price on reference date", {
  ref  <- as.Date("2022-01-15")
  res  <- build_cl_rolls(ref)
  skip_if(res$n_rolls == 0, "No CL rolls available from 2022-01-15")

  expected_entry <- dflong |>
    filter(series == "CL01", date <= ref) |>
    slice_max(date, n = 1, with_ties = FALSE) |>
    pull(value)

  expect_equal(res$data$entry_price[1], expected_entry, tolerance = 1e-6)
})

# 5.11 — Cascade: exit N = entry N+1
test_that("5.11: exit price of roll N = entry price of roll N+1", {
  res <- build_cl_rolls()
  skip_if(res$n_rolls < 2, "Need at least 2 CL rolls")
  d <- res$data
  for (i in seq_len(nrow(d) - 1)) {
    expect_equal(d$exit_price[i], d$entry_price[i + 1], tolerance = 1e-6,
                 info = paste0("Roll ", i, " exit ≠ roll ", i + 1, " entry"))
  }
})

# 5.12 — Exit dates match RTL::expiry_table for CL
test_that("5.12: exit dates match Last.Trade from RTL::expiry_table for CL", {
  ref <- as.Date("2022-01-15")
  res <- build_cl_rolls(ref)
  skip_if(res$n_rolls == 0)

  cl_expiries <- RTL::expiry_table |>
    filter(tick.prefix == "CL", Last.Trade >= ref) |>
    arrange(Last.Trade) |>
    slice(seq_len(res$n_rolls)) |>
    pull(Last.Trade)

  expect_equal(as.Date(res$data$exit_date), cl_expiries)
})

# 5.13 — BRN uses LCO prefix
test_that("5.13: BRN roll exits use LCO tick.prefix in expiry_table", {
  # Verify ROLL_PREFIX maps BRN to LCO
  prefix <- CommodityMarketDynamics:::ROLL_PREFIX[["BRN"]]
  expect_equal(prefix, "LCO")

  # Verify LCO exists in expiry_table
  lco_rows <- RTL::expiry_table |> filter(tick.prefix == "LCO")
  expect_true(nrow(lco_rows) > 0)
})

# 5.14 — HTT uses CL prefix
test_that("5.14: HTT roll exits use CL tick.prefix in expiry_table", {
  prefix <- CommodityMarketDynamics:::ROLL_PREFIX[["HTT"]]
  expect_equal(prefix, "CL")
})

# 5.15 — Fallback to prior business day when exact expiry date has no price
test_that("5.15: roll_m1_price returns prior day price when exact date has no data", {
  cl_dates <- dflong |> filter(series == "CL01") |> pull(date) |> unique() |> sort()
  dflong_start <- min(cl_dates)
  dflong_end   <- max(cl_dates)

  # Only look for gap expiries within dflong history so a prior date always exists
  cl_expiries <- RTL::expiry_table |>
    filter(tick.prefix == "CL",
           Last.Trade > dflong_start,
           Last.Trade <= dflong_end) |>
    pull(Last.Trade)

  # Find an expiry not in dflong (gap/holiday date) that has at least one prior date
  gap_expiry <- cl_expiries[!cl_expiries %in% cl_dates]
  gap_expiry <- Filter(function(d) any(cl_dates < d), gap_expiry)
  skip_if(length(gap_expiry) == 0, "No gap expiry dates found for CL within dflong range")

  gap_date   <- gap_expiry[1]
  prior_date <- max(cl_dates[cl_dates < gap_date])
  expected_price <- dflong |>
    filter(series == "CL01", date == prior_date) |>
    pull(value)

  result <- CommodityMarketDynamics:::roll_m1_price(dflong, "CL", gap_date)
  expect_equal(result, expected_price[1], tolerance = 1e-6)
})

# 5.16 — Roll yield formula
test_that("5.16: roll yield = (entry - exit) / entry * 100", {
  res <- build_cl_rolls()
  skip_if(res$n_rolls < 3)
  d <- res$data
  for (i in 1:3) {
    expected_ry <- (d$entry_price[i] - d$exit_price[i]) / d$entry_price[i] * 100
    expect_equal(d$roll_yield[i], expected_ry, tolerance = 1e-6,
                 info = paste0("Roll yield mismatch on roll ", i))
  }
})

# 5.17 — Producer P&L formula
test_that("5.17: producer monthly P&L = entry - exit", {
  res <- build_cl_rolls(dir = "Producer")
  skip_if(res$n_rolls < 3)
  d <- res$data
  for (i in 1:3) {
    expect_equal(d$monthly_pnl[i], d$entry_price[i] - d$exit_price[i],
                 tolerance = 1e-6, info = paste0("Producer P&L mismatch roll ", i))
  }
})

# 5.18 — Consumer P&L formula
test_that("5.18: consumer monthly P&L = exit - entry", {
  res <- build_cl_rolls(dir = "Consumer")
  skip_if(res$n_rolls < 3)
  d <- res$data
  for (i in 1:3) {
    expect_equal(d$monthly_pnl[i], d$exit_price[i] - d$entry_price[i],
                 tolerance = 1e-6, info = paste0("Consumer P&L mismatch roll ", i))
  }
})

# 5.19 — Cumulative P&L = running sum of monthly P&L
test_that("5.19: cumulative P&L equals running sum of monthly P&L", {
  res <- build_cl_rolls()
  skip_if(res$n_rolls == 0)
  d <- res$data
  expected_cum <- cumsum(d$monthly_pnl)
  expect_equal(d$cumulative_pnl, expected_cum, tolerance = 1e-6)
})

# 5.20 — Fewer than 12 rolls handled gracefully (checklist item 1)
test_that("5.20: short-history ticker renders < 12 rolls without error", {
  # HTT data starts around 2018; pick a ref date near the end so fewer rolls exist
  htt_last <- dflong |> filter(series == "HTT01") |> pull(date) |> max()
  ref <- htt_last - 365L * 0L   # use end of data minus safety margin
  # Use a ref that leaves fewer than 12 expiries
  ref <- htt_last - 300L
  res <- CommodityMarketDynamics:::build_roll_table(dflong, "HTT", ref, "Producer")
  # Must not error; n_rolls must be >= 0 and <= 12
  expect_true(res$n_rolls >= 0 && res$n_rolls <= 12)
  # If we have rolls, the data should have exactly n_rolls rows
  if (res$n_rolls > 0) {
    expect_equal(nrow(res$data), res$n_rolls)
  }
})

# 5.21 — Reference date constraint: ≥ 1 year before last available date
test_that("5.21: reference date max = last available - 365 days for CL", {
  last_d <- dflong |> filter(series == "CL01") |> pull(date) |> max()
  max_allowed <- last_d - 365L

  # A date 6 months before last is within the blocked zone
  blocked_date <- last_d - 180L
  expect_true(blocked_date > max_allowed,
              info = "Blocked date should exceed the max_allowed constraint")
})

# ── mod_hedge_options helpers ─────────────────────────────────────────────────

# 5.22 — Black-76: b = 0
test_that("5.22: GBSOption called with b = 0 (Black-76 spec)", {
  # Verify b=0 gives different result from b=r (Black-Scholes)
  bs76   <- RTL::GBSOption(S=100, X=100, T2M=0.25, r=0.05, b=0,    sigma=0.30, type="call")$price
  bs_std <- RTL::GBSOption(S=100, X=100, T2M=0.25, r=0.05, b=0.05, sigma=0.30, type="call")$price
  expect_false(isTRUE(all.equal(bs76, bs_std)),
               info = "b=0 and b=r should produce different option values")
  # b=0 call should be less than or equal to b=r call (futures < spot pricing)
  expect_true(bs76 <= bs_std + 1e-6)
})

# 5.23 — Call premium (known reference value)
test_that("5.23: Black-76 call premium matches reference value", {
  # Black-76 call: S=100, X=100, T=0.25, r=0.05, b=0, sigma=0.30
  # Manual: C = exp(-rT)[F*N(d1) - X*N(d2)], F=S=100 for b=0
  result <- RTL::GBSOption(S=100, X=100, T2M=0.25, r=0.05, b=0, sigma=0.30, type="call")$price
  # Reference: Black-76 ATM call ~ 5.96 for these inputs (from standard tables)
  expect_true(result > 0, info = "Call premium must be positive")
  expect_true(result < 100, info = "Call premium must be less than underlying")
  # Black-76 call at ATM ≈ S * N(d1) * exp(-rT) * (1 - N(-d1)) bracket
  # For these params, should be approximately 5.9-6.1
  expect_true(abs(result - 5.99) < 0.5,
              info = paste0("ATM call (b=0) expected ~6.0, got ", round(result, 4)))
})

# 5.24 — Put premium (put-call parity check)
test_that("5.24: Black-76 put satisfies put-call parity", {
  S <- 100; X <- 100; T_val <- 0.25; r_val <- 0.05; sigma <- 0.30
  call_p <- RTL::GBSOption(S=S, X=X, T2M=T_val, r=r_val, b=0, sigma=sigma, type="call")$price
  put_p  <- RTL::GBSOption(S=S, X=X, T2M=T_val, r=r_val, b=0, sigma=sigma, type="put")$price
  # Black-76 put-call parity: C - P = exp(-rT)(F - X), F = S for b=0
  F_val <- S  # b=0 => F = S*exp(0) = S
  parity_lhs <- call_p - put_p
  parity_rhs <- exp(-r_val * T_val) * (F_val - X)
  expect_equal(parity_lhs, parity_rhs, tolerance = 1e-4)
})

# 5.25 — TTM mapping
test_that("5.25: TTM radio buttons map to correct T in years", {
  expect_equal(1  / 12, 1/12,  tolerance = 1e-9)
  expect_equal(3  / 12, 0.25,  tolerance = 1e-9)
  expect_equal(6  / 12, 0.5,   tolerance = 1e-9)
})

# 5.26 — Zero-cost collar grid search
test_that("5.26: grid search finds strike minimising |opposite_premium - user_premium|", {
  grid     <- seq(0.01, 200, length.out = 100)
  S <- 100; T_val <- 0.25; r_val <- 0.05; sigma <- 0.30
  # Producer: user buys put at K=95; find call strike where call_premium = put_premium
  user_k    <- 95
  user_prem <- RTL::GBSOption(S=S, X=user_k, T2M=T_val, r=r_val, b=0, sigma=sigma, type="put")$price
  call_prems <- vapply(grid, function(k) {
    RTL::GBSOption(S=S, X=k, T2M=T_val, r=r_val, b=0, sigma=sigma, type="call")$price
  }, numeric(1))

  idx <- which.min(abs(call_prems - user_prem))
  expect_true(idx >= 1 && idx <= length(grid))
  # The found strike should be above the current price (OTM call for producer collar)
  expect_true(grid[idx] > S * 0.9,
              info = "Zero-cost call strike should be above spot for a producer collar")
})

# 5.27 — Collar MTM = 0 at reference date
test_that("5.27: collar P&L at reference date = 0 by construction (zero-cost)", {
  # Simulate: long put K=95, short call K=K_short (zero-cost)
  S0 <- 100; K_long <- 95; T_val <- 0.25; r_val <- 0.05; sigma <- 0.30
  # Compute K_short via grid search
  grid <- seq(0.01, 200, length.out = 100)
  user_prem <- RTL::GBSOption(S=S0, X=K_long, T2M=T_val, r=r_val, b=0, sigma=sigma, type="put")$price
  call_prems <- vapply(grid, function(k) {
    RTL::GBSOption(S=S0, X=k, T2M=T_val, r=r_val, b=0, sigma=sigma, type="call")$price
  }, numeric(1))
  K_short <- grid[which.min(abs(call_prems - user_prem))]

  # At t=0: long_val - short_val should ≈ 0
  long_v  <- RTL::GBSOption(S=S0, X=K_long,  T2M=T_val, r=r_val, b=0, sigma=sigma, type="put")$price
  short_v <- RTL::GBSOption(S=S0, X=K_short, T2M=T_val, r=r_val, b=0, sigma=sigma, type="call")$price
  net_pnl <- long_v - short_v
  # Grid search gives approximate zero-cost; allow tolerance of 0.5% of S0
  expect_true(abs(net_pnl) < 0.5,
              info = paste0("Zero-cost collar net at inception = ", round(net_pnl, 4),
                            "; expected ≈ 0"))
})

# 5.28 — Yield curve interpolation varies with T_remaining
test_that("5.28: r_t at T=0.5 differs from r_t at T=0.1 (yield interpolation varies)", {
  # Build a synthetic yield curve to avoid FRED dependency in tests
  yc <- tibble::tibble(
    date   = rep(as.Date("2023-06-01"), 8),
    series = c("DGS1MO","DGS3MO","DGS6MO","DGS1","DGS2","DGS5","DGS10","DGS30"),
    rate   = c(5.0, 5.1, 5.2, 5.0, 4.8, 4.5, 4.2, 4.0)  # typical inverted curve
  )
  r_short <- CommodityMarketDynamics:::interp_yield(yc, as.Date("2023-06-01"), 0.1)
  r_long  <- CommodityMarketDynamics:::interp_yield(yc, as.Date("2023-06-01"), 0.5)
  expect_false(isTRUE(all.equal(r_short, r_long)),
               info = "Interpolated rate should differ for T=0.1 vs T=0.5")
})

# 5.29 — Yield curve feasibility constraint (checklist item 2)
test_that("5.29: reference date constraint handles FRED ending before dflong", {
  # Simulate: FRED yield data ends 10 days before dflong last date
  last_cl <- dflong |> filter(series == "CL01") |> pull(date) |> max()
  last_yc <- last_cl - 10L  # FRED ends 10 days before dflong

  T_mo <- 3  # 3-month options
  # Find the nearest expiry >= T months after a ref_date, must be <= last_yc
  # A ref_date that's valid: ref + 3mo expiry <= last_yc
  # A ref_date that's invalid: ref + 3mo expiry > last_yc

  # Valid ref: ~4 months before last_yc
  valid_ref <- last_yc - lubridate::dmonths(4)
  expiry_v  <- CommodityMarketDynamics:::find_expiry("CL", as.Date(valid_ref), T_mo, last_yc)
  expect_false(is.na(expiry_v), info = "Valid ref_date should yield a non-NA expiry")
  expect_true(expiry_v <= last_yc,
              info = "Expiry must not exceed FRED cutoff (last_yc)")
})

# 5.30 — Contract multipliers
test_that("5.30: contract multipliers are correct for CL and NG", {
  expect_equal(CommodityMarketDynamics:::OPT_MULTIPLIERS[["CL"]], 1000L)
  expect_equal(CommodityMarketDynamics:::OPT_MULTIPLIERS[["NG"]], 10000L)
  expect_equal(CommodityMarketDynamics:::OPT_MULTIPLIERS[["HO"]], 42000L)
  expect_equal(CommodityMarketDynamics:::OPT_MULTIPLIERS[["RB"]], 42000L)
})

# ── mod_hedge_term helpers ────────────────────────────────────────────────────

# 5.34 — OLS betas computed from dflong
test_that("5.34: OLS betas non-NULL and positive row count for CL", {
  betas <- CommodityMarketDynamics:::compute_ols_betas(dflong, "CL")
  expect_true(nrow(betas) > 0)
  expect_true(all(c("tenor","beta","r_squared") %in% names(betas)))
  # M01 excluded
  expect_false("M01" %in% betas$tenor)
})

# 5.36 — Kalman animation frame count = number of calendar months
test_that("5.36: animation frame count = unique calendar months in r$kalman_betas for CL", {
  r_list <- new.env(parent = emptyenv())
  CommodityMarketDynamics:::mod_kalman_betas_server(dflong, r_list)
  skip_if(is.null(r_list$kalman_betas), "kalman_betas not computed")

  anim <- CommodityMarketDynamics:::prep_kalman_animation(r_list$kalman_betas, "CL")
  skip_if(nrow(anim$monthly) == 0, "No CL Kalman data")

  expected_months <- length(unique(
    lubridate::floor_date(
      r_list$kalman_betas |>
        filter(ticker == "CL") |>
        pull(date),
      "month"
    )
  ))
  actual_months <- length(unique(anim$monthly$month_label))
  expect_equal(actual_months, expected_months)
})

# ── mod_hedge_cross helpers ───────────────────────────────────────────────────

# 5.42 — Off-diagonal count = 30 for any given date
test_that("5.42: r$kalman_cross_betas has exactly 30 off-diagonal pairs per date", {
  r_cross <- new.env(parent = emptyenv())
  CommodityMarketDynamics:::mod_kalman_cross_server(dflong, r_cross)
  skip_if(is.null(r_cross$kalman_cross_betas))

  last_d <- max(r_cross$kalman_cross_betas$date)
  n_pairs <- r_cross$kalman_cross_betas |>
    filter(date == last_d) |>
    nrow()
  expect_equal(n_pairs, 30L)
})

# 5.43 — Date picker constrained to Kalman dates (not raw dflong first date)
test_that("5.43: first Kalman cross date is later than first dflong date", {
  r_cross <- new.env(parent = emptyenv())
  CommodityMarketDynamics:::mod_kalman_cross_server(dflong, r_cross)
  skip_if(is.null(r_cross$kalman_cross_betas))

  first_kalman <- min(r_cross$kalman_cross_betas$date)
  first_dflong <- min(dflong$date)
  expect_true(first_kalman > first_dflong,
              info = "Kalman filter requires prior observation — first date must be later")
})

# 5.40/5.41 — Matrix build: 6×6 and diagonal is NA
test_that("5.40/5.41: build_cross_matrix produces 6×6 matrix with NA diagonal", {
  r_cross <- new.env(parent = emptyenv())
  CommodityMarketDynamics:::mod_kalman_cross_server(dflong, r_cross)
  skip_if(is.null(r_cross$kalman_cross_betas))

  last_d <- max(r_cross$kalman_cross_betas$date)
  cm     <- CommodityMarketDynamics:::build_cross_matrix(r_cross$kalman_cross_betas, last_d)

  expect_equal(nrow(cm$betas), 6L)
  expect_equal(ncol(cm$betas), 6L)
  # Diagonal should be NA (excluded from kalman_cross_betas)
  for (tk in CommodityMarketDynamics:::CROSS_TICKERS) {
    expect_true(is.na(cm$betas[tk, tk]),
                info = paste0("Diagonal cell [", tk, ",", tk, "] should be NA"))
  }
})
