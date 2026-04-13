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
hd_metadata_amendments(field = "beta_3yr")
```
