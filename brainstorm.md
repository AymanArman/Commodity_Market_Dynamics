# Brainstorm — Commodity Market Dynamics

**What:** A Golem app — an interactive primer on commodity market dynamics
**Who:** Risk managers and portfolio managers unfamiliar with the space

---

## Educational Design Philosophy

- Each page serves as an educational guide — not a tool for a seasoned professional
- Concepts progress from simple to complex both **within each page** and **across pages**
- Page ordering reflects this: simpler concepts first, more statistically complex later
  1. Forward Curves
  2. Volatility
  3. Market Dynamics
  4. Cross-Market Relationships
  5. Hedging Analytics
- No definitions for basic concepts — assume financial literacy and preliminary stats knowledge
- Narrative text is **fixed** and written at a conceptual level — applicable across tickers and regimes, not specific to any one scenario
- Interactive/mutable charts **are** the worked examples — user explores and draws conclusions themselves

---

## Baseline Requirements (per assignment brief)

**Audience framing:** User is a Risk or Trading Manager with limited experience in the markets they now have accountability for. The app is the tool to tell the story — to themselves, their team, and stakeholders.

**Minimum analytical requirements (all must be covered):**
1. Behavior of the historical forward curve
2. Volatility across time to maturity and over time
3. How the market relates to itself over time
4. Seasonality and its impact on market dynamics
5. Hedging analytics — hedge ratio dynamics across the term structure and across markets

**Grading basis:** Accuracy, quality, readability, usability, and creativity. Treated as a capstone project graded on an absolute basis — going beyond the minimum is expected and rewarded.

---

## Architecture

**Framework:** Golem app built with the bslib framework (Bootstrap 5). Layout via `page_navbar()` and `card()` components. Themed with `bs_theme()`.

**Page structure**
- Pages are organised by analytical concept, not by ticker
- Tentative pages (mapping to baseline requirements): Forward Curves, Volatility, Seasonality, Cross-Market Relationships, Hedging Analytics
- Each page has a ticker selector — the user picks which commodity to analyse
- The ticker selection routes to the appropriate namespaced module behind the scenes
- Namespaces are an internal scoping mechanism only — invisible to the user, not reflected in navigation

**Data loading**
- `dflong` loaded once in `app_server.R` — never reloaded by child modules
- Filtered/sliced reactives passed down as arguments
**Commodity tickers in `dflong`**
- `CL` — WTI Crude (36 tenors)
- `BRN` — Brent Crude (36 tenors)
- `NG` — Henry Hub Natural Gas (36 tenors)
- `HO` — Heating Oil (18 tenors)
- `RB` — RBOB Gasoline (18 tenors)
- `HTT` — WTI Houston (Argus) vs. WTI Trade Month differential (12 tenors)

**Commodity groups**
- Infrastructure supports named groups of tickers — extensible to any grouping
- Two group buttons, each with a distinct analytical story:
  - **Crude** (`CL`, `BRN`, `HTT`) — WTI/Brent spread and Houston differential; crack spread story against refined products
  - **Refined Products** (`HO`, `RB`) — refinery margin story; crack spreads against crude benchmark
- `NG` is standalone — no group button warranted
- Group buttons anchored to specific panels that support group-level analysis
- Clicking a group button replaces current ticker selection with the group's tickers — modal confirmation shown before applying
- Pressing the same active group button again does nothing
- User exits group view by clicking another group button or manually changing the ticker selector — no locking
- Group buttons trigger group-specific panels to appear; non-applicable panels hide

**Module structure**
- **Core module** — combines analysis across tickers; owns cross-market comparisons and any global controls (e.g. shared date range, ticker selector)
- **Individual ticker modules** — cover single-ticker analysis (forward curve, volatility, seasonality, etc.); stateless and self-contained
- Individual modules can be called from the core module *or* directly from `app_server.R` — they are reusable in both contexts because they depend only on their inputs, never on where they are called from

**Three layers of modules**
1. **Overall namespace** — cross-ticker primer; compares and contextualises markets against each other
2. **Individual ticker namespaces** — single-ticker primers; read from `r` reactive to display results
3. **Analysis modules** — pure computation; sole purpose is to run analysis and write results back to `r` reactive; no UI

**`r` reactive (shared state)**
- Initialised empty in `app_server.R`
- Populated lazily — computed on first demand, not on startup
- Analysis modules write to it; ticker namespaces read from it

**Key disciplines**
- Subsidiary modules must never reach up to grab data — everything they need is passed in as a reactive argument
- Individual ticker modules only ever *read* from `r` — they never write to it
- Analysis modules only ever *write* to `r` — they have no UI and do not read from `r` to trigger their own computation; input data is always passed in as a reactive argument

---

## Forward Curves Page

**Panel 1 — Scaled comparison chart**
- Single normalised chart — snapshot of selected tickers on a specific date
- Single date slider (not a range) to move through time and watch relative structure evolve
- User can select one or more tickers to display
- `bslib::input_switch()` toggles to historical overlay mode:
  - Ticker selector (single ticker) + 4 calendar date inputs (all optional — empty = not plotted)
  - Each selected date overlays that date's forward curve on the chart; 0–4 curves displayed simultaneously
  - Allows direct comparison of curve shape across specific historical dates for a single ticker

**Panel 2 — 3D Forward Curve Surface**
- X: tenor, Y: date, Z: price
- Viridis color scale mapped to price level
- Regime haze projected onto the floor of the 3D plot (not the surface itself) — cleaner visually
- Floor colored by contango/backwardation regime for each date, spanning all tenors
- Regime classification smoothed to avoid flickering from short-lived switches
- Built in plotly

