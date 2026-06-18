# PLAN: Financial Contagion Networks

## Scientific Question

**Do stock correlation communities predict crash propagation?**

Specifically, using rolling correlation networks of ~30 major US stocks (2019-2024):

1. **H1 (Structure):** Do sector-aligned community structures dissolve into a single mega-cluster during market crashes?
2. **H2 (Leading indicator):** Do network metrics (avg correlation, modularity, max eigenvalue) change significantly in the 20 trading days *before* a crash?
3. **H3 (Hub propagation):** Do financial-sector stocks act as contagion hubs, gaining the most connections during crashes?

## Data

- **Source:** Yahoo Finance via `quantmod::getSymbols()`
- **Period:** 2019-01-01 to 2024-12-31 (1509 trading days)
- **Universe:** 28 stocks across 6 sectors + SPY benchmark
  - Tech (6): AAPL, MSFT, GOOGL, AMZN, NVDA, META
  - Finance (5): JPM, BAC, GS, MS, WFC
  - Health (4): JNJ, PFE, UNH, ABBV
  - Energy (3): XOM, CVX, COP
  - Consumer (5): WMT, PG, KO, MCD, NKE
  - Industrial (4): CAT, BA, HON, UPS
- **Fallback:** Synthetic correlated returns with known regime structure

## Interface Contract

### Engine output (`build_rolling_networks()` return value):

```r
list(
  networks       = list(),   # igraph objects per window (V: name, sector; E: weight)
  metrics        = tibble(), # date, avg_corr, max_eigenvalue, modularity, n_communities, density, mean_degree
  communities    = tibble(), # date, ticker, community_id, degree, betweenness
  returns        = xts(),    # daily log returns
  dates          = Date(),   # window center dates
  events         = tibble(), # date, label, type (crash/control)
  spy_returns    = tibble(), # date, spy_return, spy_cumulative
  sector_map     = tibble(), # ticker, sector
  sector_colors  = c(),      # named character vector
  tests          = tibble(), # Welch t-test results
  hubs           = list()    # hub analysis (summary + change tibbles)
)
```

## Division of Labor

| Component | Primary Author | Enhancer | Lines |
|-----------|---------------|----------|-------|
| engine.R | Claude-Alpha | Claude-Beta (hub fix) | 627 |
| visualize.R | Claude-Alpha | Claude-Beta (robustness) | 675 |
| main.R | Claude-Alpha | — | 109 |
| **Total** | | | **~1400** |

## Packages Required

All confirmed available in nix shell:
- `quantmod` (data download), `igraph` (networks), `plotly` (interactive plots)
- `visNetwork` (interactive network graph), `DT` (tables), `htmlwidgets` + `htmltools` (dashboard)
- `dplyr`, `tidyr`, `tibble`, `xts`, `zoo`, `scales`, `viridis`

## Success Criteria

1. [x] Real data downloaded and processed (28 stocks, 1509 days)
2. [x] H1 tested with statistical significance (7/7 metrics significant)
3. [x] H2 tested (1/7 pre-crash metrics significant)
4. [x] H3 tested (surprise: consumer/tech hubs, not finance)
5. [x] Interactive HTML dashboard with 6 sections
6. [x] All plots have captions with variables, units, and conclusions

## Results Summary

| Hypothesis | Verdict | Key Evidence |
|------------|---------|-------------|
| H1 (Structure) | **STRONGLY SUPPORTED** | 7/7 metrics significant (p < 0.001); communities collapse from 4-8 to 1-2 during crashes |
| H2 (Leading indicator) | **PARTIALLY SUPPORTED** | n_communities drops before crash (p=0.008); other metrics trend but not significant at 20-day horizon |
| H3 (Hub propagation) | **REFUTED** | Consumer (MCD, NKE) and Tech (AAPL) gain most connections, not Finance; defensive stocks get dragged into crash correlation |
