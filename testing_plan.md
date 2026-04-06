# Testing Plan — Commodity Market Dynamics

## Conventions

- **Type tags:** `unit` = isolated function/output test; `integration` = cross-module or data pipeline test; `visual` = must be verified by eye; `smoke` = fast critical-path check run at the start of the next phase
- **Pass criterion:** every test must match an expected value or behavior — "runs without error" is never sufficient
- **Blocking rule:** a failing test blocks progression to the next phase
- **Framework:** `testthat` for R unit/integration tests; visual tests noted explicitly and signed off manually
- **Regression:** at the start of each new phase, run smoke tests for all prior phases before writing any new code

---

## Phase 0 — Scaffold & Shared Infrastructure

### EIA File Loading

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 0.1 | All 6 EIA files load | Each `readxl::read_xls()` call returns a non-empty tibble | 6 tibbles, nrow > 0 | smoke |
| 0.2 | Excel date parsing | Spot-check one known date in each EIA file after `as.Date(as.numeric(date), origin = "1899-12-30")` conversion | Parsed date matches the label in the source file | unit |
| 0.3 | No NAs after filter | After `filter(!is.na(date), !is.na(value))`, no NA rows remain in any EIA tibble | `sum(is.na(df$date)) == 0` and `sum(is.na(df$value)) == 0` for all 6 files | unit |
| 0.4 | Value column is numeric | `class(df$value) == "numeric"` for all 6 EIA tibbles | TRUE for all | unit |

### `compute_returns`

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 0.5 | Log returns for CL | Output for CL M1 uses `log(P_t / P_{t-1})` | Spot-check 3 known consecutive prices — computed log return matches manual calculation | unit |
| 0.6 | Level differences for HTT | HTT M1 has negative values; output uses `P_t - P_{t-1}` not log returns | Spot-check: `compute_returns` output for HTT M1 = raw price difference on known dates | unit |
| 0.7 | HTT detection is automatic | No manual flag needed; function detects negative values in the series | Pass HTT data; confirm level differences used without any explicit argument | unit |
| 0.8 | Output schema | Returns tibble with columns `date`, `tenor`, `return` (or equivalent wide/long format per implementation) | Column names present; no extra columns; nrow matches input dates minus 1 | unit |
| 0.9 | No NAs in return output | After first-differencing, leading NA from lag is dropped or handled | `sum(is.na(returns)) == 0` after NA rows removed | unit |

### `apply_theme`

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 0.10 | Returns plotly object | `apply_theme(plot_ly())` returns a plotly htmlwidget | `inherits(result, "plotly")` is TRUE | unit |
| 0.11 | plot_bgcolor applied | Layout contains `plot_bgcolor = "#fffff2"` | `p$x$layout$plot_bgcolor == "#fffff2"` | unit |
| 0.12 | paper_bgcolor applied | Layout contains `paper_bgcolor = "#fffff2"` | `p$x$layout$paper_bgcolor == "#fffff2"` | unit |
| 0.13 | Font family applied | Layout font family = Times New Roman | `p$x$layout$font$family == "Times New Roman"` | unit |

### `mod_yield_curves`

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 0.14 | Output written to `r$yield_curves` | Slot is non-NULL after module runs | `!is.null(r$yield_curves)` | smoke |
| 0.15 | 8 FRED series present | All 8 CMT tickers in the data (DGS1MO, DGS3MO, DGS6MO, DGS1, DGS2, DGS5, DGS10, DGS30) | `all(c("DGS1MO","DGS3MO","DGS6MO","DGS1","DGS2","DGS5","DGS10","DGS30") %in% unique(r$yield_curves$series))` | unit |
| 0.16 | Date column is Date class | `class(r$yield_curves$date) == "Date"` | TRUE | unit |

