# Planning — Commodity Market Dynamics (MVP)

> MVP scope: namespaces wired, charts render, architecture validated.
> No narrative text, no UI polish, no edge case handling.
> Locked decisions live here. Do not modify without explicit user sign-off.
> Brainstorm source: `../brainstorm.md`

---

## Phase 0 — Scaffold

**Goal:** App launches. Navigation works. Data is loaded. Reactive state is initialized. All module stubs exist. Nothing analytical.

**Deliverables:**

*App setup*
- `create_golem("CommodityMarketDynamics")` scaffold generated
- `bs_theme()` applied in `app_ui.R` — any theme, cosmetics irrelevant for MVP
- `page_navbar()` with 5 pages: Forward Curves, Volatility, Market Dynamics, Cross-Market Relationships, (Hedging Analytics placeholder — empty, no content)

*Data*
- `RTL::dflong` loaded once at the top of `app_server.R` and passed down — never reloaded by any child module
- Confirm dimensions and column names on load: `date`, `series`, `value`
- Helper: `get_ticker()` — filters dflong to a given ticker prefix (e.g. `"CL"`) and returns a wide or long tibble as needed; used by all modules

*Reactive state*
- `r <- reactiveValues()` initialized empty in `app_server.R`
- No values written yet — just the container

*Ticker selector*
- Shared UI component: dropdown of the 6 tickers (`CL`, `BRN`, `NG`, `HO`, `RB`, `HTT`)
- Placed on each page independently (not a global selector) — pages are analytically independent
- Returns selected ticker string as a reactive

*Module stubs*
- One stub pair (UI + server) per page module — renders a placeholder `card()` with the page name, nothing else
- Stub files created for analysis modules (empty functions, correct signatures)

**File structure created:**
```
R/
  app_ui.R
  app_server.R
  utils_data.R          # get_ticker() and any shared data helpers
  mod_fwd_curves.R      # UI + server in one file for MVP
  mod_volatility.R
  mod_market_dynamics.R
  mod_cross_market.R
  mod_analysis_pca.R    # stub
  mod_analysis_regime.R # stub
  mod_analysis_returns.R# stub
  mod_analysis_var.R    # stub
```

**Tests:**
- App launches without error (`shinytest2` or manual)
- All 5 pages navigate without error
- `dflong` loads: confirm ~150k+ rows (updated dataset), 3 columns (`date`, `series`, `value`)
- `get_ticker("CL")` returns only CL series; `get_ticker("HTT")` returns only HTT series
- `r` initializes as empty reactiveValues

**Dependencies:** None.

---

## Phase 1 — Forward Curves Page

**Goal:** Forward Curves page module wired. Ticker selector drives two charts: scaled comparison (Panel 1) and 3D surface (Panel 2). Panels 3 and 4 are stubs.

**Panel 1 — Scaled Comparison Chart**

*What it does:*
- User selects one or more tickers from the ticker selector
- A single date slider (snapshot, not a range) lets the user move through available dates
- On a given date, all selected tickers' forward curves are plotted on one chart — price on Y, tenor number on X
- Each ticker normalized independently: `(price - min) / (max - min)` across its own history so curves are comparable on a [0,1] scale
- One line per ticker, colored distinctly

*Implementation notes:*
- Filter `dflong` to selected tickers and the selected date
- Extract tenor number from series string (e.g. `"CL03"` → `3`) for X axis ordering
- Built with `plotly` — interactive hover showing ticker, tenor, raw price

*Module behavior:*
- `mod_fwd_curves_server` receives `dflong` and the ticker selector reactive as arguments
- Filtered reactive computed inside the module — does not reach up to `app_server.R` for anything beyond what is passed in

**Panel 2 — 3D Forward Curve Surface**

