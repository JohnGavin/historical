# Momentum x Lottery-Skewness (MAX) Double Sort

**Run:** `nix develop . --command Rscript explorations/momentum_max_lottery/run.R`
**Last output committed at:** `results/` (regenerate by re-running the command above; every number below is transcribed verbatim from that run, none hand-typed or carried over from an earlier draft).

## Provenance limit (read this before reading anything else)

The claim being tested comes from Joachim Klement's Substack post, ["The price momentum of lottery tickets"](https://klementoninvesting.substack.com/p/the-price-momentum-of-lottery-tickets) (2026-09-09), which summarises a 2026 paper by Reihaneh Haghighi Zadeh. **The underlying Zadeh paper was NOT read directly for this exploration — only Klement's summary of it.** Every "vs Zadeh" comparison below is therefore a comparison against a third party's characterisation of the paper, not the paper's own methodology, sample construction, or robustness checks. If Klement's summary omits or simplifies a detail of Zadeh's actual construction (universe, weighting, exact skip convention), that detail is invisible to this comparison.

## (a) The claim being tested

Zadeh (2026), per Klement, reports the following annualised returns for US equities, 1962-2023:

| Bucket | Zadeh's reported annualised return |
|---|---|
| Traditional momentum winners (high 12-2) | 16.5% |
| Traditional momentum losers (low 12-2) | 0.1% |
| Lottery-like winners (high 12-2, high MAX) | 15.0% |
| Lottery-like losers (low 12-2, high MAX) | **-14.8%** |

The interesting structure in this table: the long leg is barely touched by the lottery filter (15.0% vs 16.5%), while the short leg is transformed (-14.8% vs 0.1%). The entire claimed enhancement lives in the short leg — lottery stocks allegedly do fine while momentum is positive, and crash hard when it turns, making them a proposed source of momentum crashes.

**Signal definitions used here** (as specified in the exploration brief, implemented literally — see the header comment in `run.R` for the exact look-ahead-guard mechanics):

- **Momentum (12-2):** cumulative return over months `[t-12, t-2]` inclusive (11 monthly returns), explicitly skipping month `t-1`.
- **MAX:** the maximum single-day return within month `t-1` (Bali, Cakici & Whitelaw 2011).
- **Formation/holding:** rank at the close of month `t`, hold the realised return of month `t+1`. As a side effect of following the brief's exact wording, month `t` itself is not used by either signal (momentum stops at `t-2`, MAX is drawn from `t-1`) — this is more conservative than strictly necessary to avoid look-ahead bias, but it removes any ambiguity about whether the future leaks into the signal.
- **Weighting:** equal-weighted only. Value-weighting was checked and explicitly skipped — see §(f) below.

## (b) Detection-power verdict — read this before any Sharpe ratio

Per this repo's `detection-power-required` rule, every positive-Sharpe row below carries its own detection-power verdict, computed via `hd_detection_power(sharpe_annual, n_obs, ann_factor = 12)`.

**Long-only corner and single-sort buckets are all adequately powered** (52.8 years of monthly data is generous for the Sharpes observed):

| Row | Sharpe | n (months) | min years for 80% power | Verdict |
|---|---:|---:|---:|---|
| High-mom, high-MAX (lottery winners) | +1.150 | 633 | 4.8 | adequately powered |
| High-mom, low-MAX | +1.030 | 633 | 5.9 | adequately powered |
| Low-mom, high-MAX (lottery losers) | +0.765 | 633 | 10.6 | adequately powered |
| Low-mom, low-MAX | +0.826 | 633 | 9.2 | adequately powered |
| Single-sort high-mom (traditional winners) | +1.147 | 633 | 4.8 | adequately powered |
| Single-sort low-mom (traditional losers) | +0.871 | 633 | 8.2 | adequately powered |

**The three long/short strategies are a completely different story — every one of them is UNDERPOWERED, most by an enormous margin:**

| Strategy | Sharpe | n (months) | min years needed for 80% power | Verdict |
|---|---:|---:|---:|---|
| mom_plain — GROSS | +0.163 | 633 | 231.4 | **UNDERPOWERED** (need 4.4x the available sample) |
| mom_lottery — GROSS | +0.221 | 633 | 126.1 | **UNDERPOWERED** (need 2.4x the available sample) |
| mom_nonlottery — GROSS | +0.200 | 633 | 154.8 | **UNDERPOWERED** (need 2.9x the available sample) |
| mom_plain — NET | -0.082 | 633 | N/A | N/A — non-positive Sharpe, no positive effect to detect |
| mom_lottery — NET | +0.027 | 633 | **8467.5** | **UNDERPOWERED** (need 160x the available sample) |
| mom_nonlottery — NET | -0.162 | 633 | N/A | N/A — non-positive Sharpe, no positive effect to detect |

The long/short strategy Sharpes are all so close to zero that even 52.8 years of monthly returns cannot reliably distinguish them from a coin flip at the standard one-sided alpha = 0.05, target power = 0.80. `mom_lottery` net of costs needs **8,467 years** of data to be adequately powered at its own observed Sharpe of +0.027 — a number that itself signals the observed Sharpe is indistinguishable from zero for any practical purpose.

