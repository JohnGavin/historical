# Column Naming Conventions — historicaldata

This document is the single source of truth for canonical column names across
all datasets in this package.  It documents source-system synonyms and records
where each rename happens.

See GitHub issue [#316](https://github.com/JohnGavin/historical/issues/316)
for the design decision that prompted this document (option A: keep
`adjusted_close` for `alphavantage_daily`).

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

## Adjusted-close column — per dataset

This is the column that records the dividend- and split-adjusted close.  The
name differs by dataset because each upstream API uses a different identifier;
the rename (where needed) happens at ingest, not inside this package.

| Dataset | Column name | Upstream API field | Rename location | Note |
|---|---|---|---|---|
| `equity_daily` | `adjusted` | `adj_close` (yfinance) | [`scripts/fetch_equity.py`](../../../scripts/fetch_equity.py) L163 | Yahoo Finance source; renamed for compactness |
| `alphavantage_daily` | `adjusted_close` | `adjusted_close` (AV API) | none — native name | AlphaVantage returns this name natively; no rename needed |

### Why the names differ

`equity_daily` is built from yfinance (Python), which calls the field
`adj_close`.  The ingest script `fetch_equity.py` renames it to `adjusted`
(shorter; avoids confusion with the raw `close`).

`alphavantage_daily` is built from the AlphaVantage
`TIME_SERIES_DAILY_ADJUSTED` endpoint, which returns a column literally named
`adjusted_close`.  We keep that name unchanged — it is explicit and matches
the schema declared in `hd_datasets()$alphavantage_daily$schema`.

### Design decision (issue #316, option A)

The two datasets are intentionally separate and are never joined internally.
Callers that need to join them must rename one side:

```r
# Joining alphavantage_daily to equity_daily — rename AV side first
av   <- hd_alphavantage("AAPL") |> dplyr::rename(adjusted = adjusted_close)
eq   <- hd_equity_daily |> dplyr::filter(ticker == "AAPL")
both <- dplyr::full_join(av, eq, by = c("date", "ticker", "adjusted"))
```

Alternatively, use `adjusted_close` as the canonical name on the equity side
by renaming in the other direction:

```r
eq_renamed <- eq |> dplyr::rename(adjusted_close = adjusted)
```

Either approach is valid; be explicit and consistent within a single analysis.

---

## Other synonym mapping (for reference)

| Concept | This package | Yahoo Finance (yfinance) | AlphaVantage API | Alpaca API |
|---|---|---|---|---|
| Adjusted close | `adjusted` or `adjusted_close` (see above) | `Adj Close` | `adjusted_close` | `vwap` (no split-adj close) |
| Unadjusted close | `close` | `Close` | `close` | `close` |
| Trade date | `date` | `Date` | `timestamp` | `timestamp` |
| Volume | `volume` | `Volume` | `volume` | `volume` |

---

## Adding a new dataset

When adding a new data source that includes an adjusted-close concept:

1. Pick a canonical column name (`adjusted_close` preferred for new datasets;
   it is explicit).
2. Document the source API field in this table.
3. Note the rename location in the ingest script.
4. Update `hd_datasets()` in `R/registry.R` to include the chosen name in
   the `schema` vector.
