# Changelog

## 2026-05-16

### #78 daloopa/investing gap analysis

Added `knowledge/wiki/daloopa-gap-analysis.md`: gap analysis of daloopa/investing (institutional fundamental data MCP) vs our current data setup. Conclusion: 1 adopt (REST API design lessons for #2), 2 defer (MCP integration + `hd_fundamentals()` wrapper pending paid account), 4 reject as out-of-scope (15 analyst-workflow skills and standalone earnings/SEC features). Full analysis at `knowledge/wiki/daloopa-gap-analysis.md`.

### Quantocracy May-3 2026 roundup curated (#126)

Curated 5 articles from the Quantocracy May 3 2026 roundup into `knowledge/wiki/quantocracy-may-2026.md`. Cross-referenced against open issues: StratProof covered by #125, Macrosynergy by #124. Two new topics surfaced: optimal regime-dependent exposure sizing (Alpha Architect, actionable for plan_regime.R) and risk parity 58-year tail audit (Beyond Passive, context for #114).

## 2026-05-15

### #150 Option C — top-100 market-cap restriction on stk_universe

**Context:** Option B (disclosure banner) deployed 2026-05-12. Option C narrows `stk_universe` from 667 to top-100 by current market cap to limit *forward* survivorship exposure. Backtest results remain survivorship-biased — see Known Limitations.

**Completed:**

- New `stk_top_tickers` target reads `hd_datasets()[["metadata"]]` and slices the top-100 by `market_cap` (cue=always so the universe refreshes with external metadata).
- `stk_params$top_n_market_cap = 100L` parameter exposes N.
- `stk_universe` filters to `ticker %in% stk_top_tickers`.
- `disclosure_survivorship()` rewritten to dynamically reflect N and reframe as "limit forward exposure" rather than "reduce bias" — the historical bias is unchanged.

**Spike findings (read-only, equal-weighted proxy):** Full universe (667) Sharpe 0.884; top-100 Sharpe 1.036 (+0.15, +17%); top-50 1.077; top-200 0.987. Higher Sharpe at smaller N reflects mega-cap concentration, not bias removal. Cap cutoff at top-100: $155B. Median history of top-100: ~33 years. Only 13/100 have full 56-year history.

### Known Limitations

- **Option A (point-in-time data acquisition) remains open.** Top-100 restriction does not retroactively add Lehman/Bear/Enron/etc. to the universe. Strategies still need a banner.
- **Validation seal already broken on stk_max family (#114 work).** Option C does not change that — N is chosen from current metadata, not from validation results, but the same validation window has been used for prior tuning.

## 2026-05-14

### HRP allocator + ADV-cap cost realism (4 commits, 3 issues touched)

**Context:** Two issue-driven workstreams in one session: (a) #114 — implement HRP (Lopez de Prado 2016) via `HierPortfolios` CRAN package after surveying alternatives to re-implementation; (b) #143 gap #3 — add ADV-based participation cap as the cost-realism follow-up. Both treated as empirical experiments, not as commitments to ship the underlying strategy.

**Completed:**

- **#114 Phase 0 (`2105727`)** — `HierPortfolios` 1.0.2 added to `tproject.toml` + `DESCRIPTION`; `t update` regenerated `flake.nix`. CRAN survey before adopting: `HierPortfolios` covers HRP/HCAA/HERC/DHRP; `tdaverse` covers persistent-homology/Mapper for the speculative TRP track. Re-implementation rejected in favour of CRAN.
- **#114 Phase 1 (`5e72205`)** — `port_hrp_weights` target in `R/plan_portfolio_opt.R` for the 4-strategy meta-allocator (PSO vs HRP vs equal-weight). HRP weights stk_max=13%, stk_drif=17%, fac_max=40%, fac_drif=30%. **HRP Sharpe -0.63 vs PSO 0.63 on training** — meta-allocator is the wrong universe for HRP because it diversifies into structurally loss-making stock strategies.
- **#114 Phase 2 (`cde2ea2`)** — `portfolio_longshort_hrp()` + `stk_max_portfolio_hrp` + `stk_max_hrp_comparison` in `R/plan_stock_backtest.R` (191 lines). Per-leg HRP fits with rolling 36-month covariance, insufficient-history fallback to equal-weight (<3 tickers), actual weight-change turnover replaces hardcoded 0.80. **Sharpe improved across all periods (Training -1.34→-1.06, Testing -1.32→-0.81, Validation -0.92→-0.61, Full -1.33→-1.04). Turnover 0.80→0.63 (-21%). Cost drag 22%→18%.** Both weightings remain unprofitable in absolute terms.
- **#143 gap #3 (`796a42b`)** — `apply_adv_cap()` + `stk_monthly_adv` + `stk_max_portfolio_hrp_adv` + `stk_max_adv_cap_impact` (226 lines). 10% ADV cap as a hard constraint on per-stock notional. **Sharpe improved everywhere (Full -1.04→-0.86, Validation -0.61→-0.26).**
- **#158 filed** — Solana APIs investigation (CoinEdition comparison, including tokenised-equity / DEX depth as ADV proxy).

### Failed Approaches

- **HRP on the 4-strategy meta-allocator (Phase 1)** — HRP saw 4 series with similar covariance structure and diversified into the worst (loss-making) stock-level strategies. PSO discriminates by Sharpe; HRP only by covariance. Lesson: HRP belongs at the leg level (cross-section of stocks), not at the strategy level.
- **`%||%` chain on `HierPortfolios::HRP_Portfolio()` output** — defensive `w$w %||% w$weights %||% w[[1]]` was unnecessary; output is a clean data.frame with `$weights` column. Use directly.
- **ADV cap as a cost-reduction lever** — counter to thesis: cap *raised* turnover (0.633→0.734) and monthly cost (1.52%→1.72%), yet still improved Sharpe by 0.18. The cap forces redistribution against HRP's concentration gradient; that's a marginal signal improvement, not a cost reduction. ADV cap is a hard constraint; reducing turnover requires Almgren-style cost modelling instead.
- **Tinsley issue almost duplicated** — `gh issue list --search` caught #143 already audits the same article; extended via comment instead of filing. Lesson worth keeping: search before filing.
- **`t update` blocked by untracked LOCAL wiki file** — `knowledge/wiki/cakici-2024-coverage-audit.md` is intentionally untracked per `wiki-storage-policy`; had to `git stash --include-untracked` then pop. Tooling friction worth a future hook.

### Accuracy / Metrics

- **Strategy Sharpe progression on `stk_max` long-short (Full Period):** PSO EW -1.33 → HRP -1.04 → HRP+ADV-cap -0.86. Three sequential improvements, +0.47 cumulative Sharpe, **never crossed zero.**
- **Validation period (2023-01-01 onwards, ~3.5 yrs):** Sharpe -0.92 → -0.26 (largest delta, also smallest sample — confidence interval wide; seal now broken by the comparison itself).
- **Cost drag remains 17-18%/year** after both interventions. Floor on cost-side optimisation reached.
- **Issues:** #114 open with two phase-summary comments; #143 open with gap #3 implementation comment; #158 newly filed.
- **Push state:** 4 commits to origin/main (`2105727`, `5e72205`, `cde2ea2`, `796a42b`).

### Known Limitations

- **Stock-level Sharpes still survivorship-biased** (#150 unresolved). Three rounds of portfolio-construction tuning have hit a floor of negative Sharpe — the gross-alpha input is overstated, so further cost-side or allocation work cannot change the conclusion until the universe is rebuilt with delisted tickers.
- **Validation seal broken on `stk_max` family** — the comparison sequence has now used validation as a tuning signal. Future deployment of any `stk_max` variant requires either (a) a new untouched validation window or (b) explicit acknowledgement in the vignette.
- **HRP Phase 2b (DRIF) and Phase 3 (HERC/DHRP) deferred** — likely to reproduce the Phase 2 pattern (improve Sharpe but stay negative) until #150 is resolved.
- **TRP / `tdaverse` track deferred** — Phase 6 (Wasserstein regime detector via `phutil`) promoted as the only `tdaverse` application that doesn't require profitable underlying strategy. Speculative; not on critical path.
- **ADV cap is single-fill model** — cap residual is dropped, not spilled to next period. Realistic for retail; understates effective trade size for larger AUM.

### Next Session

- **Pivot to #150 (survivorship bias in 660-stock universe).** Rationale: cost-side ceiling reached on `stk_max`; gross alpha is the next variable; #150 says it's overstated. Until fixed, every leaderboard Sharpe is biased upward.
- **Fresh context.** Burn this session: ~$294 → projected ~$687 (137% of $500 cap). Quadratic loop cost on continuation. #150 work in `R/plan_universe.R` + HuggingFace fetch scripts has near-zero overlap with this session's portfolio-optimisation files; nothing in this conversation accelerates it.
- **#158 follow-up** — when bandwidth permits, smoke-test 1-2 Solana finalists for tokenised-equity coverage.

## 2026-05-13

### Pipeline reliability + registry expansion (11 commits, 7 issues touched)

**Context:** Continuation from 2026-05-12's PR-merge cycle (#150, #151, #147). Today's session: Group A pipeline-hygiene fixes that compound the prior session's work, then Group H quick wins (#140 DAG interactivity), then Group B's #148 alignment-helper completion + a registry expansion that surfaced 10 latent silent-join bugs.

**Completed:**

- **#152 (`0db2687`)** — `dv_join_key_types` and `dv_monthly_convention` validators pinned to producer dependencies via `tar_target_raw + deps`; replaced forbidden `tar_read_raw()` with `readRDS()` pattern; extracted `check_monthly_convention()` for testability. **32 PASS** tests.
- **#145 layer 2 (`7420288`)** — `cb_data` falls back to direct `fredr::fredr()` for the 4 Fed series (WALCL, WSHOMCB, DPCREDIT, TOTRESNS) absent from upstream HuggingFace `macro_daily.parquet`. **9336 rows, all 4 series, 1959-01-01 to 2026-05-11.** Unblocked 5 cascade targets.
- **#153 (closed not-a-bug)** — Both glmnet/xgboost already in `tproject.toml + flake.nix`; root cause was `tar_make()` invoked from outer dev shell. Documented `nix develop` requirement.
- **#140 labeled edges (`5c52e44`)** — `addEdgeInteractivity()` framework + 2 labeled-edge tooltips/click-links in `docs/causal-diagrams.js`.
- **#140 unlabeled edges, Option B (`193223a`)** — Floating popups for **55 unique unlabeled edges** across 5 DAGs. Mermaid v11 `id="L_<SRC>_<DST>_<idx>"` parsing with underscore-aware split. Single shared popup div, midpoint-positioned via base64 `data-points`, dark/light themed via `--bs-*` vars.
- **#148 + #146 (`869a019`, `18e6fe5`)** — `asof_lookup()` (duckplyr ASOF JOIN wrapper for level lookups, distinct from `align_period()` aggregation). New `dv_frequency_alignment` validator. **fals_tail_independence verified at 254 complete monthly rows** (≥100 acceptance criterion). 35+45 PASS tests.
- **#118 (audit page, not closed)** — Wiki page at `knowledge/wiki/cakici-2024-coverage-audit.md` (162 lines, 8 keyword categories, 3 AI-inferred markers, Sources block). Result: **2 Implemented / 5 Partial / 1 Not implemented (multiverse)**. LOCAL only per `wiki-storage-policy`.
- **#157 filed** — Follow-up from #118: 2^4 multiverse on `plan_drif.R` (~1d). Captures the audit's #1 recommended action.
- **Registry expansion (`4047019`, `4444426`, `1cf28ae`)** — `dataset_registry()` 11 → 34 entries. Validator caught 10 POSIXct producers; all coerced to Date at producer side via `mutate(date = as.Date(date, tz = "UTC"))`. Final state: **34/34 series Date class, 0 frequency violations.**

### Failed Approaches

- **wiki-curator agent for #118 stalled** at the file-write step (600s watchdog, no file produced). Took it over directly — was cheaper than respawning. Lesson: large research-then-write tasks may exceed wiki-curator's productive window; consider splitting into two prompts (research, then write).
- **Initial registry expansion added `fm_monthly` and `jst_raw` without verification** of `date` column presence. Validator (correctly) aborted. Removed both; documented inline why. Lesson: agents should verify schema before adding to registries — wrote no test for this ahead of time.

### Accuracy / Metrics

- **Tests:** +80 PASS (test-utils_align: 35, test-utils_validation: 45).
- **Validator coverage:** `dv_join_key_types` 9/9 ok pre-expansion → 24/34 → **34/34 ok** post-fix. `dv_frequency_alignment` 34/34 ok, 0 violations.
- **Bugs eliminated:** 10 latent POSIXct silent-join bugs + 14 cb_* cascade errors + ~8 dv_* false negatives = **~32 fewer error surfaces in `tar_make()`**.
- **DAG interactivity:** 100% edge coverage across 5 DAGs (57 of 57 enumerated edges have metadata).

### Known Limitations

- **Stock-level DRIF (#117) blocked on #150 Option A** (PIT data acquisition). Stock-level Sharpes remain survivorship-biased until then.
- **Multiverse / specification-curve absent** (largest paper gap — tracked as #157).
- **`fm_monthly` not in registry** — uses `last_date` not `date`; re-add when registry schema gains `date_col` field, or fm_monthly is renamed.
- **`commodities_returns`, `crypto_returns`, `ecb_raw`** — registry candidates excluded today (unbuilt cache or multi-frequency schema). Not tracked separately (low value).

### Next Session

- Resume on either #157 (multiverse, ~1d) or remaining #118 audit follow-ups (citations ~1h, horizon-decay table ~3h).
- Burn was at 42% / projected 148% of cap by week-end after today; tomorrow ideally a rest day to pull projection back under cap. Resume Wed+ at ≤ ~$95/day.

## 2026-05-11

### Week 1 Execution: Website Fixes + Research Findings (Issues #128, #129, #119, #123, #127)

**Context:** Post-momentum decomposition (#121 complete), executed Week 1 plan via parallel git worktrees with appropriate model/skill allocation.

**Completed (4 PRs merged, all tests pass):**

1. **PR #130: Fix 404 errors** (Issue #128, quick-fix/haiku, 30 min)
   - Added explicit anchor IDs to examples.qmd: `{#equity}`, `{#crypto}`, `{#macro}`, `{#factors}`
   - Expanded falsification.qmd explanations: HAC t, Naive Sharpe, Alpha %, Alpha t, R²
   - All anchor links now resolve correctly

2. **PR #131: Improve leaderboard vignette** (Issue #129, general-purpose/sonnet, 45 min)
   - Fixed caption color: #ddd (white) → #888 (gray) for dark mode
   - Added numeric right-justification via `.dt-right` CSS class
   - Added CVaR 95% column, Years column (Training/Testing periods)
   - Added Wikipedia link for elastic net
   - Improved pros/cons section structure in stock-backtest.qmd

3. **PR #132: Volatility spike analysis Phase 1** (Issue #119, general-purpose/sonnet, 2.5 hours)
   - Created R/volatility_spike_analysis.R (140 lines, 4 functions):
     - detect_volatility_spikes(), calculate_spike_duration(), calculate_reversal_speed(), compare_spike_frequency()
   - Created R/plan_volatility_spikes.R (8 targets)
   - **Finding:** Only 2 spikes detected in 2014-2024 (April 2025, August 2024) using VIX ≥ 1.5× 63-day MA threshold
   - **Discrepancy:** Alpha Architect paper claims 3× frequency increase — parameter sweep needed

4. **PR #133: Regime-dependent momentum** (Issue #123, general-purpose/sonnet, 3.5 hours)
   - Created R/regime_momentum.R (374 lines, 4 functions):
     - classify_vix_regimes() (Calm <20, Elevated 20-30, Spike >30)
     - partition_returns_by_regime(), regime_conditional_performance(), compare_strategies_by_regime()
   - Created R/plan_regime_momentum.R (13 targets originally, 12 after duplicate fix)
   - **CRITICAL FINDING: Decomposition fails in ALL regimes**
     - Baseline (total 12m): Calm Sharpe 0.63, Elevated 0.15, Spike -1.44
     - Paper decomposed: Calm -0.44, Elevated -0.46, Spike -0.66 (ALL NEGATIVE)
     - Data-Driven: Calm -0.15, Elevated -0.66, Spike -0.86 (ALL NEGATIVE)
     - Conservative: Calm -0.27, Elevated -0.81, Spike -0.85 (ALL NEGATIVE)
   - **Regime rescue test: 0/9 positive Sharpe ratios (0%)**
   - **Conclusion: ABANDON momentum decomposition entirely**
   - **Actionable insight:** Baseline Sharpe 0.63 in calm (65% of time) suggests regime-conditional allocation of baseline momentum

5. **Issue #127 comment: Update ROI tracker** (manual, 15 min)
   - Documented #121 results: Expected +10-20% Sharpe, Actual -0.39 to -0.44 (ALL negative), Delta -0.40 to -0.45
   - Lesson: Academic persistence (rank IC) ≠ Portfolio profitability (net Sharpe after costs)

**Post-Merge Fix (commit 5cdfe74):**
- Fixed duplicate target error: Both plan_volatility_spikes and plan_regime_momentum defined `vix_daily`
- Refactored plan_regime_momentum to reuse vix_daily from plan_volatility_spikes
- Verified all 12 regime momentum targets + 8 volatility spike targets build successfully
- Confirmed key finding via targets: `regime_rescue_test$any_positive = FALSE` (0 out of 9 positive)

**Execution Notes:**
- Parallel worktree execution: #128 + #129 (simultaneously), then #119, then #123
- Total time: ~7 hours (vs 12-17 estimated — faster via parallelization)
- All PRs merged to main, pipeline validated, no regressions

**Next Steps (Optional Week 2):**
- Option A: Regime-based allocation Phase 2 (#123) — apply Zakamulin continuous allocation to baseline
- Option B: Volatility spike parameter sweep (#119 Phase 2) — test 1.2×-1.5× thresholds, extend to 1990
- Option C: Knowledge audit + DRIF (#118 + #117)
- Option D: Pivot to Macro/GenAI (#124, #120)

---

## 2026-05-10

### Completed
- **Momentum decomposition Phase 2: Optimized Signals** (Issue #121, Phase 2: 3 hours)
  - **Critical Finding: Decomposition destroys value. All component-based strategies have negative Sharpe ratios.**
  - Extended R/momentum_decomposition.R: +3 functions (192 lines)
    - build_optimized_signals(): Construct paper/data-driven/conservative signals from components
    - backtest_momentum_signals(): Long-short portfolio simulator with transaction costs
    - summarize_backtest_performance(): Sharpe, drawdown, turnover metrics
  - Extended R/plan_momentum_decomposition.R: +6 targets
    - optimized_signals: All four variants (baseline, paper, data_driven, conservative)
    - backtest_results: Monthly returns with 0.153% per-trade costs (from #125)
    - performance_summary: Performance table with Sharpe, annual return, max DD, turnover
    - cumulative_returns_plot: Cumulative return curves (log scale)
    - rolling_sharpe_plot: 36-month rolling Sharpe
    - turnover_analysis: Mean/median/min/max turnover by strategy
  - **Backtest Results (2000-2026, 529 stocks, 742 months):**
    - Baseline (Total 12m LTR): Net Sharpe 0.054, Gross 0.069, Turnover 7.9%
    - Paper (Style + Industry): Net Sharpe **-0.337**, Gross -0.232, Turnover 26.4%
    - Data-Driven (Industry + Stock-Spec): Net Sharpe **-0.342**, Gross -0.229, Turnover 27.5%
    - Conservative (Industry Only): Net Sharpe **-0.386**, Gross -0.282, Turnover 26.4%
  - **Why Decomposition Failed:**
    1. Turnover explosion: Decomposed signals 3.3x more volatile (26% vs 8% monthly)
    2. Signal dilution: Isolating components breaks covariance structure (they're not independent)
    3. Persistence ≠ Profitability: Rank IC of 0.02-0.03 too weak after costs
    4. Baseline momentum too weak: Sharpe 0.05 leaves nothing to optimize
  - **Conclusion:** Do NOT decompose momentum. Use total 12m return if momentum is required.
  - Based on: De Boer, Gao, Montminy (2025) SSRN 5716502
  - Next: Optional deep dive (correlation analysis, regime effects) OR move to #119/#123
- **Momentum decomposition infrastructure** (Issue #121, Phase 1: 2 hours)
  - Created R/momentum_decomposition.R: 4 functions
    - hd_ff_factors(): Download Ken French 5-factor, momentum, industry data
    - decompose_momentum(): Split 12-month returns into 5 components (beta, style, industry, stock-specific)
    - compute_persistence(): Measure component predictive power (rank IC by horizon)
    - plot_persistence_by_component(): Visualize IC by component and forecast horizon
  - Created R/plan_momentum_decomposition.R: 10 targets
    - Download: ff_5factors, ff_momentum, ff_industries_12
    - Decompose: stock_returns_monthly → momentum_components
    - Analyze: persistence_metrics, persistence_plot, momentum_comparison
    - Validate: sum of components ≈ total return
    - Dispersion: cross-sectional dispersion over time
  - Integrated into docs/_targets.R (source + plan call)
  - Based on: De Boer, Gao, Montminy (2025) SSRN 5716502
  - Next: Test pipeline (download data, run decomposition, validate vs paper findings)
- **Transaction cost audit** (Issue #125, Phase 1: 3 hours)
  - Completed: Cost Audit Phase 1 - measured actual liquidity
  - LTR universe: 529 stocks (not 51 as comment said)
  - Liquidity classification (2024 ADV):
    - Tier 1 (Mega >$1B ADV): 26 stocks (5%) - cost 0.02%
    - Tier 2 (Large $100M-1B): 237 stocks (45%) - cost 0.05%
    - Tier 3 (Mid $10M-100M): 258 stocks (49%) - cost 0.25%
    - Tier 4 (Small <$10M): 8 stocks (1.5%) - cost 0.50%
  - Realistic cost: 0.153% per trade (equal-weight average)
  - Current LTR: 0.10% (53% too low)
  - Expected Sharpe impact: -15 to -25% (recorded in #127)
  - Decision: Skip Phase 2 re-run (user chose to move to #121)
- **Issue grouping and prioritization** (30 min)
  - Created 5 thematic groups: Momentum Optimization, Risk Management, ML/GenAI, Diversification, Research Exploration
  - Week 1 priority: #125 (cost audit BLOCKING), #121 (momentum decomposition), #123 (regime allocation)
  - 30-40 hour first week roadmap
- **Issues created:**
  - #119: Momentum volatility spikes (Mozes 2026)
  - #120: StockGPT transformer (Mai 2024)
  - #121: Momentum decomposition (De Boer et al. 2025)
  - #122: Causal crash prediction (Ranjan 2025)
  - #123: Regime-dependent allocation (Zakamulin 2026)
  - #124: Curve trades with macro signals (Macrosynergy 2026)
  - #125: Transaction cost reality check (StratProof 2026)
  - #126: Quantocracy roundup (May 3, 2026)
  - #127: Research ROI tracking (meta-validation issue)

### Failed Approaches
- Tried to load historicaldata package in global shell: package not available. Ken French functions will download directly from web.

### Accuracy / Metrics
- Cost audit: 529 stocks analyzed, 4 liquidity tiers, 0.153% measured cost (vs 0.50% rule default)
- Momentum decomposition: 4 functions, 10 targets, integrated into pipeline
- Issue creation: 9 issues in ~45 minutes

### Phase 1 Testing Complete (4-5 hours)
- ✅ Downloaded Ken French data (753 months, 1963-2026)
- ✅ Fixed 5 pipeline issues:
  - RcppRoll dependency (add to tar_option_set packages)
  - Date convention (month-end vs month-start → year-month join)
  - Forward return calculation (use slider::slide_dbl)
  - Cache path and parquet writing (use tools::R_user_dir + saveRDS)
- ✅ Successfully decomposed 209,065 stock-months (529 tickers)
- ✅ Computed persistence metrics (rank IC by horizon)
- **Results:**
  - Industry momentum: Persists (IC=0.028 at 1m, t=2.95 ***)
  - Stock-specific: Persists at ALL horizons (unexpected - should revert)
  - Style: Weak (IC≈0, not significant - should be strong)
  - Beta: Not robust (IC≈0 as expected)
- **Discrepancies from De Boer et al. (2025):**
  - 2/4 components match expectations (Industry ✅, Beta ✅)
  - Stock-specific persists instead of reverting (opposite of paper)
  - Style momentum weak instead of strong
  - Likely due to: time period (2000-2026 vs pre-2000), universe size (529 vs broader)

### Known Limitations
- Decomposition findings differ from paper on Style and Stock-Specific components
- Methodology differences not fully investigated (attribution approach, industry classification)
- Forward return alignment should be verified (month T signal → T+1 to T+h return)

## 2026-05-09

### Completed
- **Weekly data poll workflow fixed** (8 iterations, PR #112): all 5 sources now running
  - Missing R packages: added httr2, pkgload, quantmod, DBI, duckdb, duckplyr, ggplot2
  - System dependencies: libcurl4-openssl-dev, libuv1-dev
  - Kalshi safe_num() zero-length bug fixed
  - Directory creation: `mkdir -p data/raw`
  - Git force-add: `git add -f data/raw/` (gitignored)
  - GitHub Actions permissions: `contents: write`
  - Parallel push race: `git pull --rebase origin main` before push
  - FRED_API_KEY secret confirmed by user
- **VVIX analysis** (Tier 2 gap #105: volatility coverage 70% → 90%)
  - Created R/vvix_analysis.R: 4 functions (classify_vvix_regimes, vix_stability_metrics, detect_vol_transitions, enhanced_crisis_detection)
  - Created R/plan_vvix.R: 7 targets (vvix_daily, vvix_regimes, vix_stability, vol_transitions, enhanced_crisis, 3 display targets)
  - Integrated into docs/_targets.R (commented out missing Tier 1 source files for now)
- **JST Macrohistory dashboard deployed** (Phase 3 complete)
  - Rendered docs/jst-dashboard.qmd: 6 sections (pervasiveness table, heatmap, crisis timeline, crisis table, overview, data notes)
  - Fixed YAML !expr syntax (wrapped in single quotes)
  - Converted gt tables → DT::datatable() (gt package not available in global shell)
  - Built JST targets: jst_raw, jst_equity_premium, jst_pervasiveness, jst_crises, jst_summary
  - Created knowledge/wiki/jst-dms-comparison.md: documents JST as free DMS alternative, survivorship bias correction (3-4% equity premium reduction), cross-geography pervasiveness findings
  - Deployed to branch sonnet-0508, will be live at https://johngavin.github.io/historical/jst-dashboard.html after PR merge
- **Issues created:**
  - #114: European UCITS wrappers (EQQQ/CNDX) — investigate via IBKR
  - #115: Financial planning optimization models — multi-objective, dynamic programming, integration premium
  - #116: Quantitativo 5-paper comparison — DRIF, momentum decomposition, cross-asset risk, order-flow entropy, StockGPT review

### Failed Approaches
- Tried rendering jst-dashboard.qmd with gt package: `Error: no package called 'gt'` — global dev shell doesn't have gt. Fixed by converting all gt tables to DT::datatable()
- Tried running tar_make() with missing Tier 1 source files (liquidity.R, tracking_error.R, regime_correlations.R, tail_keff.R, plan_integration.R): build failed. Commented out missing source() lines in docs/_targets.R — TODO: create these files for real Tier 1/2 integration
- First 6 workflow runs failed sequentially (missing packages, system deps, directory, git permissions, parallel race) — each fixed one-by-one with evidence table showing progress

### Accuracy / Metrics
- Weekly poll: 5/5 sources now operational (kalshi, ecb, guardian, commodities, cboe_vol)
- JST targets: 6/6 built successfully (jst_raw cached, 525 KB; 18 countries, 1870-2020)
- VVIX targets: 7 targets defined (not yet built — depends on cboe_vol.parquet from weekly poll)
- Dashboard sections: 6/6 implemented (100% of Phase 3 scope)
- Wiki pages: +1 (jst-dms-comparison.md, 400+ lines)

### Known Limitations
- Weekly poll not yet validated end-to-end (waiting for next Saturday cron or manual trigger)
- VVIX targets not built (cboe_vol.parquet doesn't exist yet — first poll hasn't run)
- JST dashboard extensions planned but not implemented: USA/FF comparison chart, housing returns analysis, crisis-regime performance
- Tier 1/2 source files (liquidity.R, tracking_error.R, etc.) still missing — need to create for real integration
- roborev: 51 failed findings, 14 addressed (pre-existing, not from this session)

## 2026-05-08

### Completed
- **Tier 1 Data Integration Test** (PR #111): All 4 gap implementations validated via fast test pipeline
  - Created `_targets_integration_test.R` — mock strategy returns, validates in <20s
  - 14/14 integration targets passing: tracking error/IR, regime correlations, tail K_eff, contagion detection
  - Fixed date type mismatch: Changed `as.Date()` → `as.POSIXct()` to match `hd_ohlcv()` output
  - Fixed VIX granularity: `regime_correlations()` now expands monthly VIX to daily via year-month join
  - Updated `knowledge/LOG.md` with completion entry
  - All changes committed and pushed to `feature/tier1-data-integration`

### Failed Approaches
- Tried using `consolidated_equity` in docs pipeline — doesn't exist there, docs pipeline uses `hd_ohlcv()` directly
- Tried helper function with `{{ ret_col }}` for column selection — scoping issues with tidyeval, simplified to inline transformations
- Tried `date >= as.Date("2020-01-01")` for TLT — returns all NAs (TLT starts ~2010), changed to 2010-01-01
- Tried left_join by `date` for daily returns + monthly VIX — most days don't match month-end, resulted in NAs. Fixed with year-month join.

### Accuracy / Metrics
- Integration test: 14/14 targets pass, <20s runtime (vs 10+ min for full pipeline)
- Test targets: 8 core + 6 display (tables/plots)
- Full pipeline attempted: 88 targets completed before 600s timeout
- roborev: 42 failed, 14 addressed (33% resolution rate, unchanged from session start)

### Known Limitations
- Full pipeline integration targets not yet validated — strategy feature engineering (stk_drif_features, etf_a_features) takes >10 min
- Integration test uses mock data — real integration with actual strategy portfolios still needs validation
- Integration plan (`R/plan_integration.R`) wired to docs pipeline but not yet exercised end-to-end

### Known Limitations
- Weekly poll not yet validated end-to-end (waiting for next Saturday cron or manual trigger)
- VVIX targets not built (cboe_vol.parquet doesn't exist yet — first poll hasn't run)
- JST dashboard extensions planned but not implemented: USA/FF comparison chart, housing returns analysis, crisis-regime performance
- Tier 1/2 source files (liquidity.R, tracking_error.R, etc.) still missing — need to create for real integration
- roborev: 51 failed findings, 14 addressed (pre-existing, not from this session)
>>>>>>> c9c1353 (chore: session-end 2026-05-09 — CHANGELOG + CURRENT_WORK)
## 2026-05-07

### Completed
- Closed 12 issues: #85 (tooltips), #86 (source links), #87 (leaked code), #88 (ECB 29 series), #89 (Guardian NLP), #90 (ggplot2 audit), #92 (tab scroll), #93 (CISS dashboard), #94 (LR layout), #95 (clickable nodes), #48 (Bloomberg closed), #98 Phase 1 (JST)
- ECB: 29 series via SDMX REST API, CISS sub-market decomposition, VIX correlations (r=0.75), wired into European overlay
- Guardian NLP: Phase 1-3a complete. sentimentr body text sentiment: no predictive signal (next-month r<0.08)
- CISS overlay: 4/5 EU ETFs improve Sharpe ratio (Euro Stoxx 50: 0.56→1.03). New european-overlay.qmd dashboard deployed
- JST Macrohistory: hd_jst() + hd_jst_variables() — 18 countries, 1870-2020, 59 variables
- Knowledge base: knowledge/ with 4 wiki pages (ecb-data, ciss-stress, guardian-nlp, priced-in-signals)
- roborev: .roborev.toml, codex wrapper fixed, roborev-resolution rule + template in llm project
- Weekly scheduler: 5 active sources (kalshi, ecb, guardian, commodities, cboe_vol)

### Failed Approaches
- Guardian keyword counts as trading signal: all |r|<0.15 with SP500. Priced in by publication time.
- Guardian body text NLP (sentimentr): same-month r≈0.27 (contemporaneous) but next-month r<0.08 (no prediction). FinBERT not recommended — constraint is timing, not NLP quality.
- roborev `--agent codex` silently fell back to claude-code because codex not in nix PATH. Fixed with /usr/local/bin/codex wrapper + codex_cmd config.
- HICP core inflation series key (ICP/M.U2.N.TOT_X_NRG_FOOD.4.ANR) returns 404 from ECB API.

### Accuracy / Metrics
- roborev: 6/19 addressed this week (32% resolution rate, was 0%)
- ECB: 29/29 series fetching, 163K total observations
- CISS equity vs VIX: Spearman r=0.751 (6,653 daily obs)
- Guardian: ~289 business articles/month, 6 keywords tested

### Session 2 (continued)

#### Completed
- #96 closed: Hover tooltips on diagram nodes — 38 tooltips via SVG `<title>`, definitions + source refs
- #98 Phase 2: plan_jst.R — 6 targets (equity premium, pervasiveness, FF comparison, crises, summary)
- European Overlay + Falsification added to site navigation (index.qmd)
- flake.nix: usethis added (from stash)
- `.claude/` directory tracked — 18 project-specific rules now version controlled
- **Destructive filesystem guard**: Enforced protection via PreToolUse:Bash hook
  - Protected paths: .claude/, R/, packages/, data/, *.nix, _targets, knowledge/
  - User must provide 4-digit confirmation code to proceed
  - Audit logs: ~/.claude/logs/destructive_blocked.log, destructive_confirmed.log

#### Failed Approaches
- Suggested `rm -rf .claude/` to clear roborev working tree error — **wrong**, .claude/ is critical project config
- Suggested gitignoring .claude/ — **wrong**, must be tracked for reproducibility
- Both mistakes caught by user. Lesson: rules are advisory, not enforced. Led to implementing the destructive filesystem guard hook.

#### roborev
- 5 new failed reviews from this session's commits (codex errors)
- Background refine process failed due to untracked files — roborev requires clean working tree

### Known Limitations
- roborev backlog: ~90 open reviews (continue burn-down with codex in terminal)
- ECB frequency mismatch: daily/monthly/business-daily series need frequency-aware joins (roborev high-severity finding)
- hd_ecb() missing req_timeout()/req_retry() (roborev high-severity finding)
- VSTOXX has no free API — CISS equity is best available proxy
- #98 Phase 3: JST dashboard vignette (long-run returns comparison) not started

## 2026-05-01

### Completed
- RAFI fundamental-weighted strategy (#75): plan_rafi.R (7 targets) — synthetic RAFI via FF factors (50% HML + 30% SMB + 20% Mom). Negative result: OOS Sharpe -0.19 vs market 0.94. Pre-2000 Sharpe 1.66, post-2000 Sharpe 0.24 — 85% decay consistent with value crowding.
- CRPS forecast evaluation (#66): hd_crps_empirical(), hd_crps_normal(), hd_crps_skill(), hd_brier_score(), hd_horizon_skill() + plan_forecast_eval.R (6 targets). Distributional scoring without scoringRules dependency.
- Daloopa data access test (#78, #79): downloaded FinRetrieval HuggingFace dataset (500 questions, Parquet). Our coverage: 0% — all questions require company fundamentals. Documented 4-phase integration plan.
- Issues closed: #55, #56, #58, #62 (from prior session, formally closed with comments)

### Failed Approaches
- RAFI FF regression R²=100%: tautological — we constructed returns from FF factors then regressed on the same factors. Real test needs actual RAFI ETF returns (PRF, FNDF).
- Mom factor not available monthly in our dataset — only daily. Fixed by compounding daily Mom returns to monthly.
- RAFI OOS (2010+) negative CAGR for all variants — value/size premium has decayed post-2000.

### Findings: RAFI Strategy (#75)

| Strategy | Pre-2000 Sharpe | Post-2000 Sharpe | Decay |
|----------|:-:|:-:|:--:|
| RAFI Composite | 1.66 | 0.24 | -85% |
| Revenue Proxy (HML) | 0.87 | 0.11 | -87% |
| Equal-Weight (SMB) | 0.55 | 0.09 | -84% |
| Benchmark (Market) | 0.83 | 0.53 | -36% |

Verdict: RAFI premium existed historically but has been arbitraged away. Cap-weighted market dominates post-2000.

### Findings: CRPS Forecast Evaluation (#66)

CRPS skill (negative = worse than naive unconditional distribution):

| Strategy | CRPS Model | CRPS Naive | Skill | Obs |
|----------|:----------:|:----------:|:-----:|:---:|
| DRIF | 0.016 | 0.016 | -0.04 | 679 |
| Factor MAX | 0.014 | 0.013 | -0.06 | 728 |
| LTR | 0.027 | 0.025 | -0.05 | 243 |

Brier score (directional probability calibration):

| Strategy | Brier Model | Brier Naive | Skill | Win Rate |
|----------|:----------:|:----------:|:-----:|:--------:|
| DRIF | 0.258 | 0.241 | -0.07 | 61.1% |
| Factor MAX | 0.257 | 0.250 | -0.03 | 59.3% |
| LTR | 0.272 | 0.263 | -0.03 | 54.9% |

Horizon skill (correlation of strategy signal with forward SPY returns):

| Strategy | 1d | 5d | 10d | 21d |
|----------|:---:|:---:|:----:|:----:|
| DRIF | -0.010 | -0.016 | -0.031 | -0.045 |
| Factor MAX | +0.019 | +0.045 | +0.068 | +0.102 |
| LTR | -0.023 | -0.057 | -0.084 | -0.129 |

Verdict: No strategy beats the unconditional distribution as a probabilistic forecast. Factor MAX shows weak positive correlation at longer horizons (r=0.10 at 21d). DRIF and LTR are contrarian — negatively correlated with forward market returns by construction.

### Findings: Daloopa Data Coverage (#78, #79)

FinRetrieval benchmark (500 questions, freely available on HuggingFace):

| Category | Questions | Our coverage |
|----------|----------:|:------------:|
| income_statement | 126 | 0% |
| balance_sheet | 119 | 0% |
| cash_flow | 93 | 0% |
| operational_kpis | 78 | 0% |
| guidance_outlook | 43 | 0% |
| segments_geography | 28 | 0% |
| market_data | 8 | Partial |
| valuation_metrics | 5 | 0% |

Our `hd_*()` pipeline (OHLCV, FRED macro, FF factors, CBOE vol) has zero overlap with fundamentals-focused questions. Daloopa API would fill the gap — 4-phase integration plan documented in #78.

### Accuracy / Metrics
- Pipeline: ~270 targets across 31 plan files
- 2 new plan files: plan_rafi.R, plan_forecast_eval.R
- 5 new exported pkg functions: hd_crps_empirical, hd_crps_normal, hd_crps_skill, hd_brier_score, hd_horizon_skill
- 13 open issues remaining (was 16 at session start)

### Known Limitations
- RAFI FF regression is tautological — need real RAFI ETF data (PRF, FNDF) for genuine falsification
- scoringRules not in nix shell — CRPS/Brier implemented manually (correct but less battle-tested)
- Daloopa API requires free signup — not yet tested
- fe_horizon target uses SPY forward returns — may not align well with monthly strategy signals

## 2026-04-30 (session 2)

### Completed
- Tail-weighted independence test (#55): hd_tail_keff(), hd_tail_dependence(), hd_drawdown_overlap() + fals_tail_independence target — crisis vs calm K_eff, pairwise tail dependence, drawdown synchronisation
- Enhanced Kelly variants (#56): hd_kelly_bayesian(), hd_kelly_rolling(), hd_kelly_bounded() + plan_kelly_variants.R (6 targets) — fractional sweep (25/50/75/100%), Bayesian posterior, rolling window, survival-constrained
- Shadow trades (#62): hd_shadow_trades() + plan_shadow_trades.R (5 targets) — parallel entry/exit timing analysis with offset grid for signal quality diagnostics
- European risk overlay (#58): plan_european_overlay.R (7 targets) — US VIX regime applied to 5 EU ETFs (EXSA.DE STOXX 600, FEZ Euro Stoxx 50, VGK FTSE Europe, EWG Germany, EWQ France). Negative result.
- Daloopa API gap analysis (#78): documented 4 MCP tools, 12 REST endpoints, 24 Claude Code skills; cross-linked to #2 (public API)
- Daloopa finretrieval evaluation (#79): LLM retrieval benchmark for financial QA
- Issues created: #78, #79

### Failed Approaches
- Yahoo Finance v7/download CSV endpoint returns 401 Unauthorized — switched to v8/chart JSON API
- Yahoo v8 chart API with simplifyVector=TRUE flattens nested indicators structure — must use simplifyVector=FALSE
- Yahoo returns mismatched timestamp/adjclose lengths for EXSA.DE (4655 vs 4652) — truncate to shorter
- EU ETFs (FEZ, VGK, EWG, EWQ, EXSA.DE) not in HuggingFace equity dataset — must fetch via Yahoo API directly
- quantmod not available in nix develop shell — used raw Yahoo JSON API instead
- POSIXt/Date mismatch: rsc_regime$date is POSIXct, factor dates are Date — inner_join produces 0 rows silently. Fix: as.Date() coercion on all date columns before joining

### Findings: European RSC Overlay (#58)

**Verdict: Negative result — same conclusion as US SPY overlay.**

OOS comparison (2020 onward):

| ETF | Strategy | CAGR (%) | Vol (%) | Max DD (%) | Sharpe |
|-----|----------|-------:|-------:|----------:|-------:|
| SPY (US) | Buy & Hold | 14.3 | 20.5 | -33.7 | 0.76 |
| SPY | RSC Overlay | 10.3 | 17.2 | -31.3 | 0.66 |
| EXSA.DE (STOXX 600) | Buy & Hold | 10.6 | 17.4 | -35.9 | 0.67 |
| EXSA.DE | RSC Overlay | 9.1 | 15.3 | -32.9 | 0.65 |
| FEZ (Euro Stoxx 50) | Buy & Hold | 11.0 | 23.6 | -39.0 | 0.56 |
| FEZ | RSC Overlay | 7.1 | 20.9 | -35.7 | 0.44 |

FF5+Mom falsification:

| ETF | Alpha (% ann) | Alpha t-stat | R² (%) |
|-----|-------------:|-------------:|-------:|
| EXSA.DE (STOXX 600) | +4.04 | 1.38 | 15.0 |
| FEZ (Euro Stoxx 50) | -4.70 | -1.70 | 62.2 |
| VGK (FTSE Europe) | -5.14 | -2.06 | 65.7 |
| EWG (Germany) | -4.14 | -1.47 | 56.8 |
| EWQ (France) | -4.19 | -1.59 | 55.7 |

Key: STOXX 600 is closest to neutral (Sharpe 0.67→0.65, small drag). All other EU ETFs show clear negative impact. The overlay reduces vol 2-3% and max DD 2-5% but sacrifices more CAGR. STOXX 600 low R² (15%) suggests US FF factors are a poor fit — European-specific factors may be needed. Negative alpha on US-listed EU ETFs (FEZ, VGK) is -4% to -5% annualised.

### Accuracy / Metrics
- Pipeline: ~260 targets across 29 plan files
- 4 new plan files: plan_kelly_variants.R, plan_shadow_trades.R, plan_european_overlay.R, (plan_falsification.R updated)
- 7 new exported pkg functions: hd_tail_keff, hd_tail_dependence, hd_drawdown_overlap, hd_kelly_bayesian, hd_kelly_rolling, hd_kelly_bounded, hd_shadow_trades

### Known Limitations
- EXSA.DE (STOXX 600) only from 2008 — shorter history than other ETFs
- STOXX 600 FF regression R²=15% — US Fama-French factors poorly explain European broad index
- Shadow trades (#62) only implemented for Avoid Worst strategy — needs upstream in_market flag for other strategies
- Kelly variants (#56) use falsification bridge targets (fals_*_input) — only 3 of 5 strategies tested (drif, fac_max, ltr)
- quantmod not in nix develop shell — EU ETF fetch uses raw Yahoo API which may break if Yahoo changes endpoint

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
