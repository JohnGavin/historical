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
hd_jumps("equity_daily", threshold = 0.5, n = 20)
#> # A tibble: 20 × 6
#>    ticker date       prev_close         close log_ret pct_change
#>    <chr>  <date>          <dbl>         <dbl>   <dbl>      <dbl>
#>  1 BID3.L 2024-02-16    1.80e-4     18.7        11.6   10389538.
#>  2 3TSE.L 2024-02-16    4.60e-4     25.3        10.9    5502859.
#>  3 3TSL.L 2024-02-16    4.60e-4     25.3        10.9    5502859.
#>  4 CON3.L 2022-12-09    1.26e+1      0.000350  -10.5       -100 
#>  5 CON3.L 2021-12-14    4.74e+0 167608          10.5    3536210.
#>  6 CON3.L 2022-12-19    2.10e-4      6.55       10.3    3119981.
#>  7 3SQ.L  2021-03-30    6.54e+6    230.        -10.3       -100 
#>  8 SQ3.L  2023-09-07    2.98e+1      0.00125   -10.1       -100 
#>  9 SQ3.L  2021-03-30    2.97e+0  69031.         10.1    2327435.
#> 10 3SQ.L  2023-09-08    9.70e-2   1832.          9.85   1889075.
#> 11 3SQE.L 2023-09-08    1.15e-3     21.3         9.83   1855074.
#> 12 SQ3.L  2023-09-08    1.25e-3     22.9         9.81   1828660.
#> 13 VIXL.L 2024-07-22    8.50e-3     49.3         8.67    579659.
#> 14 VILX.L 2024-07-22    6.60e-1   3817.          8.66    578262.
#> 15 NIO3.L 2022-12-09    7.87e+1      0.0138     -8.65      -100 
#> 16 3PYP.L 2021-03-30    1.48e+6    301.         -8.50      -100 
#> 17 NIO3.L 2023-08-14    5.15e-3     25.1         8.49    487865.
#> 18 NIO3.L 2021-12-14    4.73e+0  20713.          8.38    437976.
#> 19 SJPN.L 2026-01-22    1.02e+2 382781           8.23    373345.
#> 20 SJPN.L 2026-01-23    3.83e+5    102.         -8.23      -100 
```