### `mod_kalman_betas`

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 0.17 | Output written to `r$kalman_betas` | Slot is non-NULL after module runs | `!is.null(r$kalman_betas)` | smoke |
| 0.18 | Output schema | Columns are exactly `date, ticker, tenor, beta, r_squared` | `names(r$kalman_betas) == c("date","ticker","tenor","beta","r_squared")` | unit |
| 0.19 | All tickers present | CL, BRN, NG, HO, RB all appear (HTT excluded) | `all(c("CL","BRN","NG","HO","RB") %in% unique(r$kalman_betas$ticker))` | unit |
| 0.20 | M1 vs M1 excluded | No row where tenor == "M01" (diagonal excluded) | `nrow(filter(r$kalman_betas, tenor == "M01")) == 0` | unit |
| 0.21 | R² in valid range | All R² values between 0 and 1 | `all(r$kalman_betas$r_squared >= 0 & r$kalman_betas$r_squared <= 1)` | unit |
| 0.22 | Causal filter | Kalman betas use only data up to each date — no look-ahead; verify first date in output corresponds to first date a beta is estimable (requires at least one prior observation) | First date in `r$kalman_betas` > first date in `dflong` for each ticker | integration |

### `mod_kalman_cross`

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 0.23 | Output written to `r$kalman_cross_betas` | Slot is non-NULL | `!is.null(r$kalman_cross_betas)` | smoke |
| 0.24 | Output schema | Columns are exactly `date, from_ticker, to_ticker, beta, r_squared` | `names(r$kalman_cross_betas) == c("date","from_ticker","to_ticker","beta","r_squared")` | unit |
| 0.25 | Exactly 30 directed pairs | 6 tickers × 5 non-self pairs = 30 unique `from_ticker`/`to_ticker` combinations per date | `length(unique(paste(r$kalman_cross_betas$from_ticker, r$kalman_cross_betas$to_ticker))) == 30` | unit |
| 0.26 | No diagonal | No row where `from_ticker == to_ticker` | `nrow(filter(r$kalman_cross_betas, from_ticker == to_ticker)) == 0` | unit |
| 0.27 | HTT uses level differences | `compute_returns` output consumed — HTT rows use ΔP not log returns | Verify HTT is routed through `compute_returns` at the call site; not computed separately | integration |

### `mod_var`

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 0.28 | Output written to `r$var_results` | Slot is non-NULL | `!is.null(r$var_results)` | smoke |
| 0.29 | Weekly Friday-close filter | All dates in the VAR input data fall on Fridays (or last available trading day of that week) | `all(weekdays(var_dates) == "Friday")` — or check no date is Saturday/Sunday | unit |
| 0.30 | All 6 tickers present after inner join | No ticker silently dropped due to missing dates | `ncol(var_matrix) == 6` after pivoting to wide | integration |
| 0.31 | HTT is weekly first differences | HTT column in VAR input = weekly ΔP; all other columns = weekly log returns | Spot-check: HTT row `t` = `HTT_price_t - HTT_price_{t-1}`; CL row `t` = `log(CL_t / CL_{t-1})` | unit |
| 0.32 | Z-score standardization | All 6 series in VAR input have mean ≈ 0, sd ≈ 1 | `abs(mean(series)) < 0.01` and `abs(sd(series) - 1) < 0.05` for each ticker | unit |
| 0.33 | VAR object is valid | `r$var_results` is a `varest` object | `inherits(r$var_results, "varest")` | unit |

### Phase 0 Smoke

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 0.34 | App loads | `shiny::testApp()` or manual launch — app starts without error | No R console errors; UI renders | smoke |

---

## Phase 1 — Forward Curves

### Phase 1 Smoke (prior phases)
Run `testthat::test_dir("tests/")` filtering to Phase 0 tests — all must pass before writing Phase 1 code.

### `mod_fc_comparison` — Scaled Comparison Chart

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 1.1 | M1 = 100 normalization | For any ticker on any date, the M01 value in the chart data = 100 | `filter(chart_data, tenor == "M01")$indexed_price == 100` for all tickers | unit |
| 1.2 | Other tenors indexed correctly | M2 value = `(raw_M2 / raw_M1) * 100` on the selected date | Spot-check one ticker, one date, two tenors | unit |
| 1.3 | Integer date map | `date_map$date[date_map$idx == k]` returns the correct date for index `k` | Verify first, last, and mid-point of `date_map` | unit |
| 1.4 | Sparse ticker filter | Select two tickers with different history start dates — chart only renders dates where both have data | `nrow(chart_data)` equals intersection of both tickers' available dates | integration |
| 1.5 | No partial curves | No ticker in chart_data is missing any tenors on the selected date | All tickers have the same set of available tenors on the selected date | unit |
| 1.6 | Slider max updates on ticker change | After adding a ticker with shorter history, `max` of slider shrinks to new intersection date count | `updateSliderInput` is fired; new max = `nrow(new_date_map)` | integration |
| 1.7 | Historical overlay mode switch | `input_switch` ON replaces multi-ticker selector with single-ticker selector | Single ticker selector rendered; multi-selector hidden | visual |
| 1.8 | Up to 4 date inputs in overlay mode | With overlay mode ON, up to 4 date inputs can each render a curve independently | 4 curves rendered when all 4 dates populated; 2 curves when 2 dates populated | visual |
| 1.9 | Empty date inputs not plotted | A date input left empty in overlay mode does not render a curve | Only populated date inputs produce traces | unit |

