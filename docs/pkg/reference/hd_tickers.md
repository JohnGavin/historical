# List available tickers in a dataset

Queries the remote Parquet file for distinct tickers. Uses DuckDB httpfs
— only fetches the ticker column.

## Usage

``` r
hd_tickers(dataset = "equity_daily")
```

## Arguments

- dataset:

  Name of dataset (from
  [`hd_datasets()`](https://johngavin.github.io/historical/pkg/reference/hd_datasets.md))

## Value

Character vector of tickers

## See also

Other discovery:
[`hd_datasets()`](https://johngavin.github.io/historical/pkg/reference/hd_datasets.md),
[`hd_exchanges()`](https://johngavin.github.io/historical/pkg/reference/hd_exchanges.md),
[`hd_macro_series()`](https://johngavin.github.io/historical/pkg/reference/hd_macro_series.md),
[`hd_summary()`](https://johngavin.github.io/historical/pkg/reference/hd_summary.md)
