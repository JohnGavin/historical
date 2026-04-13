# FRED series metadata (frequency, units)

Returns known metadata for FRED macro series. These are hardcoded since
the FRED API requires an API key.

## Usage

``` r
hd_fred_meta()
```

## Value

Tibble with series_id, frequency, units, title
