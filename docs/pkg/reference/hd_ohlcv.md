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
hd_ohlcv("AAPL", from = "2024-01-01")
#> # A tibble: 570 × 11
#>    date                 open  high   low close adjusted   volume ticker source
#>    <dttm>              <dbl> <dbl> <dbl> <dbl>    <dbl>    <dbl> <chr>  <chr> 
#>  1 2024-01-02 00:00:00  187.  188.  184.  186.     184. 82488700 AAPL   yahoo 
#>  2 2024-01-03 00:00:00  184.  186.  183.  184.     182. 58414500 AAPL   yahoo 
#>  3 2024-01-04 00:00:00  182.  183.  181.  182.     180. 71983600 AAPL   yahoo 
#>  4 2024-01-05 00:00:00  182.  183.  180.  181.     179. 62379700 AAPL   yahoo 
#>  5 2024-01-08 00:00:00  182.  186.  182.  186.     184. 59144500 AAPL   yahoo 
#>  6 2024-01-09 00:00:00  184.  185.  183.  185.     183. 42841800 AAPL   yahoo 
#>  7 2024-01-10 00:00:00  184.  186.  184.  186.     184. 46792900 AAPL   yahoo 
#>  8 2024-01-11 00:00:00  187.  187.  184.  186.     184. 49128400 AAPL   yahoo 
#>  9 2024-01-12 00:00:00  186.  187.  185.  186.     184. 40477800 AAPL   yahoo 
#> 10 2024-01-16 00:00:00  182.  184.  181.  184.     182. 65603000 AAPL   yahoo 
#> # ℹ 560 more rows
#> # ℹ 2 more variables: asset_class <chr>, updated_at <dttm>
hd_ohlcv(c("AAPL", "MSFT", "GOOGL"), from = "2024-01-01")
#> # A tibble: 1,710 × 11
#>    date                 open  high   low close adjusted   volume ticker source
#>    <dttm>              <dbl> <dbl> <dbl> <dbl>    <dbl>    <dbl> <chr>  <chr> 
#>  1 2024-01-02 00:00:00  187.  188.  184.  186.     184. 82488700 AAPL   yahoo 
#>  2 2024-01-03 00:00:00  184.  186.  183.  184.     182. 58414500 AAPL   yahoo 
#>  3 2024-01-04 00:00:00  182.  183.  181.  182.     180. 71983600 AAPL   yahoo 
#>  4 2024-01-05 00:00:00  182.  183.  180.  181.     179. 62379700 AAPL   yahoo 
#>  5 2024-01-08 00:00:00  182.  186.  182.  186.     184. 59144500 AAPL   yahoo 
#>  6 2024-01-09 00:00:00  184.  185.  183.  185.     183. 42841800 AAPL   yahoo 
#>  7 2024-01-10 00:00:00  184.  186.  184.  186.     184. 46792900 AAPL   yahoo 
#>  8 2024-01-11 00:00:00  187.  187.  184.  186.     184. 49128400 AAPL   yahoo 
#>  9 2024-01-12 00:00:00  186.  187.  185.  186.     184. 40477800 AAPL   yahoo 
#> 10 2024-01-16 00:00:00  182.  184.  181.  184.     182. 65603000 AAPL   yahoo 
#> # ℹ 1,700 more rows
#> # ℹ 2 more variables: asset_class <chr>, updated_at <dttm>
hd_ohlcv(hd_group("FAANG"), from = "2024-01-01")
#> # A tibble: 2,850 × 11
#>    date                 open  high   low close adjusted   volume ticker source
#>    <dttm>              <dbl> <dbl> <dbl> <dbl>    <dbl>    <dbl> <chr>  <chr> 
#>  1 2024-01-02 00:00:00  187.  188.  184.  186.     184. 82488700 AAPL   yahoo 
#>  2 2024-01-03 00:00:00  184.  186.  183.  184.     182. 58414500 AAPL   yahoo 
#>  3 2024-01-04 00:00:00  182.  183.  181.  182.     180. 71983600 AAPL   yahoo 
#>  4 2024-01-05 00:00:00  182.  183.  180.  181.     179. 62379700 AAPL   yahoo 
#>  5 2024-01-08 00:00:00  182.  186.  182.  186.     184. 59144500 AAPL   yahoo 
#>  6 2024-01-09 00:00:00  184.  185.  183.  185.     183. 42841800 AAPL   yahoo 
#>  7 2024-01-10 00:00:00  184.  186.  184.  186.     184. 46792900 AAPL   yahoo 
#>  8 2024-01-11 00:00:00  187.  187.  184.  186.     184. 49128400 AAPL   yahoo 
#>  9 2024-01-12 00:00:00  186.  187.  185.  186.     184. 40477800 AAPL   yahoo 
#> 10 2024-01-16 00:00:00  182.  184.  181.  184.     182. 65603000 AAPL   yahoo 
#> # ℹ 2,840 more rows
#> # ℹ 2 more variables: asset_class <chr>, updated_at <dttm>
```
