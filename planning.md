# Planning — Commodity Market Dynamics

Derived from `brainstorm.md`. All phases must be fully planned and approved before execution begins. Locked decisions live here — do not re-derive from brainstorm.

---

## Global Theme

### Colors
| Element | Value | Notes |
|---|---|---|
| App background / navbar | `#757a8a` | Space grey |
| Card / panel background | `#7e8081` | 3D shadowy border effect |
| Chart plot background (`plot_bgcolor`) | `#fffff2` | Off-white, yellowish |
| Chart paper background (`paper_bgcolor`) | `#fffff2` | Matches plot so axis labels sit on same surface |
| Primary text (narrative, card headers) | `#f9f9f9` | Near-white |
| Secondary text (axis labels, captions) | `#343d46` | Space grey — sits on chart paper background |
| Primary accent | `#F87217` | Pumpkin orange — buttons, active states, highlights |
| Secondary accent | `#179df8` | Complementary blue — stat card values, secondary selected states; used sparingly |
| Gridline color | `#210000` | Near-black with slight red tint — intentional |
| Axis line color | `#210000` | Matches gridlines |

### Card Styling
- Border: slightly darker than card background; shadow applied for 3D effect
- Border radius: moderate (~10–12px)
- Shadow: yes

### Chart Defaults
- Font family: Times New Roman
- Font size: plotly defaults unless visually off — adjust at implementation
- All plotly charts apply `plot_bgcolor`, `paper_bgcolor`, gridline color, axis line color, and font family globally via `apply_theme()` — built in Phase 0, listed in the modules table

### Color Scales
| Context | Scale | Status |
|---|---|---|
| Density chart / vol bar chart | turbo | locked |
| Correlation heatmap | Spectral, reversed | locked |
| 3D forward curve surface | viridis | locked |
| Monthly forward curve overlays (12 discrete months) | viridis-derived 12-color palette | adjust at implementation |
| Any other multi-series scale | viridis family | default |

---

## Phase 0 — Scaffold & Shared Infrastructure

### Modules

| Module | Role |
|---|---|
| `app_server.R` | Loads `dflong` once; initialises `r` reactive; wires all analysis modules and page modules |
| `mod_yield_curves` | Loads FRED Treasury CMT rates from static file in `inst/extdata/` at startup; writes `r$yield_curves`; reused by Hedging Analytics page Row 3 (options pricer) |
| `mod_kalman_betas` | Pre-computes within-ticker Kalman betas (M1 vs all back tenors) for all tickers at startup; writes `r$kalman_betas`; output schema: long-format tibble with columns `(date, ticker, tenor, beta, r_squared)` — one row per date × ticker × tenor pair; R² consumed by Phase 5 Row 4 OLS hover tooltip and Kalman animation frames |
| `mod_kalman_cross` | Pre-computes cross-ticker Kalman betas (M1 vs M1) for all 30 off-diagonal pairs at startup; writes `r$kalman_cross_betas`; output schema: long-format tibble with columns `(date, from_ticker, to_ticker, beta, r_squared)` — one row per date × directed pair, diagonal excluded; R² consumed by Phase 5 Row 5 hover tooltip; must consume `compute_returns` output for all tickers — ensures HTT uses level differences (ΔP) rather than log returns; do not compute raw log returns directly in this module |
| `mod_var` | Estimates weekly VAR model once at startup; writes `r$var_results`; Cholesky ordering BRN→CL→HO→RB→HTT→NG; weekly aggregation: filter `dflong` to Friday closes (or last available trading day of each week) before computing returns — do not pass daily data |
| `compute_returns` | Utility function (not a Shiny module); computes daily log returns per tenor from a long-format ticker tibble; automatically uses level differences (ΔP) for spread tickers with negative values (HTT); used by `mod_vol_density`, `mod_vol_heatmap`, `mod_vol_rolling`, and any other module requiring per-tenor returns |
| `apply_theme` | Utility function (not a Shiny module); applies the global plotly theme to any plotly object — sets `plot_bgcolor`, `paper_bgcolor`, gridline color, axis line color, and font family (Times New Roman) consistently; every plotly chart in the app must be piped through this function before returning |

### Notes
- `r` reactive initialised empty in `app_server.R`; populated lazily or at startup per module contract above
- All subsidiary modules receive data as reactive arguments — never reach up to grab data
- Phase 0 scaffold includes page stubs only; no page content implemented here

### Static Data Files

All external data is pre-downloaded and bundled with the app — no API calls at runtime. This ensures reproducibility, eliminates runtime dependencies on third-party APIs, and allows the Docker image to run without credentials.

**File location:** `inst/extdata/` — standard golem location for bundled data files

**Universal loading pattern (cross-platform — works on Windows, Linux, Mac, Docker):**
```r
# All EIA files share this structure: sheet = "Data 1", skip = 2, two columns (date, value)
# Date column is Excel serial numbers — convert via as.Date(as.numeric(date), origin = "1899-12-30")
path <- system.file("extdata", "filename.xls", package = "CommodityMarketDynamics")
readxl::read_xls(path, sheet = "Data 1", skip = 2, col_names = c("date", "value")) |>
  dplyr::mutate(
    date = as.Date(as.numeric(date), origin = "1899-12-30"),
    value = as.numeric(value)
  ) |>
  dplyr::filter(!is.na(date), !is.na(value))
```
Never use hardcoded absolute paths or `setwd()` — `system.file()` resolves correctly on all platforms and inside Docker containers.

**All static data loaded at startup in `app_server.R` and written to `r$`** — same pattern as `r$var_results` and `r$kalman_betas`; modules receive data as arguments, never reach up into `r` directly.

**Files in `inst/extdata/` and their `r$` assignments:**

| File | `r$` slot | Series | Used In | Units |
|---|---|---|---|---|
| `PET.WCRFPUS2.W.xls` | `r$eia_crude_prod` | US weekly crude field production | Crude Row 4 | Thousand bbl/day |
| `PET.WCRRIUS2.W.xls` | `r$eia_crude_inputs` | US weekly refinery crude inputs | Crude Row 4 | Thousand bbl/day |
| `PET.WDISTUS1.W.xls` | `r$eia_distillate_stocks` | US weekly distillate stocks | Refined Row 3 | Thousand barrels |
| `PET.WGTSTUS1.W.xls` | `r$eia_gasoline_stocks` | US weekly gasoline stocks | Refined Row 3 | Thousand barrels |
| `NG.NW2_EPG0_SWO_R48_BCF.W.xls` | `r$eia_ng_storage` | NG weekly working underground storage | NG Rows 1 & 2 | Bcf |
| `N9133US2m.xls` | `r$eia_lng_exports` | US LNG exports | NG Row 4 | MMcf/month |

**Still needed (add to `inst/extdata/` before Phase 3 execution):**

| File | `r$` slot | Series | Used In |
|---|---|---|---|
| EIA-923 annual `.xlsx` files (one per year, 2008–2025) | `r$eia923_coal` | Coal Netgen MWh by state/region, monthly | NG Row 3 |
| FRED Treasury CMT rates | `r$yield_curves` | DGS1MO, DGS3MO, DGS6MO, DGS1, DGS2, DGS5, DGS10, DGS30 | Hedging Row 3 |

**Docker cross-platform note:**
The Dockerfile uses a Linux base image (`rocker/shiny`). `system.file()` resolves correctly inside the container — no path adjustments needed. Do not use `file.path(getwd(), ...)` or Windows-style paths anywhere in the codebase.

---

## Phase 1 — Forward Curves Page

### Modules

