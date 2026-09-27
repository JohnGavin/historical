# Overnight / Intraday Return Split

**Run:** `nix develop . --command Rscript explorations/overnight_intraday_split/run.R`
**Results committed at:** `results/` (regenerate by re-running the command above; every number below is transcribed verbatim from that run, none hand-typed).

## Source idea (read for ideas only -- nothing copied)

["The overnight gain is real, no trade keeps it, the rule that chases it buys wrecks"](https://quanterlab.com/research/the-overnight-gain-is-real-no-trade-keeps-it-the-rule-that-chases-it-buys-wrecks) -- Serhat Girgin, QuanterLab, 2026-09-13 ([issue #914](https://github.com/JohnGavin/historical/issues/914)). Its central diagnostic -- splitting a daily return into a close-to-open (overnight) leg and an open-to-close (intraday) leg -- had no equivalent in this package before this exploration.

## New package function: `hd_return_legs()`

`packages/historicaldata/R/return_legs.R` (58 tests, `packages/historicaldata/tests/testthat/test-return-legs.R`). Given a panel with `date`, `ticker`, `open`, `close`, and (required unless the caller opts out) `adjusted_close`, it returns `overnight`, `intraday`, and `close_to_close` per (ticker, date), asserting on every call that `(1 + overnight)(1 + intraday) - 1` reproduces the correct close-to-close return.

**Why `adjusted_close` is required by default.** `equity_daily`'s `open` and `close` are both raw, unadjusted prices (`packages/historicaldata/inst/COLUMN_NAMING.md`). A naive `open_t / close_{t-1} - 1` computed from raw prices alone fabricates a huge fake "overnight crash" on any split date -- a 2:1 split makes tomorrow's raw open roughly half of today's raw close, with zero real return behind it. `hd_return_legs()` corrects for this by carrying the adjustment ratio (`adjusted_close / close`) across the close-to-open boundary; the correction cancels out of the intraday leg entirely (both prices are quoted the same day). See the function's roxygen "Details" for the full derivation, and its `.hd_check_compounding()` helper's own falsification test for the proof that the compounding assertion actually has power to fail (the identity cannot diverge on internally-consistent input, so it needed a deliberately-wrong synthetic case, not real data, to prove it fires).

A synthetic 2:1-split fixture in the test suite is the sharpest illustration: naive raw arithmetic reports the split day as a **-49%** overnight return; `hd_return_legs()` reports the correct **+2%**.

## (a) SPY overnight vs intraday, 1993-2026 -- sanity check, not a target

| Leg | $1 (1993-02-01) grows to (2026-04-10) |
|---|---:|
| Overnight only (close→open) | **$22.69** |
| Intraday only (open→close) | **$1.24** |
| Close-to-close (full day) | $28.11 |

**Matches the article's claimed direction** (overnight return dwarfs daytime return) -- SPY's overnight leg alone very nearly reproduces the full close-to-close compounded return; the intraday leg alone is close to flat over 33 years. This is a sanity check against a third party's published claim on our own data, not a pre-registered hypothesis of ours (per `research-log-honesty.md`, it is not logged to the research-log database) -- and it is explicitly **not evidence of a tradable edge**: per the source article's own finding (25 of 26 years losing after a 0.05%/trade cost on the naive close-to-open-then-back trade), the raw overnight premium does not survive being traded.

134 of 8,355 SPY trading days were flagged `corp_action_adjusted = TRUE` (a detected split/dividend event) -- consistent with roughly 4/year of quarterly ex-dividend dates over 33 years; see the "Calibration note" below for how that threshold was chosen.

Full daily series: `results/spy_overnight_intraday_daily.csv`. Summary: `results/spy_overnight_intraday_summary.csv`.

### Calibration note: `corp_action_adjusted`'s detection threshold

`hd_return_legs()` flags a day as a detected corporate action when the adjustment ratio changes by more than a threshold vs the previous day. The threshold is **not** a bare "any nonzero change" (`1e-9`, the first value tried) -- measured directly on SPY during this exploration, `adjusted_close / close` carries real day-to-day floating-point/rounding noise even on days with **no** corporate action (90th percentile of `|ratio change|` ≈ 5.0e-7), while every one of SPY's 134 real quarterly ex-dividend days showed a ratio change ≥ 4.0e-3 -- a three-order-of-magnitude gap with nothing in between (`count(> 1e-4) == count(> 1e-3) == 134` exactly). The naive `1e-9` threshold flagged 8,253 of 8,355 days (99% of the whole series) as a "detected" action, which made the diagnostic meaningless; `1e-4` sits cleanly in the empirical gap. This is documented as a code comment at the constant's definition in `return_legs.R`.

## (b) Per-strategy attribution

Two of the leaderboard's SPY-based strategies expose a daily exposure schedule applied to a single underlying asset (SPY) in the `docs/_targets` store, which makes a reproducible overnight/intraday attribution possible without re-deriving any unpersisted state:

| Strategy | Underlying | $1 grows to (overnight leg only) | $1 grows to (intraday leg only) | $1 grows to (actual strategy) | Legs recombine exactly? |
|---|---|---:|---:|---:|---|
| Avoid Worst (Days) / VIX Protection | SPY | $10.74 | $0.51 | $5.48 | **Yes** — 0 mismatches (tol 1e-6) across 8,353 days |
| Risk State (VIX Overlay) | SPY | $12.46 | $0.94 | $7.23 | No — see note below |

**Avoid Worst (Days):** a full-day in/out switch, decided from the *prior* day's close (`R/plan_avoid_worst.R`'s `aw_practical_backtest`: `shocked`/`vix_elevated` are computed off `d$ret[i-1]`/`d$vix[i-1]`), so `in_market[t]` is already known before day `t`'s overnight leg begins. Both legs are captured together on an in-market day, neither on an out day -- **no leg is unreachable by this execution.** Because the indicator is binary, `(1 + in_market·overnight)(1 + in_market·intraday) − 1` reconstructs the strategy's own recorded return *exactly*: recompounding the two "legs-only" cumulative series (`$10.74 × $0.51 ≈ $5.48`) reproduces the actual strategy total to the last cent, verified row-by-row (0 mismatches beyond 1e-6 across all 6,673 in-market days). The overnight leg alone accounts for essentially all of this strategy's edge over holding cash — the strategy is not merely compatible with an overnight-dominant SPY, it inherits SPY's own overnight/intraday split almost unchanged whenever it participates.

