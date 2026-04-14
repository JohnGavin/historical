# Detect price jumps across all tickers in a dataset

Finds dates where the absolute log return exceeds a threshold. Large
jumps may indicate: missing split adjustments, share consolidations,
currency redenominations, or genuine market events.

## Usage

``` r
hd_jumps(dataset = "equity_daily", threshold = 0.4, n = 100)
```

## Arguments

- dataset:

  Dataset name (default "equity_daily")

- threshold:

  Minimum absolute log return to flag (default 0.4 = ~50%)

- n:

  Maximum number of jumps to return (default 100)

## Value

Tibble with: ticker, date, prev_close, close, log_ret, pct_change

## Examples

``` r
if (FALSE) { # interactive()
hd_jumps("equity_daily", threshold = 0.5, n = 20)
}
```
