# OSAP Survivorship-Gap Comparison

**Run:** `nix develop . --command Rscript explorations/osap_survivorship_gap/run.R` (requires `Rscript scripts/fetch_osap.R` first, and read access to the main checkout's `docs/_targets` store)
**Last output committed at:** `results/summary_metrics.csv` -- every number below is transcribed verbatim from that file, none hand-typed.

## Correction (#900 review round)

The first version of this script keyed our aggregated strategy return by the
**formation** month while `hold_ret` is the return **earned** the following
month. OSAP's `Mom12m` is keyed by the earn month. Joining our
formation-keyed series to OSAP's earn-keyed series by raw month index
therefore compared our month-`(t+1)` return to OSAP's month-`t` return -- a
one-month misalignment. This produced a near-zero (-0.051) correlation that
was read, in the original write-up, as evidence the two portfolios share
little common signal. Re-keying our series by the month its return is
actually earned (see `run.R`'s "CORRECTION" note and its `earn_midx`
construction, plus a new deterministic alignment guard) gives a correlation
of **+0.578** over the overlap window -- the two series clearly share real
common momentum signal. The Sharpe/CAGR/volatility comparison itself barely
moved (our own Sharpe was 0.192, now 0.187; OSAP's was 0.422, now 0.418),
since the bug was in how the two series were *joined*, not in either
series' own construction.

## What this measures, and what it does not

This compares a 12-2 cross-sectional momentum long-short built from **our own** `equity_daily`-derived panel (documented `survivorship_biased = TRUE`, `known_delistings = 0L`) against Open Source Asset Pricing's `Mom12m` -- the same nominal signal, built by Chen & Zimmermann (2022) from CRSP, a delisting-inclusive universe (#862 P1: 86.7% of firm-level permnos exit more than a year before the panel end, vs. 0% for our universe).

**This is not a clean survivorship-only measurement**, and the result below confirms why that caveat matters rather than being boilerplate. Beyond the delisting difference, the two series differ in:

- **Universe composition** -- our 529-ticker LTR universe (currently-listed large/mid caps, backfilled) vs. CRSP's full common-stock universe (which #862's P1 investigation found is likely broader than "US common stocks" alone -- it includes ETFs/ADRs/REITs, since the panel size *grows* past its 1998 peak by 2024, contradicting the well-documented US listing decline).
- **Portfolio construction** -- our independent equal-weighted terciles vs. OSAP's own documented sort (decile-based per `SignalDoc.csv`'s `LS Quantile` field for most signals, not necessarily terciles, and possibly a different weighting).
- **Sample overlap** -- OSAP's `Mom12m` series runs 1927-2024; ours is thinness-filtered (>= 30 stocks/month) to 1973-2026.

Any gap reported here is the **combined** effect of survivorship bias *and* these construction/universe differences. It cannot be attributed to survivorship alone -- that is a materially weaker claim than #816's headline "the bias is total, not partial", and this exploration reports it as such.

## Method