### `mod_fc_surface` — 3D Forward Curve Surface

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 1.10 | Contango classification | On a date where M12 > M1: regime = contango | `classify_regime(M1=50, M12=55) == "contango"` | unit |
| 1.11 | Backwardation classification | On a date where M1 > M12: regime = backwardation | `classify_regime(M1=55, M12=50) == "backwardation"` | unit |
| 1.12 | 5-day rolling majority vote | An isolated 1-day regime switch surrounded by 4 days of the opposite regime is smoothed out | Input: 4 contango, 1 backwardation, 4 contango → output: all contango for that window | unit |
| 1.13 | Regime floor on plot | Regime color projected onto floor of 3D plot, not onto the surface | Visual check — surface color = viridis by price; floor color = regime | visual |
| 1.14 | Viridis scale on surface | Surface color mapped to price level using viridis scale | Visual check — color gradient follows price | visual |

### `mod_fc_monthly` — Monthly Forward Curve Overlays

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 1.15 | Exactly 12 lines rendered | For any ticker with data covering all 12 calendar months | `length(unique(chart_data$month)) == 12` | unit |
| 1.16 | Values are averages across years | For Jan M1 CL: value = mean of all January M1 CL prices across available years | Spot-check: manually compute mean of January M1 CL; compare to chart data | unit |
| 1.17 | X-axis is tenor | X-axis runs M01 to Mn (available tenors for selected ticker) | Visual check | visual |

### `mod_fc_pca` — PCA Decomposition

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 1.18 | PCA slot written on first selection | After selecting ticker, `r$[ticker]_pca` slot is populated | `!is.null(r[[ paste0("CL_pca") ]])` after CL selected | integration |
| 1.19 | Variance explained sums to 100% | Sum of all PC variance proportions = 1.0 | `sum(pca_obj$sdev^2 / sum(pca_obj$sdev^2)) == 1.0` | unit |
| 1.20 | 2% threshold filter | Only PCs explaining ≥ 2% of variance individually are plotted | `all(plotted_pcs_variance >= 0.02)` | unit |
| 1.21 | Variance shown in legend | Each plotted PC's legend label includes its variance explained percentage | Visual check — legend reads e.g. "PC1: 94%" | visual |
| 1.22 | Loadings plotted against tenors | X-axis = tenor (M01…Mn); Y-axis = loading value | Visual check; loading values are between -1 and 1 | visual |

### Phase 1 Smoke

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 1.23 | All 4 panels render for CL | Manually launch app, select CL in all 4 panels | No console errors; all charts render with data | smoke |

---

## Phase 2 — Volatility

### Phase 2 Smoke (prior phases)
Run Phase 0 + Phase 1 smoke tests — all must pass.

