# BDBB R-Metric Position-Sizing Overlay — Graduation Test (#443)

**Run:** `nix develop . --command Rscript explorations/bdbb_r_sizing/run.R`
**Last output committed at:** `results/` (regenerate by re-running the command above; every number below is transcribed verbatim from that run, none hand-typed or carried over from an earlier draft).

## This tests a pre-registered, SEALED hypothesis — read this first

Two hypotheses were sealed **before** this script existed or ran, by commit
`7706205` ("research(prereg): seal BDBB R-sizing overlay hypotheses at
inception (#443)"), one per asset:

| Asset | Hypothesis uuid | `sealed_at` | `commit_hash` |
|---|---|---|---|
| BTC | `c0e60522-5a51-4563-a619-14b4a557779c` | 2026-09-19 22:16:32 | `d59cf7c6...` |
| SOL | `e9357c9b-d162-4317-bd6e-960736809c69` | 2026-09-19 22:16:32 | `92b6f391...` |

This exploration runs exactly the test those rows describe and reports what
happened. Neither hypothesis's wording is restated or re-derived here beyond
what is needed to implement it (see the header comment in `run.R` for the
verbatim `economic_claim`, `null_hypothesis`, `decision_rule`, and
`required_controls` fields read directly off the sealed rows). Per
`research-log-honesty.md`, the hypotheses themselves are **not** touched —
`log_to_research_db.R` only appends `implementations`/`results`/`critiques`
rows with `parent_uuid` pointing at these existing sealed uuids.

**Closure.** Both hypotheses were appended-to (never edited) with
`status = "inconclusive-underpowered"` by
`explorations/bdbb_r_sizing/close_hypotheses.R`, which reads the outcome
straight from `results/decision_table.csv`, carries `commit_hash` /
`sealed_at` / `seal_method` over unchanged, and re-verifies
`hd_rlog_seal_verify()` on the newly appended rows before reporting
success — recomputed hash matched the stored hash for both, confirming
the append changed only `status` and no claim field. The previously
`"proposed"` rows are left in the append-only store exactly as sealed;
the closure is a NEW row per uuid, not an edit. `log_to_research_db.R` was
then run once, appending 2 `implementations`, 52 `results`, and 10
`critiques` rows, each `parent_uuid`-linked to these two sealed hypotheses
(both uuids confirmed present in the research log before linking).

## (a) Combination mode

**"time"**, per `.claude/rules/strategy-combination-modes.md`. The R-metric
scales gross exposure of a *single* asset over time (down when R sits in its
own trailing top tercile). It is **not a filter** (it never changes which
asset is held — BTC or SOL is held throughout) and **not a blend** (R is
never averaged with another score). Declared here per that rule's
requirement to name the mode before writing any code.

## (b) The bottom line, stated first: every variant, every weight, both assets, is underpowered

Per `detection-power-required.md`, this goes before any Sharpe is discussed.
`hd_detection_power()` was run on every positive-Sharpe row's **naive**
annualised Sharpe (the convention this repo's own reference exploration,
`momentum_max_lottery`, uses — `hd_detection_power()`'s theoretical basis is
the classic/naive Sharpe sampling distribution, not a HAC-adjusted one).

- **52 of 52 rows** in `results/summary_metrics.csv` (every asset x variant x
  weight x gross/net combination) report `detection_verdict = UNDERPOWERED`.
- **0 of 52 rows** have `fixed_threshold_underpowered = FALSE` — i.e. not one
  variant, at any weight, on either asset, clears the pre-registered fixed
  detectability threshold (0.75 BTC, 1.17 SOL).
- The observed naive Sharpes across all 52 rows range from **+0.238 to
  +0.545** — nowhere near either threshold.
- Even **buy-and-hold itself** does not clear its own asset's threshold:
  BTC benchmark naive Sharpe +0.500 vs threshold 0.75 (net); SOL benchmark
  naive Sharpe +0.318 vs threshold 1.17 (net). This is not a criticism of the
  study design — the threshold is calibrated to detect an overlay's *own*
  claimed effect at 80% power, a materially higher bar than simply comparing
  two point estimates — but it puts the scale of the problem in context: the
  sample cannot even confirm passive BTC/SOL holding has a positive Sharpe
  at this standard, let alone resolve a ~0.02-0.10 gap between two
  overlay variants.

| Asset | n_obs (analysis sample) | Years available | Fixed threshold (min detectable annual SR) | Benchmark naive SR (net) | `min_n_years` needed for benchmark's own SR |
|---|---:|---:|---:|---:|---:|
| BTC | 95,411 | 10.89 | 0.75 | +0.500 | 24.69 |
| SOL | 38,773 | 4.43  | 1.17 | +0.318 | 61.08 |

BTC overlay variants (net) need **23.4-25.2 years** at their own observed
Sharpe for 80% power (2.1-2.3x the 10.89 available). SOL overlay variants
(net) need **51.1-57.3 years** (11.5-13.0x the 4.43 available). BTC is
closer to resolvable by waiting; SOL is not, within any practical horizon.

## (c) Results tables

All four weights (`w_low in {0.00, 0.25, 0.50, 0.75}`) reported for every
variant — none selected as "the" result, per `strategy-combination-modes.md`
check 5/6 and the task's explicit instruction not to pick a winner.

### BTC — net of costs (primary; see (f) for gross)

| Variant | w_low | sharpe_naive | sharpe_hac | CAGR | turnover_annual | detect |
|---|---:|---:|---:|---:|---:|---|
| benchmark | — | +0.500 | +0.606 | +55.73% | 0.09x | UNDERPOWERED |
| overlay | 0.00 | +0.495 | +0.563 | +46.60% | 9.09x | UNDERPOWERED |
| overlay | 0.25 | +0.510 | +0.583 | +48.83% | 6.84x | UNDERPOWERED |
| overlay | 0.50 | +0.515 | +0.597 | +51.10% | 4.59x | UNDERPOWERED |
| overlay | 0.75 | +0.511 | +0.604 | +53.40% | 2.34x | UNDERPOWERED |
| complement | 0.00/0.25/0.50 | +0.394 | +0.523 | +57.86% | 9.09x | UNDERPOWERED |
| complement | 0.75 | +0.464 | +0.581 | +56.44% | 3.09x | UNDERPOWERED |
| volsizing | 0.00 | +0.514 | +0.578 | +43.49% | 3.95x | UNDERPOWERED |
| volsizing | 0.25 | +0.534 | +0.605 | +46.45% | 2.98x | UNDERPOWERED |
| volsizing | 0.50 | +0.535 | +0.617 | +49.48% | 2.02x | UNDERPOWERED |
| volsizing | 0.75 | +0.521 | +0.616 | +52.57% | 1.06x | UNDERPOWERED |

(complement is identical across w_low = 0.00/0.25/0.50 because
`min(1/w_low, 2.0)` caps all three at the same up-scale of 2.0 — the cap
specified in the sealed hypothesis's `required_controls.complement`.)

### SOL — net of costs (primary; see (f) for gross)

| Variant | w_low | sharpe_naive | sharpe_hac | CAGR | turnover_annual | detect |
|---|---:|---:|---:|---:|---:|---|
| benchmark | — | +0.318 | +0.328 | +39.78% | 0.23x | UNDERPOWERED |
| overlay | 0.00 | +0.348 | +0.355 | +41.33% | 7.00x | UNDERPOWERED |
| overlay | 0.25 | +0.344 | +0.351 | +40.94% | 5.31x | UNDERPOWERED |
| overlay | 0.50 | +0.337 | +0.346 | +40.55% | 3.61x | UNDERPOWERED |
| overlay | 0.75 | +0.329 | +0.338 | +40.16% | 1.92x | UNDERPOWERED |
| complement | 0.00/0.25/0.50 | +0.238 | +0.250 | +33.45% | 7.00x | UNDERPOWERED |
| complement | 0.75 | +0.292 | +0.302 | +37.63% | 2.49x | UNDERPOWERED |
| volsizing | 0.00 | +0.395 | +0.397 | +40.14% | 11.97x | UNDERPOWERED |
| volsizing | 0.25 | +0.388 | +0.392 | +40.05% | 9.04x | UNDERPOWERED |
| volsizing | 0.50 | +0.370 | +0.376 | +39.96% | 6.10x | UNDERPOWERED |
| volsizing | 0.75 | +0.346 | +0.354 | +39.87% | 3.16x | UNDERPOWERED |

Full table (both assets, gross and net, plus `ann_vol`, `max_dd`, `skew`,
`detection_power`, `detection_min_n_years`): `results/summary_metrics.csv`.

## (d) Complement control — the check most often skipped

Required control: scale UP (to `1/w_low`, capped at 2.0) instead of down,
when R is in the top tercile. If overlay and complement perform alike, R is
not sizing anything.

**They do not perform alike — overlay beats complement on both assets, at
every weight, net of costs:**

| Asset | w_low | overlay sharpe_hac | complement sharpe_hac | gap |
|---|---:|---:|---:|---:|
| BTC | 0.00 | +0.563 | +0.523 | +0.040 |
| BTC | 0.25 | +0.583 | +0.523 | +0.060 |
| BTC | 0.50 | +0.597 | +0.523 | +0.074 |
| BTC | 0.75 | +0.604 | +0.581 | +0.023 |
| SOL | 0.00 | +0.355 | +0.250 | +0.105 |
| SOL | 0.25 | +0.351 | +0.250 | +0.101 |
| SOL | 0.50 | +0.346 | +0.250 | +0.096 |
| SOL | 0.75 | +0.338 | +0.302 | +0.036 |

This is a directionally consistent, non-trivial pattern (overlay always
ahead, never behind, on both assets and every one of 8 weight cells), and it
is the single most encouraging number this exploration produced — it is
**not** the "looks the same either way" pattern that would flatly kill the
claim. But every one of these Sharpes, on both sides of every comparison,
sits below its asset's detection threshold (see (b)): a 0.02-0.10 gap
between two Sharpes that are themselves each individually undetectable from
zero is not evidence the gap itself is real. The honest reading is: the
complement control does not kill the hypothesis, but it cannot confirm it
either — the direction is consistent with the claim, the magnitude is not
established.

## (e) Is R just a repackaged vol filter? — required control #2

`cor(rank(R), rank(trailing_realised_vol))`, same 30-day window for both:

| Asset | Spearman correlation | n_pairs |
|---|---:|---:|
| BTC | **0.708** | 95,662 |
| SOL | **0.646** | 39,024 |

Both are strongly positive — R and trailing realised volatility move
together most of the time, as would be expected given R's own definition
(variance per unit signed flow — variance is the numerator).

**Does plain vol-sizing do at least as well as R-sizing? Yes, on both
assets, at nearly every weight** (net, `sharpe_hac`):

| Asset | w_low | R-overlay | vol-sizing | vol-sizing wins by |
|---|---:|---:|---:|---:|
| BTC | 0.00 | +0.563 | +0.578 | +0.015 |
| BTC | 0.25 | +0.583 | +0.605 | +0.022 |
| BTC | 0.50 | +0.597 | +0.617 | +0.020 |
| BTC | 0.75 | +0.604 | +0.616 | +0.012 |
| SOL | 0.00 | +0.355 | +0.397 | +0.042 |
| SOL | 0.25 | +0.351 | +0.392 | +0.041 |
| SOL | 0.50 | +0.346 | +0.376 | +0.030 |
| SOL | 0.75 | +0.338 | +0.354 | +0.016 |

Plain trailing realised volatility beats the BDBB R-metric at **every one of
these 8 cells**, net of costs, on both assets. Combined with the 0.65-0.71
rank correlation, the honest conclusion is: **there is no evidence R adds
anything over a much simpler vol filter here.** If anything, R is a
slightly noisier proxy for the same underlying effect (R adds the
signed-flow denominator on top of variance; that extra structure did not
pay for itself in this sample). This does not itself refute the sealed
hypothesis (which is about R vs buy-and-hold, not R vs vol), but it is a
material finding for the graduation question: R is not shown to be a better
sizing signal than a much cheaper one already in wide use.

Turnover tells a mixed, asset-dependent story on the mechanism, worth
recording even though it does not change the headline: on BTC, vol-sizing
trades **less** than R-sizing at every weight (e.g. w=0: 3.95x vs 9.09x);
on SOL it trades **more** (e.g. w=0: 11.97x vs 7.00x). R and trailing vol
are correlated but not identical, and they disagree about *when* to size
down often enough to produce very different trading frequency on SOL
specifically.

## (f) Turnover and cost — gross-only would be misleading

Kraken taker fee, 0.26% per side (task-specified, applied to the absolute
change in exposure at each bar — one trade per rebalance). Annualised
turnover ranges from **0.09x** (BTC benchmark, near-zero since it is a
single buy-and-hold position) up to **12.0x** (SOL vol-sizing at w=0.00).
At w=0.00 (the most aggressive sizing swing, 100%->0% exposure), overlay
turnover alone is **9.09x BTC / 7.00x SOL** — annually trading roughly nine
and seven times the notional, respectively.

Costs measurably erode every overlay variant. Representative examples
(gross -> net, `sharpe_naive`):

- BTC `overlay_w0.00`: 0.526 -> 0.495 (-0.031)
- BTC `volsizing_w0.00`: 0.529 -> 0.514 (-0.015, lower turnover than R-overlay here)
- SOL `volsizing_w0.00`: 0.431 -> 0.395 (-0.036, this variant's 11.97x turnover is the highest in the study)

**No conclusion in this exploration changes sign between gross and net** —
every variant is underpowered under both cost models, and the complement
and vol-sizing orderings in (d)/(e) hold gross and net alike (see
`results/summary_metrics.csv`, filter `cost_type`). But the *margins*
shrink under cost, and a report that only showed gross numbers would
overstate every one of these Sharpes by a consistent 0.01-0.04, which
matters given how close several of the complement-control gaps in (d) are
to that same size. Net is used as the primary series throughout this
document and in the decision rule below.

## (g) Decision rule — applied literally, both assets, all four weights

From the sealed `extra_json.decision_rule`, applied as an ordered procedure
(the underpowered gate evaluated first, unconditional on sign, since it is
about whether the sample can resolve the question at all — see the
INTERPRETATION CHOICE note in `run.R`'s header for why `|sharpe|` there
means the naive Sharpe, following this repo's own precedent):

1. if `|sharpe_naive(overlay, net)| < asset threshold` -> `inconclusive-underpowered`
2. else if `sharpe_hac(overlay, net) > sharpe_hac(benchmark, net)` -> `supported`
3. else -> `refuted`

| Asset | w_low | overlay sharpe_naive | overlay sharpe_hac | benchmark sharpe_hac | **status** |
|---|---:|---:|---:|---:|---|
| BTC | 0.00 | +0.495 | +0.563 | +0.606 | **inconclusive-underpowered** |
| BTC | 0.25 | +0.510 | +0.583 | +0.606 | **inconclusive-underpowered** |
| BTC | 0.50 | +0.515 | +0.597 | +0.606 | **inconclusive-underpowered** |
| BTC | 0.75 | +0.511 | +0.604 | +0.606 | **inconclusive-underpowered** |
| SOL | 0.00 | +0.348 | +0.355 | +0.328 | **inconclusive-underpowered** |
| SOL | 0.25 | +0.344 | +0.351 | +0.328 | **inconclusive-underpowered** |
| SOL | 0.50 | +0.337 | +0.346 | +0.328 | **inconclusive-underpowered** |
| SOL | 0.75 | +0.329 | +0.338 | +0.328 | **inconclusive-underpowered** |

All 8 cells land on `inconclusive-underpowered` — step 1 of the procedure
terminates every case before step 2/3 is ever reached, because every
overlay naive Sharpe (0.33-0.52) sits below its asset's threshold (0.75
BTC, 1.17 SOL). Per `research-log-honesty.md`: this is **not** `refuted`.
The claim was not tested to a conclusion in either direction — the sample
cannot resolve it.

Worth noting for the record, without over-reading it: on BTC, overlay
`sharpe_hac` is marginally *below* benchmark at every weight (by
0.002-0.043); on SOL it is marginally *above* at every weight (by
0.010-0.027). Had step 1 not gated first, BTC would nominally read
`refuted` and SOL would nominally read `supported` — directly opposite
verdicts on the two assets the hypothesis was meant to generalise across.
That instability itself is more evidence the sample is too short to
support a directional call, not less.

## (h) Does more data of the same kind help?

**BTC: plausibly yes, eventually.** The overlay variants need 23.4-25.2
years for 80% power against 10.89 available — roughly 2.1-2.3x more data.
That is over a decade more of BTC/USD history, which is a long wait but not
structurally impossible (Kraken's BTC series is 12+ years old and growing).

**SOL: not on any practical horizon.** The overlay variants need 51.1-57.3
years for 80% power against 4.43 available — 11.5-13.0x more data, i.e.
roughly half a century more of SOL/USD history. SOL itself is 4.5 years
old. This is `inconclusive-underpowered`, not `inconclusive-unmeasurable`
(the required population — more SOL price history — is not structurally
absent the way, say, delisted-stock returns are absent from a
survivorship-biased equity panel), but "more data would help" is true only
in a sense with no practical bearing on a graduation decision made this
year.

Neither asset's answer can be sped up by re-running the same backtest
differently — this is a sample-size limit, not an implementation bug. A
higher-frequency panel of the SAME underlying price process (e.g. minute
bars instead of hourly) would **not** help either: it would add more
*observations* without adding more independent *information*, since minute
returns within an hour are highly autocorrelated with the hourly move they
compose — `hd_hac_sharpe()`'s Newey-West correction exists precisely
because naively treating correlated high-frequency observations as
independent overstates power. What would help is a genuinely different,
independent evidence source: BTC/SOL history on another venue (to test
whether the effect, if real, is venue-specific or market-wide), or waiting
for calendar time to pass.

## (i) Look-ahead and construction controls (as specified in the sealed hypothesis)

- **Tercile breakpoints: expanding, never full-sample.** Implemented via an
  O(n log n) Fenwick-tree percentile rank (`expanding_percentile_rank()` in
  `run.R`) that, at each bar, uses only R (or trailing-vol) values observed
  at or before that bar. A minimum of 250 prior valid observations is
  required before the first tercile assignment (0.98-2.4% of each asset's
  bars fall in this warm-up and are excluded from the analysis sample —
  970 of 96,381 BTC bars, 970 of 39,743 SOL bars).
- **Diagnostic lag: R at window_end t sizes exposure for bar t+1, resolved
  by row order, not clock arithmetic.** `dplyr::lag(R_tercile, 1L)` in
  `run.R`, matching the task's explicit instruction — Kraken bars exist
  only where trades occurred (see the data characteristic below), so
  `window_end + 3600s` is not reliably the next row.
- **`bdbb_tail_predict()` deliberately NOT used**, per the sealed
  hypothesis's `look_ahead_controls.blocked_by`: that function currently
  scores the in-window bar rather than the next one (#868). Sizing is built
  directly from `bdbb_fit()`'s own `window_end`/`R` output instead, with the
  lag applied explicitly and verified above.
- **Benchmark restricted to the same analysis sample as the overlay** (not
  the full raw bar count), so the comparison in (g) is over identical
  bars on both sides — not a longer benchmark sample against a shorter,
  warm-up-truncated overlay sample.

**A data characteristic worth flagging, not a bug:** the sealed hypothesis's
`sample_spec` states BTC is "11.00 yrs" of data, computed as
`n_bars_available / 8760` (bar-count-implied years assuming no gaps). The
*calendar* span actually observed is **12.24 years** (2013-10-06 to
2025-12-31) for the same 96,381 bars — meaning roughly 1.24 bar-years'
worth of hours have no Kraken trade at all somewhere across that span,
consistent with the registry's own documented caveat ("bars exist only for
periods with trades"; likely concentrated in BTC's earliest, thinnest
years on Kraken). This has no effect on any result here, precisely because
sizing is resolved by row order rather than clock time, but it is worth
recording for anyone reconciling bar counts against calendar dates later.

## (j) Does this survive our gates?

**No — it does not graduate from diagnostic to tradeable overlay, and the
data cannot rule it out either. Both are complete, honest outcomes of the
test as pre-registered.**

Every one of 52 rows across 2 assets, 4 weights, 3 sizing variants
(R-overlay, complement, vol-sizing) and 2 cost models is underpowered
against its own pre-registered detectability threshold — including the
passive buy-and-hold benchmark itself. The pre-registered decision rule
resolves to `inconclusive-underpowered` in all 8 primary (asset, weight)
cells, not `refuted` and not `supported`. Two things point in mildly
encouraging directions without approaching significance: the complement
control shows overlay consistently ahead of its inverted twin (see (d)),
and the direction differs by asset only in whether overlay edges benchmark
or falls marginally short (see (g)) — but a single strongly negative
finding sits alongside them: plain trailing realised volatility, a much
simpler and already-standard signal, matches or beats the BDBB R-metric at
every one of 8 tested cells net of costs, despite the 0.65-0.71 rank
correlation between the two (see (e)). Combined with a BTC data requirement
that is merely a long wait (2.1-2.3x available) and a SOL data requirement
that is not practically resolvable (11.5-13.0x available, ~50 more years),
the honest conclusion is: **this exploration does not support deploying
the BDBB R-sizing overlay as specified, it does not refute the underlying
economic claim either, and on the evidence available today a much simpler
volatility-based overlay would be at least as good a use of the same
capital.**

## (k) Max-drawdown mechanism check — did the overlay protect against BTC's worst loss?

`results/summary_metrics.csv` shows BTC's `overlay` `max_dd` (net) is
**identical to the benchmark's to 4 decimal places at every one of the four
`w_low` weights** (all read `-0.8392`) — including `w_low = 0.00`, where the
overlay goes fully flat whenever R sits in its top tercile. The implied
reading, stated in the dispatch that produced this section: **R was never
in its top tercile during BTC's worst drawdown, so the overlay held full
exposure right through the single largest loss in the sample** — a failure
independent of Sharpe and independent of detection power, and therefore not
excused by the `inconclusive-underpowered` verdict in (g)-(j).

This is verified directly from the per-bar series (`results/drawdown_analysis.csv`,
computed in `run.R` step 8b from the same in-memory analysis sample used
for every other number in this document — not re-derived from the
aggregate `max_dd` figure alone):

| Asset | Peak | Trough | Window | `max_dd` (benchmark, net) | Frac. bars R in top tercile | Mean exposure, overlay `w_low=0.00` | Mean exposure, volsizing `w_low=0.00` |
|---|---|---|---:|---:|---:|---:|---:|
| BTC | 2017-12-17 13:00 | 2018-12-15 15:00 | 363.1 days / 8,663 bars | -83.92% | **0.0000** | **1.0000** | 0.7278 |
| SOL | 2021-11-06 23:00 | 2022-12-29 20:00 | 417.9 days / 10,029 bars | -96.80% | 0.0966 | 0.9034 | 0.7350 |

**The implied reading is confirmed exactly for BTC, not merely consistent
with it.** Across all 8,663 bars of BTC's year-long 2017-2018 crash, `R`
was in its top (highest-R) tercile on **zero** of them — `frac_bars_top_tercile_R
= 0`. The `w_low = 0.00` overlay's mean exposure over the entire window is
therefore exactly **1.0000**: the de-risking mechanism did not fire even
once during the single worst loss in the 11-year sample, for the reason
the overlay is built to de-risk on high R and R was simply never high
during this crash. This is not a sampling artefact of `w_low = 0.00`
specifically — it holds identically at every weight (0.00/0.25/0.50/0.75)
because exposure only changes when the tercile condition is met, and it
never was met.

Vol-sizing, by contrast, engaged its mechanism for roughly 27% of the
window (mean exposure 0.7278, i.e. de-risked on ~27% of bars) — this is
exactly why volsizing's `max_dd` (net, `w_low=0.00`) is **-78.40%**, a
5.5pp smaller loss than the identical-to-benchmark overlay. Realised
volatility, unlike R, *was* elevated for a meaningful share of BTC's 2018
decline; the BDBB R-metric was not.

**SOL's picture is less extreme but points the same direction.** During
SOL's 2021-2022 drawdown, R was in its top tercile on 9.7% of bars (not
zero, but still low), giving `w_low=0.00` overlay a mean exposure of 0.9034
— nearly full exposure throughout. This is consistent with SOL's overlay
`max_dd` (net, `w_low=0.00`, -97.14% per `summary_metrics.csv`) being
*slightly worse* than its own benchmark (-96.80%): the overlay engaged
often enough to add turnover cost, but not often enough to meaningfully
reduce the drawdown. Vol-sizing again de-risked more (mean exposure 0.7350)
and posted a smaller loss (-93.75%).

**Conclusion: the data confirms the implied reading for BTC and is directionally
consistent for SOL.** This is a second, independent line of evidence against
the R-metric as a drawdown-protection signal, distinct from (e)'s
Sharpe-based "vol-sizing beats R-sizing at every cell" finding: it shows
specifically *why* — on the one loss event that would have mattered most to
avoid, R gave no warning at all on BTC and only a weak one on SOL, while
plain trailing volatility gave a stronger one on both.

## Files

- `run.R` — the script (self-contained, re-runnable; `cli::cli_abort()` on
  hard failures; no silent NA coercion; ~46s per asset for `bdbb_fit()`,
  ~3.5 min end-to-end for both assets). Extended (this pass) to also
  compute the max-drawdown window analysis in step 8b and write the two new
  files below.
- `close_hypotheses.R` — appends a `status`-only update row per sealed
  hypothesis (see the "Closure" note under the header table). Append-only
  and NOT idempotent by design: re-running it appends a second, redundant
  closure row per uuid. Already run once as part of this pass.
- `log_to_research_db.R` — writes `implementations`/`results`/`critiques`
  rows linked to the two sealed hypotheses. Already run once as part of
  this pass (verified beforehand that both target uuids resolve in the
  research log).
- `results/summary_metrics.csv` — every metric row summarised in (b)/(c)
  above, one row per (asset, variant, w_low, cost_type), 52 rows.
- `results/decision_table.csv` — the 8 (asset, w_low) verdicts in (g).
- `results/correlation_checks.csv` — the `cor(rank(R), rank(trailing_vol))`
  figures in (e).
- `results/turnover.csv` — annualised turnover per (asset, variant),
  referenced throughout (d)/(e)/(f).
- `results/drawdown_analysis.csv` — the max-drawdown peak-to-trough window,
  per asset, and the fraction-in-top-tercile / mean-exposure figures in (k).
- `results/daily_series.csv` — **committed**, 6,005 rows (both assets),
  ~0.92MB. Daily-downsampled per-bar series: `date`, `n_bars` (hourly bars
  aggregated into that day), `log_ret` (day's total compounded log return —
  exact, since log returns sum losslessly regardless of the aggregation
  window), `R_last`/`R_tercile_lag1_last` (end-of-day BDBB state),
  `frac_bars_top_tercile_R` (share of that day's hourly bars in R's top
  tercile), `trailing_realised_vol_last`/`vol_tercile_lag1_last`, and for
  benchmark / R-overlay (`w_low=0.00`) / vol-sizing (`w_low=0.00`): mean
  intraday exposure and the day's total net-of-cost strategy return. Any
  other `w_low` weight's exposure/return is a deterministic function of
  `R_tercile_lag1` alone (`exposure = w_low` if tercile `== 3` else `1.0`)
  and is fully reconstructable from `R_tercile_lag1_last`/`frac_bars_top_tercile_R`
  plus `log_ret` without needing a column per weight.
  **What is lost by downsampling to daily, stated explicitly rather than
  silently truncated:** intra-day exposure transitions (an overlay that
  flips exposure mid-day shows only that day's mean exposure, not when
  within the day it flipped) and per-bar return timing (only the day's
  total compounded return survives, not its intraday path). Total return
  over any date range, end-of-day regime state, and the within-day
  top-tercile share are all exact, not approximated.
- `results/analysis_sample_series.parquet` — the full **hourly** bar-level
  series (now also carrying `exposure_benchmark`, `ret_net_benchmark`,
  `exposure_overlay_w0.00`, `ret_net_overlay_w0.00`,
  `exposure_volsizing_w0.00`, `ret_net_volsizing_w0.00` in addition to the
  columns `daily_series.csv` downsamples from) for both assets, 134,184
  rows, 8.7MB. **Not committed** — well over a reasonable committed
  footprint for this exploration; it is fully regenerable by re-running
  `run.R`. `daily_series.csv` above is the committed, reproducibility-gap-closing
  substitute this dispatch adds; regenerate the hourly file locally with
  `run.R` for bar-level inspection beyond what the daily file preserves.
