# hd_datasets snapshot

    Code
      str(hd_datasets())
    Output
      List of 9
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

