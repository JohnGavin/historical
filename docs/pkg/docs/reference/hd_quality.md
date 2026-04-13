# Summary of data quality per ticker

Returns per-ticker stats: row count, date range, number of jumps, max
absolute jump, number of gaps \> 5 days.

## Usage

``` r
hd_quality(dataset = "equity_daily", jump_threshold = 0.4)
```

## Arguments

- dataset:

  Dataset name (default "equity_daily")

- jump_threshold:

  Log return threshold for counting jumps (default 0.4)

## Value

Tibble with quality metrics per ticker

## See also

Other quality-audit:
[`hd_amendments()`](https://johngavin.github.io/historical/pkg/reference/hd_amendments.md)
