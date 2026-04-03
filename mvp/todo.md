# To-Do — Commodity Market Dynamics (MVP)

> Derived from `planning.md`. Work through sequentially — do not start a phase until the previous is signed off.
> Update checkboxes as tasks complete.

---

## Phase 0 — Scaffold ✓

- [x] Create Golem app scaffold inside `mvp/CommodityMarketDynamics`
- [x] Apply `bs_theme()` in `app_ui.R`
- [x] Build `page_navbar()` with 5 pages: Forward Curves, Volatility, Market Dynamics, Cross-Market Relationships, Hedging Analytics (placeholder)
- [x] Load `RTL::dflong` once in `app_server.R`; confirm columns: `date`, `series`, `value`
- [x] Initialize `r <- reactiveValues()` empty in `app_server.R`
- [x] Write `get_ticker()` in `utils_data.R`
- [x] Create all module stubs (UI + server pairs, placeholder cards)
- [x] Create analysis module stubs (empty functions, correct signatures)
- [x] Write Phase 0 tests
- [x] All tests pass
- [x] User sign-off

---

## Phase 1 — Forward Curves Page

- [ ] Implement `mod_analysis_regime.R` — regime classification + 5-day smoothing; writes `r$[ticker]_regime`
- [ ] Implement Panel 1 — scaled comparison chart (multi-ticker, date slider, normalized, plotly)
- [ ] Implement Panel 2 — 3D forward curve surface (plotly surface, viridis, regime floor)
- [ ] Add stub cards for Panel 3 (Slope & Regime) and Panel 4 (PCA)
- [ ] Wire ticker selector reactive into module
- [ ] Write Phase 1 tests
- [ ] All tests pass
- [ ] User sign-off

---

## Phase 2 — Volatility Page

- [ ] Implement `mod_analysis_returns.R` — log returns computation; writes `r$[ticker]_returns`; lazy + cached
- [ ] Implement Panel 1 — stacked return distribution histogram (per tenor, viridis, plotly)
- [ ] Implement tenor range filter (dynamic per ticker)
- [ ] Implement Panel 2 — correlation matrix heatmap (plotly heatmap, [-1,1] scale)
- [ ] Wire `r$[ticker]_returns` so Panel 2 reuses Panel 1 computation
- [ ] Write Phase 2 tests
- [ ] All tests pass
- [ ] User sign-off

---

## Phase 3 — Market Dynamics Page

- [x] Implement group button UI (Crude | Refined Products | Natural Gas)
- [x] Implement modal confirmation on group switch
- [x] Implement active state logic (no-op on same button, exit on manual ticker change)
- [x] Implement panel show/hide routing per active group
- [x] Crude: implement calendar spread chart (CL M1–M2 over time)
- [x] Refined Products: implement crack spread chart (HO01 × 42 vs CL01 — unit conversion applied)
- [x] Natural Gas: implement monthly return seasonality bar chart
- [x] Add stub cards for secondary panels within each group
- [x] Write Phase 3 tests
- [x] All tests pass (21/21)
- [ ] User sign-off

---

## Phase 4 — Cross-Market Relationships Page

- [x] Implement `mod_analysis_var.R` — VAR fit, lag selection, Granger, IRFs; writes `r$var_results`
- [x] Implement lag consensus logic (AIC/BIC/HQ/FPE via `vars::VARselect()`)
- [x] Implement Panel 1 — rolling correlation line + vol regime shading (two-ticker selector, window slider)
- [x] Implement Panel 2 — IRF chart (shock ticker selector, 5 responding lines, confidence bands)
- [x] Implement green/grey significance coloring on IRF
- [x] Display selected lag and criterion in UI
- [x] Display VAR caveat below chart
- [x] Write Phase 4 tests
- [x] All tests pass (31/31)
- [ ] User sign-off

---

## Phase 5 — Smoke Test

- [ ] Navigate every page — no errors
- [ ] Select every ticker on every page — all charts render
- [ ] Activate every group button — panels show/hide correctly, modal fires
- [ ] Select every shock ticker in IRF dropdown — chart updates, VAR not refit
- [ ] Confirm namespace isolation (input in one module does not fire reactivity in another)
- [ ] Confirm `r$[ticker]_returns` lazy cache working (no recompute on second selection)
- [ ] Confirm `r$var_results` written exactly once
- [ ] Run `testthat::test_dir("tests/")` — zero failures
- [ ] User sign-off