**Panel 3 — Monthly forward curve overlays**
- Ticker selector (individual tickers)
- 12 lines — one per calendar month (Jan–Dec) — each line is the average forward curve for that month across all available years for the selected ticker
- X-axis: tenor (M1…Mn); Y-axis: price
- Static, non-reactive beyond ticker selection
- Shows the seasonal shape embedded in forward curve prices — e.g. NG in November carries a steep winter premium; NG in May is flatter; RB peaks ahead of summer blend season

**Panel 4 — PCA decomposition**
- Forward curves of different commodities broken apart into their most significant principal components to display the characteristic moves of each market (level, slope, curvature)
- Reveals how each commodity's curve deforms distinctively
- PCA plots chart PC loadings against tenors
- Computed lazily per commodity on first selection, cached in `r$[ticker]_pca`

**Additional forward curve analytics (to be scoped in planning)**
- Historical snapshot overlays — user selects specific dates to compare
- Roll yield → moved to hedging analytics page (tentative, how it fits TBD)

---

## Variance / Volatility Page

**Panel 1 — Stacked return distribution histogram (per ticker)**
- One chart per ticker showing historical return distributions stacked by tenor
- Low opacity per layer to keep overlapping distributions readable
- Tenor range filter dynamically generated from available tenors for that ticker (varies by commodity)
- Colors via viridis or similar

**Panel 2 — Correlation matrix heatmap (per ticker)**
- Normalized covariance matrix displayed as a heatmap — tenors on both axes, color scale [-1, 1]
- Serves as an educational bridge between variance and forward curve structure — the heatmap makes visible how uncertainty is shared across the term structure and connects directly to why the forward curve moves the way it does
- Narrative framing: high front-tenor correlation = parallel shifts dominate; correlation decay toward back tenors = slope and curvature dynamics emerging; this is the covariance structure that PCA decomposes on the forward curves page

**Panel 3 — Rolling realised volatility over time**
- Ticker selector + tenor selector (M1, M2, … dynamically generated from available tenors)
- Rolling realised volatility line over time — satisfies the "volatility over time" dimension of the assignment requirement; Panel 1 covers "across time to maturity"
- Event markers: cherry-picked significant market events plotted at (date, vol_value) with plotly custom symbols and hover labels naming the event — shortlist TBD at implementation; candidates include GFC 2008, Shale revolution, COVID March 2020, 2022 Russia/Ukraine energy spike

---

## Cross-Market Relationships Page

**Core goal:** Communicate the impact of price changes in one commodity on others — accurately, efficiently, and readably for a risk manager audience.

**Panel 1 — Rolling correlation with volatility regime shading**
- Two-commodity selector (limited to two tickers for readability)
- Rolling correlation line between front month returns of the two selected commodities
- Background shaded by volatility regime (high/low vol periods) — data-driven, not manually tagged events
- Narrative: shows whether cross-market relationships strengthen or break down during stress periods
- Simpler concept than IRF — intentionally placed first as the entry point to cross-market thinking

**Panel 2 — VAR + Granger Causality with Impulse Response Functions (IRFs)**
- One VAR model fitted across all tickers simultaneously using front month (M1) returns only
- Front month only: most liquid, most representative, avoids sparse data in back months

**Data frequency — weekly end-of-week:**
- VAR estimated on weekly returns, not daily — crude-to-refined product transmission takes weeks to propagate through inventory, refinery run rates, and contractual obligations; daily IRFs (1–5 days) are too narrow a window to capture this
- Weekly frequency also eliminates the high-lag, oscillating IRF problem from the MVP — daily noise was forcing lag selection to 10; weekly data should yield a much cleaner, lower-lag model
- Aggregation: end-of-week prices (Friday close) from `dflong`; weekly log returns computed as log(P_friday_t / P_friday_{t-1})
- End-of-week chosen over weekly averages — averaging induces the Working effect (spurious negative first-order autocorrelation in returns), which biases VAR lag selection and distorts IRF estimates
- ~750 weekly observations (2008–2026) — sufficient for a well-specified 6-ticker VAR with 4–8 lags
- HTT, HO, and RB have shorter histories than CL and BRN — VAR must be estimated on the **intersection of available dates** across all tickers; inner join on date before aggregating to weekly frequency; the overlapping window determines the effective sample size
- HTT is a spread and can be negative — log returns are meaningless; use weekly first differences (ΔP) for HTT instead of log returns; standardise all series (log returns for CL, BRN, NG, HO, RB and first differences for HTT) to z-scores before VAR estimation to ensure scale comparability across tickers; IRFs interpreted as response to a 1 standard deviation shock
- **Cholesky ordering:** BRN → CL → HO → RB → HTT → NG — theoretically motivated by the global-to-local price transmission hierarchy (see brainstorm narrative); this ordering is locked and must be applied consistently at implementation

**Lag selection:**
- Use `vars` package in R for VAR estimation
- Run selection across multiple criteria simultaneously: AIC, BIC, HQ, FPE
- Select lag length where multiple criteria agree rather than blindly trusting one
- Surface selected lag to the user in the app (e.g. "VAR estimated with 4 lags, selected by BIC") — not a black box

**IRFs — primary output:**
- User selects a shock ticker (e.g. CL)
- One IRF chart rendered with all responding tickers overlaid (5 lines)
- X axis: weeks following shock; Y axis: scaled response
- Confidence bands shown around each response path
- IRF horizon: 8–12 weeks — sufficient to capture full crude-to-refined product transmission

**Communicating significance honestly:**
- Confidence bands are the signal — if the band straddles zero, the relationship is not distinguishable from noise
- Color convention: response line **green** when outside the confidence band (statistically meaningful), **grey** when inside (no meaningful relationship)
- No p-values surfaced to the user — the visual is self-explanatory

**`r` reactive object:**
- One single Granger/VAR analysis module runs all computations once and writes results to `r$granger_results`
- Individual ticker namespaces read their relevant slice — no duplicated computation

