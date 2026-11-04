# OLMAR-1 universe findings: #976 (20 vs 30 tickers) and #977 (survivorship)

Read-only investigation, 2026-11-02. No hypotheses edited, no pipeline re-run,
no network, no downloads. Verdict words: PASS / FAIL / INDETERMINATE.
Sources are files in this repo plus a read-only read of the main checkout's
built store (`docs/_targets`, `olmar_prices`, built 2026-09-21 13:06:04).

## #976: why the ten sector ETFs are absent

Missing: XLF, XLE, XLV, XLK, XLI, XLP, XLU, XLB, XLY, XLRE.

| Question | Verdict | Evidence |
|---|---|---|
| Were they declared? | PASS (declared) | `R/plan_olmar.R:41-45` lists 30 tickers incl. all ten. They have been in the list since the first commit 59d1aa4 (2026-05-23); no commit ever removed them (`git log -S"XLRE"`). |
| Deliberate cut in code? | FAIL (no such cut exists) | No filter in `olmar_prices` (`R/plan_olmar.R:50-92`) names or excludes them. The only drops are a failed fetch (`:60-63`, a warning) and fewer than `window + 1` observations (`:80-89`, a warning). |
| Dropped for short history? | FAIL (not that) | Nine of the ten (all except XLRE, listed Oct 2015) are sector funds that existed in 2010. XLRE would still have far more than `window + 1` rows. More decisive: the stored `olmar_prices` has `warnings = NA` in `tar_meta`, so neither warning path fired. |
| What the stored matrix holds | PASS (observed) | `tar_read(olmar_prices)` columns: date + SPY QQQ IWM DIA AAPL MSFT GOOGL AMZN META JPM BAC GS JNJ PFE UNH XOM CVX HD WMT PG = 20 tickers. Every one of the ten sector ETFs is missing; all four index ETFs and all 16 stocks are present. The ten missing are exactly the sector funds, not a random subset. |
| Why do they not reach the matrix | INDETERMINATE | The fetch is `hd_ohlcv(tkr, from=...)` (`:55`), which routes non-crypto tickers to `equity_daily` (`packages/historicaldata/R/query.R:498-508`). No error and no warning was recorded, so the call evidently returned zero rows for these tickers and the pivot (`:76-78`) dropped them without comment. That points to the tickers being absent from `equity_daily`, i.e. a data-source gap, but I could not confirm it: the `equity_daily` parquet (HuggingFace) is not in the repo and I had no network. |

What I could not determine: whether the tickers were never in the upstream
`equity_daily` universe (672 tickers per `query.R:80`; `DATA_SOURCING_LESSONS.md:100`
mentions a 1,622-ticker producer that was never run end-to-end) or were lost
in the repo's own copy. That needs a one-line read of the distinct ticker
column of `equity_daily` (a download). The deliberate-cut and short-history
explanations are ruled out; data-source gap vs ingest gap is open.

Defect independent of the cause: a ticker that returns no rows is dropped
silently (zero-row frames survive `purrr::compact()` and disappear in the
pivot). The "~30 tickers" comment at `:39` and the declared list therefore
disagree with what is tested. The universe prose written to the log and
dashboard uses `ncol(olmar_prices) - 1` (`:174`, `:365`), i.e. the observed 20,
while the params carry 30 (I did not read the stored hypothesis claim text).
Suggested follow-up (not done):
make `olmar_prices` abort or loudly record when a declared ticker is absent.

Side observation: the stored matrix ends 2026-04-13, while the issue quotes
2026-02-27 (a different build); not investigated.

## #977: what can be established about survivorship in the fixed 20 tickers