| Module | Role |
|---|---|
| `mod_fc_comparison` | Scaled comparison chart (Panel 1); owns ticker selector, date slider, historical overlay toggle, 0–4 date inputs; switches between multi-ticker comparison mode and single-ticker historical overlay mode |
| `mod_fc_surface` | 3D forward curve surface (Panel 2); owns ticker selector; filters `dflong` internally based on selection |
| `mod_fc_monthly` | Monthly forward curve overlays (Panel 3); owns ticker selector; computes average curve per calendar month |
| `mod_fc_pca` | PCA decomposition (Panel 4); owns ticker selector; lazy computes per ticker; writes `r$[ticker]_pca` — explicit exception to the architecture discipline: lazy caching on first selection does not break the app and avoids a redundant analysis module for a single computation |

---

### Row 1 — Scaled Comparison Chart

**Layout:**
```
row(
  col(width=2),   # empty — left margin
  col(width=8),   # chart + controls (center stage)
  col(width=2)    # empty — right margin
)
```

**Narrative:**
- No narrative card — Panel 1 is a pure interactive tool; the user is meant to explore and draw conclusions directly
- Ticker selector label doubles as a light framing cue: "Select commodities to compare their forward curve structures"

**Visualization:**
- Single normalised chart — all selected tickers on one date, prices index-based (M1 = 100 for each ticker on the selected date) so curve shapes are directly comparable across different-priced commodities
- Single date slider (not a range); moves through all available dates; updates chart reactively
- **Date slider implementation (integer-mapped):** compute `available_dates` as the sorted intersection of dates present in `dflong` for all currently selected tickers; build `date_map <- data.frame(idx = seq_along(available_dates), date = available_dates)`; `sliderInput(min=1, max=nrow(date_map), value=nrow(date_map), step=1)`; selected date resolved server-side as `date_map$date[input$date_idx]`; display resolved date as a `textOutput` label adjacent to the slider; when ticker selection changes, recompute `available_dates` and fire `updateSliderInput()` to reset `max` — current value clamps automatically if it exceeds new max; do not use `sliderTextInput()` — render performance degrades on large date vectors
- `bslib::input_switch()` toggles to **historical overlay mode**:
  - Replaces multi-ticker selector with a single-ticker selector
  - Four optional calendar date inputs (empty = not plotted); 0–4 historical curves overlaid simultaneously
  - Allows direct comparison of curve shape across specific historical dates for one ticker
- Data: `dflong` filtered to selected tickers and date
- Sparse early history on some tickers creates gaps — filter to dates where all selected tickers have data

---

### Row 2 — 3D Forward Curve Surface

**Layout:**
```
row(
  col_a(width=6),   # 3D surface chart
  col_b(width=6)    # narrative card
)
```

**Narrative:**
- Short instructional card — explains the three axes:
  - X: tenor — how far out along the forward curve (M01 = front month, Mn = furthest available)
  - Y: date — the historical date on which that curve was observed
  - Z: price — the futures price for that tenor on that date
- Explains the regime floor: the floor of the plot is colored by contango/backwardation regime — contango = back months priced above front (normal carry), backwardation = front months priced above back (supply tightness or demand spike)

**Visualization:**
- X: tenor (M01…Mn), Y: date, Z: price
- Viridis color scale mapped to price level on the surface
- Regime haze projected onto the floor of the 3D plot (not the surface) — floor colored by contango/backwardation regime per date, spanning all tenors
- Regime classification smoothed via centered 5-day rolling majority vote (2 days either side of current date) to suppress flickering from short-lived switches — centered window chosen for retrospective accuracy, not forecasting
- Built in plotly; ticker selector drives the surface
- Data: `dflong` filtered to selected ticker; all tenors; all available dates

---

### Row 3 — Monthly Forward Curve Overlays

**Narrative:**
- Brief framing above chart: "Each line is the average forward curve shape for that calendar month, computed across all available years for the selected commodity. Seasonal premia embedded in the forward curve are visible as systematic differences between months."
- No interactive narrative — the visual is the explanation

**Visualization:**
- 12 lines — one per calendar month (Jan–Dec)
- Each line = average forward curve for that month across all available years for the selected ticker
- X-axis: tenor (M1…Mn); Y-axis: price
- Color by month — distinct palette (not viridis; 12 discrete colors needed)
- Ticker selector (individual tickers only); static beyond ticker selection
- Data: `dflong` filtered to selected ticker; group by calendar month + tenor; compute mean price

---

### Row 4 — PCA Decomposition

**Layout:**
```
row(
  col_a(width=6),   # narrative card
  col_b(width=6)    # PCA chart
)
```

**Narrative:**
- **What PCA is:** PCA identifies the directions along which the forward curve has historically varied the most. It does not model prices — it models the shape changes of the curve over time.
- **Loadings:** Each principal component represents a recurring pattern of forward curve movement observed over the historical data range. The components reveal how tenors co-move — which parts of the curve tend to move together and which move independently. Loadings are a relative directionality measure: a large positive loading means that tenor moves strongly in the direction of that component; a large negative loading means it moves strongly against it; a loading near zero means that tenor is largely unaffected by that particular curve dynamic.
- **Interpretation:**
  - PC1 shape describes the historical behaviour of the forward curve movements across tenors that is most common
  - PC2 shape describes the second most common historical behaviour of forward curve movements across tenors
  - PC3 shape describes the third most common historical behaviour of forward curve movements across tenors
- Framing connects back to the correlation heatmap on the Volatility page — PCA is the decomposition of the covariance structure shown there

**Visualization:**
- PC loadings plotted against tenors — one line per principal component; include all PCs that individually explain ≥2% of variance; clip if too many lines render at implementation
- X-axis: tenor; Y-axis: loading
- Variance explained per component displayed in the legend (e.g. "PC1: 94%") — visible without hovering so the user can immediately see which component is most informative
- Ticker selector (individual tickers only); lazy computed per ticker on first selection; cached in `r$[ticker]_pca`
- Data: `dflong` filtered to selected ticker; pivot to wide (date × tenor); compute PCA via `stats::prcomp`

---

## Phase 2 — Volatility Page

### Modules

| Module | Role |
|---|---|
| `mod_vol_density` | Overlaid density chart + volatility bar chart; owns ticker selector + tenor range filter |
| `mod_vol_heatmap` | Correlation matrix heatmap; owns ticker selector |
| `mod_vol_rolling` | Rolling realised volatility over time; owns ticker + tenor selectors; applies event markers |

---

### Row 1 — Stacked Return Distribution Histogram

**Layout:**
```
row(
  col_a(width=6),   # stacked return distribution histogram
  col_b(width=4),   # horizontal bar chart — volatility per tenor
  col_c(width=2)    # narrative card
)
```

**Narrative:**
- Small card (col_c): "Return distributions stacked by tenor reveal how volatility decays across the term structure. Front months carry the most uncertainty; back months are anchored by slower-moving supply/demand fundamentals."

**Visualization:**
- col_a — Overlaid density chart:
  - One density curve per tenor, overlaid (not stacked/cascading)
  - Back tenors rendered first (front of chart visually), more translucent; front month tenors rendered last (back of chart visually), more opaque — layering order ensures front months are most visible
  - Tenor range filter: `sliderInput` dynamically generated from available tenors for the selected ticker (M1–M18 for HO/RB, M1–M36 for CL/BRN/NG, M1–M12 for HTT); controls this chart only
  - X-axis clipped to 1st/99th percentile across all selected tenors before computing densities — removes extreme outliers without distorting the bulk of the distribution
  - Colors via turbo color scale mapped by tenor
- col_b — Horizontal bar chart — volatility per tenor:
  - One bar per tenor; X-axis: annualised volatility (sd of returns × sqrt(252)); Y-axis: tenor
  - Always shows all available tenors for the selected ticker — not filtered by the slider
  - Colors via turbo — same scale as density chart for visual consistency
  - Computed from the same returns data as the density chart; no additional data work
