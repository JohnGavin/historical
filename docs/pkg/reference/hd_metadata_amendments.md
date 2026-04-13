# Get metadata amendments (Point-in-Time tracking)

Returns the PIT log of all metadata changes: computed fields,
enrichments, corrections. Every change to metadata.parquet is tracked
with old/new values, source, method, and timestamp.

## Usage

``` r
hd_metadata_amendments(ticker = NULL, field = NULL)
```

## Arguments

- ticker:

  Filter to one ticker. NULL = all.

- field:

  Filter to one field (e.g. "beta_3yr"). NULL = all.

## Value

Tibble with: ticker, field, old_value, new_value, source, method,
amended_at, amended_by, reversible

## Examples

``` r
hd_metadata_amendments("AAPL")
#> # A tibble: 3 × 9
#>   ticker field           old_value new_value source method amended_at amended_by
#>   <chr>  <chr>           <chr>     <chr>     <chr>  <chr>  <chr>      <chr>     
#> 1 AAPL   beta_3yr        NA        1.143     compu… beta=… 2026-04-1… enrich_me…
#> 2 AAPL   three_yr_return NA        0.1801    compu… beta=… 2026-04-1… enrich_me…
#> 3 AAPL   ytd_return      NA        -0.038    compu… beta=… 2026-04-1… enrich_me…
#> # ℹ 1 more variable: reversible <lgl>
hd_metadata_amendments(field = "beta_3yr")
#> # A tibble: 990 × 9
#>    ticker field    old_value new_value source       method amended_at amended_by
#>    <chr>  <chr>    <chr>     <chr>     <chr>        <chr>  <chr>      <chr>     
#>  1 AGG    beta_3yr NA        0.058     computed_fr… beta=… 2026-04-1… enrich_me…
#>  2 BIL    beta_3yr NA        -0.001    computed_fr… beta=… 2026-04-1… enrich_me…
#>  3 DBC    beta_3yr NA        0.191     computed_fr… beta=… 2026-04-1… enrich_me…
#>  4 EEM    beta_3yr NA        0.795     computed_fr… beta=… 2026-04-1… enrich_me…
#>  5 EFA    beta_3yr NA        0.747     computed_fr… beta=… 2026-04-1… enrich_me…
#>  6 GLD    beta_3yr NA        0.153     computed_fr… beta=… 2026-04-1… enrich_me…
#>  7 IAU    beta_3yr NA        0.151     computed_fr… beta=… 2026-04-1… enrich_me…
#>  8 IEF    beta_3yr NA        0.018     computed_fr… beta=… 2026-04-1… enrich_me…
#>  9 PDBC   beta_3yr NA        0.193     computed_fr… beta=… 2026-04-1… enrich_me…
#> 10 SHY    beta_3yr NA        -0.001    computed_fr… beta=… 2026-04-1… enrich_me…
#> # ℹ 980 more rows
#> # ℹ 1 more variable: reversible <lgl>
```
