# Todo — Commodity Market Dynamics

Execution guide derived from `planning.md`. Work sequentially — one phase at a time. Do not begin a phase until the prior phase is fully implemented, tested, and signed off. Testing plan lives in `testing_plan.md`.

---

## Locked Coloring Decisions (applied across all phases)

| Element | Value |
|---|---|
| Page / navbar background | `#48495e` |
| Card body | `#757a8a` |
| Card header | `#75858a` |
| Chart plot + paper background | `#fffff2` |
| Major gridlines | `rgba(33,0,0,0.08)`, width 0.5 |
| Minor gridlines | hidden |
| Axis / zeroline color | `#210000` |
| Row divider | `1px dashed rgba(249,249,249,0.25)` |
| Primary accent | `#F87217` |
| Secondary accent | `#179df8` |
| Spinner color | `#F87217` |

---

## Phase 0 — Scaffold & Shared Infrastructure ✅ COMPLETE

All 82 tests pass. Signed off 2026-04-05.

---

## Phase 1 — Forward Curves Page ✅ COMPLETE

All 25 tests pass. Signed off 2026-04-05.

### Locked implementation details (deviations from original plan)
- Date slider uses Date-typed `sliderInput` (not integer-mapped) — snaps to nearest available trading date; performs fine in practice
- PCA shows top 3 PCs by variance explained (not ≥2% filter)
- Historical overlay defaults: 2010-06-01, 2014-06-02, 2020-06-01, 2024-06-03
- Row 3 has centered title "Seasonal Forward Curve Shapes" + 1-line italic narrative

---

## Phase 2 — Volatility Page

**Smoke:** run Phase 0–1 tests before writing any Phase 2 code.

### `mod_vol_density` — Row 1
- [x] Pipe `dflong` for selected ticker through `compute_returns()`; build `sliderInput` dynamically from available tenors for the selected ticker (M1–Mn); clip returns for each tenor to its own 1st/99th percentile before passing to density
- [x] Render overlaid density chart (col_a, width=6): one `density()` curve per tenor in the slider range; render back tenors first at higher transparency, front tenors last at lower transparency; turbo color scale ordered by tenor; x-axis label = "Level Difference" for HTT, "Log Return" otherwise; `apply_theme()`
- [x] Render horizontal vol bar chart (col_b, width=4): one bar per tenor showing annualised vol `sd(returns) × sqrt(252)`; always shows all available tenors regardless of density slider; turbo colors matching density chart; `apply_theme()`
- [x] Narrative card (col_c, width=2)

### `mod_vol_heatmap` — Row 2
- [x] Pipe `dflong` for selected ticker through `compute_returns()`; pivot returns to wide (date × tenor); compute `cor()` matrix; render plotly heatmap with Spectral color scale reversed, range fixed to [−1, 1]; `apply_theme()`
- [x] Ticker selector; static beyond ticker change
- [x] Layout: col_a (width=6) narrative card, col_b (width=6) heatmap

### `mod_vol_rolling` — Row 3
- [x] Pipe `dflong` for selected ticker + tenor through `compute_returns()`; compute rolling sd with 21-day window (`zoo::rollapply` or equivalent); annualise (`× sqrt(252)`); render plotly line chart; `apply_theme()`
- [x] Add 3 locked event markers via plotly `add_markers()` with custom symbol: (2014-03-03, "Crimea Annexation"), (2020-03-09, "COVID-19 / Oil Price War"), (2022-03-07, "Russia-Ukraine Invasion"); render marker at the vol value on that date; silently omit if date falls outside the ticker/tenor's available date range
- [x] Ticker selector + tenor selector (dynamically generated from available tenors for selected ticker); x/y-axis labels update to "Level Difference" units when HTT selected
- [x] Layout: col_a (width=6) narrative card, col_b (width=6) chart

### Phase 2 Tests & Review
- [x] Run all Phase 2 tests from `testing_plan.md` (tests 2.1–2.19)
- [x] User visual review: density layering (back tenors translucent), event markers on CL M1, HTT label switching; sign off
- [ ] Commit

---

## Phase 3 — Market Dynamics Page ✅ COMPLETE

All 174 tests pass (48 Phase 3 tests, 126 prior phases). Signed off 2026-04-06.

