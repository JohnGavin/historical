# Get price data amendments (Point-in-Time tracking)

Returns the amendment log showing corrections made to historical price
data. Each row records: what was changed, when, why, and the original
value.

## Usage

``` r
hd_amendments(ticker = NULL)
```

## Arguments

- ticker:

  Filter to one ticker. NULL = all.

## Value

Tibble with amendment records

## See also

Other quality-audit:
[`hd_quality()`](https://johngavin.github.io/historical/pkg/reference/hd_quality.md)
