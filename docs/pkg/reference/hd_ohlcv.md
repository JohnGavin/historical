# Query OHLCV data for one or more tickers

Fetches data from HF-hosted Parquet via DuckDB httpfs. Only the matching
rows are transferred (predicate pushdown). Accepts a single ticker or a
character vector for batch queries.

## Usage

``` r
hd_ohlcv(ticker, from = NULL, to = NULL, dataset = NULL, local = FALSE)
```

## Arguments

- ticker:

  Ticker symbol(s). Character scalar or vector. Single: `"AAPL"`. Batch:
  `c("AAPL", "MSFT", "GOOGL")`.

- from:

  Start date (character or Date). Default: no filter.

- to:

  End date (character or Date). Default: no filter.

- dataset:

  Dataset name from registry. If NULL, auto-detected from first ticker.

- local:

  If TRUE, query local cache instead of remote.

## Value

Tibble of OHLCV data (multiple tickers stacked by ticker + date)

## Examples

``` r
if (FALSE) { # interactive()
hd_ohlcv("AAPL", from = "2024-01-01")
hd_ohlcv(c("AAPL", "MSFT", "GOOGL"), from = "2024-01-01")
hd_ohlcv(hd_group("FAANG"), from = "2024-01-01")
}
```