*What it does:*
- One ticker selected at a time (single ticker selector drives this panel)
- X axis: tenor number (1–N, derived from series suffix)
- Y axis: date
- Z axis: price
- Color mapped to price level using viridis scale
- Contango/backwardation regime classification computed per date:
  - Contango: M1 < MN (front cheaper than back)
  - Backwardation: M1 > MN (front more expensive than back)
  - Classification smoothed: rolling 5-day majority vote to suppress single-day flickers
- Regime haze projected onto the floor of the 3D plot only — not on the surface itself
  - Floor colored by regime: one color for contango, one for backwardation
- Built with `plotly` `plot_ly(type = "surface")`

*Implementation notes:*
- Reshape filtered dflong to a matrix: rows = dates, columns = tenors, values = price
- Regime vector computed from M01 vs MN spread per date, then smoothed
- Floor trace added as a separate `plot_ly` scatter3d or surface layer at Z = min(price)
- `mod_analysis_regime.R` handles regime computation — writes `r$[ticker]_regime`; Panel 2 reads from it

**Panels 3 & 4 — Stubs**
- Placeholder `card()` with label "Slope & Regime Analytics — coming soon" and "PCA — coming soon"
- No computation, no UI beyond the card

**Module files modified:**
- `mod_fwd_curves.R` — full Panel 1 and Panel 2 implementation; stub cards for 3 and 4
- `mod_analysis_regime.R` — regime classification + smoothing; writes `r$[ticker]_regime`

**Tests:**
- Normalization: known price series normalizes to [0,1] correctly
- Tenor extraction: `"CL03"` → `3`, `"HTT12"` → `12`, `"BRN36"` → `36`
- Regime classification: known M1/MN spread → correct contango/backwardation label
- Regime smoothing: a single-day regime flip in a 5-day window is suppressed
- `r$[ticker]_regime` is populated after first render and not recomputed on second render
- Panel 1 renders for all 6 tickers without error
- Panel 2 renders for all 6 tickers without error
- Date slider range matches available dates for the selected ticker

**Dependencies:** Phase 0 complete.

---

## Phase 2 — Volatility Page

**Goal:** Volatility page module wired. Two charts render for selected ticker: return distribution histogram (Panel 1) and correlation heatmap (Panel 2).

**Panel 1 — Stacked Return Distribution Histogram**

*What it does:*
- Log returns computed daily per tenor: `log(price_t / price_t-1)`
- One chart showing return distributions for all tenors stacked/overlaid
- Each tenor rendered as a semi-transparent histogram layer (opacity ~0.3)
- Tenor range filter: slider or multi-select dynamically generated from available tenors for that ticker
  - CL/BRN/NG: up to 36 tenors; HO/RB: up to 18; HTT: up to 12
- Colors via viridis palette, one color per tenor
- Built with `plotly`

*Implementation notes:*
- `mod_analysis_returns.R` computes log returns from dflong for selected ticker; writes `r$[ticker]_returns`
- Returns stored as a wide tibble: rows = dates, columns = tenor labels
- Histogram built by iterating over selected tenors and adding one `add_histogram` trace per tenor

**Panel 2 — Correlation Matrix Heatmap**

*What it does:*
- Pairwise correlation of log returns across all tenors for selected ticker
- Heatmap: tenors on both axes, color scale anchored at [-1, 1]
- Diagonal = 1 by definition; color gradient shows correlation decay across the term structure
- Built with `plotly` `plot_ly(type = "heatmap")`

*Implementation notes:*
- Correlation matrix computed from `r$[ticker]_returns` (reuses returns computed for Panel 1)
- `cor()` applied to the wide returns tibble, `use = "pairwise.complete.obs"`

**Module files modified:**
- `mod_volatility.R` — Panel 1 and Panel 2 implementation
- `mod_analysis_returns.R` — log returns computation; writes `r$[ticker]_returns`; lazy + cached

**Tests:**
- Log returns: known price series produces known return series (verify formula)
- Returns matrix dimensions: rows = trading days, columns = N tenors for that ticker
- Correlation matrix: symmetric, diagonal = 1, all values in [-1, 1]
- Tenor filter renders correct number of options per ticker (CL: 36, HO: 18, HTT: 12)
- `r$[ticker]_returns` cached — not recomputed on second panel render
- Both panels render for all 6 tickers without error

