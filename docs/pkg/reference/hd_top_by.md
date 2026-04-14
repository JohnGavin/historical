# Top N tickers by a metadata metric

Queries the metadata Parquet for tickers ranked by the specified metric.

## Usage

``` r
hd_top_by(dataset, metric, n = 10, desc = TRUE)
```

## Arguments

- dataset:

  Dataset name (e.g. "equity_daily", "crypto_daily")

- metric:

  Column name to rank by: "market_cap", "volume_avg", "total_obs",
  "missing_pct"

- n:

  Number of tickers to return (default 10)

- desc:

  Sort descending? (default TRUE = largest first)

## Value

Tibble with ticker + metadata columns, sorted by metric

## Examples

``` r
if (FALSE) { # interactive()
hd_top_by("equity_daily", "market_cap", 5)
hd_top_by("crypto_daily", "volume_avg", 3)
}
```
