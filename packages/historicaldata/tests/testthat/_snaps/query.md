# hd_ohlcv snapshot of AAPL structure

    Code
      str(result)
    Output
      tibble [4 x 11] (S3: tbl_df/tbl/data.frame)
       $ date       : POSIXct[1:4], format: "2026-04-07" "2026-04-08" ...
       $ open       : num [1:4] 256 258 259 260
       $ high       : num [1:4] 256 260 261 262
       $ low        : num [1:4] 246 257 256 259
       $ close      : num [1:4] 254 259 260 260
       $ adjusted   : num [1:4] 254 259 260 260
       $ volume     : num [1:4] 62148000 41032800 28121600 31259500
       $ ticker     : chr [1:4] "AAPL" "AAPL" "AAPL" "AAPL"
       $ source     : chr [1:4] "yahoo" "yahoo" "yahoo" "yahoo"
       $ asset_class: chr [1:4] "equity" "equity" "equity" "equity"
       $ updated_at : POSIXct[1:4], format: "2026-04-12 18:55:57" "2026-04-12 18:55:57" ...

# hd_datasets snapshot

    Code
      str(hd_datasets())
    Output
      List of 7
       $ equity_daily       :List of 4
        ..$ url        : chr "hf://datasets/dsfefvx/finance-historical-data/equity_daily.parquet"
        ..$ schema     : chr [1:10] "date" "open" "high" "low" ...
        ..$ frequency  : chr "daily"
        ..$ description: chr "US equities daily OHLCV (Yahoo Finance)"
       $ crypto_daily       :List of 4
        ..$ url        : chr "hf://datasets/dsfefvx/finance-historical-data/crypto_daily.parquet"
        ..$ schema     : chr [1:7] "date" "close" "volume" "market_cap" ...
        ..$ frequency  : chr "daily"
        ..$ description: chr "Cryptocurrency daily prices (CoinGecko)"
       $ macro_daily        :List of 4
        ..$ url        : chr "hf://datasets/dsfefvx/finance-historical-data/macro_daily.parquet"
        ..$ schema     : chr [1:4] "date" "value" "series_id" "source"
        ..$ frequency  : chr "mixed"
        ..$ description: chr "FRED macro series (SP500, VIX, rates, GDP, CPI, etc.)"
       $ factors            :List of 4
        ..$ url        : chr "hf://datasets/dsfefvx/finance-historical-data/factors.parquet"
        ..$ schema     : chr [1:6] "date" "factor_name" "value" "dataset" ...
        ..$ frequency  : chr "daily+monthly"
        ..$ description: chr "Fama-French factors (FF3, FF5, Momentum, 1926+)"
       $ metadata           :List of 4
        ..$ url        : chr "hf://datasets/dsfefvx/finance-historical-data/metadata.parquet"
        ..$ schema     : chr [1:25] "ticker" "dataset" "long_name" "exchange" ...
        ..$ frequency  : chr "static"
        ..$ description: chr "Per-ticker metadata: exchange, sector, market cap, ETF fees/yield/returns, coverage stats"
       $ macro_vintages     :List of 4
        ..$ url        : chr "hf://datasets/dsfefvx/finance-historical-data/macro_vintages.parquet"
        ..$ schema     : chr [1:4] "series_id" "date" "pub_date" "value"
        ..$ frequency  : chr "vintage"
        ..$ description: chr "FRED macro revision history: value as known at each publication date (ALFRED API)"
       $ metadata_amendments:List of 4
        ..$ url        : chr "hf://datasets/dsfefvx/finance-historical-data/metadata_amendments.parquet"
        ..$ schema     : chr [1:9] "ticker" "field" "old_value" "new_value" ...
        ..$ frequency  : chr "append-only"
        ..$ description: chr "PIT log of all metadata changes: computed fields, enrichments, corrections"

