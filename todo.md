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

## Phase 5 — Hedging Analytics Page ✅ COMPLETE

All 292 tests pass (221 prior + 71 new). Visual review complete. Signed off 2026-04-06.

All 5 modules built and deployed: mod_hedge_swap, mod_hedge_roll, mod_hedge_options, mod_hedge_term, mod_hedge_cross.

### Phase 5 Tests & Review
- [x] Run all Phase 5 tests from `testing_plan.md` (tests 5.1–5.46) — 71 pass, 1 skip (expected), 0 fail
- [x] User visual review: all rows render correctly; signed off
- [ ] Commit (pending final narrative revisions)

---

## Deployment ✅ COMPLETE

- [x] Dockerfile written (`rocker/r-ver:4.4.2` base; all CRAN deps via pak; package installed from source)
- [x] `.github/workflows/docker.yml` — triggers on push to main; builds and pushes to `aymanarman/commodity-market-dynamics` on DockerHub
- [x] Tested locally on Docker Desktop — app loads at localhost:3838, all charts render
- [x] FRED yield curve fetch wrapped in tryCatch; 5% fallback rate used when FRED unreachable in container

---

## Remaining Work — Narrative Revisions Only

Light text edits to narrative cards across the app. No code changes, no dependency changes, no tests needed.

- [x] Forward Curve Row 2 (3D surface): added "Notice" paragraph on contango/backwardation and mean reversion
- [ ] Additional narrative changes per user direction