- **HTT handling:** HTT is a spread and can take negative values — log returns are meaningless; use weekly first differences (ΔP) instead; x-axis label updates to "Level Difference" instead of "Log Return" when HTT is selected; this applies to both the density chart and the volatility bar chart; the correlation heatmap (Row 2) must apply the same transformation for HTT — never compute correlations on log returns of a spread
- Data: log returns (or level differences for HTT) computed from `dflong` for all tenors of selected ticker

---

### Row 2 — Correlation Matrix Heatmap

**Layout:**
```
row(
  col_a(width=6),   # narrative card
  col_b(width=6)    # correlation heatmap
)
```

**Narrative:**
- High correlation between front tenors reflects parallel shifts dominating the curve; correlation decay toward the back indicates slope and curvature dynamics emerging — the covariance structure that PCA decomposes on the Forward Curves page
- Seasonality is visible in the matrix for NG and RB — tenors that span different demand seasons (e.g. summer vs. winter) decorrelate from each other, reflecting structurally different price drivers across the curve
- HTT shows a particularly sharp front vs. back month decorrelation — front tenors are driven by real-time pipeline and storage dynamics at Cushing, while back tenors are anchored by longer-term structural expectations; the two ends of the curve respond to different information sets
- Crude (CL, BRN) tends to show a matrix that is predominantly one colour — front month price changes propagate across the entire curve; correlation decays slightly toward the back but remains high throughout, reflecting that crude supply shocks reprice the whole forward curve, not just the front

**Visualization:**
- Normalized covariance matrix (correlation matrix) — tenors on both axes; Spectral color scale, reversed, [−1, 1]
- Symmetric heatmap with diagonal = 1
- Ticker selector; static beyond ticker selection
- **HTT handling:** `compute_returns` detects negative values and automatically uses level differences (ΔP) instead of log returns for HTT; correlation matrix consumes `compute_returns` output directly — correct transformation applied at source, no per-chart logic needed
- Data: output of `compute_returns` for selected ticker; `cor()` on returns matrix

---

### Row 3 — Rolling Realised Volatility

**Layout:**
```
row(
  col_a(width=6),   # narrative card
  col_b(width=6)    # rolling volatility chart
)
```

**Narrative:**
- "Rolling realised volatility surfaces the episodic nature of commodity risk. Extended calm periods are punctuated by sharp spikes driven by supply shocks, geopolitical events, and demand collapses. The events marked here are a curated shortlist of the most significant moves in the data."
- "Volatility spikes when uncertainty around supply and demand is high — markets reprice rapidly when the outlook becomes unclear. Importantly, these spikes tend to be sharp and short-lived: the largest vol readings typically occur at the onset of an event, as the market digests the shock, not over its full duration. Once a new supply/demand equilibrium is priced in, volatility subsides even if the underlying event is still unfolding."

