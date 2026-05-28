# Column Naming Conventions — historicaldata

This document is the single source of truth for canonical column names across
all datasets in this package.  It documents source-system synonyms and records
where each rename happens.

See GitHub issue [#316](https://github.com/JohnGavin/historical/issues/316)
for the original design discussion, and
[#325](https://github.com/JohnGavin/historical/issues/325) for the decision
to normalise to `adjusted_close` across all datasets.

---

## OHLCV columns

| Canonical name | Type | Description |
|---|---|---|
| `date` | Date | Trade date (calendar day, not timestamp) |
| `open` | double | Opening price |
| `high` | double | Intraday high price |
| `low` | double | Intraday low price |
| `close` | double | Unadjusted closing price |
| `volume` | integer | Shares traded |
| `ticker` | character | Symbol (upper-case, Yahoo Finance format) |

---

## Adjusted-close column — canonical name

`adjusted_close` is the single canonical column name for the dividend- and
split-adjusted close across **all** datasets (#325).

| Dataset | Column name | Upstream API field | Rename location | Note |
|---|---|---|---|---|
| `equity_daily` | `adjusted_close` | `adj_close` (yfinance) | [`scripts/fetch_equity.py`](../../../scripts/fetch_equity.py) L163 | Renamed from `adj_close` at fetch time (new parquets from #325 onwards) |
| `alphavantage_daily` | `adjusted_close` | `adjusted_close` (AV API) | none — native name | AlphaVantage returns this name natively; no rename needed |

### Backward compatibility

Cached parquet files produced before #325 may still contain a column named
`adjusted` (the old yfinance rename).  The read-time alias in `hd_lazy()` and
`hd_ohlcv()` transparently renames `adjusted` to `adjusted_close` at load time,
so callers always see the canonical name without a full re-fetch.

### Cross-dataset joins (no rename needed from #325 onwards)

Both datasets now share `adjusted_close`.  A join that previously required an
explicit rename:

```r
# OLD (before #325): required rename on one side
av   <- hd_alphavantage("AAPL") |> dplyr::rename(adjusted = adjusted_close)
eq   <- hd_ohlcv("AAPL")
both <- dplyr::full_join(av, eq, by = c("date", "ticker", "adjusted"))
```

now works without any rename:

```r
# NEW (#325 onwards): column names match — no rename needed
av   <- hd_alphavantage("AAPL")
eq   <- hd_ohlcv("AAPL")
both <- dplyr::full_join(av, eq, by = c("date", "ticker", "adjusted_close"))
```

---

## Other synonym mapping (for reference)

| Concept | This package | Yahoo Finance (yfinance) | AlphaVantage API | Alpaca API |
|---|---|---|---|---|
| Adjusted close | `adjusted_close` | `Adj Close` | `adjusted_close` | `vwap` (no split-adj close) |
| Unadjusted close | `close` | `Close` | `close` | `close` |
| Trade date | `date` | `Date` | `timestamp` | `timestamp` |
| Volume | `volume` | `Volume` | `volume` | `volume` |

---

## Adding a new dataset

When adding a new data source that includes an adjusted-close concept:

1. Use `adjusted_close` as the canonical column name.
2. Document the source API field in this table.
3. Note the rename location in the ingest script.
4. Update `hd_datasets()` in `R/registry.R` to include `adjusted_close` in
   the `schema` vector.
