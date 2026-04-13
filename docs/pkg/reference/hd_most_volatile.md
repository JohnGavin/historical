# Most volatile tickers by recent realised volatility

Computes 21-day rolling annualised volatility for all tickers in a
dataset and returns the top N. Uses a single DuckDB window query over
the full Parquet.

## Usage

``` r
hd_most_volatile(dataset = "equity_daily", n = 5, window_days = 21)
```

## Arguments

- dataset:

  Dataset name (default "equity_daily")

- n:

  Number of tickers to return (default 5)

- window_days:

  Rolling window in trading days (default 21)

## Value

Tibble with ticker, vol_21d, sorted by vol descending

## Examples

``` r
hd_most_volatile("equity_daily", 3)
#> # A tibble: 3 × 3
#>   ticker vol_21d as_of              
#>   <chr>    <dbl> <dttm>             
#> 1 5HEP.L    28.0 2026-04-10 00:00:00
#> 2 INTS.L    24.6 2026-04-10 00:00:00
#> 3 BUFF.L    23.1 2026-04-10 00:00:00
```
