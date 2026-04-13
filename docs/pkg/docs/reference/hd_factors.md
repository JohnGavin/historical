# Query Fama-French factor returns

Query Fama-French factor returns

## Usage

``` r
hd_factors(
  dataset = "FF3",
  frequency = "daily",
  from = NULL,
  to = NULL,
  local = FALSE
)
```

## Arguments

- dataset:

  Factor dataset: "FF3", "FF5", or "Mom"

- frequency:

  "daily" or "monthly"

- from:

  Start date. Default: no filter.

- to:

  End date. Default: no filter.

- local:

  If TRUE, query local cache.

## Value

Tibble with date, factor_name, value columns
