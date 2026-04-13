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
hd_ticker_meta(c("AAPL", "MSFT"))
#> # A tibble: 2 × 11
#>   ticker long_name    currency exchange market_cap volume_avg yield_pct beta_3yr
#>   <chr>  <chr>        <chr>    <chr>         <dbl>      <dbl>     <dbl>    <dbl>
#> 1 AAPL   Apple Inc.   USD      NMS         3.83e12   47088316        NA    1.14 
#> 2 MSFT   Microsoft C… USD      NMS         2.76e12   36928775        NA    0.991
#> # ℹ 3 more variables: start_date <date>, end_date <date>, total_obs <dbl>
hd_ticker_meta(hd_group("FAANG"))
#> # A tibble: 5 × 11
#>   ticker long_name    currency exchange market_cap volume_avg yield_pct beta_3yr
#>   <chr>  <chr>        <chr>    <chr>         <dbl>      <dbl>     <dbl>    <dbl>
#> 1 AAPL   Apple Inc.   USD      NMS         3.83e12   47088316        NA    1.14 
#> 2 AMZN   Amazon.com,… USD      NMS         2.56e12   51022547        NA    1.4  
#> 3 GOOGL  Alphabet In… USD      NMS         3.84e12   33721403        NA    1.12 
#> 4 META   Meta Platfo… USD      NMS         1.59e12   16470273        NA    1.50 
#> 5 NFLX   Netflix, In… USD      NMS         4.37e11   48604790        NA    0.933
#> # ℹ 3 more variables: start_date <date>, end_date <date>, total_obs <dbl>
```
