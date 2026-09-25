# OSAP Survivorship-Gap Comparison

**Run:** `nix develop . --command Rscript explorations/osap_survivorship_gap/run.R` (requires `Rscript scripts/fetch_osap.R` first, and read access to the main checkout's `docs/_targets` store)
**Last output committed at:** `results/summary_metrics.csv` -- every number below is transcribed verbatim from that file, none hand-typed.

## What this measures, and what it does not

This compares a 12-2 cross-sectional momentum long-short built from **our own** `equity_daily`-derived panel (documented `survivorship_biased = TRUE`, `known_delistings = 0L`) against Open Source Asset Pricing's `Mom12m` -- the same nominal signal, built by Chen & Zimmermann (2022) from CRSP, a delisting-inclusive universe (#862 P1: 86.7% of firm-level permnos exit more than a year before the panel end, vs. 0% for our universe).

**This is not a clean survivorship-only measurement**, and the result below confirms why that caveat matters rather than being boilerplate. Beyond the delisting difference, the two series differ in:

- **Universe composition** -- our 529-ticker LTR universe (currently-listed large/mid caps, backfilled) vs. CRSP's full common-stock universe (which #862's P1 investigation found is likely broader than "US common stocks" alone -- it includes ETFs/ADRs/REITs, since the panel size *grows* past its 1998 peak by 2024, contradicting the well-documented US listing decline).
- **Portfolio construction** -- our independent equal-weighted terciles vs. OSAP's own documented sort (decile-based per `SignalDoc.csv`'s `LS Quantile` field for most signals, not necessarily terciles, and possibly a different weighting).
- **Sample overlap** -- OSAP's `Mom12m` series runs 1927-2024; ours is thinness-filtered (>= 30 stocks/month) to 1973-2026.

Any gap reported here is the **combined** effect of survivorship bias *and* these construction/universe differences. It cannot be attributed to survivorship alone -- that is a materially weaker claim than #816's headline "the bias is total, not partial", and this exploration reports it as such.

## Method

- **Momentum construction:** identical signal definition to `explorations/momentum_max_lottery/run.R` -- cumulative return over months `[t-12, t-2]` (11 months), skipping `t-1`, holding the realised return of `t+1`, look-ahead guarded via `dplyr::lag()`/`lead()` only. Re-implemented here against `targets::tar_read(stock_returns_monthly, store = <main checkout's docs/_targets>)` (a 529-ticker monthly panel already materialised by the live pipeline, per `R/plan_momentum_decomposition.R`) rather than re-querying `equity_daily` from scratch.
- **OSAP data:** `hd_osap_load()` (this PR's loader), filtered to `predictor == "Mom12m"`.
- **Overlap window:** inner-joined on year-month; 619 overlapping months.

## Results

| Series | Window | n (months) | CAGR | Ann. vol | Sharpe | Detection verdict |
|---|---|---:|---:|---:|---:|---|
| Our momentum (equity_daily) | Overlap (1973-2024) | 619 | +1.61% | 12.38% | +0.192 | **UNDERPOWERED** (needs 167.8yr) |
| OSAP Mom12m | Overlap (1973-2024) | 619 | +6.81% | 26.87% | +0.422 | adequately powered (needs 34.8yr) |
| Our momentum (equity_daily) | Full available sample | 634 | +1.77% | 12.33% | +0.205 | **UNDERPOWERED** (needs 147.8yr) |
| OSAP Mom12m | Full available sample (1927-2024) | 1176 | +4.68% | 28.34% | +0.381 | adequately powered (needs 42.7yr) |

**Correlation of monthly returns over the overlap window: -0.051.**

## Reading the gap

1. **OSAP's Mom12m has roughly 4x our CAGR, more than 2x our volatility, and roughly double our Sharpe**, over the identical 619-month window. This is directionally consistent with #816's argument -- a delisting-inclusive momentum short leg should capture more of the crash risk that a survivorship-biased panel structurally excludes, which would show up as *higher* volatility and (for a strategy with a positive mean) higher Sharpe on the CRSP-based series. Our own full-sample Sharpe (+0.205) is in the same range as the #816-cited figure from the independent `momentum_max_lottery` exploration (Sharpe 0.163 on a different but overlapping universe/window) -- the two independently-built "our own momentum" numbers corroborate each other.

2. **Both series are underpowered relative to the OTHER, in opposite directions on the vocabulary that matters:** our series is UNDERPOWERED (needs 147.8-167.8 years against 51.6-52.8 available), OSAP's is adequately powered. This is not a coincidence of scale -- OSAP's higher volatility widens its Sharpe enough, and its longer full sample (98 years) helps further, to clear the detection bar our own construction cannot clear even over the same overlap window length. Per `detection-power-required`, this means: **we cannot currently tell whether our own cross-sectional momentum has a real, non-zero Sharpe at all** -- a materially different and more specific finding than "survivorship makes our number too small".

3. **The near-zero (-0.051) correlation is the finding that most complicates a clean "survivorship explains the gap" reading.** If the two series were the same signal on overlapping-but-biased-vs-unbiased universes, a reasonably strong *positive* correlation would be the expected signature (both should be long recent winners, short recent losers, in the same market, in the same months). A correlation this close to zero is more consistent with the two portfolios holding substantially different stocks in most months than with "the same portfolio, minus its worst tail". This is reported as an honest, somewhat surprising result, not smoothed into the "survivorship" story -- per `research-log-honesty`, a null or unexpected result is exactly the kind of finding worth logging plainly. Plausible (untested here) contributors: OSAP's construction may sort within CRSP deciles rather than terciles, weight differently, or draw from a universe broad enough (see the "universe composition" caveat above) that the *effective* cross-section barely overlaps with our 529-name large/mid-cap set in a typical month.

## Verdict

**INDETERMINATE on "how much of the gap is survivorship" -- the two constructions differ on too many axes simultaneously to isolate that one variable from this comparison alone.** What this exploration DOES establish, directly and without that caveat:

- Our own 12-2 momentum long-short, built from `equity_daily`, is **not detectably different from a zero Sharpe** at any sample length we currently have (147.8-167.8 years needed vs. ~52-53 available) -- consistent with, and independently corroborating, #816's and `momentum_max_lottery`'s prior finding.
- OSAP's `Mom12m`, over the identical calendar window, **is** adequately powered and shows a materially larger CAGR, volatility, and Sharpe.
- The two series are **not simply the same portfolio with the tail removed** -- their near-zero correlation means construction/universe differences are doing real work alongside (or instead of) survivorship, and a future attempt to isolate survivorship's contribution specifically would need to hold universe and sort methodology fixed, which requires the firm-level OSAP characteristic VALUES (not just the pre-built portfolio returns used here) joined to a permno-to-ticker crosswalk -- both open sub-tasks per #862's closing comment, neither available today.

## Files

- `run.R` -- the script (self-contained, re-runnable, `cli::cli_abort()` on hard failures, no silent NA coercion).
- `results/summary_metrics.csv` -- every metric row in the table above, plus the correlation, in one file. No panel-shaped or per-month OSAP data is committed (#862 P3 -- no data licence found; operating position is compute-freely, publish-derived-statistics-only).