### `mod_vol_density` — Return Distribution & Volatility Bar Chart

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 2.1 | 1st/99th percentile clip applied before density | Returns passed to density computation have no values outside [p1, p99] | `all(clipped_returns >= quantile(raw_returns, 0.01) & clipped_returns <= quantile(raw_returns, 0.99))` | unit |
| 2.2 | Clip is per-tenor | Percentile clip computed independently for each tenor | Each tenor's clip range = that tenor's own 1st/99th percentile | unit |
| 2.3 | HTT x-axis label | When HTT selected, x-axis label = "Level Difference" | Visual check; label not "Log Return" | visual |
| 2.4 | Non-HTT x-axis label | When CL/BRN/NG/HO/RB selected, x-axis label = "Log Return" | Visual check | visual |
| 2.5 | Vol bar chart shows all tenors | Vol bar chart is not filtered by the density slider | Select M1–M3 in slider; bar chart still shows all available tenors | visual |
| 2.6 | Annualized vol formula | Vol per tenor = `sd(returns) × sqrt(252)` | Spot-check CL M1: compute manually and compare to bar chart value | unit |
| 2.7 | Back tenors more translucent | In density chart, back tenors rendered first with higher transparency than front tenors | Visual check — M18 more translucent than M1 | visual |
| 2.8 | Turbo color scale | Colors follow turbo palette ordered by tenor | Visual check | visual |

### `mod_vol_heatmap` — Correlation Matrix Heatmap

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 2.9 | Matrix is symmetric | `cor_matrix[i,j] == cor_matrix[j,i]` for all i, j | `all(cor_matrix == t(cor_matrix))` | unit |
| 2.10 | Diagonal = 1 | All diagonal entries equal 1 | `all(diag(cor_matrix) == 1)` | unit |
| 2.11 | Values in [-1, 1] | No correlation outside valid range | `all(cor_matrix >= -1 & cor_matrix <= 1)` | unit |
| 2.12 | HTT routes through `compute_returns` | HTT correlation computed on level differences, not log returns | Verify at the call site that `compute_returns` output is passed to `cor()` — no separate log return computation for HTT | integration |
| 2.13 | Spectral reversed scale | Color scale goes from red (high positive) to blue (high negative) — reversed Spectral | Visual check | visual |

### `mod_vol_rolling` — Rolling Realised Volatility

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 2.14 | 21-day window | Rolling vol computed with window = 21 | For a known 21-day window, `sd(returns[1:21]) × sqrt(252)` matches chart value | unit |
| 2.15 | Annualized output | Output is annualized (`× sqrt(252)`) | Spot-check matches manual computation | unit |
| 2.16 | Event marker appears in range | For CL M1: Crimea (2014-03-03), COVID (2020-03-09), Ukraine (2022-03-07) all appear | Visual check — all 3 markers visible on CL M1 | visual |
| 2.17 | Event marker silently omitted out of range | Select a ticker/tenor with history starting after 2014-03-03 — Crimea marker absent | No marker rendered for Crimea; no error thrown | integration |
| 2.18 | Hover label names the event | Hovering over an event marker shows the event name | Visual check — e.g. "COVID-19 / Oil Price War" | visual |

### Phase 2 Smoke

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 2.19 | All 3 rows render for CL M1 | Manually launch app, navigate to Volatility page, select CL M1 | No console errors; all 3 charts render with data | smoke |

---

## Phase 3 — Market Dynamics

### Phase 3 Smoke (prior phases)
Run Phase 0–2 smoke tests — all must pass.

