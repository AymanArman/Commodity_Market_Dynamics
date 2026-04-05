---
name: Testing Checklist
description: Code-breaking issues deferred to execution — must be caught and fixed through robust testing, not planning
type: project
---

These items were identified in the pre-execution audit and explicitly deferred to testing. At the start of each phase, verify the relevant items before proceeding.

**Why:** User confirmed these do not require planning changes — they are implementation-level issues caught by smoke tests and module-level tests.

**How to apply:** Flag these during phase execution. Do not skip them. Each one will cause silent failures or crashes if not addressed.

---

## Phase 0
- Excel origin date `"1899-12-30"`: load all EIA files immediately and verify parsed dates are correct before any downstream module consumes them

## Phase 1
- Sparse ticker filter: test multi-ticker selection with tickers that have different history start dates — verify chart does not render partial or empty curves
- Dynamic `r[[paste0(ticker, "_pca")]]` slot naming: verify slot is correctly written and read in a smoke test before animation renders

## Phase 2
- Percentile clip (1st/99th) applied before density calculation: verify visually that the density chart represents the intended display behaviour — intentional design choice but confirm it looks correct

## Phase 3
- Crude Row 4 STL gaps: add `na.approx()` or equivalent gap-filling before passing EIA weekly data to `stats::stl()` — test with actual EIA files which contain holiday gaps
- Refined Row 2 inner join: test crack spread join with early history dates — verify row drops are logged with a warning, not silent
- NG Row 3 EIA-923 column positions (col 7, 8, 15, 80–91, 97): load one file immediately and verify columns align before writing the full parsing logic
- NG Row 4 frequency mismatch: test the NG01 daily × LNG exports monthly join explicitly — verify alignment logic before rendering

## Phase 4
- VAR missing ticker dates: test VAR estimation with the actual `dflong` dataset — verify all six tickers have sufficient overlapping dates; add an explicit error or warning if any ticker is missing

## Phase 5
- Row 2 roll expiration count: test rolling hedge simulator with short-history tickers (e.g. HTT) — verify graceful handling if fewer than 12 roll expirations exist in the selected range
- Row 3 yield curve vs dflong cutoff: test reference date UI constraint with the actual FRED file — verify the constraint does not become infeasible when yield curve data ends earlier than dflong
