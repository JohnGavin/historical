# Compact metadata table for a vector of tickers

Returns key metadata columns for display below plots. Accepts single or
multiple tickers. Uses batch `IN (...)` query.

## Usage

``` r
hd_ticker_meta(tickers)
```

## Arguments

- tickers:

  Character vector of ticker symbols

## Value

Tibble with: ticker, long_name, currency, exchange, market_cap,
volume_avg, yield_pct, beta_3yr

## Examples

``` r
if (FALSE) { # interactive()
hd_ticker_meta(c("AAPL", "MSFT"))
hd_ticker_meta(hd_group("FAANG"))
}
```
