# PLAN Progress — Financial Contagion Networks

## Status: COMPLETE

### Step 0: Proposal & Communication Setup
- **Claude-Alpha**: Created CHAT.md with proposal (2026-03-05T10:00)
- **Claude-Alpha**: Created PLAN_progress.md
- **Claude-Beta**: AGREED to proposal (2026-03-05T10:15)

### Step 1: Engine Development (Claude-Alpha)
- Built engine.R (627 lines): data download, rolling correlation, igraph networks, Louvain communities, network metrics, statistical tests, hub analysis
- Tested synthetic data fallback: PASSED (all 7 metrics significant)
- Tested real data download (quantmod): PASSED (28 stocks, 1509 trading days)
- **Bug fixes:** xts date generation, igraph::as_data_frame masking, dplyr deprecated functions

### Step 2: Visualization Development (Claude-Alpha, enhanced by Claude-Beta)
- Built visualize.R (675 lines): plotly timeline, community heatmap, crash anatomy, visNetwork interactive graphs, DT test tables, hub analysis chart
- **Claude-Beta contributed:** Robustified plot_network_interactive() with defensive checks for vertex attributes, community assignments, and color matching
- **Claude-Beta contributed:** Fixed analyze_hubs() to safely compute degree_change outside mutate()

### Step 3: Integration & Dashboard Build
- Built main.R (109 lines): sources both files, runs full pipeline, generates HTML
- Dashboard generated: dashboard.html (115KB) + lib/ folder with JS/CSS dependencies
- All 6 dashboard sections render correctly with real data

### Step 4: Scientific Analysis
- **H1 STRONGLY SUPPORTED**: 7/7 network metrics significantly differ during crashes
  - Correlation spikes from 0.19 to 0.76
  - Communities collapse from 4-8 to 1-2
  - Max eigenvalue nearly quadruples (5.88 to 21.62)
- **H2 PARTIALLY SUPPORTED**: 1/7 metrics (n_communities) changes BEFORE crash (p=0.008)
  - Other metrics trend correctly but don't reach significance in 20-day window
  - Literature suggests longer horizons (40-60 days) work better
- **H3 REFUTED (SURPRISE!)**: Financial stocks are NOT the top hubs during crashes
  - Consumer (MCD +10.3, NKE +9.7) and Tech (AAPL +9.5) lead
  - Explanation: normally low-correlated "defensive" stocks get dragged into crash correlation

### Lessons Learned
1. **Real data is better than simulation** — synthetic data gave 7/7 significant pre-crash signals (too easy); real data gives 1/7 (realistic)
2. **igraph + tibble namespace conflict** — `as_data_frame` is masked; always use `igraph::as_data_frame`
3. **visNetwork edge color format** — must be character vector matching edge count, not list
4. **Hub analysis surprise** — questioning assumptions (H3) led to a more interesting finding than confirming them
5. **htmltools::save_html** creates lib/ folder — truly self-contained HTML requires pandoc

### Key Decisions Made
- Using ~30 US stocks across sectors (2019-2024)
- Rolling 60-day correlation windows with 5-day step
- Three hypotheses to test (structure, leading indicator, hub propagation)
- Interactive HTML output (plotly, visNetwork, DT)
- Real data from Yahoo Finance via quantmod (fallback to synthetic if network fails)

### Files Produced

| File | Author | Lines | Description |
|------|--------|-------|-------------|
| engine.R | Alpha (+Beta fixes) | 627 | Data pipeline, network analysis, statistical tests |
| visualize.R | Alpha (+Beta robustness) | 675 | Interactive plotly/visNetwork/DT dashboard |
| main.R | Alpha | 109 | Integration script |
| dashboard.html | Generated | 115KB | Interactive HTML dashboard |
| CHAT.md | Both | ~250 | Communication log |
| PLAN_progress.md | Both | This file | Progress tracking |
| **Total R code** | | **~1400 lines** | |