## (c) Results tables

### Four corner buckets vs Zadeh's table

| Bucket | Our ann. return (CAGR) | Zadeh (via Klement) | Sharpe | Max DD | Skew |
|---|---:|---:|---:|---:|---:|
| High-mom, high-MAX (lottery winners) | **+26.11%** | 15.0% | +1.150 | -57.12% | -0.183 |
| High-mom, low-MAX (no Zadeh figure) | +15.79% | — | +1.030 | -42.46% | -0.161 |
| Low-mom, high-MAX (lottery losers) | **+19.15%** | **-14.8%** | +0.765 | -54.70% | +2.634 |
| Low-mom, low-MAX (no Zadeh figure) | +12.85% | — | +0.826 | -48.00% | +0.620 |

The low-mom/high-MAX ("lottery losers") corner is the headline test and it is **not just smaller than Zadeh's -14.8%, it is the opposite sign**: +19.15% vs -14.8%. It is also *larger*, not smaller, than the low-mom/low-MAX ("non-lottery losers") corner (+19.15% vs +12.85%) — the MAX filter moves the loser leg in the **opposite direction** to what the claim predicts. See §(d) for why this is expected given our data, not a refutation of Zadeh's underlying claim.

### Traditional (single-sort) momentum legs vs Zadeh's table

| Leg | Our ann. return (CAGR) | Zadeh (via Klement) | Sharpe |
|---|---:|---:|---:|
| High-mom (traditional winners) | +19.91% | 16.5% | +1.147 |
| Low-mom (traditional losers) | **+16.67%** | **+0.1%** | +0.871 |

The winner leg is at least directionally and magnitude-comparable (both very high, consistent with a survivorship-biased, large-cap-only, 64-year sample). The loser leg is not: +16.67% vs +0.1% is a huge divergence, and it is the *same* leg (the short/loser side) that diverges even more badly once the lottery filter is added (previous table). This is a consistent pattern, not noise — see §(d).

### Three long/short strategies — gross and net

