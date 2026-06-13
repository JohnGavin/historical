# hd_ohlcv snapshot of AAPL structure

    Code
      str(result)
    Output
      tibble [4 x 11] (S3: tbl_df/tbl/data.frame)
       $ date          : POSIXct[1:4], format: 
    Condition
      Warning in `as.POSIXlt.POSIXct()`:
      Coercing nanoseconds to a lower resolution may result in a loss of data.
    Output
      "2026-04-07" "2026-04-08" ...
       $ open          : num [1:4] 256 258 259 260
       $ high          : num [1:4] 256 260 261 262
       $ low           : num [1:4] 246 257 256 259
       $ close         : num [1:4] 254 259 260 260
       $ adjusted_close: num [1:4] 254 259 260 260
       $ volume        : num [1:4] 62148000 41032800 28121600 31259500
       $ ticker        : chr [1:4] "AAPL" "AAPL" "AAPL" "AAPL"
       $ source        : chr [1:4] "yahoo" "yahoo" "yahoo" "yahoo"
       $ asset_class   : chr [1:4] "equity" "equity" "equity" "equity"
       $ updated_at    : POSIXct[1:4], format: "2026-04-12 18:55:57" "2026-04-12 18:55:57" ...
# hd_datasets snapshot

    Code
      str(hd_datasets())
    Output
      List of 10
       $ equity_daily       :List of 6
        ..$ url                : chr "hf://datasets/JohnGavin/finance-data/equity_daily.parquet"
        ..$ schema             : chr [1:11] "date" "open" "high" "low" ...
        ..$ frequency          : chr "daily"
        ..$ description        : chr "US equities daily OHLCV (Yahoo Finance). WARNING: survivorship-biased — universe reflects currently-listed tick"| __truncated__
        ..$ survivorship_biased: logi TRUE
        ..$ known_delistings   : int 0
       $ crypto_daily       :List of 4
        ..$ url        : chr "hf://datasets/JohnGavin/finance-data/crypto_daily.parquet"
        ..$ schema     : chr [1:10] "date" "open" "high" "low" ...
        ..$ frequency  : chr "daily"
        ..$ description: chr "Cryptocurrency daily OHLCV (Yahoo Finance)"
       $ macro_daily        :List of 4
        ..$ url        : chr "hf://datasets/JohnGavin/finance-data/macro_daily.parquet"
        ..$ schema     : chr [1:4] "date" "value" "series_id" "source"
        ..$ frequency  : chr "mixed"
        ..$ description: chr "FRED macro series (SP500, VIX, rates, GDP, CPI, etc.)"
       $ factors            :List of 4
        ..$ url        : chr "hf://datasets/JohnGavin/finance-data/factors.parquet"
        ..$ schema     : chr [1:7] "date" "factor_name" "value" "dataset" ...
        ..$ frequency  : chr "daily+monthly"
        ..$ description: chr "Fama-French factors (FF3, FF5, Momentum, 1926+)"
       $ metadata           :List of 4
        ..$ url        : chr "hf://datasets/JohnGavin/finance-data/metadata.parquet"
        ..$ schema     : chr [1:31] "ticker" "dataset" "long_name" "exchange" ...
        ..$ frequency  : chr "static"
        ..$ description: chr "Per-ticker metadata: exchange, sector, market cap, ETF fees/yield/returns, coverage stats"
       $ macro_vintages     :List of 4
        ..$ url        : chr "hf://datasets/JohnGavin/finance-data/macro_vintages.parquet"
        ..$ schema     : chr [1:4] "series_id" "date" "pub_date" "value"
        ..$ frequency  : chr "vintage"
        ..$ description: chr "FRED macro revision history: value as known at each publication date (ALFRED API)"
       $ metadata_amendments:List of 4
        ..$ url        : chr "hf://datasets/JohnGavin/finance-data/metadata_amendments.parquet"
        ..$ schema     : chr [1:9] "ticker" "field" "old_value" "new_value" ...
        ..$ frequency  : chr "append-only"
        ..$ description: chr "PIT log of all metadata changes: computed fields, enrichments, corrections"
       $ jst_macrohistory   :List of 4
        ..$ url        : chr "https://www.macrohistory.net/app/download/9834512469/JSTdatasetR6.dta"
        ..$ schema     : chr [1:27] "iso" "year" "eq_tr" "bond_tr" ...
        ..$ frequency  : chr "annual"
        ..$ description: chr "Jorda-Schularick-Taylor Macrohistory Database (Release 6): 18 countries, 1870-2020, annual returns for equity, "| __truncated__
       $ alphavantage_daily :List of 4
        ..$ url        : chr NA
        ..$ schema     : chr [1:8] "date" "open" "high" "low" ...
        ..$ frequency  : chr "daily"
        ..$ description: chr "US equities daily adjusted OHLCV via AlphaVantage API (not a parquet snapshot). Use hd_alphavantage(ticker) to "| __truncated__
       $ kraken_ohlcvt      :List of 4
        ..$ url        : chr "hf://datasets/JohnGavin/finance-data/kraken_ohlcvt.parquet"
        ..$ schema     : chr [1:10] "ticker" "pair" "interval_min" "time" ...
        ..$ frequency  : chr "60min+1440min"
        ..$ description: chr "Kraken exchange OHLCVT bars (hourly + daily) for 19 pairs: 6 crypto majors (BTC, ETH, SOL, XRP, ADA, LINK vs US"| __truncated__

# hd_ohlcv split-and-bind: collect=FALSE informs user

    Code
      result <- hd_ohlcv(c("AAPL", "BTC"), from = "2026-04-01", to = "2026-04-05",
      collect = FALSE)
    Message
      Mixed-dataset batch detected: "crypto_daily" and "equity_daily".
      i Returning materialised tibble; `collect = FALSE` cannot be honoured when binding across datasets.

# hd_ohlcv: empty ticker vector errors

    Code
      hd_ohlcv(character(0))
    Condition
      Error in `hd_ohlcv()`:
      ! `ticker` must be a non-empty character vector.

# date filter works against TIMESTAMP-typed parquet column (#453)

    Code
      names(result)
    Output
      [1] "date"   "ticker" "close" 

# hd_ohlcv: API stability snapshot (#453)

    Code
      args(hd_ohlcv)
    Output
      function (ticker, from = NULL, to = NULL, dataset = NULL, local = FALSE, 
          collect = TRUE) 
      NULL