**Framing for the audience:**
- Present as "predictive relationships" not "causes" — statistically honest and still actionable
- Economic reasoning (e.g. oil prices affect aluminium smelting costs) surfaced as narrative context alongside the charts
- Caveat surfaced explicitly alongside IRF charts: VAR is calibrated on historical return innovations — unprecedented shocks or structural regime changes (e.g. pre/post shale revolution, COVID) mean historical relationships may not hold going forward
- Cholesky ordering caveat: the ordering BRN → CL → HO → RB → HTT → NG reflects the typical causal flow (global crude drives refined products); tickers above the shock ticker in the ordering show zero contemporaneous response by construction — their response will appear from week 1 onwards even if in reality it would be immediate; this is standard VAR practice and is noted in the narrative so the user is not misled; no alternative ordering is computed

---

## Market Dynamics Page

**Concept:** A commodity class primer — each group button loads a completely different experience with its own narrative, analytics, and layout. Shared elements are only the page container and group buttons.

**Group buttons:** Crude | Refined Products | Natural Gas

**Narrative:** Static, high-level, written per commodity class — not regime-aware. Explains the dominant dynamics of each market at a conceptual level.

---

**Crude** (`CL`, `BRN`, `HTT`)
- Seasonal price patterns by month
- Cushing inventory cycles (RTL `cushing` dataset available)
- Calendar spread behavior over the year (M1-M2, M1-M3)
- WTI/Brent spread dynamics
- Houston differential behavior (HTT)

### Crude — Row 1 Layout

**HTT note:** WTI Houston (Argus) is a location differential (Cushing vs. Gulf Coast export hub), not a quality differential. Both legs are light sweet WTI-grade crude. The spread captures pipeline congestion, export optionality, and Cushing storage dynamics.

**Layout:**
```
row(
  col_a(width=8),   # Brent − WTI spread chart, full height
  col_b(width=4,
    row_1(),        # stats card
    row_2()         # narrative card
  )
)
```

**Spread chart (col_a):**
- Brent − WTI (BRN01 − CL01), front month only
- Non-reactive — no user inputs; fixed chart
- Event markers for major global shocks (wars, COVID, supply shocks) — cherry-picked to most dramatic; plotly markers at (date, spread_value) with a custom symbol (e.g. star) and hover label naming the event; shortlist TBD
- Positive reads as Brent premium over WTI — makes global supply shocks intuitively readable

**Stats card (col_b, row_1):**
- Current spread (most recent BRN01 − CL01 value)
- YoY change
- Percentile vs. full history — where today's spread sits relative to all observed values; high percentile = historically wide Brent premium, low = compressed

**Narrative card (col_b, row_2):**
- Static text explaining the Brent premium and its drivers (export optionality, global vs. US benchmark, infrastructure constraints)

### Crude — Row 2 Layout

Three-beat infrastructure story following Row 1:
1. Row 1 — global benchmark (Brent − WTI spread)
2. Row 2 — does the spread predict Cushing draws? (the direct relationship)
3. Row 3 — domestic consequence (HTT spread + Cushing WoW change)

Timescale note: Row 1 tells the global/secular story; Rows 2 and 3 operate on the same dynamic, week-to-week timescale. Cushing WoW change is the real-time US supply/demand balance — builds mean supply outpacing demand/exports, draws mean the opposite. Production is sticky; storage is where the signal shows up first.

**Layout:**
```
row(
  col_a(width=6),   # narrative — Brent-WTI as export arbitrage signal; storage as real-time balance
  col_b(width=6)    # chart — Brent-WTI spread vs. Cushing WoW change
)
```

**Narrative (col_a):**
- Static text: when Brent premium widens, US crude becomes cheap relative to international markets; export arbitrage opens; crude flows out of Cushing toward Houston; shows up immediately as Cushing draws
- Frames storage as the real-time supply/demand balance, not production

**Chart (col_b):**
- Brent−WTI spread (line) vs. Cushing WoW inventory change (bars) on shared x-axis
- Thesis: wider spread → export arbitrage → Cushing draws
- Non-reactive — fixed chart
- Data: Brent−WTI from `dflong`; Cushing WoW change from `RTL::cushing`

### Crude — Row 3 Layout

**Layout:**
```
row(
  col_a(width=6),   # subplot chart (HTT spread + Cushing WoW change)
  col_b(width=6)    # narrative — Houston as international hub vs. Oklahoma as regional hub
)
```
*Note: 6/6 split provisional — may be adjusted after visual review.*

**Chart (col_a) — plotly subplot, shared x-axis:**
- Top panel: HTT spread line chart over time
- Bottom panel: Cushing week-over-week inventory change as a bar chart — positive bars = build, negative bars = draw
- Linked via `plotly::subplot()` with `shareX = TRUE` — pan/zoom applies to both panels simultaneously
- Non-reactive — fixed chart
- Data: HTT from `dflong`; Cushing WoW change derived from `RTL::cushing`

**Narrative (col_b):**
- Static text: Houston serves international customers (export terminal, Gulf Coast); Cushing is a landlocked regional hub
- Explains the mechanism: sustained Cushing draws → inventory pressure relieved → HTT spread compresses; builds → bottleneck → spread widens

### Crude — Row 4 Layout

Four-row narrative arc for Crude:
1. Row 1 — global price signal (Brent − WTI)
2. Row 2 — arbitrage mechanism (Brent−WTI spread vs. Cushing WoW change)
3. Row 3 — domestic infrastructure consequence (HTT spread + Cushing WoW change)
4. Row 4 — structural seasonal cycles (production + demand) that drive the builds/draws seen in Rows 2 and 3

**Layout:**
```
row(
  col_a(width=6),   # STL decomposition — US crude production
  col_b(width=6),   # STL decomposition — US refinery crude inputs (demand proxy)
)
```
*Narrative chains both charts together — sits above or below the two charts as a full-width caption; TBD.*

