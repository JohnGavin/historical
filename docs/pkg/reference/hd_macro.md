# Query FRED macro series

Accepts a single series ID or a character vector for batch queries.

## Usage

``` r
hd_macro(series_id, from = NULL, to = NULL, local = FALSE)
```

## Arguments

- series_id:

  FRED series ID(s). Scalar or vector. Single: `"SP500"`. Batch:
  `c("SP500", "VIXCLS", "DGS10")`.

- from:

  Start date (character or Date). Default: no filter.

- to:

  End date (character or Date). Default: no filter.

- local:

  If TRUE, query local cache instead of remote.

## Value

Tibble with date, value, series_id columns

## Examples

``` r
hd_macro("SP500", from = "2024-01-01")
#> # A tibble: 595 × 5
#>    date       value series_id source updated_at         
#>    <date>     <dbl> <chr>     <chr>  <dttm>             
#>  1 2024-01-01   NA  SP500     fred   2026-04-11 13:33:49
#>  2 2024-01-02 4743. SP500     fred   2026-04-11 13:33:49
#>  3 2024-01-03 4705. SP500     fred   2026-04-11 13:33:49
#>  4 2024-01-04 4689. SP500     fred   2026-04-11 13:33:49
#>  5 2024-01-05 4697. SP500     fred   2026-04-11 13:33:49
#>  6 2024-01-08 4764. SP500     fred   2026-04-11 13:33:49
#>  7 2024-01-09 4756. SP500     fred   2026-04-11 13:33:49
#>  8 2024-01-10 4783. SP500     fred   2026-04-11 13:33:49
#>  9 2024-01-11 4780. SP500     fred   2026-04-11 13:33:49
#> 10 2024-01-12 4784. SP500     fred   2026-04-11 13:33:49
#> # ℹ 585 more rows
hd_macro(c("SP500", "VIXCLS", "DGS10"), from = "2024-01-01")
#> # A tibble: 1,783 × 5
#>    date       value series_id source updated_at         
#>    <date>     <dbl> <chr>     <chr>  <dttm>             
#>  1 2024-01-01 NA    DGS10     fred   2026-04-11 13:33:49
#>  2 2024-01-02  3.95 DGS10     fred   2026-04-11 13:33:49
#>  3 2024-01-03  3.91 DGS10     fred   2026-04-11 13:33:49
#>  4 2024-01-04  3.99 DGS10     fred   2026-04-11 13:33:49
#>  5 2024-01-05  4.05 DGS10     fred   2026-04-11 13:33:49
#>  6 2024-01-08  4.01 DGS10     fred   2026-04-11 13:33:49
#>  7 2024-01-09  4.02 DGS10     fred   2026-04-11 13:33:49
#>  8 2024-01-10  4.04 DGS10     fred   2026-04-11 13:33:49
#>  9 2024-01-11  3.98 DGS10     fred   2026-04-11 13:33:49
#> 10 2024-01-12  3.96 DGS10     fred   2026-04-11 13:33:49
#> # ℹ 1,773 more rows
```
