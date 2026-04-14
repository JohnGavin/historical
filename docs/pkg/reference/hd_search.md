# Search tickers by pattern across all datasets

Searches ticker symbols and long names using regex or glob patterns.

## Usage

``` r
hd_search(pattern, dataset = NULL)
```

## Arguments

- pattern:

  Regex pattern (default) or glob (if contains `*` or `?`)

- dataset:

  Filter to one dataset (e.g. "equity_daily"). NULL = all.

## Value

Tibble of matching tickers with metadata

## Examples

``` r
if (FALSE) { # interactive()
hd_search("^APP")     # regex: tickers starting with APP
hd_search("*coin*")   # glob: names containing "coin"
}
```
