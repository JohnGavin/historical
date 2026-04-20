# Changelog

## 2026-04-20

### Completed
- Robustness batch: 4 new plan files, 24 targets (#34 #36 #37 #38) — all built and verified
  - plan_kelly.R: fractional Kelly vs flat 1%/2% sizing (6 targets)
  - plan_bootstrap_ci.R: block bootstrap CI on Sharpe/DD (6 targets)
  - plan_regime.R: regime-aware portfolio reweighting via VIX/realized vol (7 targets)
  - plan_alpha_decay.R: signal decay t+1..t+10 execution delay (5 targets)
- Leaderboard vignette: new Robustness page with 4 tabs (Bootstrap CI, Alpha Decay, Regime, Kelly)
- Leaderboard audit (#41): assumptions 0.50%/trade, validation sealed, correlations kable, PSO links
- Leaderboard: bootstrap CI columns joined onto leaderboard target (sharpe_ci_lo/hi, ci_crosses_zero)
- Leaderboard: equity curves caption explains stock vs factor cost divergence (~22%/yr vs ~2%/yr)
- XGBoost section moved from leaderboard to stock-backtest.qmd (#40), documented as failed experiment
- XGBoost feature importance table removed entirely (c13=48% was artifact, not credible)
- Monthly returns: color-coded borders, DT order descending (#42), marginal means, pageLength=60
- DT tables: regex search enabled globally via hd_dt()
- Index page: leaderboard added to Links section
- prompt_backtesting.md: costs updated to 0.50%/trade + borrow/turnover/winsor
- Min trading days lowered 15→10 (#43), min 50 stocks per month for decile formation

### Failed Approaches
- XGBoost c13=48% feature importance: artifact of monotonic constraints + shallow trees, not meaningful
- XGBoost equity curve jumps: monotonic constraints force concentrated predictions in certain months
- 15→10 trading day threshold: only recovered 1 March (13→14). Root cause is elastic net complete.cases()
- DT negative lookahead regex `^(?!.*Validation)`: not supported by DataTables JS engine

### Accuracy / Metrics
- Pipeline: 175 targets (15 plan files), 0 errors
- 10 commits this session, 8 issues closed (#34 #36 #37 #38 #40 #41 #42 #43)
- 2 issues remain open: #2 (Public API), #33 (perspectiveR)

### Known Limitations
- stk_drif_portfolio has uneven month coverage (Mar=14/52, Sep=51/52) — structural, elastic net needs 200+ complete training rows
- port_returns inner_join propagates stk_drif gaps → 127 NAs in monthly heatmap (20% cells)
- Monthly returns "Mean" row sorts to top with DT desc order (cosmetic)

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
