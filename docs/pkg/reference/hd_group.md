# Get tickers for a named group

Get tickers for a named group

## Usage

``` r
hd_group(name)
```

## Arguments

- name:

  Group name (e.g. "FAANG", "Magnificent 7", "Stablecoins")

## Value

Character vector of ticker symbols

## Examples

``` r
hd_group("FAANG")
#> [1] "META"  "AAPL"  "AMZN"  "NFLX"  "GOOGL"
hd_group("Major Crypto")
#> [1] "BTC" "ETH" "SOL" "BNB"
```