**Chart col_a — US crude production STL decomposition:**
- STL decomposition via `stats::stl()` — trend, seasonal, remainder components
- Data: EIA weekly US field production of crude oil via `RTL::eia2tidy`
- Non-reactive — fixed chart

**Chart col_b — US refinery crude inputs STL decomposition:**
- Same STL decomposition treatment
- Refinery crude inputs used as demand proxy — EIA does not publish explicit demand; this is what the market watches
- Data: EIA weekly US refinery crude inputs via `RTL::eia2tidy`
- Non-reactive — fixed chart

**Narrative:**
- Chains production and demand cycles together — when they align the market is balanced; divergence shows up as inventory builds or draws (connects back to Rows 2 and 3)
- Explicitly notes that demand is a proxy (refinery inputs), not directly measured
- Seasonal patterns: spring/fall refinery turnarounds suppress demand; summer driving season and winter heating sustain runs; production is stickier but has its own multi-year shale-driven trend

**Refined Products** (`HO`, `RB`)
- Seasonal demand patterns — heating oil winter peak, gasoline summer peak
- Crack spread behavior over the calendar year
- Spread between HO and RB across seasons

### Refined Products — Row 1 Layout

**Layout:**
```
row(
  col_a(width=6),   # two STL decompositions stacked — HO on top, RB below
  col_b(width=6)    # two narrative blocks — one per commodity
)
```

**Charts (col_a):**
- Top: STL decomposition of HO front month (M1) price — trend, seasonal, remainder
- Bottom: STL decomposition of RB front month (M1) price — trend, seasonal, remainder
- Both via `stats::stl()`, non-reactive, fixed
- Data: HO01 and RB01 from `dflong`

**Narrative (col_b) — two distinct blocks:**
- Block 1 (HO): winter heating demand drives price seasonality — northeast US residential heating oil demand peaks December–February; prices build through fall in anticipation
- Block 2 (RB): summer driving season drives price seasonality — EPA summer blend gasoline specifications (higher octane, lower volatility) are more expensive to produce; demand peaks Memorial Day through Labor Day; prices typically peak April–May ahead of the season

### Refined Products — Row 2 Layout

**Layout:**
```
row(
  col_a(width=4,
    row_1(),   # stats card
    row_2()    # narrative card
  ),
  col_b(width=8)   # crack spread chart with radio buttons + event markers
)
```

**Stats card (col_a, row_1):**
- Current spread (most recent value of selected crack spread)
- YoY change
- Percentile vs. full history

**Narrative card (col_a, row_2):**
- Static text explaining crack spreads — refinery gross margin; wide = fat margins, narrow/negative = refiners squeezed; how cracks drive refinery run rates and crude demand

**Chart (col_b):**
- Front month crack spread over time with event markers
- Crack spread selector: `shinyWidgets::radioGroupButtons()` — HO crack, RB crack, 3-2-1; styled pill buttons, active state highlighted
- Event markers: plotly markers at (date, spread_value) with custom symbol; cherry-picked to largest moves; mix of crude supply shocks and refinery-specific events (Gulf Coast outages, hurricane disruptions); shortlist TBD at implementation
- Stats card updates reactively with selected spread
- Data: HO01, RB01, CL01 from `dflong`; unit conversion HO/RB × 42 applied

### Refined Products — Row 3 Layout

**Layout:**
```
row(
  col_a(width=6),   # plotly subplot — HO/RB spread line (top) + roll yield bars (bottom)
  col_b(width=6)    # spread diagnostics card + basis risk narrative
)
```

**Chart (col_a) — plotly subplot, shared x-axis:**
- Top panel: HO/RB spread line (HO01 × 42 − RB01 × 42), daily
- Bottom panel: roll yield bars — one bar per roll date (monthly), positive = backwardation, negative = contango
- Roll yield computed as `(M1 - M2) / M1` at each contract expiry date
- Expiry dates sourced from `RTL::expiry_table` for HO and RB
- Mixed frequency (daily line + monthly bars) on shared date x-axis — plotly handles natively
- Non-reactive — fixed chart

**Spread diagnostics card (col_b):**
- Stationarity testing workflow (run at startup, result surfaced in card):
  1. ADF test (`tseries::adf.test()`) and KPSS (`tseries::kpss.test()`) on raw HO/RB spread — opposite null hypotheses, both required
  2. If stationary → fit GARCH directly on spread returns
  3. If non-stationary → regress out trend (or use OU residuals); fit GARCH on residuals
  4. GARCH unconditional volatility = `ω / (1 - α - β)` from fitted model
  5. Card surfaces which path was taken so the user is not reading a misleading number
- Displayed parameters: OU long-run mean, mean reversion speed, half-life; GARCH unconditional volatility; stationarity test result
- RTL functions: `RTL::fitOU`, `RTL::garch`

**Narrative (col_b):**
- Static text: basis risk explained — holding HO exposure and hedging with RB (or vice versa) leaves residual product-to-product spread risk; OU half-life tells you how quickly that risk resolves; GARCH unconditional vol tells you how large the deviations can be

**Natural Gas** (`NG`)
- Storage injection/withdrawal cycle (summer inject, winter withdraw)
- Strong seasonal patterns in monthly returns
- Winter premium in forward curve
- EIA storage data if accessible (RTL `eiaStocks` dataset — to confirm if NG is included)

### Natural Gas — Narrative Arc

Four-beat story, each row building on the last. Useful reference for writing static narrative text across all NG rows.

**Row 1 — Production is structural, demand is seasonal**
US dry gas production has grown steadily year-over-year (shale), but that growth is relatively flat across months. Demand is what swings seasonally — injection in summer, withdrawal in winter. Production alone doesn't explain price volatility; the mismatch between flat production and spiky demand is what makes storage critical.

