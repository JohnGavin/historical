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
if (FALSE) { # interactive()
hd_macro("SP500", from = "2024-01-01")
hd_macro(c("SP500", "VIXCLS", "DGS10"), from = "2024-01-01")
}
```