### `mod_md_crude` — Crude Group

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 3.1 | BRN-WTI spread formula | Spread = BRN01 − CL01 on each date | Spot-check 3 dates: `spread == BRN01 - CL01` | unit |
| 3.2 | Event markers in range | All 3 events appear on BRN-WTI spread (dates within both tickers' history) | Visual check | visual |
| 3.3 | Event markers absent on HTT when outside range | HTT data starts later than 2014 — Crimea marker absent | No marker; no error | integration |
| 3.4 | Crude Row 2 WoW change | WoW change = `inventory_t - inventory_{t-1}` (level, not %) | Spot-check: `change == current_week - prior_week` on known dates | unit |
| 3.5 | Crude Row 3 calendar spread | Calendar spread = M2 - M1 price on selected date | Spot-check: `spread == M2 - M1` | unit |
| 3.6 | EIA production/inputs files loaded | `r$eia_crude_prod` and `r$eia_crude_inputs` are non-NULL and have correct date range | nrow > 0; min(date) ≥ 2008-01-01 | smoke |
| 3.7 | Crude Row 4 gap-filling | `na.approx()` applied before STL — no NA values passed to `stats::stl()` | After gap-fill: `sum(is.na(series)) == 0` | unit |
| 3.8 | Crude Row 4 date constraint | Chart data constrained to 2008-01-01 – 2025-12-31 | `min(dates) >= as.Date("2008-01-01")` and `max(dates) <= as.Date("2025-12-31")` | unit |
| 3.9 | STL runs without error | `stats::stl()` completes on gap-filled EIA production data | Returns valid `stl` object; no error | integration |

### `mod_md_refined` — Refined Products Group

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 3.10 | HO crack spread formula | `(HO01 × 42) − CL01` on known date | Spot-check: `crack == HO01 * 42 - CL01` | unit |
| 3.11 | RB crack spread formula | `(RB01 × 42) − CL01` on known date | Spot-check: `crack == RB01 * 42 - CL01` | unit |
| 3.12 | Crack spread inner join warning | When early history dates have no matching CL data, a warning is issued (not silent drop) | `expect_warning(compute_crack_spread(...))` catches at least one warning on early-date inputs | unit |
| 3.13 | Distillate/gasoline stocks files loaded | `r$eia_distillate_stocks` and `r$eia_gasoline_stocks` non-NULL | nrow > 0 | smoke |
| 3.14 | 5yr average excludes first 5 years | When computing 5yr rolling average for EIA stocks, first 5 calendar years of data are dropped entirely before averaging begins | `min(date_of_first_5yr_avg) >= min(eia_date) + years(5)` | unit |

### `mod_md_ng` — Natural Gas Group

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 3.15 | NG Row 1 one line per year | Seasonal overlay has exactly one line per year in the data | `length(unique(chart_data$year)) == nrow(distinct(chart_data, year))` | unit |
| 3.16 | NG Row 1 X-axis is Jan–Dec | X-axis represents week-of-year or month; no dates outside Jan–Dec | Visual check | visual |
| 3.17 | NG storage file loaded | `r$eia_ng_storage` non-NULL, units in Bcf range (typically 500–4000) | `max(r$eia_ng_storage$value) < 5000` and `min > 0` | smoke |
| 3.18 | 5yr average methodology | For week W of year Y: average = mean of storage values for week W across years Y-5 to Y-1 (EIA calendar average) | Spot-check one week manually | unit |
| 3.19 | Surplus/deficit bars | `surplus = actual_storage - 5yr_avg` — positive = above average | Spot-check: `surplus == actual - five_yr_avg` on known date | unit |
| 3.20 | EIA-923 skip logic | 2008–2010 files loaded with skip=6; 2011+ loaded with skip=5 — verify year extraction from filename drives correct skip | Load 2009 file: col 7 = "State", col 15 = "Reported Fuel Type Code" (not blank); load 2012 file: same positions populated | unit |
| 3.20b | EIA-923 positional column access | After read + rename, output has columns `plant_state`, `census_region`, `fuel_type_code`, `netgen_jan`…`netgen_dec`, `year` regardless of source year | `names(df) == c("plant_state","census_region","fuel_type_code","netgen_jan",…,"year")` for both a 2009 file and a 2020 file | unit |
| 3.20c | EIA-923 "." treated as NA | Netgen values of `"."` become NA after numeric conversion, not 0 | `is.na(df$netgen_jan[df$netgen_jan_raw == "."])` is TRUE | unit |
| 3.21 | Coal fuel type filter | Only rows with `Reported Fuel Type Code %in% c("ANT","BIT","LIG","RC","SUB","WC")` retained | `all(filtered_df$fuel_code %in% c("ANT","BIT","LIG","RC","SUB","WC"))` | unit |
| 3.22 | Census region mapping | Spot-check one division per region: NEW → Northeast; ENC → Midwest; WSC → South; MTN → West | `map_region("NEW") == "Northeast"` etc. | unit |
| 3.23 | NG Row 4 frequency join | NG01 daily × LNG monthly join — join on month-year; no row duplication; each daily NG01 row matched to its month's LNG value | `nrow(joined) == nrow(daily_ng)` (LNG values repeated per trading day of that month) | unit |
| 3.24 | LNG file loaded | `r$eia_lng_exports` non-NULL; dates start ≥ 2016 (first exports) | `min(r$eia_lng_exports$date) >= as.Date("2016-01-01")` | smoke |
| 3.25 | Sabine Pass vertical line | Vertical dashed line at exactly 2016-02-24 | `annotation_date == as.Date("2016-02-24")` | unit |

### Phase 3 Smoke

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 3.26 | Crude group renders | Navigate to Market Dynamics, select Crude — all 4 rows render | No console errors | smoke |
| 3.27 | Refined group renders | Select Refined Products — all 3 rows render | No console errors | smoke |
| 3.28 | NG group renders | Select Natural Gas — all 4 rows render (or stub message if EIA-923 files absent) | No console errors | smoke |

---

## Phase 4 — Cross-Market Relationships

### Phase 4 Smoke (prior phases)
Run Phase 0–3 smoke tests — all must pass.

### `mod_cm_rolling_corr` — Rolling Correlation

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 4.1 | Default window = 90 | Rolling correlation computed with 90-day window on load | First non-NA correlation appears at day 90 of the series | unit |
| 4.2 | Slider updates window | Change slider to 21 — correlation recomputes; first non-NA at day 21 | `min(which(!is.na(corr_series))) == 21` | integration |
| 4.3 | Vol regime threshold is 80th percentile | High-vol threshold = `quantile(rolling_vol, 0.80)` computed from data, not hardcoded | Verify threshold value = `quantile(rolling_vol, 0.80)` in server code | unit |
| 4.4 | Shading only in high-vol periods | Red background shading appears only where rolling vol exceeds 80th percentile threshold | Visual check — shaded bands align with vol spikes | visual |
| 4.5 | Shading opacity = 20% | Red shading at 20% opacity | Visual check | visual |

### `mod_cm_var` — VAR & IRF

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 4.6 | All 6 tickers in VAR data | After inner join on overlapping dates, all of CL, BRN, NG, HO, RB, HTT present | `all(c("CL","BRN","NG","HO","RB","HTT") %in% colnames(var_data))` | integration |
| 4.7 | Sufficient overlapping dates | Inner join produces enough rows for VAR estimation (> max lag × 10 at minimum) | `nrow(var_data) > 60` | integration |
| 4.8 | Missing ticker warning | If any ticker is absent after join, an explicit warning/error is thrown — not silent | `expect_warning(prep_var_data(...))` when a ticker has no overlapping dates | unit |
| 4.9 | Weekly returns are weekly | All consecutive dates in VAR data are 5–7 days apart (Friday to Friday) | `all(diff(var_dates) >= 5 & diff(var_dates) <= 8)` | unit |
| 4.10 | HTT is ΔP in VAR | HTT column = weekly price difference; spot-check 3 rows | `var_data$HTT[t] == HTT_price_friday_t - HTT_price_friday_{t-1}` | unit |
| 4.11 | Z-score standardization | Each of the 6 series in VAR input: mean ≈ 0, sd ≈ 1 | `abs(mean(series)) < 0.05` and `abs(sd(series) - 1) < 0.05` for all 6 | unit |
| 4.12 | Lag selection uses multi-criterion consensus | Lag = value where ≥ 2 of AIC, BIC, HQ, FPE agree | Verify in server code that consensus logic is applied; log selected lag | unit |
| 4.13 | Cholesky ordering locked | VAR estimated with ordering BRN→CL→HO→RB→HTT→NG | Column order of VAR input matrix matches exactly | unit |
| 4.14 | IRF shock ticker drives shock | Selecting CL as shock ticker produces IRF where the shock is applied to CL | `irf_obj$irf[["CL"]]` is the shocked series | unit |
| 4.15 | IRF returns 5 responding tickers | All tickers except the shock ticker appear as responding series | `length(irf_traces) == 5` | unit |
| 4.16 | IRF horizon = 12 weeks | IRF chart X-axis runs from 0 to 12 | `max(irf_obj$irf[[shock_ticker]]$horizon) == 12` (or equivalent) | unit |
| 4.17 | CI ribbon at 15% opacity | Confidence band rendered at 15% opacity | Visual check | visual |
| 4.18 | Per-ticker viridis colors | Each responding ticker has a distinct viridis color; CI ribbon same color as response line | Visual check | visual |

### Phase 4 Smoke

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 4.19 | Rolling correlation renders for CL/BRN | Navigate to Cross-Market, select CL + BRN | Chart renders with shading; no console errors | smoke |
| 4.20 | VAR/IRF renders for CL shock | Select CL as shock ticker | IRF chart renders 5 response lines; lag count displayed | smoke |

---

## Phase 5 — Hedging Analytics

### Phase 5 Smoke (prior phases)
Run Phase 0–4 smoke tests — all must pass.

### `mod_hedge_swap` — CMA Swap Pricer

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 5.1 | Period generation covers only fully available periods | A period where any delivery month has no forward price on reference date is excluded | Select a reference date near end of data; Bal/Cal periods missing back tenors should not appear | integration |
| 5.2 | Period selector updates on date change | Changing reference date regenerates valid periods reactively | Select early vs. late reference date; period list changes accordingly | integration |
| 5.3 | Swap price from RTL::swapCOM | Swap price = RTL::swapCOM output for selected instrument/period | Spot-check CL Bal[year] on a known date — compare to manual CMA of forward prices | unit |
| 5.4 | HO ×42 conversion | HO forward prices multiplied by 42 before swap pricing | `RTL::swapCOM` called with ×42-adjusted prices for HO | unit |
| 5.5 | RB ×42 conversion | Same as HO | `RTL::swapCOM` called with ×42-adjusted prices for RB | unit |
| 5.6 | Producer shading direction | Above swap line = green, below = red for producer | Visual check | visual |
| 5.7 | Consumer shading direction | Above swap line = red, below = green for consumer | Visual check | visual |
| 5.8 | Forward curve color | Line color = `#210000` | Visual check | visual |
| 5.9 | Swap line color | Horizontal line color = `#F87217` | Visual check | visual |

### `mod_hedge_roll` — Rolling Hedge Simulator

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 5.10 | Roll 1 entry = reference date M1 price | Entry price for first roll = M1 price from dflong on reference date | `table$entry_price[1] == dflong[date == ref_date & tenor == "M01" & ticker == selected, value]` | unit |
| 5.11 | Cascade: exit N = entry N+1 | Exit price of roll N equals entry price of roll N+1 | For all N: `table$exit_price[N] == table$entry_price[N+1]` | unit |
| 5.12 | Exit date from RTL::expiry_table | Exit dates match `Last.Trade` from `RTL::expiry_table` for the correct `tick.prefix` | Spot-check CL exit dates against `RTL::expiry_table` | unit |
| 5.13 | BRN uses LCO prefix | BRN expiry dates looked up with `tick.prefix == "LCO"` | Verify at call site in server code | unit |
| 5.14 | HTT uses CL prefix | HTT expiry dates looked up with `tick.prefix == "CL"` | Verify at call site in server code | unit |
| 5.15 | Fallback to prior business day | If no M1 price on exact expiry date, prior available business day price is used | Test with a known holiday/gap date — price filled correctly | unit |
| 5.16 | Roll yield formula | `roll_yield == (entry - exit) / entry * 100` for all rows | Spot-check 3 rolls | unit |
| 5.17 | Producer P&L formula | `monthly_pnl == entry - exit` | Spot-check 3 rolls | unit |
| 5.18 | Consumer P&L formula | `monthly_pnl == exit - entry` | Spot-check 3 rolls | unit |
| 5.19 | Cumulative P&L = running sum | `cumulative_pnl[N] == sum(monthly_pnl[1:N])` | Check last row: cumulative = sum of all monthly P&L | unit |
| 5.20 | Fewer than 12 rolls handled gracefully | Select HTT with short history — table renders with however many rolls are available, no crash | No error; table shows < 12 columns without breaking layout | integration |
| 5.21 | Reference date constrained to ≥1yr before last available | Date picker does not allow selection within 1 year of last available date for ticker | Attempt to select a date 6 months before last available — picker rejects it | integration |

### `mod_hedge_options` — Options Pricer & Zero Cost Collar

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 5.22 | Black-76: b = 0 | `RTL::GBSOption` called with `b = 0` for all pricing | Verify at call site — `b` argument is 0 | unit |
| 5.23 | Call premium formula | Known inputs (S=100, X=100, T=0.25, r=0.05, σ=0.30, b=0) produce expected call premium | Compare to independently computed Black-76 call value | unit |
| 5.24 | Put premium formula | Same inputs as above — put premium matches Black-76 put formula | Compare to independently computed Black-76 put value | unit |
| 5.25 | TTM mapping | 1 month → T=0.0833; 3 months → T=0.25; 6 months → T=0.5 | `T_values == c(1/12, 3/12, 6/12)` for respective radio selections | unit |
| 5.26 | Zero-cost collar grid search | Grid search finds strike where `abs(opposite_premium - user_leg_premium)` is minimized | `which.min(abs(premiums - target_premium))` returns a valid index within the strike grid | unit |
| 5.27 | Collar MTM = 0 at reference date (View 2) | At `t = reference_date`, collar P&L = 0 by construction | `collar_pnl[date == reference_date] == 0` | unit |
| 5.28 | View 2 yield curve interpolation | `r_t` varies with `T_remaining` — not a fixed rate throughout | Verify `r_t` at T_remaining=0.5 ≠ r_t at T_remaining=0.1 on same date | unit |
| 5.29 | Yield curve feasibility constraint | Reference date constraint does not become infeasible when FRED data ends before dflong | Test with actual FRED file — verify picker has valid dates | integration |
| 5.30 | Contract multipliers | Total P&L = 100 × multiplier × per-unit P&L for each ticker | CL: `total == 100 * 1000 * per_unit`; NG: `total == 100 * 10000 * per_unit` | unit |
| 5.31 | Inputs locked in view mode | All inputs disabled (`shinyjs::disable`) on load | Visual check — inputs greyed out; clicking has no effect | visual |
| 5.32 | Edit/Apply toggle | Edit mode unlocks inputs; Apply re-renders and re-locks | Visual check — flow works correctly | visual |
| 5.33 | View 2 disabled when T out of range | Toggle disabled when `reference_date + T > last_available_date` | Visual check — switch greyed out with tooltip | visual |

### `mod_hedge_term` — Hedge Ratio Dynamics

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 5.34 | OLS betas from RTL::promptBeta | OLS beta curve renders for selected ticker | Non-NULL output from `RTL::promptBeta`; nrow > 0 | unit |
| 5.35 | R² in OLS hover | Hover on OLS dot shows R² value | Visual check | visual |
| 5.36 | Kalman animation frame count | One frame per calendar month in `r$kalman_betas` for selected ticker | `length(unique(animation_data$month_label)) == expected_months` | unit |
| 5.37 | X-axis fixed across frames | X-axis (tenor range) does not change between animation frames | Visual check — no "growing" curve as back months are introduced | visual |
| 5.38 | Early frames show NA gaps | Tenors not yet available in early frames render as gaps (NA), not as zero | Visual check — gaps appear in early animation frames | visual |
| 5.39 | OLS trace static across frames | OLS reference trace persists unchanged on all Kalman animation frames | `frame == NULL` for OLS trace; visual check — OLS line does not move | visual |

### `mod_hedge_cross` — Cross-Market Kalman Beta Matrix

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 5.40 | Matrix is 6×6 | Reactable renders 6 rows × 6 columns | Row labels and column labels = CL, BRN, NG, HO, RB, HTT | visual |
| 5.41 | Diagonal cells greyed | Diagonal cells (CL/CL, BRN/BRN, etc.) have grey background | Visual check | visual |
| 5.42 | Off-diagonal count = 30 | Non-diagonal cells populated from `r$kalman_cross_betas` | `nrow(filter(r$kalman_cross_betas, date == selected_date)) == 30` | unit |
| 5.43 | Date picker constrained to Kalman dates | Date picker range = dates present in `r$kalman_cross_betas`, not raw dflong dates | Attempt to select dflong's first date (before first Kalman observation) — picker rejects it | integration |
| 5.44 | Hover shows R² | Hovering a cell displays R² for that pair at selected date | Visual check | visual |
| 5.45 | RdBu scale | Positive betas = blue; negative = red; white at zero | Visual check — magnitude drives intensity | visual |

### Phase 5 Smoke

| # | Test | Checks | Expected Output | Type |
|---|------|--------|-----------------|------|
| 5.46 | All 5 rows render on default inputs | Navigate to Hedging Analytics — all rows render without interaction | No console errors; all charts/tables populate | smoke |