**Row 2 — Storage is the heartbeat**
Storage absorbs the mismatch. The 5-year average is the market's reference point — above it prices are suppressed, below it prices spike. This is the single most watched weekly data release in NG. For a hedger, storage relative to the 5-year average tells you whether to lock in supply aggressively or wait.

**Row 3 — Domestic price has a ceiling**
When NG prices rise, coal-heavy regions switch back to coal and gas demand softens. The price cap isn't a fixed number — it's geographically distributed. The South and Midwest are still sensitive to it; the Northeast has largely retired coal so the cap mechanism is weaker there. The map makes this geographic reality visible.

**Row 4 — The market is no longer purely domestic**
Since 2016, LNG exports have connected Henry Hub to international prices. There is now a soft floor — when US prices fall far enough below international LNG prices, export demand absorbs the surplus. The market has a ceiling from coal switching and a floor from LNG exports. A hedger operating without understanding both is missing half the picture.

---

### Natural Gas — Row 1 Layout

**Layout:**
```
row(
  col(width=3),   # empty — left margin
  col(width=6),   # seasonal production overlay chart (center stage)
  col(width=3)    # empty — right margin
)
row(
  col(width=3),   # empty
  col(width=6),   # narrative block (centered below chart)
  col(width=3)    # empty
)
```

**Chart (center col, row 1):**
- Seasonal overlay chart — one line per year (2016–2025), x-axis Jan–Dec, y-axis notional US dry gas production
- Each year rendered as a separate line; magma color scale by year — earlier years lighter, recent years darker; encodes the production growth trend visually
- Non-reactive — fixed chart
- Data: US total dry gas production, monthly, EIA via `RTL::eia2tidy`
- Note: NG production data comes from EIA, not `dflong` (futures prices only)

**Narrative (center col, row 2):**
- Static text block: seasonal demand cycles for natural gas — summer injection season (Apr–Oct) builds storage ahead of winter; winter withdrawal season (Nov–Mar) draws storage down; demand peaks driven by heating; production relatively flat year-round compared to demand, making storage the critical buffer

### Natural Gas — Row 2 Layout

**Layout:**
```
row(
  col_a(width=6),   # plotly subplot chart + date range slider
  col_b(width=6)    # narrative
)
```

**Chart (col_a) — plotly subplot, shared x-axis:**
- Top panel: three normalized lines — NG front month price (NG01 from `dflong`), EIA weekly storage (Bcf), 5-year average storage
- Bottom panel: storage surplus/deficit bars — storage minus 5-year average; positive = above average (bearish), negative = below average (bullish)
- 5-year average computed as calendar average — average storage for each week-of-year across the prior 5 years (EIA standard methodology)
- Date range slider controls both panels simultaneously
- Reactive — slider input drives chart; self-contained within NG module
- Data: NG01 from `dflong`; EIA weekly storage via `RTL::eiaStocks` or `RTL::eia2tidy` (confirm at implementation)

**Narrative (col_b):**
- Static text: storage as the heartbeat of the NG market — the 5-year average is the universal benchmark; above average = oversupply, price suppressed; below average = tightness, price spikes; weekly EIA storage report is one of the most market-moving data releases in energy; relevant for hedgers deciding when to lock in gas supply or sales

### Natural Gas — Row 3 Layout *(tentative — EIA-923 series ID to confirm at implementation)*

**Layout:**
```
row(
  col_a(width=8),   # chart card — two views via radio buttons
  col_b(width=4)    # narrative
)
```

**Chart card (col_a):**
- Top-level view toggle: `bslib::input_switch()` — off = Price vs Generation, on = State Coal Share Map

**View 1 — HH Price vs Coal Generation:**
- Normalized NG front month price line (monthly average of NG01 from `dflong`)
- Normalized coal-based electricity generation as bar chart overlaid on same axis — bars rise when utilities switch to coal as NG becomes relatively expensive
- Census region filter within card: `shinyWidgets::radioGroupButtons()` — All | Northeast | Midwest | South | West
- Reactive — region selection filters coal generation bars; NG price line unchanged
- Monthly frequency throughout

**View 2 — State Coal Share Map:**
- US choropleth map via `plotly::plot_ly(type = "choropleth")` — state-level coal share (coal generation / total generation per state)
- Month slider (`sliderInput()`) steps through available months — map updates reactively
- Uses same state-level data already pulled for View 1 — no additional API calls

**Data sources (both views):**
- NG price: NG01 from `dflong`, averaged to monthly
- Coal generation + total generation by state: EIA-923 via EIA API v2 (`electricity/electric-power-operational-data` endpoint); pull by state, aggregate to Census regions for View 1; keep state-level for View 2; series IDs to confirm at implementation — `RTL::eia2tidy` or `eia` package (rOpenSci)

**Data loading strategy:**
- Lazy load on first NG group button click — pull from EIA API, write to `r$eia923_coal`; reused on all subsequent visits
- Fits existing lazy cache pattern (`r$[ticker]_returns`)
- `shinycssloaders::withSpinner()` wraps chart output — spinner shown during API call
- Graceful error handling if EIA API unreachable — display message rather than crash
- App stays perpetually up to date; no pre-computed RDS needed

**Regional expectations:**
- South and Midwest: strong coal-to-gas switching relationship — significant coal capacity remains (KY, WV, TX, IL, IN, OH)
- Northeast: weak/flat relationship — coal largely retired; contrast is itself analytically informative
- West: moderate — some coal (WY, CO) but hydro and renewables dampen the signal

**Narrative (col_b):**
- Static text: fuel switching story — when NG price rises, utilities in coal-heavy regions switch back to coal, softening gas demand and acting as a price cap; regional filter reveals where switching is still active vs. where coal has been retired; map view shows geographic distribution of coal dependency; relevant for NG hedgers understanding the ceiling on gas prices

### Natural Gas — Row 4 Layout