**Visualization:**
- Rolling realised volatility line over time — annualised; 21-day window (default, fixed)
- Ticker selector + tenor selector (M1, M2, … dynamically generated from available tenors for selected ticker)
- Event markers: plotly custom symbols at (date, vol_value); hover label names the event; always shown for all tickers when the date falls within the selected ticker/tenor's available date range — silently omitted if outside range; three locked events:
  - 2014-03-03 — "Crimea Annexation" (Brent +2.2% in one session on Russia's military move into Crimea)
  - 2020-03-09 — "COVID-19 / Oil Price War" (oil -20%+ in one day; Saudi Arabia flooded market after Russia rejected OPEC cuts)
  - 2022-03-07 — "Russia-Ukraine Invasion" (WTI $133, Brent $139 — highest since 2008)
- **HTT handling:** `compute_returns` detects negative values and automatically uses level differences (ΔP) instead of log returns for HTT; all charts in this page consume `compute_returns` output — no per-chart transformation logic needed; x-axis/y-axis labels should update to reflect "Level Difference" units when HTT is selected
- Data: output of `compute_returns` for selected ticker + tenor; rolling sd × sqrt(252) for annualised vol

---

## Phase 3 — Market Dynamics Page

### Modules

| Module | Role |
|---|---|
| `mod_md_crude` | Entire Crude group view — 4 rows; reads `dflong` + `RTL::cushing` + EIA production/inputs data |
| `mod_md_refined` | Entire Refined Products group view — 3 rows; reads `dflong` + EIA data |
| `mod_md_ng` | Entire Natural Gas group view — 4 rows; reads `dflong` + EIA storage + EIA-923 coal generation + EIA LNG exports |
| `mod_md_eia923` | Analysis module — lazy loads EIA-923 coal generation data on first NG group click; writes `r$eia923_coal` |

---

### Crude Group

#### Row 1 — Crude Benchmarks & Spreads

**Narrative (col_b, width=4):**
- Stats card: value at most recent available date ($/bbl for flat price; spread level in $/bbl for spreads), YoY change, percentile vs. full history — updates reactively with selection
- Narrative card:
  - Brent crude is the global benchmark, underpinning roughly two-thirds of international oil contracts. It is physically based on the BFOET basket (Brent, Forties, Oseberg, Ekofisk, Troll); US Midland WTI was added to the Dated Brent basket in 2023.
  - WTI is the US benchmark, with its delivery point at Cushing, Oklahoma — a landlocked pipeline hub. Its location limits export optionality; crude stranded at Cushing must find a domestic buyer or wait for pipeline capacity to move it south.
  - Houston sits on the Gulf Coast with direct access to export terminals and the largest refinery complex in North America. This gives Houston-delivered crude a structural premium over Cushing; Houston prices are reported by Argus. The HTT spread (Houston − Cushing) directly measures this location differential.
  - The Brent−WTI spread reflects the global vs. landlocked premium — Brent typically trades at a premium, narrowing or inverting when US export infrastructure is unconstrained and Cushing inventory draws.

**Visualization (col_a, width=8):**
- `shinyWidgets::radioGroupButtons()`: Brent−WTI Spread (default) | WTI | Brent | HTT Spread (Houston−Cushing)
- Single line chart over full available history for selected series; Y-axis: $/bbl
- Event markers: same three locked events (2014-03-03, 2020-03-09, 2022-03-07); silently omitted if date falls outside selected series' available range
- Data: BRN01, CL01, HTT01 from `dflong`; Brent−WTI spread computed as BRN01 − CL01

---

#### Row 2 — Spread vs. Cushing WoW Change

**Narrative (col_a, width=6):**
- Static text: when Brent premium widens, US crude becomes cheap relative to international markets; export arbitrage opens; crude flows from Cushing toward Houston; shows up as Cushing draws; storage is the real-time supply/demand balance — production is sticky, storage is where the signal surfaces first; draws larger than expected push prices up, builds push prices down — the weekly EIA inventory report is the primary data release traders watch to gauge this balance

**Visualization (col_b, width=6):**
- Dual-series chart: Brent−WTI spread (line, left axis) vs. Cushing WoW inventory change (bars, right axis)
- Shared x-axis (date); spread plotted at daily frequency; Cushing WoW bars sit at their Wednesday EIA report date — mixed frequency on shared axis
- Spread line color: royal blue / lapis (`#4169E1`)
- Bar colors: draws (negative WoW change) = green; builds (positive WoW change) = red
- Right Y-axis units: thousands of barrels (kb)
- Thesis: wider spread → export arbitrage → Cushing draws
- Non-reactive — fixed chart
- Data: BRN01−CL01 from `dflong`; Cushing WoW change derived from `RTL::cushing` (units: kb)

---

#### Row 3 — HTT Spread + Cushing WoW Change

**Narrative (col_b, width=6):**
- Static text: Houston serves international customers (export terminal, Gulf Coast); Cushing is a landlocked regional hub; HTT is a location differential (pipeline congestion, export optionality), not a quality differential — both legs are light sweet WTI-grade crude
- Below the text: static two-row HTML flow diagram rendered via `shiny::HTML()`:
  - Row 1 (green): Cushing Draws → Inventory pressure relieved → HTT spread compresses
  - Row 2 (red): Cushing Builds → Bottleneck at hub → HTT spread widens
  - Styled boxes connected by arrows; color matches chart bar colors (draws = green, builds = red)

**Visualization (col_a, width=6):**
- plotly subplot with `shareX = TRUE`:
  - Top panel: HTT spread line over time; line color: deep orange (`#CC5500`)
  - Bottom panel: Cushing WoW inventory change bars (positive = build, negative = draw); draws = green, builds = red; units: kb
- Pan/zoom applies to both panels simultaneously
- Non-reactive — fixed chart
- Data: HTT01 from `dflong`; Cushing WoW from `RTL::cushing` (units: kb)

---

#### Row 4 — STL Decomposition: Production & Demand

**Narrative (full-width, below charts):**
- Static text: US crude production has a structural upward trend (shale-driven) with modest seasonal variation; refinery crude inputs are the demand proxy — EIA does not publish explicit demand; when production and demand cycles align the market is balanced; divergence shows up as inventory builds or draws (connects back to Rows 2 and 3); spring/fall refinery turnarounds suppress demand; summer driving season and winter heating sustain runs

**Visualization (col_a width=6, col_b width=6):**
- col_a: STL decomposition of US weekly field production of crude oil — trend, seasonal, remainder panels stacked vertically via `stats::stl()`
- col_b: STL decomposition of US weekly refinery crude inputs (demand proxy) — same treatment
- STL parameters: `frequency = 52` (annual seasonality on weekly data), `s.window = "periodic"`
- Both non-reactive — fixed charts
- Data: `r$eia_crude_prod` (production, thousand bbl/day); `r$eia_crude_inputs` (refinery inputs, thousand bbl/day); both loaded from `inst/extdata/` at startup; filter both series to Jan 2008 – Dec 2025 before passing to `stl()`

---

### Refined Products Group

#### Row 1 — Seasonal Demand Patterns

**Layout:**
```
row(
  col(width=2),    # empty left margin
  col_a(width=6),  # STL charts
  col_b(width=4)   # narrative
)
```

**Narrative (col_b, width=4):**
- **HO:** winter heating demand peaks December–February; northeast US residential demand drives prices higher through fall in anticipation
- **RB:** summer driving season peaks Memorial Day through Labor Day; EPA summer blend specs are more expensive to produce; prices typically peak April–May ahead of the season
- Both products come from the same crude barrel — refiners adjust the distillation cut to favour distillates (HO, diesel) ahead of winter or lighter products (RB) ahead of summer; inventory is built in advance of each seasonal peak
- The forward curve embeds these premia directly — winter HO contracts trade at a premium to summer months, summer RB contracts at a premium to winter months; hedgers who understand the cycle can time curve entries before the seasonal premium builds rather than after it is already priced in

**Visualization (col_a, width=6):**
- Two STL decompositions stacked vertically via plotly subplots:
  - Top: STL decomposition of HO front month (HO01) price
  - Bottom: STL decomposition of RB front month (RB01) price
- STL parameters: `frequency = 52` (annual seasonality on weekly data), `s.window = "periodic"`
- Both via `stats::stl()`, non-reactive, fixed
- Data: HO01 and RB01 from `dflong`; aggregate to weekly (Friday close) before passing to `stl()`

---

#### Row 2 — Crack Spread

**Narrative (col_a, width=4):**
- Stats card: current spread (most recent value of selected crack spread), YoY change, percentile vs. full history — updates reactively with crack spread selection
- Narrative card: crack spreads represent the refinery gross margin — the difference between the value of refined products and the cost of crude input; wide cracks = fat margins, refiners incentivised to run hard; narrow or negative cracks = refiners squeezed, run rates cut; crack spread dynamics drive crude demand
- Refiners are naturally long the crack spread — wider cracks mean cheaper crude inputs relative to product outputs, expanding margins; when cracks are wide, refiners lock in that margin by selling the crack: short refined product futures (HO/RB), long crude futures (CL)
- Heating oil and diesel consumers are naturally short the crack — rising product prices increase their cost of supply; they offset that exposure by going long HO or RB futures to lock in prices

**Crack spread formulas (all results in $/bbl):**
- HO crack = `HO01 × 42 − CL01`
- RB crack = `RB01 × 42 − CL01`
- 3-2-1 crack = `(2 × RB01 × 42 + 1 × HO01 × 42 − 3 × CL01) / 3`

**Visualization (col_b, width=8):**
- Front month crack spread over time with event markers
- Crack spread selector: `shinyWidgets::radioGroupButtons()` — HO crack (default) | RB crack | 3-2-1; styled pill buttons, active state highlighted
- Spread line color: burgundy (`#800020`)
- Y-axis label: $/bbl
- Event markers (three locked events — silently omit if outside available date range):
  - 2017-08-25 — "Hurricane Harvey" (Gulf Coast refinery outages; ~25% of US capacity offline; RB crack spiked)
  - 2020-03-09 — "COVID-19 / Oil Price War" (demand destruction; RB crack went negative)
  - 2022-03-07 — "Russia-Ukraine Invasion" (Russia ~50% of EU diesel supply; HO crack hit record highs)
- Stats card updates reactively with selected spread
- Data: HO01, RB01, CL01 from `dflong`; inner join on overlapping dates before computing any spread

---

#### Row 3 — Product Inventories vs. 5-Year Average

**Layout:**
```
row(
  col_a(width=6),   # chart
  col_b(width=6)    # narrative
)
```

**Narrative (col_b, width=6):**
- EIA weekly product inventory levels are the primary supply/demand balance signal for refined products; the weekly report is one of the most market-moving data releases in energy
- Below the 5-year average signals tighter supply — prices and crack spreads are bid up; above average signals oversupply — margins compress and prices soften
- Distillate inventories draw sharply in winter as heating demand peaks; gasoline inventories tighten ahead of summer driving season

**Visualization (col_a, width=6):**
- Product selector: `shinyWidgets::radioGroupButtons()` — Distillate (HO) (default) | Gasoline (RB)
- plotly subplot with `shareX = TRUE` and date range slider:
  - Top panel: three lines — front month price (HO01 or RB01, left axis), EIA weekly stocks (right axis), 5-year average stocks (right axis)
  - Bottom panel: surplus/deficit bars — weekly stocks minus 5-year average; positive = above average (bearish), negative = below average (bullish); above average = red, below average = green
  - 5-year average: calendar average (average stocks for each week-of-year across prior 5 years — EIA standard methodology); exclude the first 5 years of data entirely — do not compute 5-year average for that window
- Date range slider controls both panels simultaneously
- `shinycssloaders::withSpinner()` wraps chart during initial data load
- Reactive — selector and slider drive chart
- Data: HO01/RB01 from `dflong`; distillate stocks from `r$eia_distillate_stocks` (thousand barrels); gasoline stocks from `r$eia_gasoline_stocks` (thousand barrels); both loaded from `inst/extdata/` at startup

---

### Natural Gas Group

#### Row 1 — Storage Seasonality

**Layout:**
```
row(
  col(width=3),    # empty left margin
  col(width=6),    # chart
  col(width=3)     # empty right margin
)
row(
  col(width=2),    # empty left margin
  col(width=8),    # narrative
  col(width=2)     # empty right margin
)
```

**Narrative (col width=8, centered below chart):**
- Static text: Natural gas demand is highly seasonal and weather-driven. Summer months are injection season — demand is low, production flows into storage in preparation for winter. Winter flips the dynamic: residential and commercial heating demand draws on those reserves, tightening supply and pushing prices higher. Cold snaps amplify this further — extreme temperatures not only spike heating demand but can cause well freeze-offs and pipeline outages, simultaneously constraining supply at the moment demand peaks. The result is that winter price spikes in natural gas can be sharp and sudden, driven as much by weather as by fundamentals.

**Visualization (col width=6, centered):**
- Seasonal overlay chart — one line per year; constrained to Jan 2008 – Dec 2025; partial years plotted up to the most recent available week within that range
- X-axis: Jan–Dec; Y-axis: US natural gas working underground storage (Bcf)
- Magma color scale by year — earlier years lighter, recent years darker
- Non-reactive — fixed chart
- Data: `r$eia_ng_storage` — Lower 48 States natural gas working underground storage, weekly, Bcf; loaded from `inst/extdata/` at startup

---

#### Row 2 — Storage vs. Price

**Layout:**
```
row(class = "mt-3",
  col_a(width=6),   # narrative
  col_b(width=6)    # chart
)
```

**Narrative (col_a, width=6):**
- Static text: storage is the heartbeat of the NG market; the 5-year average is the universal benchmark — above average means oversupply, prices suppressed; below average means tightness, prices spike; the weekly EIA storage report is one of the most market-moving data releases in energy; relevant for hedgers deciding when to lock in gas supply or sales

**Visualization (col_b, width=6):**
- plotly subplot with `shareX = TRUE` and date range slider:
  - Top panel: three series — NG front month price (NG01, left axis $/MMBtu, daily frequency, color `#210000`); actual weekly storage (right axis Bcf, sits at Thursday EIA report date, color `#800020` burgundy); 5-year average storage (right axis Bcf, sits at Thursday EIA report date, color `#4169E1` royal blue); raw values, no normalisation
  - Bottom panel: storage surplus/deficit bars — actual minus 5-year average (Bcf); positive = above average (bearish) = red; negative = below average (bullish) = green; bars sit at Thursday EIA report dates
  - 5-year average computed as calendar average (average storage for each week-of-year across the prior 5 years — EIA standard methodology)
- Date range slider controls both panels simultaneously; default = full available range; minimum selectable range = 5 weeks enforced via server-side validation (snaps back to 5-week minimum if user selects less)
- Reactive — slider input drives chart; self-contained within NG module
- `shinycssloaders::withSpinner()` wraps chart output during initial data load
- Data: NG01 from `dflong`; `r$eia_ng_storage` — Lower 48 States natural gas working underground storage, weekly, Bcf; loaded from `inst/extdata/` at startup

---

#### Row 3 — Fuel Switching (Coal-to-Gas)
**Execution note:** This row depends on EIA-923 annual files (2008–2024) in `inst/extdata/`. If those files are not available when Phase 3 executes, stub this row and implement retroactively once data is in hand — do not block Phase 3 completion on it.

**Narrative (col_b, width=4):**
- Static text: when NG price rises, utilities in coal-heavy regions switch back to coal, softening gas demand and acting as a price cap; the cap is not a fixed number — it is geographically distributed; South and Midwest retain significant coal capacity (KY, WV, TX, IL, IN, OH); Northeast has largely retired coal so the switching mechanism is weaker; the map shows geographic distribution of coal dependency

**Visualization (col_a, width=8):**
- Top-level view toggle: `bslib::input_switch()` — off = Price vs. Generation, on = State Coal Share Map

- **View 1 — HH Price vs. Coal Generation:**
  - Dual axis: NG front month price (monthly average of NG01, left axis $/MMBtu, line color `#db243a`, rendered last so it sits in front of bars); coal-based electricity generation (right axis, raw units from EIA-923 — GWh or MWh confirmed at implementation, bars single viridis blue color, rendered first)
  - Region selector: `selectInput()` — Overall | Northeast | Midwest | South | West; reactive — selection filters coal generation bars; NG price line unchanged
  - Date range slider (two handles); default = 5-year window ending at most recent available month; minimum range = 5 weeks enforced via server-side validation
  - Monthly frequency throughout
  - Data: NG price from `dflong` (NG01, averaged to monthly); coal generation from `r$eia923_coal`; lazy loaded on first NG group click; `shinycssloaders::withSpinner()` during load

- **View 2 — State Coal Share Map:**
  - US choropleth map via `plotly::plot_ly(type = "choropleth")` — state-level coal usage for selected month
  - Viridis color scale mapped to raw coal usage values (data-driven min/max)
  - Single month picker (`sliderInput`, one handle) — steps through available months; default = most recent available month; independent of View 1 date range slider
  - Hover tooltip: state name, coal usage (native units), mm-yyyy
  - Uses same state-level data from `r$eia923_coal` — no additional data calls

- Data loading: lazy load on first NG group click; write to `r$eia923_coal`; `shinycssloaders::withSpinner()` during load
- Data sources: NG price from `dflong`; coal generation from EIA-923 annual files in `inst/extdata/` — all 18 annual files (2008–2025) confirmed present; `mod_md_eia923` reads and binds all annual files at load time via a shared helper function

**EIA-923 file structure (verified against actual files):**
- Sheet: `Page 1 Generation and Fuel Data` — consistent across all years
- Skip rows: **`skip = 6` for 2008–2010; `skip = 5` for 2011–2025** — the three earliest files have an extra header row; using the wrong skip produces blank column names
- File extensions: `.xls`/`.XLS` for 2008–2010; `.xlsx` for 2011–2025 — `readxl::read_excel()` handles both without switching functions
- Column positions are **identical across all years** once the correct skip is applied; use positional access only — column names vary across years (e.g. `NETGEN_JAN` vs `Netgen_Jan` vs `Netgen\nJanuary`) and must not be relied upon:
  - Col 7 = Plant State
  - Col 8 = Census Region (10 division codes)
  - Col 15 = Reported Fuel Type Code
  - Cols 80–91 = Netgen January through Netgen December (MWh)
  - Col 97 = Year
- Read with `col_types = "text"` to prevent type coercion failures on mixed columns; convert Netgen cols to numeric after read; `"."` values in Netgen columns are missing data — treat as NA, do not coerce to 0

**Loading helper (`read_eia923_file`)** — single function used by `mod_md_eia923`:
```r
# Reads one EIA-923 annual file and returns a tidy tibble with standardised column names.
# Handles skip differences between 2008-2010 (skip=6) and 2011+ (skip=5).
# col_types="text" avoids coercion failures on mixed-format columns.
# Example: read_eia923_file("inst/extdata/EIA923_Schedules_2_3_4_5_M_12_2020_Final_Revision.xlsx")
read_eia923_file <- function(path) {
  yr <- as.integer(stringr::str_extract(basename(path), "\\d{4}"))
  sk <- if (yr <= 2010) 6L else 5L
  df <- readxl::read_excel(path,
                            sheet = "Page 1 Generation and Fuel Data",
                            skip = sk,
                            col_types = "text")
  df <- df[, c(7, 8, 15, 80:91, 97)]
  names(df) <- c("plant_state", "census_region", "fuel_type_code",
                 "netgen_jan", "netgen_feb", "netgen_mar", "netgen_apr",
                 "netgen_may", "netgen_jun", "netgen_jul", "netgen_aug",
                 "netgen_sep", "netgen_oct", "netgen_nov", "netgen_dec", "year")
  # Convert Netgen cols to numeric; "." = NA (EIA missing data marker)
  netgen_cols <- paste0("netgen_", c("jan","feb","mar","apr","may","jun",
                                     "jul","aug","sep","oct","nov","dec"))
  df[netgen_cols] <- lapply(df[netgen_cols], function(x) {
    x[x == "."] <- NA
    as.numeric(x)
  })
  df$year <- as.integer(df$year)
  df
}
```

- Coal fuel type filter: `fuel_type_code %in% c("ANT", "BIT", "LIG", "RC", "SUB", "WC")`
- Census division → region mapping (hardcoded in module):
  - Northeast: NEW, MAT
  - Midwest: ENC, WNC
  - South: SAT, ESC, WSC
  - West: MTN, PACC, PACN
- Aggregation: filter to coal types → pivot `netgen_*` cols to long (month, MWh) → group by Census Region + year-month (View 1) or Plant State + year-month (View 2) → sum MWh, removing NAs
- Units: MWh throughout

---

#### Row 4 — LNG Exports & Price Floor

**Layout:**
```
row(
  col_a(width=4),   # narrative
  col_b(width=8)    # chart
)
```

**Narrative (col_a, width=4):**
- Static text: before 2016 the US gas market was largely isolated — prices determined by domestic supply and demand alone; Sabine Pass (2016) structurally changed this; Henry Hub now has a global floor linked to international LNG prices; when domestic prices fall far enough below international levels, export demand absorbs the surplus; hedgers can no longer treat Henry Hub as a purely domestic market

**Visualization (col_b, width=8):**
- Two series over time: Henry Hub monthly average price (line, left axis, color `#db243a`); US LNG export volumes (bars, right axis, single viridis blue, same as Row 3 coal bars)
- Vertical dashed line at 2016-02-24 (Sabine Pass first export) via plotly `shapes`; color `#F87217`; text label "Sabine Pass First Export" via plotly `annotations`
- Non-reactive — fixed chart
- Data: NG price from `dflong` (NG01, averaged to monthly); LNG export volumes from `r$eia_lng_exports` (MMcf/month); both aggregated to monthly; inner join on overlapping dates

---

## Phase 4 — Cross-Market Relationships Page

### Modules

| Module | Role |
|---|---|
| `mod_cm_rolling_corr` | Rolling correlation with vol regime shading (Panel 1); owns two-ticker selector |
| `mod_cm_var` | VAR + IRF display (Panel 2); reads `r$var_results` written by `mod_var` in Phase 0 |

---

### Row 1 — Rolling Correlation with Vol Regime Shading

**Layout:**
```
row(
  col(width=2),    # empty left margin
  col(width=8),    # chart
  col(width=2)     # empty right margin
)
row(
  col(width=2),    # empty left margin
  col(width=8),    # narrative
  col(width=2)     # empty right margin
)
```

**Narrative (col width=8, centered below chart):**
- Static text: rolling correlation reveals whether cross-market relationships are stable or regime-dependent; vol regime shading tests the assumption directly — if the correlation line behaves differently inside high-vol windows than outside, the relationship strengthens or breaks down under stress; this has direct implications for diversification and cross-market hedges

**Visualization (col width=8, centered):**
- Two-ticker selector (limited to two for readability)
- Rolling window slider: default = 90 days; range = 21–252 days; step = 1
- Rolling correlation line between front month returns of the two selected tickers; line color `#210000` (near-black, slight red tint)
- Background shaded by volatility regime — high-vol periods shaded red at low opacity (~20%); threshold: rolling vol above 80th percentile = high vol regime; data-driven, not manually tagged
- Reactive to ticker selection and window slider
- Data: M1 log returns from `dflong` for selected tickers

---

### Row 2 — VAR + IRF

**Layout:**
```
row(class = "mt-3",
  col_a(width=8),   # chart
  col_b(width=4)    # narrative
)
```

**Narrative (col_b, width=4):**
- Static text: VAR estimates predictive relationships between all markets simultaneously using historical return data; IRFs trace how a shock in one market propagates through the others over subsequent weeks; confidence bands are the signal — when the band straddles zero, no meaningful relationship is distinguishable from noise
- Caveats surfaced explicitly:
  1. VAR is calibrated on historical return innovations — unprecedented shocks or structural regime changes mean historical relationships may not hold forward
  2. Cholesky ordering (BRN→CL→HO→RB→HTT→NG) reflects typical causal flow; tickers above the shock ticker show zero contemporaneous response by construction — their response appears from Week 1 onward; this is standard VAR practice

**Visualization (col_a, width=8):**
- Shock ticker selector (any of the 6 tickers)
- Lag selection displayed as inline text below selector — e.g. "Model estimated with 4 lags (BIC)"
- One IRF chart: all 5 responding tickers overlaid as separate lines
- X-axis: weeks following shock (horizon 12 weeks); Y-axis: scaled response (standard deviation units)
- Per-ticker viridis colors — each responding ticker assigned a distinct viridis color; same color applied to both response line and CI ribbon
- CI ribbon: filled, 15% opacity, same viridis color as response line
- Horizontal reference line at y = 0
- Data: `r$var_results` written at startup by `mod_var`

**VAR specification (locked):**
- Weekly end-of-week (Friday close) returns from `dflong`; inner join on overlapping dates across all 6 tickers
- Log returns for CL, BRN, NG, HO, RB; weekly first differences (ΔP) for HTT (spread, can be negative)
- All series standardised to z-scores before estimation — IRFs interpreted as response to 1 SD shock
- Cholesky ordering: BRN → CL → HO → RB → HTT → NG
- Lag selection: AIC, BIC, HQ, FPE simultaneously via `vars` package; select where multiple criteria agree
- IRF horizon: 12 weeks

---

## Phase 5 — Hedging Analytics Page

### Modules

| Module | Role |
|---|---|
| `mod_hedge_swap` | CMA swap pricer (Row 1); owns ticker + period + direction inputs |
| `mod_hedge_roll` | Rolling hedge simulator (Row 2); owns ticker + reference date + direction inputs; generates cascading table |
| `mod_hedge_options` | Options pricer + zero cost collar (Row 3); owns all inputs; reads `r$yield_curves` |
| `mod_hedge_term` | Hedge ratio dynamics across term structure (Row 4); reads `r$kalman_betas`; owns ticker + delta inputs |
| `mod_hedge_cross` | Cross-market Kalman beta matrix (Row 5); reads `r$kalman_cross_betas`; owns date picker |

---

### Row 1 — CMA Swap Pricer

**Layout:**
```
row(
  col_a(width=6),   # chart
  col_b(width=6)    # flat swap stat + inputs + narrative (stacked vertically)
)
```

**col_b (top to bottom):**
- Flat swap price stat card (most prominent — sits at top of col_b)
- Inputs:
  - Instrument selector: CL, BRN, NG, HO, RB, HTT, WTI/Brent spread (BRN−CL), HO/RB spread (HO×42−RB×42)
  - Reference date picker (`dateInput`): default = most recent available date in `dflong` for selected instrument; range constrained to available dates for that instrument; drives both period selector and curve used for pricing
  - Period selector: Bal[year], Cal[year+1]…Cal[year+3] — dynamically generated from reference date; only periods fully covered by available tenors on that date are shown; updates reactively when date or instrument changes; snaps to next valid period if current selection becomes unavailable
  - Direction toggle: Producer / Consumer
- Narrative (static text):
  - A commodity swap fixes a flat price against the calendar month average (CMA) of daily settlement prices over the swap period — not the current front month price.
  - The shading reveals the embedded financing structure. Months where the forward sits above the swap line represent the bank subsidising that leg — effectively an implied loan built into the structure. The bank prices this cost of carry into the flat swap rate upfront.
  - In contango, fixing via swap costs more than rolling month-to-month — the carry premium is embedded in the flat price. In backwardation, fixing captures the discount — the swap is cheaper than rolling. The chart makes this trade-off concrete for any instrument and period.

**col_a — Chart:**
- Monthly forward curve prices (line, color `#210000`) + horizontal swap price line (color `#F87217`) + shaded areas between the two at 25% opacity
  - Producer hedge: above-swap = green, below-swap = red
  - Consumer hedge: above-swap = red, below-swap = green
- Pricing: `RTL::swapCOM`; spread instruments compute CMA of the spread directly; HO/RB ×42 conversion applied automatically
- Period generation logic: filter `dflong` to selected instrument on selected reference date → map tenors to delivery months via `RTL::expiry_table` → validate each candidate period against covered months vector → drop any period missing any month

---

### Row 2 — Rolling Hedge Simulator

**Layout:**
```
row(
  col_a(width=6),   # narrative
  col_b(width=6)    # table
)
```

**Narrative (col_a, above table):**
- Producer: short hedge via rolling front-month futures; in backwardation each roll earns the carry — effective hedge price improves relative to a flat swap; in contango each roll costs; frames when a rolling strategy is preferable to locking in a swap
- Consumer: long hedge via rolling; backwardation benefits the consumer (buys next month cheaper each roll); contango erodes the hedge; frames the decision between rolling and fixing via swap

**Visualization (col_b):**
- Inputs: ticker selector (CL, BRN, NG, HO, RB, HTT), reference date picker, direction toggle (Producer / Consumer)
- Reference date constrained to dates at least 1 year before the last available date for the selected ticker in `dflong`
- Cascading table — 12 columns (one per roll), rows:

| Row | Content |
|---|---|
| Contract | Contract name + delivery month for each roll |
| Entry Date | Date position is entered |
| Entry Price | M1 price from `dflong` on entry date |
| Exit Date | Contract expiry date |
| Exit Price | M1 price from `dflong` on exit date (cascade: prior exit = next entry) |
| Roll Yield % | `(Entry − Exit) / Entry × 100` — positive in backwardation, negative in contango; same formula regardless of direction |
| Monthly P&L | Producer (short): `Entry − Exit`; Consumer (long): `Exit − Entry`; native price units |
| Cumulative P&L | Running total across all rolls |

- **Roll logic:**
  - Entry into roll 1: reference date; entry price = M1 price on reference date
  - Exit from roll N / entry into roll N+1: contract expiry date from `RTL::expiry_table`; price = M1 price on that date from `dflong`
  - If no price exists on exact expiry date (holiday/gap): use prior available business day
  - HTT has no standard futures expiry — use CL expiry dates as proxy (`tick.prefix == "CL"` in `RTL::expiry_table`); both HTT legs are WTI-grade crude
  - BRN maps to `tick.prefix == "LCO"` in `RTL::expiry_table` — apply this mapping at lookup; dflong uses `BRN` as the label
- P&L cell color: green = gain, red = loss for selected direction; applied via `reactable` conditional styling
- Units: $/bbl (CL, BRN, HTT), $/MMBtu (NG), $/gal (HO, RB); unit label in table header
- Expiry dates: `RTL::expiry_table` — bundled in RTL, no API or download needed; covers 2003–2029; columns used: `tick.prefix`, `Last.Trade`

---

### Row 3 — Options Pricer & Zero Cost Collar

**Layout:**
```
row(
  col_a(width=3),   # inputs panel
  col_b(width=9)    # charts area
)
```

**col_a — Inputs panel (top to bottom):**
- All inputs pre-filled with valid defaults on load; locked via `shinyjs::disable()` in view mode — user sees charts immediately
- Ticker selector: CL (default), BRN, NG, HO, RB — HTT excluded (Black-76 invalid for spread instruments)
- Direction toggle: Producer (default) / Consumer
- Implied volatility slider: 0.01–1.00, step 0.01, default 0.30
- Time to maturity (`radioButtons`): 1 month | 3 months (default) | 6 months; T = months/12 years; drives reference date constraint — rendered before reference date in UI
- Reference date (`dateInput`): constrained to dates where the nearest futures expiry from `RTL::expiry_table` at ≥ T months out falls ≤ `last_available_date` in `dflong` for selected ticker; constraint updates reactively when T or ticker changes; default = most recent valid date given default T = 3 months; underlying = M1 on that date
- Collar strike (numeric input): default = M1 price on reference date × 0.95; label updates with direction — producer: "Floor Strike (Put to Buy)"; consumer: "Cap Strike (Call to Buy)"
- **Edit / Apply button:** single button that toggles between modes
  - View mode → "Edit Inputs": click unlocks all inputs, greys out charts with "Click Apply to update" banner, disables View 2 toggle
  - Edit mode → "Apply": click locks all inputs, re-renders charts, re-evaluates View 2 toggle constraint
- **View 2 toggle** (`bslib::input_switch()`): sits below Edit/Apply button; disabled during edit mode and when `reference_date + T months > last_available_date`; tooltip on disabled state explains requirement

**col_b — View 1 (switch off, default):**
- Top: BS Pricing Curve
  - X: strike (~100 evenly spaced points); Y: option premium
  - Two curves: put (color `#4169E1`) + call (color `#db243a`) across full strike range
  - Strike range: 0–2× M1 underlying for CL/BRN/HO/RB/HTT; 0–3× for NG
  - Horizontal dashed line at premium of user's collar leg (color `#F87217`); vertical dashed lines at both zero-cost collar strikes (color `#F87217`)
- Bottom: Payoff Diagram at Expiry
  - X: underlying price at expiry (same strike range); Y: net P&L
  - Two lines: unhedged (color `#343d46`) + collar payoff (kinked — flat beyond both collar strikes, color `#F87217`)
  - Unhedged line: producer = `S_T − S_0`; consumer = `S_0 − S_T`; where `S_0` = M1 price on reference date
  - Collar payoff: producer = `max(K_floor, min(K_cap, S_T)) − S_0`; consumer = `S_0 − max(K_floor, min(K_cap, S_T))`
  - X-axis range fixed to strike grid (`[0, 2×S_0]` for CL/BRN/HO/RB; `[0, 3×S_0]` for NG); Y-axis range fixed to `[min_payoff − 0.1×S_0, max_payoff + 0.1×S_0]` computed from collar payoff endpoints — suppresses plotly auto-scaling

**col_b — View 2 (switch on, replaces View 1):**
- `expiry_date` = nearest futures contract expiry from `RTL::expiry_table` for selected ticker at ≥ T months after `reference_date`; BRN maps to `tick.prefix == "LCO"`; must be ≤ `last_available_date` in `dflong` (guaranteed by reference date constraint above)
- Dual-axis line chart — X: date from `reference_date` to `expiry_date`
- Left Y-axis: M1 underlying price (native units per ticker); line color `#210000`
- Right Y-axis: collar MTM value in $; line color `#db243a`; axis label "Collar P&L ($)"
- **Computation at each date t in `[reference_date, expiry_date]`:**
  - `S_t` = M1 price from `dflong` on date t; if no price on exact date use prior available date
  - `T_remaining` = `(expiry_date − t)` in years; at final date substitute intrinsic value instead of passing T=0 to BS formula
  - `r_t` = linear interpolation of `r$yield_curves` at date t and T_remaining; forward-fill FRED missing values; FRED data downloaded to current date — stale rate propagation is not a concern
  - σ = user-supplied (fixed throughout — isolates price movement and time decay from vol changes)
  - Long leg value = `RTL::GBSOption(b=0, S=S_t, X=K_long, T=T_remaining, r=r_t, sigma=σ)`
  - Short leg value = `RTL::GBSOption(b=0, S=S_t, X=K_short, T=T_remaining, r=r_t, sigma=σ)`
  - Net collar value per option = long leg − short leg
  - Total collar P&L = 100 × contract_multiplier × net collar value per option
- **Contract multipliers:**

| Ticker | Multiplier |
|---|---|
| CL | 1,000 bbl/contract |
| BRN | 1,000 bbl/contract |
| HO | 42,000 gal/contract |
| RB | 42,000 gal/contract |
| NG | 10,000 MMBtu/contract |
| HTT | 1,000 bbl/contract (WTI-grade; uses CL multiplier) |

- At `reference_date`: collar P&L = 0 by construction (zero-cost collar)
- `shinycssloaders::withSpinner()` wraps View 2 chart output — loop over trading days involves repeated `GBSOption` calls and delay is perceptible

**Pricing (both views):**
- `RTL::GBSOption` with `b = 0` (futures options — Black-76)
- Risk-free rate: linear interpolation of `r$yield_curves` at selected date and T; FRED CMT tickers DGS1MO, DGS3MO, DGS6MO, DGS1, DGS2, DGS5, DGS10, DGS30; forward-fill FRED missing values; FRED data downloaded to current date — stale rate propagation is not a concern
- **Zero-cost collar strike solving:** evaluate `GBSOption` for the opposite leg across the full strike grid (~100 points, same vector used to render the pricing curve); zero-cost strike = `strike_grid[which.min(abs(opposite_premiums - user_leg_premium))]`; grid search over the existing price vector is sufficient — no root-finding required

**Narrative (static text, below charts):**
- Black-76 prices options on futures directly; the zero-cost collar is constructed by finding the strike on the opposite leg where the premium exactly offsets the chosen leg
- Producer collar: floor from put caps downside; call sold funds the put; upside capped
- Consumer collar: call bought caps cost; put sold funds the call; downside benefit surrendered
- View 2 shows the mark-to-market value of the 100-contract collar position over its life — worth zero at inception by construction; evolves as the underlying moves and time decays; sigma is held constant so the path isolates commodity price behaviour and theta decay from volatility changes

---

### Row 4 — Hedge Ratio Dynamics Across the Term Structure

**Layout:**
```
row(                                    # shared inputs
  col(width=6),   # ticker selector
  col(width=6)    # animation speed selector
)
row(
  col_a(width=6),   # top-left: static OLS beta curve
  col_b(width=6)    # top-right: animated Kalman beta curve
)
row(
  col_c(width=6),   # bottom-left: OLS narrative card
  col_d(width=6)    # bottom-right: Kalman narrative card
)
```

**Shared inputs (above chart rows):**
- Ticker selector: individual tickers only (CL, BRN, NG, HO, RB) — HTT excluded (spread instrument; log returns invalid for Kalman beta estimation)
- Animation speed (`radioButtons`): Slow | Medium (default) | Fast; maps to `animation_opts(frame = ...)` — 1000ms / 500ms / 250ms per frame; only mutates animation playback, no data recomputation

**col_a — Static OLS Beta Curve:**
- X: tenor (M2…Mn); Y: β relative to M1
- One dotted line with interactive points; horizontal reference line at β = 1.0 (color `#4169E1`)
- Hover on each point shows R² for that tenor pair
- Computed via `RTL::promptBeta` on full history for selected ticker; non-reactive beyond ticker change
- Color: `#210000`

**col_b — Animated Kalman Beta Curve:**
- Same axes as OLS chart; X: tenor (M2…Mn); Y: β relative to M1
- **Data structure for animation:** `r$kalman_betas` filtered to selected ticker; reduce to one snapshot per calendar month (last available trading day of each month); resulting data frame has columns `tenor`, `beta`, `r_squared`, `month_label`
- **X-axis stability:** fixed to the maximum set of tenors available for the selected ticker across full history; early frames where a tenor did not yet exist render that point as NA (gap in line) — prevents the curve from appearing to grow over time as back-month contracts were introduced
- **Plotly animation:** rendered via `plot_ly(frame = ~month_label)` + `animation_opts()` + `animation_slider()`; plotly handles play/pause button and frame scrubber natively — no custom JS required; `redraw = FALSE` in `animation_opts()` for smooth transitions between frames
- OLS curve added as a second trace with `frame = NULL` so it remains static across all animation frames; rendered at 25% opacity, dotted line, same color as col_a OLS curve
- Date label shown via `animation_slider(currentvalue = list(prefix = "Date: "))` — updates automatically with frame
- Changing ticker or δ triggers a full `renderPlotly()` re-render (acceptable given pre-computation)

**col_c — OLS Narrative Card (static):**
- The beta curve shows structural decay: as the tenor mismatch between physical exposure and hedge instrument grows, β declines; a 1:1 hedge of a back-month exposure with front-month futures leaves residual basis risk proportional to the gap between β and 1.0; the OLS curve is the long-run average — use it as the baseline hedge ratio before checking how far current conditions have drifted

**col_d — Kalman Narrative Card (static):**
- At each point in history, this was the best available estimate of the hedge ratio given only data up to that date — no hindsight; the curve deforming over time reflects genuine regime shifts in the basis relationship; the relationship breaks down most visibly during supply shocks, storage dislocations, and structural shifts

**Data:**
- `r$kalman_betas`: pre-computed at startup by `mod_kalman_betas` at a fixed internal delta — not user-controllable; scalar Kalman filter on daily log returns for each within-ticker tenor pair (Mn vs M1) independently; causal (uses only data up to each date); written once, read here and in Row 5; verify at execution that `RTL::promptBeta` returns R² alongside betas — if not, compute manually from the same regression
- `RTL::promptBeta`: OLS betas computed reactively on ticker change for col_a only

---

### Row 5 — Cross-Market Kalman Beta Matrix

**Narrative (below table):**
- Asymmetry: β_CL→BRN ≠ β_BRN→CL — the hedge ratio depends on which side of the trade you're on; the table reads differently row-by-row vs. column-by-column
- HTT note: as a spread instrument, betas vs. flat price tickers will be small — near-zero cells are analytically meaningful, not missing data
- Connects to Row 4: moving the date picker to a stress period (2008, COVID, 2022) reveals how cross-market hedge ratios shift under pressure; the Kalman filter's time-varying property, established in Row 4, is directly applied here

**Visualization:**
- Inputs: single date picker; range constrained to dates present in `r$kalman_cross_betas` (not raw `dflong` — Kalman requires at least one prior observation, so its first valid date is later than `dflong`'s first date); defaults to most recent available date
- 6×6 reactable beta matrix:
  - Rows: exposure ticker (what you're hedging); columns: hedge instrument ticker (what you're hedging with)
  - Tickers: CL, BRN, NG, HO, RB, HTT (all M1 front month)
  - Each cell: Kalman filter β at selected date — numeric value displayed as text
  - Cell background: `RdBu` diverging scale centered at 0 — positive betas blue, negative betas red, white at zero; magnitude drives intensity; easy to swap at execution
  - Diagonal: greyed out (not a hedge relationship)
  - Hover tooltip on cell: R² for that pair at selected date
- Pre-computed: all 30 off-diagonal pairs via scalar Kalman filter on M1 daily returns; written to `r$kalman_cross_betas` at startup
- At runtime: slice `r$kalman_cross_betas` at selected date → table populates instantly; no recalculation
- Rendered via `reactable`

---

## Technical Debt (resolve before execution begins)

1. **HTT transformation in VAR** — HTT currently included using level differences while all other tickers use log returns; planning locks this as weekly first differences (ΔP) standardised to z-scores; apply consistently
2. **VAR lag cap** — daily data in MVP forced lag selection to 10, producing noisy IRFs; weekly data in final product should resolve this naturally; if consensus lag still exceeds 6, cap `lag.max` at 6 and document the decision
3. **Sparse ticker coverage** — forward curve comparison chart must filter to dates where all selected tickers have data; do not plot empty or partially-populated curves
