# Lazy duckplyr query over a dataset

Returns an unevaluated duckplyr lazy frame. Chain dplyr verbs then call
`collect()` to execute.

## Usage

``` r
hd_lazy(dataset = "equity_daily", local = FALSE)
```

## Arguments

- dataset:

  Dataset name from registry

- local:

  If TRUE, use local cache

## Value

Lazy duckplyr frame

## See also

Other data-access:
[`hd_macro_series()`](https://johngavin.github.io/historical/pkg/reference/hd_macro_series.md)