| Strategy | Leg | Gross ann. ret | Gross Sharpe | Net ann. ret | Net Sharpe | Turnover (long/short) |
|---|---|---:|---:|---:|---:|---:|
| mom_plain (MAX-blind baseline) | L/S | +1.27% | +0.163 | -2.19% | -0.082 | 19.6% / 19.3% |
| mom_lottery (Zadeh's construction) | L/S | -0.69% | +0.221 | -4.97% | +0.027 | 51.5% / 54.2% |
| mom_nonlottery (the control) | L/S | +1.73% | +0.200 | -2.78% | -0.162 | 65.1% / 62.8% |

(Note: CAGR can be negative even with a positive arithmetic-mean-based Sharpe when monthly volatility is high and compounding drag dominates — see `results/summary_metrics.csv` for both `ann_ret_cagr` and `ann_ret_arith`.)

**Does `mom_lottery` beat `mom_nonlottery` (the control)?**

- **Gross:** Sharpe 0.221 vs 0.200 — `mom_lottery` nominally wins, by a margin (0.021) that is a small fraction of either strategy's own standard error at n=633 (both are underpowered at Sharpes an order of magnitude larger than this gap).
- **Net of costs and borrow:** Sharpe 0.027 vs -0.162 — `mom_lottery` again nominally wins, mostly because `mom_nonlottery`'s much higher turnover (65.1%/62.8% vs 51.5%/54.2%) makes it pay more in costs, not because its underlying gross signal is meaningfully worse.

**Verdict on "does MAX filtering do anything": no defensible edge.** Every one of these numbers sits inside a Sharpe range this sample cannot detect from zero (see §(b)). A 0.02-point Sharpe gap between two strategies that each individually need 2-3x (gross) to 160x (net, for `mom_lottery`) more data than we have is not evidence that the MAX filter is doing anything real. The honest reading is: **we cannot tell whether `mom_lottery` beats `mom_nonlottery`,** and the nominal "win" is consistent with noise.

## (d) Survivorship verdict: **INDETERMINATE**

`hd_datasets()[["equity_daily"]]` is documented `survivorship_biased = TRUE, known_delistings = 0L`. This was verified empirically in this run, not just asserted from the registry description: of 502 tickers passing the minimum-history filter, **zero** have a return series ending more than one year before the panel's end date (2026-04-13) — i.e., every single ticker in the universe is either still trading today or stopped within the last year (normal, not a delisting signature). Enron, Lehman, Bear Stearns, WorldCom, and WaMu are confirmed absent from the 530-ticker raw universe.

Zadeh's -14.8% headline is a claim specifically about the return of stocks that go on to crash hardest (low prior momentum, high lottery-skew) — precisely the population a survivorship-biased panel structurally cannot contain. Our short leg can only ever include names that eventually recovered enough to still be listed today (Yahoo Finance, present-day constituents, backfilled); the worst outcomes in the true population are missing by construction.

**Classification: INDETERMINATE, not FAIL.** A "FAIL" verdict would imply we measured the effect and it wasn't there; a "PASS" would imply we measured it and confirmed it. Neither is correct here — this is not a question our data can answer either way. A smaller *or* larger measured effect is equally uninformative about the true -14.8%, because the population being sampled is different in a way that specifically removes the tail the claim is about. Per `checks-must-distinguish-unknown.md`: a check whose output cannot vary with the thing being tested is not a check on that thing. Our loser-leg results (+16.67% single-sort, +19.15% lottery corner) are consistent with what survivorship bias predicts — a *positive* loser-leg return, because our "losers" are companies that had a bad 11-month stretch and recovered, not companies that went to zero — but this consistency is circumstantial, not confirmatory: we cannot rule out that Zadeh's -14.8% would also fail to replicate on a delisting-inclusive US panel for other reasons (universe breadth, exact skip convention, weighting).

**A second, related limitation worth naming explicitly:** this universe (502 large/mega-cap, mostly current or recent S&P-500-style names) is not just survivorship-biased, it is also skewed toward *large-cap* survivors. The empirical MAX/lottery literature (Bali, Cakici & Whitelaw 2011 and follow-ons) documents the effect as substantially stronger among small- and micro-cap stocks — exactly the segment most likely to be delisted and therefore most under-represented in this panel. Both biases point the same direction: our data is structurally the *least* likely subset of the US equity market to reproduce a genuine lottery-crash effect, even if the effect is real in the broader market Zadeh studied.

## (e) What would be needed to answer this properly

1. **A delisting-inclusive US equity panel spanning 1962-2023**, such as **CRSP** (the standard academic source, and very likely close to what Zadeh actually used) or a comparably complete commercial alternative (e.g. a vendor's full historical constituent file with delisting returns coded, not backfilled from currently-listed names). Without delisting returns, the short leg of any loser/lottery-loser strategy is unmeasurable in this repo's data, not merely biased — the worst outcomes are absent, not attenuated.
2. **A broader cap-weighted universe reaching into small/micro-cap territory**, since the MAX effect's magnitude in the literature is cap-dependent and our large-cap-only panel is the wrong population to test the strongest form of the claim.
3. **A genuine point-in-time market-cap series** (not the static current-day snapshot in `hd_datasets()[["metadata"]]`) if a value-weighted replication is ever wanted — see §(f).
4. **Direct access to Zadeh (2026)** rather than Klement's summary, to confirm the exact skip/lag convention, universe construction (all NYSE/AMEX/NASDAQ vs S&P 500-style), and weighting scheme actually used, several of which materially affect a replication attempt and are not fully specified in a Substack summary.

## (f) Does this survive our gates?

**No — it does not clear the first gate as a tradeable strategy, and the data cannot settle the underlying academic claim either way.**

The four corner buckets and the two single-sort legs are all comfortably powered and show large, statistically detectable positive Sharpes (0.77-1.15) — but every one of them is a *long-only* result in a 64-year bull-market-heavy US large-cap sample, which is expected and unremarkable on its own; it says nothing about the lottery-momentum interaction specifically. The actual test of the claim — does adding a MAX filter to a momentum long/short strategy do something useful — comes down to three long/short Sharpes clustered between 0.16 and 0.22 gross, none of which our 52.8-year sample can distinguish from zero, and one of which (`mom_lottery`, the exact construction Zadeh's finding implies) needs over 8,000 years of net-of-cost data to reach conventional power. The nominal "win" of `mom_lottery` over `mom_nonlottery` is real in the printed numbers but not a finding — it is noise dressed as a comparison. Separately and more fundamentally, the specific -14.8% short-leg claim cannot be tested on a survivorship-biased, large-cap-only panel at all, regardless of sample length: the stocks whose returns would decide the question are structurally absent from the data. A negative-but-honest result: this exploration does not support deploying a momentum-lottery strategy, and it cannot confirm or refute Zadeh's own number. Both are complete, successful outcomes of the test as run.

## Files

- `run.R` — the script (self-contained, re-runnable, `cli::cli_abort()` on hard failures, no silent NA coercion).
- `results/ticker_history_stats.csv` — per-ticker trading-day counts and date ranges (survivorship-check input).
- `results/dropped_thin_months.csv` — the 125 calendar months dropped for having fewer than 30 stocks with a valid signal (mostly 1962-1966, when the current 502-ticker universe's oldest constituents were still ramping up their listing history).
- `results/stock_month_signals.parquet` — the full per-ticker, per-formation-month signal table (momentum, MAX, terciles, holding return); ~198,761 rows. Parquet, not CSV, to keep the committed footprint reasonable (~9.4MB vs ~23MB as CSV).
- `results/monthly_bucket_returns.csv` — the 3x3 double-sort bucket equal-weighted monthly returns.
- `results/monthly_mom_singlesort_returns.csv` — the single-sort (MAX-blind) momentum tercile monthly returns.
- `results/strategy_returns_mom_plain.csv`, `results/strategy_returns_mom_lottery.csv`, `results/strategy_returns_mom_nonlottery.csv` — monthly long/short returns per strategy, gross and net, with turnover-implied cost components.
- `results/turnover.csv` — per-leg average monthly turnover for each strategy.
- `results/summary_metrics.csv` — every metric row printed in §(b)/(c) above, in one table, including detection-power fields.
