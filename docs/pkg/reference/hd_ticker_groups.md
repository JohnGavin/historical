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
#> # A tibble: 19 × 3
#>    group                    description                                  tickers
#>    <chr>                    <chr>                                        <list> 
#>  1 FAANG                    Meta (Facebook), Apple, Amazon, Netflix, Go… <chr>  
#>  2 Magnificent 7            7 largest US tech companies by market cap    <chr>  
#>  3 US Semiconductors        Major US semiconductor companies             <chr>  
#>  4 US Banks                 Major US financial institutions              <chr>  
#>  5 US Healthcare            Major US healthcare and pharma               <chr>  
#>  6 US Energy                Major US oil and gas                         <chr>  
#>  7 US Consumer              Major US consumer staples and retail         <chr>  
#>  8 US Industrials           Major US industrial companies                <chr>  
#>  9 US Index ETFs            Major US equity index ETFs                   <chr>  
#> 10 Major Crypto             Top 4 cryptocurrencies by market cap         <chr>  
#> 11 Stablecoins              USD-pegged cryptocurrency tokens             <chr>  
#> 12 Solana DeFi              Solana blockchain ecosystem tokens           <chr>  
#> 13 DeFi Altcoins            Alternative cryptocurrencies outside top 4   <chr>  
#> 14 Defense First            Macro rotation: 4 hedges covering deflation… <chr>  
#> 15 Macro Hedge ETFs         Extended macro hedge universe for backtesti… <chr>  
#> 16 FTSE 100 ETFs            ETFs tracking the FTSE 100 index on LSE      <chr>  
#> 17 UK Bond ETFs             UK government and corporate bond ETFs on LSE <chr>  
#> 18 Global Equity ETFs (LSE) World/global equity ETFs listed on LSE       <chr>  
#> 19 LSE Sector ETFs          Sector-specific ETFs on LSE (tech, healthca… <chr>  
hd_ticker_groups() |> dplyr::filter(group == "FAANG")
#> # A tibble: 1 × 3
#>   group description                                                tickers  
#>   <chr> <chr>                                                      <list>   
#> 1 FAANG Meta (Facebook), Apple, Amazon, Netflix, Google (Alphabet) <chr [5]>
```
