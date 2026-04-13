# Top N tickers by a metadata metric

Queries the metadata Parquet for tickers ranked by the specified metric.

## Usage

``` r
hd_top_by(dataset, metric, n = 10, desc = TRUE)
```

## Arguments

- dataset:

  Dataset name (e.g. "equity_daily", "crypto_daily")

- metric:

  Column name to rank by: "market_cap", "volume_avg", "total_obs",
  "missing_pct"

- n:

  Number of tickers to return (default 10)

- desc:

  Sort descending? (default TRUE = largest first)

## Value

Tibble with ticker + metadata columns, sorted by metric

## Examples

``` r
hd_top_by("equity_daily", "market_cap", 5)
#> # A tibble: 5 × 27
#>   ticker dataset      long_name  exchange full_exchange currency instrument_type
#>   <chr>  <chr>        <chr>      <chr>    <chr>         <chr>    <chr>          
#> 1 NVDA   equity_daily NVIDIA Co… NMS      NasdaqGS      USD      EQUITY         
#> 2 GOOGL  equity_daily Alphabet … NMS      NasdaqGS      USD      EQUITY         
#> 3 AAPL   equity_daily Apple Inc. NMS      NasdaqGS      USD      EQUITY         
#> 4 MSFT   equity_daily Microsoft… NMS      NasdaqGS      USD      EQUITY         
#> 5 AMZN   equity_daily Amazon.co… NMS      NasdaqGS      USD      EQUITY         
#> # ℹ 20 more variables: sector <chr>, industry <chr>, country <chr>,
#> #   market_cap <dbl>, volume_avg <dbl>, fifty_two_week_high <dbl>,
#> #   fifty_two_week_low <dbl>, expense_ratio <dbl>, yield_pct <dbl>,
#> #   category <chr>, fund_family <chr>, nav_price <dbl>, beta_3yr <dbl>,
#> #   ytd_return <dbl>, three_yr_return <dbl>, start_date <date>,
#> #   end_date <date>, total_obs <dbl>, missing_pct <dbl>, yield_type <chr>
hd_top_by("crypto_daily", "volume_avg", 3)
#> # A tibble: 3 × 27
#>   ticker dataset      long_name  exchange full_exchange currency instrument_type
#>   <chr>  <chr>        <chr>      <chr>    <chr>         <chr>    <chr>          
#> 1 USDT   crypto_daily Tether US… CCC      CCC           USD      CRYPTOCURRENCY 
#> 2 BTC    crypto_daily Bitcoin U… CCC      CCC           USD      CRYPTOCURRENCY 
#> 3 ETH    crypto_daily Ethereum … CCC      CCC           USD      CRYPTOCURRENCY 
#> # ℹ 20 more variables: sector <chr>, industry <chr>, country <chr>,
#> #   market_cap <dbl>, volume_avg <dbl>, fifty_two_week_high <dbl>,
#> #   fifty_two_week_low <dbl>, expense_ratio <dbl>, yield_pct <dbl>,
#> #   category <chr>, fund_family <chr>, nav_price <dbl>, beta_3yr <dbl>,
#> #   ytd_return <dbl>, three_yr_return <dbl>, start_date <date>,
#> #   end_date <date>, total_obs <dbl>, missing_pct <dbl>, yield_type <chr>
```