**Layout:**
```
row(
  col_a(width=4),   # narrative
  col_b(width=8)    # chart — Henry Hub price vs. US LNG export volumes
)
```

**Chart (col_b):**
- Two series: Henry Hub monthly average price (line) and US LNG export volumes (bars), both over time
- Non-reactive — fixed chart
- Annotation at 2016 (Sabine Pass first export) marking the structural shift
- Story: post-2016 LNG exports link US gas prices to international markets; when Henry Hub falls far enough below international LNG prices, exports ramp up and absorb domestic surplus — creating a soft price floor
- Data: NG price from `dflong` (NG01, averaged to monthly); LNG export volumes from EIA via `RTL::eia2tidy` (series ID to confirm at implementation)

**Narrative (col_a):**
- Static text: before 2016 the US gas market was largely isolated — prices were determined by domestic supply and demand alone; LNG exports changed this structurally; Henry Hub now has a global floor linked to international LNG prices; when domestic prices fall too far below international levels, export demand absorbs the surplus; hedgers can no longer treat Henry Hub as a purely domestic market

---

## Hedging Analytics Page

**Concept:** A set of self-contained hedging tools — each panel has its own ticker/instrument namespace. Educational but practical; designed for a risk manager learning how to hedge these specific markets.

---

### Row 1 — CMA Swap Pricer

**Purpose:** Price a calendar month average (CMA) swap for a selected instrument and hedge period. Communicate the financing implications of the forward curve shape to the market maker.

**Inputs:**
- Instrument selector: CL, BRN, NG, HO, RB, HTT, WTI/Brent spread (BRN − CL), HO/RB spread (HO×42 − RB×42)
- Period selector: Bal[year], Cal[year+1], Cal[year+2], Cal[year+3] — generated dynamically (see below)
- Direction toggle: Producer / Consumer

**Output:**
- Flat swap price displayed as a stat
- Chart: monthly forward curve prices + horizontal swap price line + green/red shaded areas between the two

**Shading logic — direction-aware:**
- *Producer hedge* (producer receives fixed, pays floating; bank pays fixed, receives floating): above-swap area = green (bank profit in those months), below-swap area = red
- *Consumer hedge* (consumer pays fixed, receives floating; bank receives fixed, pays floating): above-swap area = red (bank subsidizing client — embedded loan), below-swap area = green (bank recovery)
- In backwardation: front months price above the swap line → shading reveals the financing asymmetry immediately
- No separate discounted/undiscounted toggle — the shaded areas communicate the loan visually without additional controls

**Pricing:** `RTL::swapCOM` for the CMA swap price. Spread instruments compute CMA of the spread directly. Unit conversion (×42) applied automatically for HO and RB.

**Period generation — dynamic, data-driven:**

Three steps:
1. Filter `dflong` to selected ticker on most recent date → extract available tenors (M1…Mn); use `RTL::expiry_table` to map each tenor to its delivery calendar month/year → covered months vector
2. Generate candidate periods from today's date: Bal[current year] (remaining full months this year, skipped if December), Cal[year+1] through Cal[year+4]
3. Validate each candidate: include only if every month it spans appears in the covered months vector — drop if any month is missing

This means the selector updates reactively when the ticker changes — HO/RB (18 tenors) will show fewer Cal options than CL/BRN (36 tenors) automatically, with no hardcoded logic.

---

### Row 2 — Rolling Hedge Simulator

**Purpose:** Present rolling futures contracts as a hedging strategy. Show the user how roll yield accumulates (or erodes) over a 12-month window based on a historical forward curve snapshot. Producer and consumer framed separately — the same curve shape has different implications depending on which side of the hedge you're on.

**Inputs:**
- Ticker selector: CL, BRN, NG, HO, RB, HTT — individual tickers only, no spreads
- Reference date picker: selects a historical date; forward curve snapshot pulled from `dflong` at that date
- Direction toggle: Producer / Consumer — separate control, not shared with Row 1

**Narrative (static, per direction):**
- *Producer:* short hedge via rolling front-month futures; in backwardation each roll earns the carry — effective hedge price improves relative to a flat swap; in contango each roll costs; narrative frames when a rolling strategy is preferable to locking in a swap
- *Consumer:* long hedge via rolling; backwardation benefits the consumer (buys next month cheaper than current spot each roll); contango erodes the hedge — narrative frames the decision between rolling and fixing via swap

**Table — 12 columns (months), rows cascade:**

| Row | Content |
|---|---|
| Contract | M1 → M2 → M3 → … → M12 |
| Entry Price | Forward price on entering that contract (native units) |
| Exit Price | Next contract's forward price — cascades as prior month's exit becomes next month's entry |
| Roll Yield % | (Entry − Exit) / Entry × 100 |
| Monthly P&L | Direction-adjusted gain/loss in native price units |
| Cumulative P&L | Running total across all rolls |

**Units:**
- Roll Yield: percentage (%)
- P&L: native futures units — $/bbl (CL, BRN, HTT), $/MMBtu (NG), $/gal (HO, RB); unit label displayed in table header; HO/RB ×42 conversion deferred to planning phase

**Simulation mechanics:**
- Static snapshot — uses forward curve prices from `dflong` at the reference date; no price projection beyond what the curve shows
- Exit price for month k = M(k+1) price from the same snapshot (the cascade)
- P&L sign convention: Producer short hedge — positive when roll yield positive (earns backwardation); Consumer long hedge — positive when roll yield positive (buys cheaper each roll)

---

### Row 3 — Options Pricer & Zero Cost Collar

**Purpose:** Price Black-76 options across a range of strikes for a selected ticker, then construct a zero cost collar and show the payoff. Inputs are shared across both charts — they update simultaneously.