**Dependencies:** Phase 0 complete.

---

## Phase 3 — Market Dynamics Page

**Goal:** Group button mechanism works. Correct panels show/hide per group. One representative chart renders per group.

**Group button mechanics**

- Three buttons: **Crude** | **Refined Products** | **Natural Gas**
- `NG` button selects NG as a standalone ticker — no group swap needed, just routes to the NG panel
- Clicking **Crude** or **Refined Products**:
  - If a different group is active: show modal confirmation — "Switch to [group]? This will replace your current selection."
  - Confirm: apply group, update ticker selection to group tickers, show group panels
  - Cancel: leave state unchanged
  - If same group already active: do nothing
- User exits group view by clicking another group button or manually changing the ticker selector
- No locking — ticker selector remains interactive at all times

**Per-group panels and representative chart:**

*Crude (`CL`, `BRN`, `HTT`)*
- Representative chart: **Calendar spread time series** — M1–M2 spread for CL over time
- Computed as: `CL01 price - CL02 price` per date
- Line chart, date on X, spread value on Y
- Additional panel stubs: WTI/Brent spread, HTT differential, Cushing inventory (stubs only for MVP)

*Refined Products (`HO`, `RB`)*
- Representative chart: **Crack spread time series** — HO front month vs CL front month spread
- Computed as: `HO01 price - CL01 price` per date (proxy crack spread, same units after conversion note — flag if unit mismatch)
- Line chart, date on X, spread value on Y
- Additional panel stubs: RB crack spread, HO vs RB seasonal spread (stubs only for MVP)

*Natural Gas (`NG`)*
- Representative chart: **Monthly return seasonality** — average log return by calendar month across all years
- Bar chart: month on X (Jan–Dec), average return on Y
- Reveals the injection/withdrawal seasonal pattern
- Additional panel stubs: winter forward curve premium, storage cycle (stubs only for MVP)

**Module files modified:**
- `mod_market_dynamics.R` — group button logic, modal, panel routing, all three group panels

**Tests:**
- Group button state: clicking active button fires no state change
- Modal: confirm applies group switch; cancel leaves previous group active
- Panel visibility: Crude panels visible when Crude active; hidden when Refined Products active
- Calendar spread computed correctly from known CL01/CL02 prices
- Crack spread: confirm HO and CL are in compatible price units — flag discrepancy if not
- Monthly seasonality: known return series aggregated by month returns expected averages
- All three group representative charts render without error

**Dependencies:** Phase 0 complete. Confirm HO/CL unit compatibility before executing crack spread chart.

---

## Phase 4 — Cross-Market Relationships Page

**Goal:** Cross-Market Relationships page wired. Rolling correlation chart (Panel 1) renders. VAR/IRF chart (Panel 2) renders with confidence bands and significance coloring. `r$var_results` written once.

**Panel 1 — Rolling Correlation with Volatility Regime Shading**

*What it does:*
- Two-ticker selector — user picks exactly two tickers from the 6
- Rolling correlation of front month (M01) log returns between the two selected tickers
- Rolling window: 60 trading days (configurable via slider — range 20–120)
- Background shading by volatility regime — derived from rolling standard deviation of the equally-weighted average of both tickers' M01 returns:
  - High vol: rolling SD above 75th percentile of its own history
  - Low vol: rolling SD below 75th percentile
  - Two shaded regions, distinct fill colors, low opacity
- Line chart (correlation) overlaid on shaded background
- Built with `plotly`

*Implementation notes:*
- Front month returns reused from `r$[ticker]_returns` (Phase 2)
- Rolling correlation computed with `zoo::rollapply` or `slider::slide_dbl`
- Vol regime computed from rolling SD of blended return series

**Panel 2 — VAR + Granger Causality + IRFs**

