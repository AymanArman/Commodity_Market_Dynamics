# MVP Reflection

## What worked well

- The three-layer module architecture held up throughout. Analysis modules write to `r`; display modules read. No cross-module reaching. The VAR module running once at startup and serving all shock tickers from cache is a direct product of this discipline.
- The volatility page (density chart + correlation heatmap) is strong — lock in for final product essentially 1-for-1.
- The 3D forward curve surface is strong — goes straight into the final product.
- The lazy caching pattern on `r$[ticker]_returns` worked exactly as designed.
- Claude was effective at bridging modules into a coherent app. The structure is broadly working.

## What needs work

**Comparison forward curves:** needs minimal refinement to ensure all selected dates have data across all selected tickers. Sparse early history on some tickers creates gaps.

**Market Dynamics page:** currently lackluster. Each group has one chart and three stubs, and all three groups share the same layout pattern. The problem is each group has a genuinely different story:
- Crude is a spread and term structure story
- Refined Products is a seasonality and refinery margin story
- Natural Gas is almost entirely a storage and seasonality story

They should not share the same layout pattern. Needs deep brainstorming per group before building out the stubs.

## Open items for future brainstorming

**Cross-Market Relationships page — needs more depth.** There is a natural narrative arc that should be built out:
- Rolling correlation tells you *that* markets move together
- VAR/IRF tells you *how* and *how long*
- The page currently jumps between these two with no connective tissue and no third element

Directions to brainstorm:
- Rolling betas across the term structure (not just front month)
- Spread dynamics (WTI/Brent, crack spreads) as a cross-market signal
- Regime-conditional correlations — do relationships strengthen or break down during vol spikes? Connects naturally to the vol regime shading already on Panel 1

**Hedging Analytics page — not yet brainstormed.** This is a significant chunk of the minimum requirements and needs its own brainstorm session before planning can touch it.

**VAR Cholesky ordering** is currently arbitrary (`CL, BRN, NG, HO, RB, HTT` by processing order). For the final product, the ordering should be theoretically motivated — it determines which variable gets credit for contemporaneous correlation and directly affects IRF interpretation. A defensible ordering: BRN (global benchmark) → CL (WTI) → HO, RB (refined products) → HTT (differential) → NG (standalone).

## Technical debt to resolve before final product

- HTT is included in the VAR using level differences while all other tickers use log returns — a statistical inconsistency. Either drop HTT from the VAR or find a comparable transformation.
- VAR selected at lag 10 by AIC/BIC/HQ/FPE consensus. High-lag model on daily return data produces noisy, oscillating IRFs. Consider capping lag.max lower (e.g. 5) for cleaner, more interpretable responses.
