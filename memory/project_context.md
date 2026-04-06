---
name: Project Context
description: FIN 452 capstone project context, goals, grading basis, and current phase
type: project
---

FIN 452 capstone project — building a Golem app as an interactive primer on commodity market dynamics for risk and portfolio managers unfamiliar with **commodities** (not finance — audience is financially sophisticated).

Graded on accuracy, quality, readability, usability, and creativity on an absolute basis. Going beyond the minimum analytical requirements is expected and rewarded.

**Why:** Assignment requires covering forward curves, volatility, cross-market relationships, seasonality, and hedging analytics. The app must tell a story — to the manager themselves, their team, and stakeholders.

**How to apply:** Scope decisions should favor depth and creativity over just meeting minimums.

---

## Current Phase: Ready to begin Phase 0 execution

`planning.md` fully locked. `todo.md` and `testing_plan.md` both created as of 2026-04-05. Next session begins Phase 0 execution.

**Execution files:**
- `todo.md` — sequential implementation checklist, one phase at a time; each phase ends with test run + visual review + commit
- `testing_plan.md` — full test suite (~100 tests across 6 phases); unit, integration, visual, and smoke tests; organized by phase to match execution order

**Phases:**
- Phase 0: Scaffold & Shared Infrastructure
- Phase 1: Forward Curves Page
- Phase 2: Volatility Page
- Phase 3: Market Dynamics Page
- Phase 4: Cross-Market Relationships Page
- Phase 5: Hedging Analytics Page

---

## Key architectural decisions locked in planning

- `apply_theme()` utility function built in Phase 0 — every plotly chart piped through it
- `compute_returns` utility handles HTT via level differences (ΔP) — all modules must consume it, never compute log returns on HTT directly
- `r$kalman_betas` schema: `(date, ticker, tenor, beta, r_squared)` long format
- `r$kalman_cross_betas` schema: `(date, from_ticker, to_ticker, beta, r_squared)` long format, diagonal excluded
- `mod_var` aggregates `dflong` to Friday closes before VAR estimation — Cholesky ordering BRN→CL→HO→RB→HTT→NG
- All static EIA data loaded at startup in `app_server.R` and written to `r$` slots
- Phase 1 Row 1 date slider uses integer-mapped implementation (not sliderTextInput) for performance

## Key Phase 5 decisions

- Row 3 (Options Pricer): HTT excluded (Black-76 invalid); TTM = 1/3/6 months radio; inputs locked in view mode, Edit/Apply pattern; View 2 shows collar MTM over life of 100 contracts; zero-cost collar solved via grid search not uniroot
- Row 4 (Kalman Betas): no delta slider — ticker + animation speed only; HTT excluded; X-axis fixed to max tenor set across full history
- Row 5 (Cross-Market Matrix): RdBu diverging color scale; date picker constrained to `r$kalman_cross_betas` dates

## Planning decisions made 2026-04-05

- Phase 1 Row 2: centered 5-day rolling majority vote for contango/backwardation regime (2 days either side)
- Phase 3 Refined Row 3: exclude first 5 years of EIA data entirely for 5-year average computation
- Phase 5 Row 3: FRED data downloaded to current date — no stale rate concern
- Phase 3 NG Row 3: stub if EIA-923 files (2008–2024) not available at Phase 3 execution; implement retroactively
- Crude Row 4 + NG Row 1 (standalone EIA charts): constrained to Jan 2008 – Dec 2025

## Data files

- `inst/extdata/` has 6 EIA files ready
- FRED Treasury CMT rates still needed before Phase 5 execution
- EIA-923 annual files (2008–2024) still needed before Phase 3 NG Row 3 execution
- EIA-923 2025 file exists in project root — needs to be moved to `inst/extdata/`
