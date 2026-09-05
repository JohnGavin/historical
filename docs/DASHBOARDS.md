# Dashboard Inventory & Objectives

> Living inventory of every dashboard in `docs/`. This is the artifact the
> **`dashboard-output-first` rule** (issue #514) reviews against in Phase 0
> step 2 (locate the home), step 4 (template recipe), and step 5 (consolidation
> review). Keep it current: every feature that adds/changes a dashboard output
> updates the relevant row here, and every feature proposes at least one
> consolidation against this list.

**Current count: 11 standalone dashboards.** Consolidation target reached. The causal-DAG is an embedded surface inside
`falsification.qmd`, not a standalone dashboard.

## Inventory

| Dashboard | Objective | Primary visible outputs | Data source |
|---|---|---|---|
| `index.qmd` | Portal + dataset catalogue | Headline stat block (tickers/rows/datasets/years/functions); 4 dataset cards; card grid → downstream dashboards | `hd_datasets()`, `hd_tickers()`, `hd_factors()` |
| `leaderboard.qmd` | Rank all strategies by risk-adjusted return; central output | Ranking table (Sharpe/**Detection**/CAGR/MaxDD/CVaR95/Vol/**Gross (now)**/**Gross (target)**/SSR/**Rigour**/Top5%/Credible), with detection-power and rigour-coverage verdicts and vol-normalised leverage-allocator target inline (#726/#728, #626, badges + always-visible summary callout); partition table; equity-curve plotly (range slider); monthly-returns heatmap; bootstrap-CI table; alpha-decay; regime-adjusted Sharpe; Kelly table; structural-breaks dot plot; correlation matrix | `tar_read(leaderboard)`, `strat_deflated_sharpe` (Rigour tooltip only), `leverage_allocator_gross` (Gross (target) badge only), `boot_ci_summary`, `structural_breaks_summary`, `strategy_correlation` |
| `falsification.qmd` | Test causal integrity / robustness gauntlet + **Failed Strategies section (#514 merge 3/3)** | Scorecard (Verdict/HAC t/Sharpe/Alpha/R²); null-rejection heatmap (6 envs × strats); FF5+Mom alpha scatter; HAC t comparison; multiplicity K_eff table; WFC 2×2; **covariance regularisation table + conditioning/OOS dot plots (#498)**; causal DAG (Mermaid/D3, tabbed); implication tests; risk-architecture table; **failed-strategy filtered scorecard + pattern table + portfolio implications**; **Liquidity tab: ADV-cap on/off impact table (#625, discharges the standing `backtest-robustness.md` reporting requirement); dashboard-universe liquidity summary + volume stats, computed against `stk_universe` rather than the ingestion-side `consolidated_equity` (#625 Option A, wired but not yet `tar_make()`-verified)** | `fals_vig_*`, `wfc_all_summary`, `cov_diag_vig_table`, `cg_dag`, `cg_test_implications`, `fals_summary`, `fals_vig_names`, `stk_max_adv_cap_impact`, `equity_daily_liquidity_summary_tbl`, `equity_daily_volume_stats` |
| `evidence.qmd` | Negative results + 155-yr pervasiveness | Failed-strategies scorecard; pattern-analysis table; negative-result cards; JST pervasiveness table (18 countries); equity-premium heatmap; crisis timeline; crisis-frequency table | `fals_summary`, `jst_equity_premium`, `jst_pervasiveness`, `jst_crises` |
| ~~`factor-max.qmd`~~ | ~~MAX signal at factor level~~ | ~~Cumulative-return plotly (log); metrics table (IS/OOS/Full); factor-selection bar chart; MAX-signal heatmap; ETF comparison~~ | ~~`fm_cumret_plot`, `fm_metrics`, `fm_selection_freq`, `fm_heatmap`~~ **→ merged into `stock-backtest.qmd#factor-level-deep-dive` (#514 merge 2/3)** |
| ~~`drif.qmd`~~ | ~~DRIF elastic-net signal at factor level~~ | ~~Cumulative-return plotly; metrics table (seal warning on Validation); selection-frequency table; DRIF-vs-MAX comparison; parameters table~~ | ~~`drif_cumret_plot`, `drif_metrics`, `drif_params`, `drif_selection_freq`, `drif_vs_max_plot`~~ **→ merged into `stock-backtest.qmd#factor-level-deep-dive` (#514 merge 2/3)** |
| `stock-backtest.qmd` | Cross-sectional: MAX/DRIF on 660 stocks vs 5 factors | 2×2 strategy matrix; equity curves (4 strats, range slider); metrics table; key-findings matrix; per-signal detail (plots, pros/cons, factor exposure); XGBoost DRIF section | `stk_max_metrics`, `stk_drif_metrics`, `fm_metrics`, `drif_metrics`, `stk_all_comparison_plot` |
| `avoid-worst-days.qmd` | Thought experiment: return asymmetry | Conceptual $100→$165 vs $75 chart; temporal-clustering analysis; discussion (not tradeable) | Inline SPY daily returns |
| `european-overlay.qmd` | VIX-style signals on European equities vs ECB CISS | CISS-vs-VIX correlation table; CISS sub-market breakdown; CISS time series plotly; regime-allocation table; performance comparison | `ecb_raw`, `aw_vix_daily`, `hd_ecb()` |
| ~~`jst-dashboard.qmd`~~ | ~~Interactive 155-yr equity premium, 18 countries~~ | ~~Pervasiveness table; decade×country heatmap; crisis timeline; crisis-frequency table; summary callouts~~ | ~~`jst_equity_premium`, `jst_pervasiveness`, `jst_crises`~~ **→ merged into `evidence.qmd#historical-evidence` (#514 merge 1/3)** |
| `macro-defense-rotation.qmd` | Macro hedge rotation (TLT/GLD/DBC/UUP vs SPY) | Normalised price chart; performance-metrics table (by partition); regime overlay; win-rate table; allocation table | `bt_prices`, inline backtest |
| `momentum-prepeak.qmd` | Büsing (2022) pre-peak vs post-peak 12-2 momentum | Equity-curve comparison (pre/post/combined); summary metrics; bankruptcy-events table; signal-decomposition explanation | `mom_prepeak_*`, `mom_postpeak_returns`, `mom_combined_returns`, `strategy_names` |
| `bdbb-sol.qmd` | M/G/∞ queueing model (Varma 2026) on SOL/USD | Data-coverage table; rolling-diagnostics table; regime-distribution bar chart; tail-risk predictivity table | `bdbb_sol_dv`, `bdbb_sol_fit`, `bdbb_sol_metrics` |
| ~~`negative-results.qmd`~~ | ~~Archive of failed strategies (detailed)~~ | ~~Failed-strategies scorecard; detailed failure cards; lessons-learned callouts; portfolio implications~~ | ~~`fals_summary` filtered Alpha t < 2.0~~ **→ merged into `falsification.qmd#failed-strategies` (#514 merge 3/3)** |
| `quiz.qmd` | Educational: real vs synthetic equity curves | Quiz interface (side-by-side plotly); difficulty badges; results card; explanation panels | `quiz_json`, quiz-logic.js |

## Overlap Clusters

1. **Strategy performance** — `index` → `leaderboard` → `falsification`: ranking, equity curves, and verdicts that reference each other.
2. ~~**Per-strategy deep dives** — `factor-max`, `drif`, `stock-backtest`, `macro-defense-rotation`, `momentum-prepeak`: all show definition + cumulative-return plotly + metrics table + signal analysis. `stock-backtest` already subsumes `factor-max`/`drif` as a 2×2.~~ Resolved: `factor-max` and `drif` merged into `stock-backtest.qmd#factor-level-deep-dive` (#514 merge 2/3).
3. **Long-run evidence** — ~~`evidence` and `jst-dashboard` render the **same** JST pervasiveness table, heatmap, and crisis timeline.~~ Resolved: `jst-dashboard` merged into `evidence.qmd#historical-evidence` (#514 merge 1/3).
4. ~~**Robustness & falsification** — `leaderboard`, `falsification`, `negative-results`: overlapping robustness metrics; `negative-results` is a subset of the `falsification` scorecard.~~ Resolved: `negative-results` merged into `falsification.qmd#failed-strategies` (#514 merge 3/3).

## Consolidation Proposal (15 → 11)

| # | Action | Rationale | Kept / lost |
|---|---|---|---|
| 1 | ~~**Merge `jst-dashboard` → `evidence`** (tabset)~~ **DONE** (#514 consolidation 1/3) | Identical JST outputs; no new information | All data kept; redirect stub replaces standalone page; `evidence.qmd#historical-evidence` is the new anchor |
| 2 | ~~**Merge `factor-max` + `drif` → `stock-backtest`** (Factor-Level tabset)~~ **DONE** (#514 consolidation 2/3) | `stock-backtest` already shows the 2×2 (Stock/Factor × MAX/DRIF) | All data kept as Factor-Level Deep Dive tabset; redirect stubs replace standalone pages; index links to `stock-backtest#factor-level-deep-dive` |
| 3 | ~~**Merge `negative-results` → `falsification`** (final "Failed Strategies" tab)~~ **DONE** (#514 consolidation 3/3) | `negative-results` copies the falsification scorecard + failure cards; detail cards already in `evidence.qmd` | Filtered scorecard + patterns + implications in `falsification.qmd#failed-strategies`; per-strategy failure cards remain in `evidence.qmd#negative-results`; redirect stub replaces standalone page |
| 4 | **Keep** `index`, `leaderboard`, `falsification`, `evidence`, `stock-backtest`, `macro-defense-rotation`, `momentum-prepeak`, `european-overlay`, `bdbb-sol`, `avoid-worst-days`, `quiz` | Distinct objective/audience each | — |

**Resulting 11-dashboard architecture (target reached, #514 consolidation complete):** Portal (`index`) · Core (`leaderboard` → `falsification` → `evidence`) · Signals (`stock-backtest`) · Exploratory (`macro-defense-rotation`, `momentum-prepeak`, `european-overlay`, `bdbb-sol`, `avoid-worst-days`) · Interactive (`quiz`).

## Template Recipe

Clone one of these chunks into a throwaway prototype (Phase 0 step 4), swap the
data with a stub, render, attach for approval.

| New output type | Template chunk | Why |
|---|---|---|
| Multi-strategy ranking table | `leaderboard.qmd` metrics table (~L115–158) | Generic `hd_dt()` ranking with colour bars; new strategy = new row |
| Robustness / CI assessment table | `leaderboard.qmd` bootstrap-CI table (~L318–336) | Conditional styling (red if CI crosses zero) |
| Multi-hypothesis comparison | `falsification.qmd` null-rejection heatmap (~L229–236) | `geom_tile` rejection-rate scale, facet by strategy |
| Alpha vs factor-exposure diagnosis | `falsification.qmd` FF alpha scatter (~L194–200) | Standard alpha/R² placement |
| Walk-forward estimator comparison | `falsification.qmd` covariance-regularisation block (~L410–468) | Comprehensive sample-vs-shrunk OOS template — **the model for #507's weight-stability diagnostic** |
| Asset-rotation selection | `stock-backtest.qmd` Factor-Level Deep Dive → Factor MAX tab, selection-frequency block | `group_by + count` bar, facet by signal |
| Causal-assumption documentation | `falsification.qmd` causal DAG + implications (~L581–737) | DAG + conditional-independence table with source links |

## Maintenance

- Update the relevant inventory row whenever a dashboard output changes.
- Every Phase 0 run appends its consolidation decision (step 5) — even "no
  change, because …".
- When a merge from the Consolidation Proposal ships, move the merged dashboard
  to a struck-through line with the absorbing target noted, and decrement the
  count.

**Consolidation decision, #625 (liquidity module):** no change to dashboard
count. `stk_max_adv_cap_impact` and, since the #625 Option A pipeline-wiring
PR, the dashboard-side liquidity module outputs (`equity_daily_liquidity_summary_tbl`,
`equity_daily_volume_stats`, both computed against `stk_universe`) are added
as a tab inside the existing `falsification.qmd`, not a new standalone
dashboard — this is the intended default per the `dashboard-output-first`
rule (extend, don't spin up). The original ingestion-side targets
(`liquidity_summary_tbl`, `volume_stats`, computed against `consolidated_equity`)
remain root-pipeline-only and are not displayed on any dashboard.

**Consolidation decision, #726/#728 (detection power + rigour coverage,
Phase 0 build, #735 prototype):** no change to dashboard count (11). Within
`leaderboard.qmd`, the Detection and Rigour verdicts are added as two new
columns on the existing "Full Period" ranking table (Detection immediately
right of Sharpe, per `detection-power-required` requirement 2), not a new
tab or dashboard. The standalone "Deflated Sharpe" tab in the Robustness
section is **removed** — its three numbers (deflated Sharpe, DSR p-value,
haircut %) now render as the Rigour badge's hover tooltip on the same row as
the Sharpe they qualify, with zero information loss (the tab's source data,
`strat_deflated_sharpe`, is unchanged; only its second, separately-navigated
rendering is retired). Net effect: `leaderboard.qmd` tab count within the
Robustness tabset drops from 5 to 4 (Bootstrap CI, Alpha Decay, Regime,
Kelly Sizing). The Mermaid relationship diagram from the #735 prototype
(Sharpe → detection-power verdict → rigour-coverage verdict → leaderboard
row) is **not** wired into `causal-diagrams.js` in this pass — that is a
separate, larger change (migrating node→file:line links into
`R/diagram_node_links.R`) tracked as a follow-up, not part of this build.

**Consolidation decision, #626 (leverage allocator, production
implementation following the #827 prototype's approved Phase 0):** no change
to dashboard count (11). The vol-normalised allocator's per-strategy gross
target (`R/plan_leverage.R`'s `compute_allocator_gross()`) is folded into a
single new `Gross (target)` badge column on the existing `leaderboard.qmd`
ranking table, immediately beside the renamed `Gross (now)` (was `Gross`)
column — the same "one badge column, not three raw ones" consolidation
`falsification.qmd`'s Detection/Rigour precedent (#726/#728) already
established, applied to the #827 prototype's own three-raw-column proposal
(Implied G_i / G_i @ backstop / Backstop binds?). Net column count on the
ranking table grows by one. The regime-stress-ratio diagnostic
(`compute_regime_stress_ratio()`) and the #827 prototype's relationship
diagram are **not** wired into a dashboard in this pass — they remain
future work for `falsification.qmd`'s existing "Strategy & Dashboard
Relationship Map" tab (`dag-portcons-mount`), tracked against #626/#719
rather than shipped speculatively here. The gross-exposure backstop level
itself is explicitly PROVISIONAL (#626 decision D1 remains open) and is
disclosed as such in both the badge tooltip and the table's dynamic
disclosure note — never presented as settled.
