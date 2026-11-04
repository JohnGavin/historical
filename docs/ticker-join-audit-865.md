# Ticker-keyed join audit (issue #865)

Status: READ-ONLY audit. No audited site was changed in this PR. Every
site below is a follow-up candidate, not a fix.

Scope read: `R/`, `scripts/`, `packages/historicaldata/R/`,
`docs/_targets.R`. Method: `grep` for joins whose key contains `ticker`
or `symbol` (`by = ...`, `join_by`, `merge(on=...)`, SQL `ON`), then read
the join line plus about 9 lines above it. Every `file:line` is the line of
the key expression I read. `docs/*.qmd` has joins in `leaderboard.qmd`,
`momentum-prepeak.qmd` and `european-overlay.qmd`; I read their keys
(`strategy`, `code_name`, `short_name`, `date`, `asset`, `period`) and none is a
ticker, so they are out of scope. Known limits of the grep: a `by` vector
split over several lines with `"ticker"` on a later line than `by =`, or a
key held in a variable, would not have matched. The unnamed-`by` (natural
join) form `*_join(x, y)` matched only comments.

## Why it matters

A ticker is a reusable string. The #865 example: `APC` was Anadarko
Petroleum (CIK 0000773910) through 2019 and later a different issuer
(ARKO, CIK 0001835022). A join keyed on `ticker` alone merges them.
`cik` (zero-padded 10-char string) is the issuer key. After this PR the
EDGAR fundamentals triangle carries `cik`; nothing else in the repo does.

## Classification rule

- SAFE: both sides of the join are derived in the same target chain from
  one ticker-keyed series, or the key is not an equity ticker. The join
  itself cannot pair two issuers that the source had not already merged.
- AT-RISK: the two sides come from different sources or different
  snapshot dates (for example a current snapshot against history), so a
  reused ticker can attach one issuer's attributes to another's rows.
- INDETERMINATE: I could not tell from what I read; the reason is stated.

## Cross-cutting finding (source level, S1)

