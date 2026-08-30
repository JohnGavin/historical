# hd_ohlcv snapshot of AAPL structure

    Code
      str(result)
    Output
      tibble [5 x 11] (S3: tbl_df/tbl/data.frame)
       $ date          : POSIXct[1:5], format: "2024-01-15" "2024-01-16" ...
       $ open          : num [1:5] 185 186 187 188 178
       $ high          : num [1:5] 186 188 187 188 179
       $ low           : num [1:5] 185 186 186 177 173
       $ close         : num [1:5] 186 188 187 177 174
       $ adjusted_close: num [1:5] 184 186 185 175 172
       $ volume        : num [1:5] 9716473 43644065 46127478 49897172 57473442
       $ ticker        : chr [1:5] "AAPL" "AAPL" "AAPL" "AAPL" ...
       $ source        : chr [1:5] "synthetic" "synthetic" "synthetic" "synthetic" ...
       $ asset_class   : chr [1:5] "equity" "equity" "equity" "equity" ...
       $ updated_at    : POSIXct[1:5], format: "2024-03-15" "2024-03-15" ...

# hd_datasets snapshot

    Code
      str(hd_datasets())
    Output
      List of 11
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
       $ fundamentals       :List of 4
        ..$ url        : chr "hf://datasets/JohnGavin/finance-data/fundamentals.parquet"
        ..$ schema     : chr [1:9] "ticker" "fiscal_period" "period_end" "first_filed" ...
        ..$ frequency  : chr "filing"
        ..$ description: chr "SEC EDGAR XBRL company-fundamentals revision triangle: one row per (ticker, xbrl_tag, fiscal_period), carrying "| __truncated__
       $ kraken_ohlcvt      :List of 4
        ..$ url        : chr "hf://datasets/JohnGavin/finance-data/kraken_ohlcvt.parquet"
        ..$ schema     : chr [1:10] "ticker" "pair" "interval_min" "time" ...
        ..$ frequency  : chr "60min+1440min"
        ..$ description: chr "Kraken exchange OHLCVT bars (hourly + daily) for 19 pairs: 6 crypto majors (BTC, ETH, SOL, XRP, ADA, LINK vs US"| __truncated__

# hd_ohlcv split-and-bind: collect=FALSE informs user

    Code
      result <- hd_ohlcv(c("AAPL", "BTC"), from = "2024-01-02", to = "2024-01-05",
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