### Locked implementation details (deviations from original plan)
- `RTL::cushing$storage` (not `RTL::cushing` directly); inventory column is `stocks` not `value`
- LNG exports file (N9133US2m.xls) starts 1997; Sabine Pass first export at 2016-02-24 is a vertical line within the series, not the series start date
- 5-year rolling average uses `lag(rollapplyr(..., width=5), 1)` — gives mean of Y-5 to Y-1 (prior years only, excluding current year); EIA standard methodology
- Crack spread inner join warning: compares nrow(HO∩RB) vs nrow(HO∩RB∩CL) — not n_min approach
- All radioGroupButtons → `prettyRadioButtons(status="primary", inline=TRUE)`; all price lines `#000080`
- Geopolitical events: rect shapes + black text annotations (not point markers); Iran War (2026-03-01 to Sys.Date()) only on charts that also carry COVID + Ukraine shading
- Row separators: CSS extended to `.shiny-panel-conditional > .row` for Market Dynamics page
- `ns <- session$ns` required in server functions using `renderUI` with `ns()` — missing causes "could not find function ns"
- Coal census divisions use full US Census Bureau names via `division_full_name()`; `map_census_region()` retained for test 3.22
- NG Row 1: `rainbow()` color scheme; `hovermode="closest"`
- NG Row 2: surplus=green/deficit=red; layout col(1)+col(2 slider)+col(6 chart)+col(3 narrative)
- NG Row 3 coal chart: YoY change `mwh - lag(mwh, 12L)` removes both seasonality and secular decline
- NG Row 4: 2-panel subplot (price top, LNG bottom, shareX=TRUE)
- Date range sliders added to crude Rows 2/3/4 and refined Row 3; placed directly under each chart
- NG Row 3 coal slider min anchored to NG price data start (~2007), not coal data start (1983)

### Phase 3 Tests & Review
- [x] Run all Phase 3 tests from `testing_plan.md` (tests 3.1–3.28)
- [x] User visual review: all three groups render; crack spread ×42 values are sensible; seasonal storage overlay; Sabine Pass annotation; sign off
- [ ] Commit

---

## Phase 4 — Cross-Market Relationships Page

**Smoke:** run Phase 0–3 tests before writing any Phase 4 code.

### `mod_cm_rolling_corr` — Row 1
- [x] For two selected tickers, compute daily M1 log returns from `dflong`; compute rolling correlation with `zoo::rollapplyr` using selected window; default window = 90 days
- [x] Compute high-vol regime: rolling 21-day vol for each ticker; average; threshold = 80th percentile of that averaged rolling vol series; identify contiguous high-vol periods
- [x] Render plotly line chart: rolling correlation line color `#210000`; add background shading for high-vol periods via plotly `shapes` (red, 20% opacity); horizontal reference line at y=0; `apply_theme()`
- [x] Rolling window `sliderInput`: range 21–252 days, default 90, step 1; two-ticker selector limited to exactly 2 tickers
- [x] Layout: centered col (width=8) with 2-width margins; narrative card below in same centered col

### `mod_cm_var` — Row 2
- [x] Display selected lag count as inline text below shock ticker selector: "Model estimated with N lags (criterion)" — read from `r$var_results`; `lag_criterion` attribute added to mod_var.R
- [x] Shock ticker `selectInput`; compute IRF via `vars::irf` using `r$var_results`; horizon = 12 weeks; index response by `irf_obj$irf[[shock_ticker]][, responding_ticker]` for each of the 5 non-shock tickers
- [x] Assign distinct viridis colors to each responding ticker; render plotly line chart with all 5 response lines overlaid; add CI ribbon per ticker at 15% opacity same viridis color; horizontal reference line at y=0; `apply_theme()`
- [x] Layout: col_a (width=8) chart, col_b (width=4) narrative card; `class = "mt-3"` on row

### Phase 4 Tests & Review
- [x] Run all Phase 4 tests from `testing_plan.md` (tests 4.1–4.20) — 221 pass, 0 fail
- [x] User visual review: vol regime shading aligns with visible vol spikes; IRF CI ribbons readable; Cholesky ordering caveat in narrative; sign off — 2026-04-06
- [ ] Commit

---

## Phase 5 — Hedging Analytics Page

**Smoke:** run Phase 0–4 tests before writing any Phase 5 code.

### `mod_hedge_swap` — Row 1

- [ ] Build instrument selector (CL, BRN, NG, HO, RB, HTT, BRN−CL spread, HO×42−RB×42 spread); reference `dateInput` defaulting to most recent available date for selected instrument; constrain range to available dates in `dflong` for that instrument
- [ ] Generate valid delivery periods: filter `dflong` to selected instrument on reference date; map tenors to delivery months via `RTL::expiry_table`; build Bal[year] and Cal[year+1..year+3] candidates; drop any period missing any delivery month in the forward curve on that date; populate `selectInput` reactively
- [ ] Direction toggle (Producer / Consumer)
- [ ] Price swap via `RTL::swapCOM`; apply ×42 conversion for HO and RB before pricing; compute CMA of spread directly for spread instruments
- [ ] Render plotly chart (col_a, width=6): monthly forward curve line (`#210000`) + horizontal flat swap line (`#F87217`) + shaded area between (producer: above = green, below = red; consumer: reversed) at 25% opacity; `apply_theme()`
- [ ] Stat card in col_b showing flat swap price; narrative card below stat; layout col_a (width=6), col_b (width=6)

### `mod_hedge_roll` — Row 2

