# Brainstorm — Commodity Market Dynamics

**What:** A Golem app — an interactive primer on commodity market dynamics
**Who:** Risk managers and portfolio managers unfamiliar with the space

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

**Panel 2 — 3D Forward Curve Surface**
- X: tenor, Y: date, Z: price
- Viridis color scale mapped to price level
- Regime haze projected onto the floor of the 3D plot (not the surface itself) — cleaner visually
- Floor colored by contango/backwardation regime for each date, spanning all tenors
- Regime classification smoothed to avoid flickering from short-lived switches
- Built in plotly

**Additional forward curve analytics (to be scoped in planning)**
- Curve shape / regime classification timeline
- Slope & curvature metrics over time (M1-M2, M1-M12 spreads)
- Historical snapshot overlays — user selects specific dates to compare
- Roll yield → moved to hedging analytics page (tentative, how it fits TBD)
- PCA decomposition → moved to variance page (tentative pending further study — professor has a module on this)

---

## Variance / Volatility Page

**Panel 1 — Stacked return distribution histogram (per ticker)**
- One chart per ticker showing historical return distributions stacked by tenor
- Low opacity per layer to keep overlapping distributions readable
- Tenor range filter dynamically generated from available tenors for that ticker (varies by commodity)
- Colors via viridis or similar

**Tentative**
- PCA decomposition (level, slope, curvature) — pending further study

---

## Cross-Market Relationships Page

**Core goal:** Communicate the impact of price changes in one commodity on others — accurately, efficiently, and readably for a risk manager audience.

**Chosen methodology: VAR + Granger Causality with Impulse Response Functions (IRFs)**
- One VAR model fitted across all tickers simultaneously using front month (M1) returns only
- Front month only: most liquid, most representative, avoids sparse data in back months
- Optimal lag selected automatically via AIC — removes subjectivity
- Granger causality tested within the VAR system — captures indirect channels that pairwise Granger misses
- IRFs are the primary output — show how all other commodities respond over N days following a shock to the selected ticker

**User interaction**
- User selects a ticker (e.g. CL)
- One IRF chart rendered with all responding tickers overlaid (9 lines)
- X axis: days following shock, Y axis: scaled response
- Confidence bands shown around each response path

**Communicating significance honestly**
- Confidence bands are the signal — if the band straddles zero, the relationship is not distinguishable from noise
- Color convention: response line **green** when outside the confidence band (statistically meaningful), **grey** when inside (no meaningful relationship)
- No p-values surfaced to the user — the visual is self-explanatory

**Lag selection**
- Use `vars` package in R for VAR estimation
- Run selection across multiple criteria simultaneously: AIC, BIC, HQ, FPE
- Select lag length where multiple criteria agree rather than blindly trusting one
- Surface selected lag to the user in the app (e.g. "VAR estimated with 8 lags, selected by BIC") — not a black box

**`r` reactive object**
- One single Granger/VAR analysis module runs all computations once and writes results to `r$granger_results`
- Individual ticker namespaces read their relevant slice — no duplicated computation

**Framing for the audience**
- Present as "predictive relationships" not "causes" — statistically honest and still actionable
- Economic reasoning (e.g. oil prices affect aluminium smelting costs) surfaced as narrative context alongside the charts
- Caveat surfaced explicitly alongside IRF charts: VAR is calibrated on historical return innovations — unprecedented shocks or structural regime changes (e.g. pre/post shale revolution, COVID) mean historical relationships may not hold going forward

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
