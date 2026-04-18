# Changelog

## 2026-04-18

### Completed
- Strategy leaderboard vignette: transposed rankings, equity curves, XGBoost feature importance
- XGBoost monotonic binning: 7 targets, monotone_constraints format fix (parentheses)
- Auto-delegation rule + targets-runner agent updated for T lang nix develop
- perspectiveR issue #33 raised (linked to #2 API)
- Cleanup: renamed prompt files, gitignored build artifacts, synced flake.nix

### Failed Approaches
- XGBoost monotone_constraints without parentheses: `"1,1,...,1"` fails, needs `"(1,1,...,1)"`
- `nix develop --verbose 2>&1 | grep "building"`: grep buffers output — use `| head -200` without grep
- XGBoost underperforms elastic net at stock level (-6.3% vs +1.3% full CAGR) — monotonic constraints too restrictive for cross-sectional returns

### Accuracy / Metrics
- R CMD check: 0/0/1 (nix time note)
- Pipeline: 139 targets (11 plan files)
- XGBoost feature importance confirms paper: chronological features dominate (c13 = 48% gain)
- PSO optimal portfolio: 40% Stock MAX + 50% Factor DRIF + 10% Factor MAX → 11.8% CAGR, 0.93 test Sharpe

### Known Limitations
- nix develop takes ~2 min per entry (flake evaluation overhead)
- XGBoost targets need `t update && nix develop` if xgboost not in shell
- perspectiveR needs Shiny — can't use in static Quarto dashboards
- 2 open issues: #2 (Public API), #33 (perspectiveR)

## 2026-04-14

### Completed
- Stock-level backtests: Factor MAX + DRIF on 660 stocks (S&P 500 + STOXX 600)
- DRIF: real elastic net (removed PCA-OLS fallback), glmnet via tproject.toml
- 3-way train/test/validation partitions for all backtests
- PSO portfolio optimisation for strategy combination
- Macro vintage tracking with reviser integration
- R CMD check 0/0/0 with sample data fallback
- Shared CSS/JS for all vignettes (dark mode, click-to-zoom, caption wrapping)
- Strategy vignette template rule + stock-backtest.qmd rewrite
- T lang lessons: global rule + knowledge base wiki (3 files)
- S&P 500 + STOXX 600 majors added to HuggingFace (1622 tickers, 7.1M rows)

### Failed Approaches
- PCA-OLS "fallback" for elastic net: OOS looked 3x better (7.4% vs 2.6%) due to overfitting. Never ship fallbacks.
- Direct flake.nix edits: overwritten by `t update`. Always edit tproject.toml.
- `install.packages()` in nix: read-only store. Use tproject.toml.
- HuggingFace REST API upload: all endpoints return 404. Use git clone + LFS push.
- Large RDS in git (81MB): gitignored, rebuild via tar_make

### Known Limitations
- STOXX 600: only 150 majors (~70% by market cap), full list needs paid subscription
- yfinance volume bug for non-US markets (ranaroussi/yfinance#300)
- Macro vintages are simulated (real ALFRED API needs FRED key registration)