**Inputs (left column):**
- Ticker selector: CL, BRN, NG, HO, RB, HTT — individual tickers only
- Direction toggle: Producer / Consumer — determines which collar leg the user controls
- Implied volatility slider: user-supplied σ input
- Date input: calendar date picker, range constrained to available dates for the selected ticker in `dflong`; underlying price = M1 on that date
- Time to maturity: `selectInput` in whole months, 1–12; T derived as months/12 in years; expiry approximated from selected date + T months (not tied to `expiry_table` — user controls T directly); displayed as a stat on the panel
- Collar input (numeric): producer inputs floor strike (put to buy); consumer inputs cap strike (call to buy); label updates with direction toggle

**Chart 1 — BS Pricing Curve (left of two side-by-side charts):**
- X-axis: strike price; Y-axis: option premium
- Two curves plotted: put premium curve + call premium curve across full strike range
- Curves naturally intersect near ATM (put-call parity for futures)
- Horizontal line drawn at the premium of the user's collar input leg
- Line intersects both curves — the two intersection points are the zero cost collar strikes; both marked with vertical dashed lines and labeled
- Strike range by ticker:
  - CL, BRN, HO, RB, HTT: 0 to 2× current underlying price
  - NG: 0 to 3× current underlying price
- Computed across ~100 evenly spaced strikes within the range

**Chart 2 — Payoff Diagram (right of two side-by-side charts):**
- X-axis: underlying price at expiry (same range as strike range); Y-axis: net P&L
- Two lines: unhedged (linear, 45°) + collar payoff (kinked — flat beyond both collar strikes)
- Both collar strikes from Chart 1 feed directly into this chart
- Producer collar: capped upside (call sold), floored downside (put bought)
- Consumer collar: capped cost (call bought), floored benefit (put sold)

**Pricing model:** Black-76 via `RTL::GBSOption` with cost-of-carry b = 0 (futures options). Underlying S = M1 price from `dflong` on selected date.

**Risk-free rate — FRED Treasury CMT curves:**
- `RTL::usSwapCurves` is unsuitable — only covers from late 2025 onward, not historical
- Pull US Treasury constant maturity rates from FRED via `quantmod::getSymbols(src = "FRED")`
- Tickers: `DGS1MO`, `DGS3MO`, `DGS6MO`, `DGS1`, `DGS2`, `DGS5`, `DGS10`, `DGS30`
- Date range: 2008–present, matching `dflong` coverage
- Build tidy dataframe: date × tenor → rate; FRED missing values forward-filled
- At runtime: interpolate linearly between adjacent tenors at the selected date and T → risk-free rate r
- Pulled once at startup, written to `r$yield_curves`, reused across all option calculations

---

### Row 4 — Hedge Ratio Dynamics Across the Term Structure

**Purpose:** Show how the hedge ratio between M1 (the liquid front month hedge instrument) and each back tenor changes — both as a static structural fact and as a dynamic historical estimate. Two complementary views of the same question, explained side by side.

**Layout — 2×2 grid:**
```
row(
  col_left(width=6),    # static OLS beta curve
  col_right(width=6)    # animated Kalman filter beta curve
)
row(
  col_left(width=6),    # narrative — OLS chart, references Kalman
  col_right(width=6)    # narrative — Kalman chart, references OLS
)
```

**Inputs (shared, above both charts):**
- Ticker selector — individual tickers only; controls both charts simultaneously
- Delta slider — Kalman filter adaptation speed; low delta = slow-adapting (smooth), high delta = fast-adapting (noisy but responsive); makes the filter's mechanics tangible to the user

---

**Top-left — Static OLS Beta Curve:**
- X-axis: tenor (M2, M3, … Mn); Y-axis: β relative to M1
- One dotted curve with interactive points — beta of each tenor regressed on M1 returns using full history
- Computed via `RTL::promptBeta`
- Hovering on any point displays the R² for that tenor pair — no secondary axis; R² available on demand without cluttering the chart
- Horizontal reference line at β = 1.0 (perfect 1:1 hedge)
- Non-animated, always visible as a stable reference while the Kalman chart plays

**Top-right — Animated Kalman Filter Beta Curve:**
- Same axes as left chart — X: tenor, Y: β relative to M1
- Kalman filter estimated on daily returns for each tenor pair (Mn vs M1) independently
- Scalar Kalman filter — causal, no forecasting; β_t estimated using data up to t only
- Pre-computed at startup across all dates and tenors, written to `r$kalman_betas`; reused on ticker change
- **Animated on monthly snapshots** (~180 frames) — computed on daily data but displayed monthly to keep animation smooth; date label updates each frame
- Play button + speed control; user can scrub manually or let it run
- Static OLS curve shown as a faint dotted reference behind the Kalman curve — makes the deviation from the long-run average immediately visible
- No event markers — intentionally abstract; sole purpose is to communicate that hedge ratios change materially over time, not to explain why

**Bottom-left — Narrative (OLS):**
- Explains the beta curve: as the tenor mismatch between physical exposure and hedge instrument grows, the hedge ratio β declines; a 1:1 hedge of a back-month exposure with front-month futures leaves residual basis risk proportional to the gap between β and 1.0
- References the Kalman chart: the OLS curve is the long-run average — the Kalman chart shows how far that relationship drifts in practice

**Bottom-right — Narrative (Kalman):**
- Explains what the animation shows: at each point in history, this was the best available estimate of the hedge ratio given only data up to that date — no hindsight; the curve deforming over time reflects genuine regime shifts in how the forward curve moves
- References the OLS curve: the static curve is a useful starting point but the Kalman chart shows when and how much it breaks down — particularly during supply shocks, storage dislocations, or structural market shifts
- Notes the delta slider: a slow-adapting filter (low delta) stays close to the OLS estimate; a fast-adapting filter tracks short-term dislocations but is noisier