*What it does:*
- One VAR model fitted across all 6 tickers simultaneously using M01 log returns only
- Lag selection: run AIC, BIC, HQ, FPE simultaneously via `vars::VARselect()`; select the lag length where the most criteria agree; tie-break to the lower lag
- Selected lag and selecting criterion displayed in the UI (e.g. "VAR(3) — selected by BIC, HQ")
- Granger causality run within the VAR system via `vars::causality()`
- IRFs computed via `vars::irf()` — orthogonalized, 20-day horizon, 95% bootstrap confidence bands (100 runs for MVP speed)
- User selects a shock ticker from a dropdown — one IRF chart rendered showing all 5 responding tickers overlaid
- X axis: days post-shock (0–20), Y axis: scaled cumulative response
- Confidence bands shown as shaded ribbons per responding ticker
- Color convention:
  - Response line + band **green** when the entire confidence band excludes zero (statistically meaningful)
  - Response line + band **grey** when the confidence band straddles zero (no meaningful relationship)
- Caveat displayed below chart: "VAR calibrated on historical return innovations. Structural breaks (e.g. COVID, shale revolution) mean historical relationships may not hold forward."
- Built with `plotly`

*`r` reactive usage:*
- `mod_analysis_var.R` runs all VAR computation once on app load (not lazy — VAR is expensive and ticker-agnostic)
- Writes `r$var_results`: list containing the fitted VAR object, lag selection table, Granger results, and pre-computed IRFs for all shock tickers
- `mod_cross_market_server` reads from `r$var_results` — no recomputation on ticker switch

**Module files modified:**
- `mod_cross_market.R` — Panel 1 and Panel 2 implementation
- `mod_analysis_var.R` — VAR fitting, lag selection, Granger, IRF computation; writes `r$var_results`

**Tests:**
- VAR fits without error on 6-ticker M01 return dataset
- `VARselect()` returns a lag integer for each criterion; consensus selection logic returns a single integer
- IRF object dimensions: 6 tickers × 6 shock tickers × 20 horizon steps
- Confidence bands present for all IRFs (lower and upper bounds non-null)
- Green/grey logic: known IRF band fully above zero → green; band crossing zero → grey
- `r$var_results` written once; Panel 2 switching shock ticker reads from cache, no refit
- Rolling correlation computed correctly from known return series
- Vol regime shading: known SD series above 75th percentile → high vol label

**Dependencies:** Phase 0 and Phase 2 complete (`r$[ticker]_returns` must exist before VAR module reads front month returns).

---

## Phase 5 — Smoke Test

**Goal:** Confirm the full app holds together. All pages load, all charts render across all valid tickers, no namespace bleed, no redundant computation.

**Checks:**

*Functional*
- Navigate to every page — no errors, no blank screens
- Select every ticker on every page that has a ticker selector — all charts render
- Activate every group button on Market Dynamics — correct panels appear, modal fires correctly
- Select every shock ticker in the IRF dropdown — chart updates, no refit of VAR

*Namespace integrity*
- Trigger an input in one page module — confirm no reactivity fires in any other page module
- Confirm `r$[ticker]_returns` for CL is not recomputed when BRN is selected on the Volatility page (i.e. lazy cache is working)
- Confirm `r$var_results` is written exactly once (add a `message()` in `mod_analysis_var.R` during testing, remove after)

*Regression*
- Run `testthat::test_dir("tests/")` — all tests from Phases 0–4 pass
- Zero failing tests before sign-off

**Dependencies:** Phases 0–4 complete and individually signed off.

---

## Open Decisions

| Item | Decision needed | Blocking |
|---|---|---|
| Hedging Analytics page | Full brainstorm required — out of MVP scope | No |
| Returns PCA (Volatility page) | In or out of MVP | No — stub for now |
| HO/CL unit compatibility | Confirm same price units before crack spread chart | Phase 3 |
| EIA NG storage data | Confirm `RTL::eiaStocks` covers NG if storage cycle added beyond MVP | No |