- [ ] Build ticker selector (CL, BRN, NG, HO, RB, HTT); reference date picker constrained to dates ≥1 year before last available date for selected ticker; direction toggle (Producer / Consumer)
- [ ] Implement roll logic: entry roll 1 = M1 price on reference date; exit = M1 price on expiry date from `RTL::expiry_table` (BRN → `tick.prefix == "LCO"`, HTT → `tick.prefix == "CL"`); if no price on exact expiry date use prior available business day; cascade: exit N = entry N+1; generate up to 12 rolls; gracefully handle fewer than 12 rolls available
- [ ] Compute Roll Yield % = `(Entry − Exit) / Entry × 100`; Producer P&L = `Entry − Exit`; Consumer P&L = `Exit − Entry`; Cumulative P&L = running sum
- [ ] Render `reactable` table with 12 columns (one per roll); conditional cell coloring: green = gain, red = loss for selected direction; unit label in table header ($/bbl, $/MMBtu, $/gal per ticker)
- [ ] Layout: col_a (width=6) narrative, col_b (width=6) table

### `mod_hedge_options` — Row 3

- [ ] Build inputs panel (col_a, width=3): ticker selector (CL, BRN, NG, HO, RB — HTT excluded); direction toggle; implied vol slider (0.01–1.00, step 0.01, default 0.30); TTM `radioButtons` (1 / 3 / 6 months); reference `dateInput` constrained reactively to dates where nearest futures expiry at ≥ T months out is ≤ `last_available_date` in `dflong`; collar strike `numericInput` defaulting to M1 price × 0.95; Edit/Apply toggle button; View 2 `bslib::input_switch()` below button
- [ ] Lock all inputs on load via `shinyjs::disable()`; Edit mode unlocks inputs and greys charts with "Click Apply to update" banner; Apply re-locks and re-renders; disable View 2 toggle during edit mode and when `reference_date + T > last_available_date`
- [ ] **View 1 — BS Pricing Curve** (col_b, default): build strike grid (~100 points, 0–2× M1 for CL/BRN/HO/RB/HTT; 0–3× for NG); compute call (`#db243a`) and put (`#4169E1`) premiums via `RTL::GBSOption(b=0)` across full grid; horizontal dashed line at user's collar leg premium (`#F87217`); vertical dashed lines at both zero-cost collar strikes; `apply_theme()`
- [ ] **View 1 — Payoff Diagram at Expiry**: build payoff curves — unhedged (`#343d46`) and collar (`#F87217`); fixed X-axis range (0–2×S0 or 0–3×S0); fixed Y-axis range from collar payoff endpoints; `apply_theme()`
- [ ] **Zero-cost collar grid search**: evaluate `GBSOption` for the opposite leg across the existing strike grid; zero-cost strike = `strike_grid[which.min(abs(opposite_premiums - user_leg_premium))]`
- [ ] **View 2 — Collar MTM over life**: find `expiry_date` = nearest futures expiry ≥ T months after reference date (BRN → LCO prefix); loop over trading days from reference date to expiry date; for each date compute `S_t` from `dflong`, `T_remaining`, `r_t` via linear interpolation of `r$yield_curves` at that date and tenor; compute long and short leg values via `GBSOption(b=0)`; net collar P&L = 100 × multiplier × (long − short); at reference date P&L = 0 by construction; render dual-axis plotly chart (underlying price left, collar P&L right); `shinycssloaders::withSpinner()`; `apply_theme()`
- [ ] Narrative card (static text) below charts

### `mod_hedge_term` — Row 4

- [ ] Shared inputs row: ticker selector (CL, BRN, NG, HO, RB — HTT excluded); animation speed `radioButtons` (Slow=1000ms / Medium=500ms / Fast=250ms)
- [ ] **col_a — Static OLS beta curve**: call `RTL::promptBeta` on full history for selected ticker; render dotted line with interactive points (X = tenor M2…Mn, Y = β vs M1, color `#210000`); horizontal reference line at β=1.0 color `#4169E1`; hover shows R² for that tenor pair; non-reactive beyond ticker change
- [ ] **col_b — Animated Kalman beta curve**: filter `r$kalman_betas` to selected ticker; reduce to one snapshot per calendar month (last available trading day); fix X-axis to the maximum set of tenors across full history for that ticker; early frames where a tenor did not yet exist render as NA gap; build `plot_ly(frame = ~month_label)` with `animation_opts(frame = speed_ms, redraw = FALSE)` and `animation_slider(currentvalue = list(prefix = "Date: "))`; add OLS curve as second trace with `frame = NULL` at 25% opacity
- [ ] col_c (OLS narrative) and col_d (Kalman narrative) static cards below respective charts

### `mod_hedge_cross` — Row 5

- [ ] Single date picker; constrain range to dates present in `r$kalman_cross_betas`; default = most recent available date
- [ ] Slice `r$kalman_cross_betas` at selected date; pivot to 6×6 matrix (rows = exposure ticker, cols = hedge instrument ticker)
- [ ] Render via `reactable`: diagonal cells greyed out; off-diagonal cell background via `RdBu` diverging scale centered at 0; positive = blue, negative = red; magnitude drives intensity; hover tooltip shows R² for that pair at selected date
- [ ] Narrative card below table

### Phase 5 Tests & Review
- [ ] Run all Phase 5 tests from `testing_plan.md` (tests 5.1–5.46)
- [ ] User visual review: swap pricer shading directions; rolling hedge table P&L colors; options pricer View 1 and View 2; Kalman animation playback; cross-market matrix diagonal greyed; sign off
- [ ] Commit