**Computation:**
- Kalman filter is scalar and causal — ~10 arithmetic operations per date per tenor pair
- CL: 35 pairs × ~3,750 daily obs = trivial; pre-computed in well under a second per ticker
- Animation: monthly frames (~180) × tenors = ~6,300 plotly data points; no browser performance concerns

---

### Row 5 — Cross-Market Kalman Beta Matrix

**Purpose:** Show hedge ratios between all ticker pairs simultaneously at a user-selected date. By the time the user reaches this row, Row 4 has established why Kalman filter betas are preferable to static OLS — no need to re-present OLS here. The date picker is the only control.

**Narrative thread:** Row 4 proves the Kalman filter is the superior tool for dynamic hedge ratios. Row 5 applies it directly to the cross-market question — no OLS alternative offered, no explanation needed.

**Layout:**
```
row(
  col(width=12)   # date picker — full width, above table
)
row(
  col(width=12)   # reactable beta matrix — full width
)
row(
  col(width=12)   # narrative — full width below table
)
```

**Inputs:**
- Date picker: single date selector; range constrained to dates available in `dflong`; defaults to most recent available date

**Table — 6×6 Kalman beta matrix:**
- Rows: exposure ticker (what you're hedging)
- Columns: hedge instrument ticker (what you're hedging with)
- Tickers: CL, BRN, NG, HO, RB, HTT — all M1 front month returns
- Each cell displays the Kalman filter-estimated β at the selected date — actual numeric value shown as text
- Cell background colored by intensity: color scale centered at 0; positive betas one hue, negative another; magnitude drives intensity
- Diagonal (self vs self) = greyed out, not a hedge relationship
- Hover tooltip on each cell shows R² for that pair at the selected date
- Rendered via `reactable` — supports cell-level background color styling cleanly

**Pre-computation:**
- All 30 off-diagonal pairs (β is asymmetric — β_ij ≠ β_ji — so all 30 matter, not just 15 unique pairs) computed at startup via scalar Kalman filter on M1 daily returns
- Written to `r$kalman_cross_betas` — separate from `r$kalman_betas` (Row 4 is within-ticker across tenors; this is cross-ticker M1 vs M1)
- At runtime: user selects date → slice pre-computed array at that date → table populates instantly; no recalculation

**Narrative (below table):**
- Explains asymmetry: β_CL→BRN ≠ β_BRN→CL — the hedge ratio depends on which side of the trade you're on; the table reads differently row-by-row vs column-by-column
- Notes HTT: as a spread instrument, its betas vs flat price tickers will be small — near-zero cells are analytically meaningful, not missing data
- Connects back to Row 4: the date picker is powerful precisely because the Kalman filter has already been established as time-varying; moving the date to a stress period (2008, COVID, 2022) reveals how cross-market hedge ratios shift under pressure

---

## RTL Package Capabilities

**GitHub:** https://github.com/risktoollib/RTL

### Functions (49 total)

**Forward Curves & Visualization**
- `chart_fwd_curves` — plots historical forward curves
- `chart_spreads` — futures contract spreads comparison across years
- `chart_zscore` — Z-Score applied to seasonal data divergence
- `chart_pairs` — pairwise scatter plots for timeseries
- `chart_PerfSummary` — cumulative performance and drawdown summary
- `chart_eia_steo` — EIA Short Term Energy Outlook
- `chart_eia_sd` — EIA weekly supply-demand information by product group
- `getCurve` — Morningstar Commodities API forward curves

**Risk & Returns**
- `returns` — compute absolute, relative, or log returns
- `rolladjust` — adjusts daily returns for futures contract rolls
- `promptBeta` — computes betas of futures contracts across the term structure
- `tradeStats` — risk-reward statistics for quant trading
- `efficientFrontier` — Markowitz efficient frontier

**Stochastic & Volatility Modeling**
- `garch` — GARCH(1,1) wrapper returning plot or data
- `fitOU` — fits Ornstein-Uhlenbeck process to dataset
- `simGBM` — GBM process simulation
- `simOU` / `simOUt` / `simOUJ` — OU process simulations
- `simMultivariates` — multivariate normal from historical dataset

**Swap & Derivatives Pricing**
- `swapCOM` — commodity calendar month average swaps
- `swapInfo` — commodity swap details for pricing
- `swapFutWeight` — commodity CMA swap futures weights
- `spreadOption` — Kirk's approximation for spread option pricing
- `GBSOption` — generalized Black-Scholes option pricing
- `CRReuro` / `CRROption` — Cox-Ross-Rubinstein binomial option model
- `barrierSpreadOption` — barrier spread option pricing
- `bond` — bond pricing
- `swapIRS` — interest rate swap
- `npv` — NPV calculation

**Data Access**
- `getPrice` / `getPrices` — Morningstar Commodities API
- `getBoC` — Bank of Canada Valet API
- `eia2tidy` / `eia2tidy_all` — EIA API with tidy output
- `getGenscapeStorageOil` / `getGenscapePipeOil` — Genscape API
- `getGIS` — extract and convert GIS data

**Trading Strategies**
- `tradeStrategyDY` / `tradeStrategySMA` — sample quant trading strategies
- `refineryLP` — LP model for refinery optimization

### Datasets (30 total — selected relevant ones)
- `dflong` / `dfwide` — commodity prices (our primary dataset)
- `expiry_table` — expiry of common commodity futures contracts
- `futuresRef` — futures contracts metadata
- `cushing` — WTI Cushing futures and storage utilization
- `eiaStocks` — EIA weekly stocks
- `eiaStorageCap` — EIA working storage capacity
- `tickers_eia` — metadata of key EIA tickers by product
- `steo` — EIA Short Term Energy Outlook
- `fizdiffs` — randomised physical crude differentials
- `tradeCycle` — Canadian and US physical crude trading calendars
- `holidaysOil` — NYMEX and ICE holiday calendars
- `spot2futConvergence` / `spot2futCurve` — spot to futures convergence

---