All "SAFE" equity rows inherit one source-level risk: `equity_daily` is
keyed by the Yahoo ticker string, and `stk_universe` and `ltr_universe`
read that key as an issuer identity (`R/plan_stock_backtest.R:709`
filters `ticker %in% stk_top_tickers`). If a vendor series ever splices two
issuers under one ticker, no join below can detect it. I did not
verify whether any ticker in the current universes has been reused. The
universe today is current large caps (`R/plan_fip_screen.R:268`: "~51 US
equities"), so the practical exposure is latent, as #865 states.

## Sites

| # | file:line | What is joined | Reused ticker can mis-join? | Class | Severity | Recommended key |
|---|-----------|----------------|-----------------------------|-------|----------|-----------------|
| 1 | `scripts/enrich_metadata.py:125` | `metadata.parquet` (current snapshot per ticker) merged with returns computed from price files, `on="ticker"` | Yes: current-holder metadata attaches to a ticker's whole price history | AT-RISK | Medium | `(cik, ticker)` once metadata carries cik; until then record `as_of` of the metadata |
| 2 | `R/plan_stock_backtest.R:689-709` | `metadata` dataset market-cap ranking (current) selects tickers (`stk_top_tickers`), applied as `ticker %in%` filter to full `equity_daily` history. A filter, not a join, but the same key | Yes: today's top-N by market cap picks the string, history may belong to an earlier holder | AT-RISK | Medium | `(cik, ticker)`; or point-in-time universe (`R/plan_universe_pit.R` is a stub, aborts on build) |
| 3 | `packages/historicaldata/R/fundamentals.R:98` | `hd_fundamentals(ticker=)` filters the fundamentals parquet on `ticker` only; output columns (line 125) do not include `cik` | Yes once the universe is wider than 10 current mega-caps | AT-RISK | Low today (pilot of 10) | add `cik` to `out_cols` and accept a `cik=` filter. PACKAGE CHANGE: needs API doc regen and `build.sh`, so not done here |
| 4 | `packages/historicaldata/R/metadata.R:131` | `hd_ticker_meta()` looks up current snapshot rows with `ticker %in% tickers` | Yes if the caller holds historical tickers | INDETERMINATE | n/a | I did not trace callers; this is a lookup, not a join |
| 5 | `R/cross_reference.R:13` | `cross_reference(source_a, source_b, by = c("ticker","date"))`: compares two sources | Depends on caller; grep found no `cross_reference(` call in `R/`, `scripts/` or `docs/_targets.R` | INDETERMINATE | n/a | accept `by = c("cik","date")` when both sources carry cik |
| 6 | `R/plan_fip_screen.R:120` | `mom_prepeak_signal_raw` with `fip_scores`, `by = c("ticker","as_of_date")`; both derive from `ltr_universe` (lines 54-60 of that file and `R/plan_mom_prepeak.R:67-69`) | No beyond S1 | SAFE | none | unchanged |
| 7 | `R/plan_mom_prepeak.R:359` | portfolio weights with `monthly_ret` forward returns, `by = c("ticker","exec_date"="date")` | No beyond S1 (same universe) | SAFE | none | unchanged |
| 8 | `R/plan_stock_backtest.R:117` and `:118` | `ranked` and `target` frames, both built from `monthly` for one month | No beyond S1 | SAFE | none | unchanged |
| 9 | `R/plan_stock_backtest.R:892`, `:936`, `:981` | `stk_max_signal` signal with `stk_monthly`, `by = c("ticker","ym")` | No beyond S1 (both from the `stk_universe` and `stk_monthly` targets, read around lines 697-742) | SAFE | none | unchanged |
| 10 | `R/plan_stock_backtest.R:1306`, `:1336` | `stk_drif_signal` with `stk_monthly`; signal with `stk_monthly_adv` | No beyond S1 | SAFE | none | unchanged |
| 11 | `R/plan_etf_replication.R:122`, `:123` | `ranked` and `target` from `etf_monthly` | ETF tickers, same source; ETF symbol reuse not examined | SAFE | none | unchanged |
| 12 | `R/plan_xgb_signal.R:120`, `:131` | `xgb_drif_signal` with `stk_monthly`, then with `stk_monthly_adv`, `by = c("ticker","ym")` | No beyond S1 | SAFE | none | unchanged |
| 13 | `R/plan_alpha_decay.R:131`, `:135`, `:171` | entry, month index and exit frames from one `price_index`, `by = c("ticker","ym")` / `"next_ym"` | No beyond S1 | SAFE | none | unchanged |
| 14 | `R/momentum_decomposition.R:480`, `:649` | decomposed momentum with forward returns from the same stock returns frame, `by = c("ticker","date")` | No beyond S1 | SAFE | none | unchanged |
| 15 | `R/plan_momentum_decomposition.R:99` | `momentum_components` with `total_momentum` built from the same returns | No beyond S1 | SAFE | none | unchanged |
| 16 | `scripts/compute_ltr_features.R:149`, `:181`, SQL `ON` at `:171` | month-end rows with daily features; month-end rows with adjusted EOM prices (re-read from the same `equity_daily` URL) | No beyond S1 | SAFE | none | unchanged |
| 17 | `R/plan_backtest.R:383` | `bt_expanding` (`rank_1`) with `bt_returns` by ticker and date; `bt_returns` is the same frame pivoted at line 375 | No beyond S1 | SAFE | none | unchanged |
| 18 | `R/plan_european_overlay.R:410` | buy-and-hold and overlay Sharpe for the same `oos` frame, `by = "ticker"` | European ETF tickers from one frame | SAFE | none | unchanged |
| 19 | `R/plan_kalshi.R:258` | `by = c("event_ticker","meeting_date")` | Not an equity ticker: a Kalshi event code | SAFE | none | unchanged |
| 20 | `R/crypto_momentum.R:145`, `:241`, `:249`; `R/crypto_momentum_helpers.R:137`, `:216`, `:224`, `:383`, `:391` | crypto betas, positions and returns frames built in the same function, `by = "ticker"` / `c("date","ticker")` | Same-function frames, so no cross-source join. Whether a crypto symbol can be reused for a different token in the source was not examined | INDETERMINATE | n/a | not an issuer/CIK concept; a venue pair id would be the key if reuse matters |
| 21 | `R/solana_defi_data.R:207`; `R/plan_solana_momentum.R:106` | spot liquidity with perp liquidity by `ticker`; signals with vol weights by `c("date","ticker")` | Crypto symbols from the Drift API and spot data (two sources joined on a bare symbol); symbol reuse not examined | INDETERMINATE | n/a | venue market id rather than bare symbol |

## Tally (by row)

| Class | Rows | Row numbers |
|-------|------|-------------|
| AT-RISK | 3 | 1, 2, 3 |
| INDETERMINATE | 4 | 4, 5, 20, 21 |
| SAFE | 14 | 6 to 19 |
| Total | 21 | |

## Follow-ups (not done in this PR)

1. Row 1 (`enrich_metadata.py`): add an `as_of` guard or cik.
2. Row 2 (`stk_top_tickers`): decide whether the top-N universe should carry
   cik and be point-in-time; `plan_universe_pit.R` is the intended home.
3. Row 3: expose `cik` from `hd_fundamentals()` and the registry schema.
   Note `packages/historicaldata/tests/testthat/test-registry.R:34` compares
   the registry schema with the SAMPLE parquet, so the registry schema,
   `inst/extdata/sample/fundamentals_sample.parquet` and
   `data-raw/make_sample_data.R` must change together with the published
   parquet. Until then the live parquet (with `cik`) has one more column
   than the registry `schema` lists.
4. Rows 4, 5, 20, 21: resolve the INDETERMINATE reasons above before
   deciding.
5. S1: add a source-level check that no ticker in `equity_daily` has a
   price gap or metadata change that suggests a different issuer.

## Status update 2026-11-04 (refs #865)

This section supersedes the "not done in this PR" list above for rows 1 to 5.
The live instance (`scripts/fetch_fundamentals_edgar.R` CIK resolution with no
date check) was confirmed already fixed on main: `validate_cik_filing_overlap()`
(line 217) is called at line 378 and is covered by
`tests/testthat/test-fetch-fundamentals-edgar.R` (APC / ARKO regression).
Nothing was redone.

| # | Site | Verdict now | What changed or what was found |
|---|------|-------------|--------------------------------|
| 3 | `packages/historicaldata/R/fundamentals.R` `hd_fundamentals()` | RESOLVED (loud) | Output now carries `cik`; new `cik =` filter (10-digit zero-padded character, else `hd_fundamentals_bad_cik`). A ticker-only query that returns more than one CIK for a ticker warns (`hd_fundamentals_ticker_multi_cik`) and names every CIK. A parquet with no `cik` column aborts (`hd_fundamentals_no_cik_column`). Registry schema, the sample fixture (`fundamentals_sample.parquet`, regenerated by `data-raw/make_sample_data.R`; the other five fixtures are unchanged) and `test-registry.R` (now also covers `fundamentals`) were changed together, as the follow-up list required. `hd_fundamentals()` has no production caller in this repo (only the `plan_qa_fundamentals.R` guard scans for call sites), so no published number can move. |
| 1 | `scripts/enrich_metadata.py:125` | AT-RISK, now recorded | The join still keys on `ticker` alone. The published amendments log's `method` string now carries `join_key=ticker (no cik); metadata_snapshot_as_of=<date>; ticker-recycling risk #865, point-in-time universe #816`, and a ticker occurring more than once in `metadata.parquet` prints a `WARNING (#865)` to stderr (warn, not abort: aborting could break a scheduled script on data I cannot read here). Note the merged fields are trailing windows (YTD, 3-year return, 3-year beta), so the exposure is limited to a recycle inside the last three years. |
| 2 | `R/plan_stock_backtest.R` `stk_top_tickers` | AT-RISK, now recorded | New target `stk_universe_provenance` (nothing consumes it, so no existing target is invalidated and no number changes) holds one row: `n_selected`, `top_n`, `key = "ticker"`, `basis = "current market-cap snapshot (not point-in-time)"`, `metadata_as_of_proxy`, `min_selected_market_cap`, and a caveat naming #816 and #865. Helper: `R/ticker_universe_provenance.R`. |
| 4 | `hd_ticker_meta()` | SAFE | Callers traced: `R/plan_vignette.R:469-513` (11 display tables) and `docs/macro-defense-rotation.qmd:204`. The vignette tickers come from `hd_top_by()`, `hd_group()`, `hd_most_volatile()` and `hd_search()` on the same current metadata, and the qmd passes five literal ETFs (TLT, GLD, DBC, UUP, SPY). Every call displays the current snapshot for current tickers; none attaches it to history. |
| 5 | `cross_reference()` | SAFE | The original audit missed the callers because it did not read the root `_targets.R`: `_targets.R:48` (AAPL, Yahoo vs Kaggle) and `_targets.R:76` (BTC, Yahoo vs backfill). Each filters to one literal ticker before the call, so no recycled symbol can pair two issuers. Cross-project grep before any deletion (`grep -rl cross_reference ~/docs_gh/`): hits only in checkouts and worktrees of this repo (copies of the same file); no other project uses it. Not deleted. `docs/inner-join-audit-657.md` row C8 ("no caller found") is stale for the same reason and was not edited here. |

Tally after this update (rows 1 to 5 only): AT-RISK with provenance recorded 2
(rows 1, 2), RESOLVED 1 (row 3), SAFE 2 (rows 4, 5). Rows 20 and 21 are
unchanged (INDETERMINATE).

### Why no "history starts before the company existed" check (sites 1 and 2)

It cannot be decided from data in the repo:

- The metadata `start_date`, `end_date` and `total_obs` are computed from the
  same Yahoo price series (`scripts/fetch_metadata.py`, stats from
  `yfinance_equity.parquet`), so comparing them with the first price bar
  compares the series with itself and cannot vary with a recycled ticker.
- `metadata.parquet` has no snapshot-date column; `metadata_as_of_proxy` is
  `max(end_date)` of the selected rows, labelled as a proxy.
- EDGAR filing ranges are held only for the 10 fundamentals pilot tickers, not
  for the top-100 market-cap universe.
- No price or metadata parquet is present in the repo or its worktrees, so a
  price-gap heuristic could not be baselined for false positives here.

TODO(#816): once a point-in-time universe exists, key the universe on
`(cik, ticker)` with filing-range validity (the `validate_cik_filing_overlap()`
rule), replace `metadata_as_of_proxy` with a real snapshot date column, and
retire `stk_universe_provenance`. Follow-up S1 (a price-gap check over
`equity_daily`) remains open and needs a baseline run on live data first.