| Question | Verdict | Evidence |
|---|---|---|
| Is the list static? | PASS | Hard-coded in `R/plan_olmar.R:41-45` (no point-in-time membership source). Same list reused by `R/plan_mean_reversion.R:40-41`. |
| When was it chosen? | PASS (date), INDETERMINATE (basis) | Written in 59d1aa4 on 2026-05-23, so after the whole 2010-2026 test window: chosen with hindsight in time. The comment `:39` says "MVP proxy for S&P 500", giving no selection rule. |
| Is the data source survivorship-biased? | FAIL (it is biased) | `query.R:80-87`: `equity_daily` holds currently-listed tickers only, zero delistings recorded in 56 years, failed firms absent; the registry flags `survivorship_biased`; `hd_check_survivorship_bias()` warns. That is the dataset every one of the 20 tickers is read from. |
| Are the 16 stocks survivors? | FAIL (all are current mega-caps) | AAPL MSFT GOOGL AMZN META JPM BAC GS JNJ PFE UNH XOM CVX HD WMT PG. All are among the largest US companies as of the 2026 list date; META's series starts 2012-05-18 (its listing), so it enters mid-sample. Choosing today's largest names and testing from 2010 is the textbook look-ahead pattern. I did not rank 2010 market caps (no source in the repo), so the size of the effect is INDETERMINATE. |
| Are the 4 index ETFs biased? | PASS (not by selection) | SPY QQQ IWM DIA are index trackers that existed on 2010-01-04. |
| Direction of bias | PASS (direction), INDETERMINATE (size) | Upward for long-only: `query.R:84-86` cites +1 to +3 pp/year CAGR (literature estimate, unquantified for this list). The issue's own point holds: equal-weight on the same 20 shares the bias, so the OLMAR-vs-equal-weight comparison is less affected than the absolute Sharpe. |
| Overall verdict for #977 | "Biased: probably, size unknown" | Mechanism established from repo files (hindsight-dated static list, survivorship-flagged source, 16 of 20 current mega-caps). Not established: magnitude, which needs 2010 point-in-time constituents or market caps plus delisting records (the remediation in issue #150), neither available offline. |

Could not determine, and why: the 2010 liquidity and size rank of each ticker
(no point-in-time source in the repo, no network); whether any 2010-era peer
was delisted (same reason; `equity_daily` records zero delistings so it cannot
show it).

## Addendum 2026-11-03: resolution of the open items (#976, #977)

Read-only DuckDB query on the local copy of the pipeline's input,
`data/dist/equity_daily.parquet` (1,622 tickers, 7,123,143 rows, last bar
2026-04-13), run through `hd_ohlcv()`'s source table.

### #976: the open question is closed

| Ticker | Rows in equity_daily |
|---|---|
| XLF XLE XLV XLK XLI XLP XLU XLB XLY XLRE | 0 each (only unrelated LSE products `XL3S.L`, `XLE3.L`, `XLF3.L`, `XLGS.L`, `XLPE.L` match `XL%`) |

Verdict: **data-source gap**. The ten sector SPDRs were never in `equity_daily`,
so `hd_ohlcv()` returned zero rows and `olmar_prices` dropped them without a
warning (the earlier INDETERMINATE row). Not a deliberate cut, not short
history. Adding them needs a new data source and is not a trivial fix, so the
declared universe was corrected to the 20 tested tickers (`olmar_params$tickers`,
with the reason in a code comment) and the gate S48 (`qa_olmar_universe`,
`tests/testthat/test-qa-olmar-universe-s48.R`) fails whenever declared and
tested universes differ. XLRE would in any case start 2015-10, after a
2010-01-04 start. A future run with the ten added must be logged as a new
implementation row, not a re-tune.

### #977: first bar per ticker (from the data the pipeline reads)

| First bar | Tickers |
|---|---|
| before 1990 | CVX JNJ PG XOM (1962), PFE (1972), WMT (1972), BAC (1973), JPM (1980), AAPL (1980), HD (1981), UNH (1984), MSFT (1986) |
| 1990s to 2004 | SPY (1993), AMZN (1997), DIA (1998), QQQ (1999), GS (1999), IWM (2000), GOOGL (2004-08-19) |
| after 2010-01-04 | META (2012-05-18) |

19 of 20 existed and traded on 2010-01-04 (the first bar is only the first in
the source, so existence is shown, liquidity is not). META enters mid-sample.

