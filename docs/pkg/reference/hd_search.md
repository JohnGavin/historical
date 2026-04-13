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
hd_search("^APP")     # regex: tickers starting with APP
#> # A tibble: 1 × 27
#>   ticker dataset      long_name  exchange full_exchange currency instrument_type
#>   <chr>  <chr>        <chr>      <chr>    <chr>         <chr>    <chr>          
#> 1 AAPL   equity_daily Apple Inc. NMS      NasdaqGS      USD      EQUITY         
#> # ℹ 20 more variables: sector <chr>, industry <chr>, country <chr>,
#> #   market_cap <dbl>, volume_avg <dbl>, fifty_two_week_high <dbl>,
#> #   fifty_two_week_low <dbl>, expense_ratio <dbl>, yield_pct <dbl>,
#> #   category <chr>, fund_family <chr>, nav_price <dbl>, beta_3yr <dbl>,
#> #   ytd_return <dbl>, three_yr_return <dbl>, start_date <date>,
#> #   end_date <date>, total_obs <dbl>, missing_pct <dbl>, yield_type <chr>
hd_search("*coin*")   # glob: names containing "coin"
#> # A tibble: 13 × 27
#>    ticker dataset      long_name exchange full_exchange currency instrument_type
#>    <chr>  <chr>        <chr>     <chr>    <chr>         <chr>    <chr>          
#>  1 BTC    crypto_daily Bitcoin … CCC      CCC           USD      CRYPTOCURRENCY 
#>  2 DOGE   crypto_daily Dogecoin… CCC      CCC           USD      CRYPTOCURRENCY 
#>  3 USDC   crypto_daily USD Coin… CCC      CCC           USD      CRYPTOCURRENCY 
#>  4 1COI.L equity_daily LS 1x Co… LSE      LSE           USD      ETF            
#>  5 3CNE.L equity_daily Leverage… LSE      LSE           EUR      ETF            
#>  6 BITC.L equity_daily CoinShar… LSE      LSE           USD      ETF            
#>  7 BTCW.L equity_daily WisdomTr… LSE      LSE           USD      ETF            
#>  8 CO3S.L equity_daily Leverage… LSE      LSE           USD      ETF            
#>  9 COI1.L equity_daily LS 1x Co… LSE      LSE           EUR      ETF            
#> 10 COII.L equity_daily IncomeSh… LSE      LSE           GBp      ETF            
#> 11 CON3.L equity_daily Leverage… LSE      LSE           USD      ETF            
#> 12 ETHE.L equity_daily CoinShar… LSE      LSE           USD      ETF            
#> 13 S3CO.L equity_daily Leverage… LSE      LSE           GBp      ETF            
#> # ℹ 20 more variables: sector <chr>, industry <chr>, country <chr>,
#> #   market_cap <dbl>, volume_avg <dbl>, fifty_two_week_high <dbl>,
#> #   fifty_two_week_low <dbl>, expense_ratio <dbl>, yield_pct <dbl>,
#> #   category <chr>, fund_family <chr>, nav_price <dbl>, beta_3yr <dbl>,
#> #   ytd_return <dbl>, three_yr_return <dbl>, start_date <date>,
#> #   end_date <date>, total_obs <dbl>, missing_pct <dbl>, yield_type <chr>
```
