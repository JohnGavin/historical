# List all curated ticker groups

Returns a tibble of named groups with their tickers and definitions.
Groups are editorial (curated), not computed from metadata.

## Usage

``` r
hd_ticker_groups()
```

## Value

Tibble with columns: group, description, tickers (character vector in
list-column)

## Examples

``` r
hd_ticker_groups()
hd_ticker_groups() |> dplyr::filter(group == "FAANG")
```