- **Momentum construction:** identical signal definition to `explorations/momentum_max_lottery/run.R` -- cumulative return over months `[t-12, t-2]` (11 months), skipping `t-1`, holding the realised return of `t+1`, look-ahead guarded via `dplyr::lag()`/`lead()` only. Re-implemented here against `targets::tar_read(stock_returns_monthly, store = <main checkout's docs/_targets>)` (a 529-ticker monthly panel already materialised by the live pipeline, per `R/plan_momentum_decomposition.R`) rather than re-querying `equity_daily` from scratch.
- **Join key:** our aggregated strategy return is keyed by `earn_midx` (formation month + 1, the calendar month the return is actually earned), matching OSAP's `Mom12m` convention. An alignment guard in `run.R` asserts `hold_ret` equals the original `monthly_ret` at `earn_midx` for every checked row before any metric is computed; a second, softer guard warns if the resulting correlation is negative (the pre-fix defect's signature).
- **OSAP data:** `hd_osap_load()` (this PR's loader), filtered to `predictor == "Mom12m"`.
- **Overlap window:** inner-joined on the (now-aligned) year-month key; 618 overlapping months.

## Results

| Series | Window | n (months) | CAGR | Ann. vol | Sharpe | Detection verdict |
|---|---|---:|---:|---:|---:|---|
| Our momentum (equity_daily) | Overlap (1973-2026) | 618 | +1.55% | 12.38% | +0.187 | **UNDERPOWERED** (needs 176.0yr) |
| OSAP Mom12m | Overlap (1973-2026) | 618 | +6.71% | 26.88% | +0.418 | adequately powered (needs 35.4yr) |
| Our momentum (equity_daily) | Full available sample | 634 | +1.77% | 12.33% | +0.205 | **UNDERPOWERED** (needs 147.8yr) |
| OSAP Mom12m | Full available sample (1927-2024) | 1176 | +4.68% | 28.34% | +0.381 | adequately powered (needs 42.7yr) |

**Correlation of monthly returns over the overlap window: +0.578.**

## Reading the gap

1. **OSAP's Mom12m has roughly 4x our CAGR, more than 2x our volatility, and roughly double our Sharpe**, over the identical 618-month window. This is directionally consistent with #816's argument -- a delisting-inclusive momentum short leg should capture more of the crash risk that a survivorship-biased panel structurally excludes, which would show up as *higher* volatility and (for a strategy with a positive mean) higher Sharpe on the CRSP-based series. Our own full-sample Sharpe (+0.205) is in the same range as the #816-cited figure from the independent `momentum_max_lottery` exploration (Sharpe 0.163 on a different but overlapping universe/window) -- the two independently-built "our own momentum" numbers corroborate each other.

2. **Both series are underpowered relative to the OTHER, in opposite directions on the vocabulary that matters:** our series is UNDERPOWERED (needs 147.8-176.0 years against 51.5-52.8 available), OSAP's is adequately powered. This is not a coincidence of scale -- OSAP's higher volatility widens its Sharpe enough, and its longer full sample (98 years) helps further, to clear the detection bar our own construction cannot clear even over the same overlap window length. Per `detection-power-required`, this means: **we cannot currently tell whether our own cross-sectional momentum has a real, non-zero Sharpe at all** -- a materially different and more specific finding than "survivorship makes our number too small".

3. **A moderate positive correlation (+0.578) confirms the two series share real common momentum signal**, once correctly aligned by earn month. This is the expected signature for the same nominal signal built on overlapping-but-biased-vs-unbiased universes: both are long recent winners and short recent losers in the same market, in the same months, so a meaningfully positive (but well below 1) correlation is exactly what "same signal, different universe/construction" predicts. It rules out the alternative reading the pre-fix (misaligned) -0.051 figure appeared to support -- that the two portfolios hold substantially different stocks in most months -- and instead supports treating the Sharpe/CAGR/volatility gap as differences acting on a **shared** underlying factor, not as two unrelated portfolios that happen to share a name.

## Verdict

**INDETERMINATE on "how much of the gap is survivorship" -- the two constructions differ on too many axes simultaneously to isolate that one variable from this comparison alone.** The +0.578 correlation strengthens (rather than complicates, as the pre-fix -0.051 figure appeared to) the case that this is a real, common-signal comparison rather than a comparison of two unrelated portfolios -- but it still cannot decompose the gap into "survivorship" vs. "universe" vs. "construction" shares. What this exploration DOES establish, directly and without that caveat:

- Our own 12-2 momentum long-short, built from `equity_daily`, is **not detectably different from a zero Sharpe** at any sample length we currently have (147.8-176.0 years needed vs. ~52-53 available) -- consistent with, and independently corroborating, #816's and `momentum_max_lottery`'s prior finding.
- OSAP's `Mom12m`, over the identical calendar window, **is** adequately powered and shows a materially larger CAGR, volatility, and Sharpe.
- The two series **do share real common signal** (correlation +0.578, correctly aligned by earn month) -- so a future attempt to isolate survivorship's contribution specifically would need to hold universe and sort methodology fixed, which requires the firm-level OSAP characteristic VALUES (not just the pre-built portfolio returns used here) joined to a permno-to-ticker crosswalk -- both open sub-tasks per #862's closing comment, neither available today.

## Cross-check: does `momentum_max_lottery/run.R` have the same defect?

No. `explorations/momentum_max_lottery/run.R` never joins its strategy
returns to an externally-keyed series by calendar month -- its only
comparison to Zadeh (2026)/Klement is against fixed published annualised
percentages (e.g. "16.5%"), evaluated by comparing our own annualised
metric to a scalar, not by an `inner_join()` on a month index against a
second time series. Its `midx` (formation month) key is used consistently
throughout its own bucket/strategy construction, so the formation-vs-earn
distinction that broke this exploration's OSAP join has no join to break
there. No fix is needed in that script.

## Files

- `run.R` -- the script (self-contained, re-runnable, `cli::cli_abort()` on hard failures, no silent NA coercion, alignment-guarded per the Correction above).
- `results/summary_metrics.csv` -- every metric row in the table above, plus the correlation, in one file. No panel-shaped or per-month OSAP data is committed (#862 P3 -- no data licence found; operating position is compute-freely, publish-derived-statistics-only).