**Verdict: biased, probably, size unknown.** Mechanism: the list was written on
2026-05-23 (commit 59d1aa4), after the whole test window, from today's
mega-caps (16 of 20), and the only source, `equity_daily`, records no
delistings. Cannot tell the magnitude: no 2010 point-in-time constituents or
market caps in the repo (issue #150). The OLMAR-vs-equal-weight comparison
shares the bias, so it is less affected than the absolute Sharpe.

### Research-log rows that need correcting (after #1020 merges; not edited here)

The OLMAR-1 hypothesis row declares a 30-ticker universe. It should state the
20 tested tickers, the ten SPDRs absent from `equity_daily`, and a
survivorship caveat, as a new row appended by the seed script
(`scripts/seed_olmar_research_log.R`), not an edit (the log is append-only).

## #977 addendum (2026-11-04): size of the survivorship bias

Script: `scripts/olmar_survivorship_977.R` (tests: `tests/testthat/test-olmar-survivorship-977.R`).
Outputs: `docs/olmar-survivorship-977/*.csv` (a snapshot of one run; re-run the script to regenerate).
Exit codes: 0 estimate / 1 none / 2 usage / 3 INDETERMINATE.

Method. Membership of the S&P 500 on the first trading day of the window (2010-01-04; snapshot dated 2009-12-30,
501 tokens) comes from the free `fja05680/sp500` constituents-history CSV (data only, no code taken; md5
`419150594a46f6758a8afab750aa5784`). The 2010 members that `equity_daily` can supply are ranked by median
daily dollar volume (close x volume) over the six months before the window (a liquidity proxy, NOT market cap:
no point-in-time shares outstanding exist here, #150). The alternative universe keeps the four index ETFs (they never
appear in S&P 500 history and existed in 2010) and replaces the 16 hindsight stocks with the top 16 by that rank.
OLMAR-1 is `olmar_backtest()` with `olmar_params` evaluated from `R/plan_olmar.R` itself; the equal-weight
benchmark is the same function with `leverage = 0`. Same data, same window (2010-01-04 .. 2026-04-13), same costs.
Validation of the harness (type-B check): the "current" row reproduces the stored `olmar_metrics` target exactly
(Training 15.66 / 16.46 / 0.921, Testing 14.96 / 24.61 / 0.538, Full 15.96 / 18.67 / 0.780 for CAGR% / vol% / Sharpe, max DD -33.76).

Candidate data inputs and the outcome for each:

| Source | Outcome |
|---|---|
| `fja05680/sp500` constituents history CSV, GitHub raw (HTTP 200, 7.8 MB, 2,595 rows 1996-01-02 .. 2019-01-11) | USED. Parsed by `.osv_parse_membership()`. |
| SEC EDGAR shares outstanding x close (true market cap) | NOT TRIED: needs point-in-time shares for ~500 names and a symbol-to-CIK map for delisted firms; the ranking proxy above was used instead. Stated limit, not a failure. |

### What equity_daily cannot see (missing-name count)

| Class (2010-01-04 snapshot, 501 members) | n |
|---|---|
| usable (in `equity_daily`, trading at window start) | 268 |
| in `equity_daily` but series starts after the window start | 1 |
| absent from `equity_daily`, not flagged by the source | 135 |
| flagged by the source as removed (`SYM-YYYYMM`; delisted, acquired or merged) | 97 |

Names `equity_daily` cannot supply: 232 of 501 (46.3%). Nine of the 97 flagged tickers have a base symbol that is
reused by a different company in `equity_daily`; they are excluded, never used as the old firm's series. The 135 unflagged
absentees mix later acquisitions, renames and names never ingested; this run cannot split them, so "232 failed firms"
would be wrong, and "232 names no backtest on this data can ever hold" is right.

### Numbers (Full Period, net of 10 bps, rf-adjusted Sharpe)

| Universe | OLMAR-1 Sharpe | OLMAR-1 CAGR % | Equal-weight Sharpe | Equal-weight CAGR % |
|---|---|---|---|---|
| Current 20 | 0.780 | 15.96 | 0.945 | 17.56 |
| 4 ETFs + top-16 2010 members by 2009H2 dollar volume | 0.515 | 12.72 | 0.716 | 15.65 |
| Delta (current minus alternative) | +0.265 | +3.24 pp | +0.229 | +1.91 pp |
| 200 random same-size alternatives from the 268 eligible: median [p05, p95] | 0.728 [0.541, 0.897] | 15.83 [12.43, 19.39] | 0.808 [0.693, 0.924] | 15.83 [14.15, 17.80] |
| Current vs the random draws | above 68% of draws | above 52% | above 98% of draws | above 93% |

OLMAR-1 minus equal-weight Sharpe: current -0.166; alternative -0.201; random-draw median -0.082 (168 of 200 draws negative).

Of the 16 hindsight stocks, 15 were S&P 500 members in 2010 and their 2009H2 dollar-volume ranks among the 268 eligible
members were 1 to 55 (median 14); META (listed 2012-05-18) is the one name that did not exist at the window start.
So the list is mostly "2010 giants that stayed giants" plus one post-window IPO.

### Verdicts

| Question | Verdict | Evidence and limits |
|---|---|---|
| Could a hindsight-free 2010 universe be built from a free machine-readable source? | PASS (partly) | Membership yes; point-in-time size no. Dollar volume is the proxy. |
| Is the equal-weight Sharpe flattered by the hindsight list? | FAIL (flattered) | 0.945 sits at the 98th percentile of 200 random same-size 2010-eligible universes and above their p95 (0.924); +0.14 over the median, +0.23 over the liquidity-ranked alternative. |
| Is the OLMAR-1 Sharpe/CAGR flattered? | INDETERMINATE | +0.05 over the random median is well inside the draw band (rank 68th percentile); +0.26 over the liquidity-ranked alternative, but that comparator is itself tilted (six of its 16 are crisis-hit financials, BAC C JPM GS WFC AIG), so it overstates. Defensible range: +0.05 to +0.26 Sharpe, +0.1 to +3.2 pp CAGR. |
| Does survivorship inflate OLMAR-1 relative to equal-weight? | FAIL (does not) | On the current list the OLMAR-1 minus equal-weight gap is -0.166 Sharpe, more negative than the random-draw median (-0.082); against the liquidity-ranked alternative (-0.201) the current list shifts it by only +0.035 Sharpe (+1.3 pp CAGR). The relative comparison is not helped by the bias; the absolute numbers are. |
| Is the computed delta the whole bias? | FAIL (it is a floor) | 232 of 501 members are absent from the data. Both universes draw only from survivors, so the delta isolates the hindsight in the list, not the missing-failures bias of the data source. The sign of the unseen part is unknown (acquisitions at a premium push up, bankruptcies push down); the +1 to +3 pp/yr literature range cited in `query.R:84-86` is not contradicted. |

Caveats that bound the estimate. (1) Dollar volume is not market cap. (2) The membership file is a third-party,
unaudited reconstruction; the symbol-reuse check only catches reuse flagged by its `-YYYYMM` markers, and a reused
unflagged symbol would be mistaken for the old firm (guard: the series must start within 7 days of the window start).
(3) The comparison holds `olmar_params` fixed, as required by `resulting-prohibition`; no parameter, target or strategy status was changed.
(4) One window, one seed (977) for the draws.

### Proposed research-log critique row (NOT written; the dispatch forbids writing the log)

- parent: the OLMAR-1 full-period `results` row; defect_class `survivorship`, severity `major`, resolved `FALSE`.
- finding: "Universe is a 2026 list of current mega-caps tested over 2010-2026; equity_daily has no delistings and 232 of 501 S&P 500 members as of 2010-01-04 are absent from it. Against 200 random same-size universes of 2010 members present in the data, OLMAR-1 Sharpe 0.780 is at the 68th percentile (median 0.728) and equal-weight Sharpe 0.945 at the 98th (median 0.808). Hindsight inflates the absolute Sharpe by about +0.05 to +0.26 (OLMAR-1) and +0.14 to +0.23 (equal-weight); it does not explain OLMAR-1's gap to equal-weight (-0.166 vs random median -0.082). The delta is a floor: failed names cannot be tested on this data. Script: scripts/olmar_survivorship_977.R."