**Risk State (VIX Overlay):** a *fractional* daily exposure (`R/plan_risk_state.R`'s `rsc_portfolio$exposure`, 0.10-1.00, mean 0.827 over the sample) applied uniformly to the whole day's SPY return (`gross_ret_strategy = exposure * spy_ret + (1 - exposure) * rf_daily`). Both legs are partially captured every day in proportion to exposure — again, no leg is *unreachable* — but **the two legs-only figures do not multiplicatively recombine into the actual strategy return** the way they do for the binary Avoid Worst case ($12.46 × $0.94 ≈ $11.71 ≠ $7.23 actual). This is not a bug in the attribution: linearly scaling a return by `exposure` and then geometrically compounding is a different operation from geometrically compounding the unscaled legs and then linearly scaling the *result*, and the two diverge once `exposure < 1` for long enough. The two leg-only columns remain individually informative (they show the overnight leg dominates this strategy's exposure-scaled edge too — $12.46 vs $0.94), but they are reported as two separate diagnostics, not as a verified decomposition of the actual return, and the table above says so explicitly rather than implying a false identity.

Per-day detail: `results/avoid_worst_attribution_daily.csv`, `results/risk_state_attribution_daily.csv`. Combined table: `results/per_strategy_attribution.csv`.

## (c) Strategies where attribution is NOT reproducible from the store (INDETERMINATE)

Per this dispatch's instruction, a strategy whose holdings aren't in the store is reported INDETERMINATE with the specific reason, not guessed at. `results/indeterminate_strategies.csv`:

| Strategy | Targets/functions checked | Reason |
|---|---|---|
| LTR | `ltr_portfolio` (`R/plan_ltr_momentum.R`) | Persists only a monthly aggregate long-short return (`ls_ret_net`) per (date, ym); no per-ticker daily holdings/weights are persisted anywhere in the store. |
| OLMAR-1 | `olmar_portfolio` (`R/plan_olmar.R`); `olmar_backtest()` (`packages/historicaldata/R/olmar.R`) | `olmar_backtest()` returns only `date`/`gross_ret`/`net_ret`/`turnover` -- the per-ticker weight vector formed each day is computed internally but never returned or persisted. |
| Factor DRIF | `stk_drif_portfolio` (`R/plan_stock_backtest.R`) | Monthly-rebalanced decile long-short portfolio; per-ticker/month decile membership exists only as an intermediate variable (`deciled`) inside the target body, never persisted as its own target. |
| Value (HML) | `hd_factors()` / `factors` dataset (Fama-French, Ken French library) | A pre-computed long-short FACTOR RETURN series, not tradable ticker-level positions we hold -- there is no equity_daily open/close for "the HML portfolio" as a single priced asset. |
| Managed Futures | commodities/futures plan files | Trades futures/commodity series, not `equity_daily` -- out of scope for this gap (bounded to SPY-scale equity opens/closes). |
| Mom Pre-Peak | `mom_prepeak_portfolio` (`R/plan_mom_prepeak.R`) | Same shape as Factor DRIF: a monthly quantile-sorted long-short portfolio; per-ticker daily holdings are not persisted. |

None of these six is a false negative -- each reason above was checked directly against the named target/function body during this exploration, not assumed. Recovering per-ticker attribution for any of them would mean re-deriving unpersisted intermediate pipeline state (LTR, DRIF, Mom Pre-Peak), capturing weight history that the underlying algorithm currently discards (OLMAR-1), or is not applicable to the strategy's asset class/construction at all (Value HML, Managed Futures) -- each a larger, separate undertaking, not attempted here.

## Scope notes

- **No dashboard output or `tar_target` was added.** Per `dashboard-output-first.md`, that needs an owner-approved Phase 0 (relationship diagram, target dashboard/section, prototype sign-off) before implementation. This PR proposes: extend the leaderboard's existing per-strategy detail view (or `falsification.qmd`'s relationship diagram) with an overnight/intraday split column or hover-popup for any strategy with a reproducible attribution (currently: Avoid Worst, Risk State), sourced from `hd_return_legs()`, not from a new standalone page.
- **Gap 2 (per-strategy break-even cost) is explicitly out of scope** for this dispatch -- it depends on realised turnover (#567/#663), tracked separately.
- No QA gate (`R/plan_qa_gates.R`) was added: this dispatch adds no new `tar_target`, so there is nothing yet for a leaderboard-scoped gate to guard. If/when the Phase-0-approved dashboard column above is implemented as a target, that implementation should add its own gate at that point.

## Sources

- [The overnight gain is real, no trade keeps it, the rule that chases it buys wrecks](https://quanterlab.com/research/the-overnight-gain-is-real-no-trade-keeps-it-the-rule-that-chases-it-buys-wrecks) -- Serhat Girgin, QuanterLab, 2026-09-13.
- `packages/historicaldata/inst/COLUMN_NAMING.md` -- `open`/`close`/`adjusted_close` schema.
- `R/plan_avoid_worst.R` (`aw_practical_backtest`), `R/plan_risk_state.R` (`rsc_portfolio`) -- the two attributable strategies.
- [#914](https://github.com/JohnGavin/historical/issues/914) -- origin issue.
