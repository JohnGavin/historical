# Changelog

## 2026-04-25 to 2026-04-30

### Completed
- Falsification dashboard (#53): 6-page dashboard with scorecard, HAC, null environments, FF regression, multiplicity, methodology. 13 vignette targets. Deflated Sharpe Ratio added as 5th test.
- Negative results dashboard (#57): documents 3 falsified strategies with diagnoses and lessons
- Quiz (#70): real vs simulated time series quiz — micromort template, 10 real tickers, 4 difficulty levels, QR codes, score tracking
- Unified strategy_names target (#71): 9 strategies × 7 columns, single source of truth
- Duckplyr migration (#77): 13/15 functions migrated from raw SQL; 5 legitimate exceptions (complex window/regex)
- Results DB backfill (#60 #61): 71/74 columns populated; 3 new trade extraction functions
- Marginal contribution (#54): DRIF + LTR best pair (Sharpe 0.68, DD -13.8%), LTR negatively correlated
- Strategy decay (#73): Factor MAX decays >50%; DRIF and LTR stable across time
- Model interpretability (#74): DRIF selects Momentum 52% of months; LTR features stable across 22 years
- Multi-strategy portfolio (#52): decay-aware weighting (DRIF 50%/LTR 35%/FMAX 15%)
- VIX macro overlay (#59): only UUP benefits; gold hurts (crisis rally missed)
- Commodity data (#68): 145,873 rows, 37 series (FRED + Yahoo futures via quantmod)
- Mean reversion (#50): negative result (CAGR -5.9%, Sharpe -0.22)
- New pkg functions: hd_deflated_sharpe(), hd_null_env_jump_diffusion(), hd_monthly_trades(), hd_event_trades(), hd_trade_metrics()
- New global rules: strategy-name-consistency.md, visualization-standards.md updated (caption↔table consistency, % formatting, column ordering)
- Issues created: #71-#77
- Issues closed: #49 #50 #51 #52 #53 #54 #57 #59 #60 #61 #68 #69 #70 #71 #72 #73 #74 #77

### Failed Approaches
- Quarto 1.8 strips raw HTML from R chunks and fenced divs — all attempts with cat(), knitr::asis_output(), {=html} blocks, ::: divs failed. Workaround: include-after-body + JS to relocate #quiz-app into <main>
- Mean reversion on ETFs/large caps (z-score < -2, hold 5 days): CAGR -5.9% — drops that trigger signals are often start of larger drawdowns (momentum dominates reversion)
- VIX overlay on gold: hurts performance because gold rallies during crises when VIX is high
- Factor MAX shows >50% temporal decay — early Sharpe 0.93, late period lower
- hd_ohlcv() can't fetch Yahoo futures (CL=F, GC=F) — not in HuggingFace equity dataset. Fixed with quantmod::getSymbols()

### Accuracy / Metrics
- Pipeline: ~250 targets across 26 plan files, 0 errors
- Strategy scorecard: DRIF genuine alpha (DSR p<0.001), Factor MAX (DSR p=0.004), LTR borderline (DSR p=0.163)
- Results DB: 71/74 columns populated (was 42/74)
- 17 issues closed this session block
- Duckplyr: 13/15 query functions migrated (was 2/15)

### Known Limitations
- reviser package not compiled in nix store — hd_revision_analysis() exists but can't be tested (#65)
- LTR alpha decay needs XGBoost in nix develop shell — stub target
- SHAP values for LTR deferred (needs nix develop for XGBoost predict(contrib=TRUE))
- 4 results DB columns remain NA: avg_dd_duration_days, up/down_capture, turnover_annual
- Quiz Google Sheets score submission not configured (#76)
- VSTOXX data truncated at 2016
- Multi-strategy portfolio Sharpe (0.36) lower than DRIF standalone (0.42) due to rebalancing costs

## 2026-04-24

### Completed
- Avoid Worst Days strategy (#45 #46): 27 targets + vignette, t+1 execution fix dropped CAGR 18.4%→5.3%
- Risk State Classification (#51): 15 targets, 3-signal VIX design — negative result (88% market beta, no alpha)
- LTR Cross-Sectional Momentum (#49): 11 targets + 2 standalone scripts (nix ABI workaround for XGBoost)
- Falsification framework (#53 Phase 1): 12 exported pkg functions (hd_hac_tstat, 6 null generators, K_eff, delta_z, FF regression) + 33 pipeline targets across 5 strategies
- Results database (#60): 74-column schema (hd_results_schema/append/query), 23 metrics backfilled from pipeline
- Macro registry expansion: 28→81 series with forward-looking metadata (source_type, implied_from, liquidity)
- CBOE vol fetch script: 46 series (VIX term structure, equity/intl/commodity vol, skew, implied correlation/dispersion)
- International vol fetch: VSTOXX, VHSI, NKV1, AXVI, INDIAVIX
- HuggingFace upload: 78 macro series, 425K rows
- Issues created: #57-#68 (negative results dashboard, shadow trades, commodities, prediction markets, CRPS, circuit-breakers, reviser)

### Failed Approaches
- t+0 VIX execution: used d$vix[i] instead of d$vix[i-1] — physically impossible same-day trading inflated CAGR by 3.5x
- RSC overlay: 3-signal VIX design (VVIX, term structure change, term structure level) adds no alpha over buy-and-hold
- XGBoost in callr subprocess: 5.4M rows × 21 features OOM — fixed by chunked standalone scripts
- XGBoost from global nix shell: segfault from ABI mismatch — must run inside nix develop
- VDAX/VCAC/VFTSE fetch: 404 or no free bulk source available
- hd_results_append dedup: bind_rows(existing, new) kept stale rows — reversed order

### Accuracy / Metrics
- Pipeline: ~210 targets (19 plan files), 0 errors
- Strategy scorecard: DRIF genuine alpha (t=4.73), Factor MAX genuine alpha (t=3.74), LTR borderline (t=1.99), Avoid Worst no alpha (t=-0.80), RSC no alpha (t=-1.60)
- 12 issues created, multiple commits

### Known Limitations
- LTR alpha decay target is a stub — requires re-running XGBoost inside nix develop
- 29 results DB columns still NA (trade-level metrics need #61)
- VSTOXX data truncated at 2016 (STOXX .txt format issue)
- Falsification dashboard vignette (#53) not yet created
- Negative results dashboard (#57) not yet created

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
