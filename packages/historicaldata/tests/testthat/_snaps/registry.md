# hd_datasets snapshot

    Code
      str(hd_datasets())
    Output
      List of 4
       $ equity_daily:List of 4
        ..$ url        : chr "https://huggingface.co/datasets/dsfefvx/finance-historical-data/resolve/main/equity_daily.parquet"
        ..$ schema     : chr [1:10] "date" "open" "high" "low" ...
        ..$ frequency  : chr "daily"
        ..$ description: chr "US equities daily OHLCV (Yahoo Finance)"
       $ crypto_daily:List of 4
        ..$ url        : chr "https://huggingface.co/datasets/dsfefvx/finance-historical-data/resolve/main/crypto_daily.parquet"
        ..$ schema     : chr [1:7] "date" "close" "volume" "market_cap" ...
        ..$ frequency  : chr "daily"
        ..$ description: chr "Cryptocurrency daily prices (CoinGecko)"
       $ macro_daily :List of 4
        ..$ url        : chr "https://huggingface.co/datasets/dsfefvx/finance-historical-data/resolve/main/macro_daily.parquet"
        ..$ schema     : chr [1:4] "date" "value" "series_id" "source"
        ..$ frequency  : chr "mixed"
        ..$ description: chr "FRED macro series (SP500, VIX, rates, GDP, CPI, etc.)"
       $ factors     :List of 4
        ..$ url        : chr "https://huggingface.co/datasets/dsfefvx/finance-historical-data/resolve/main/factors.parquet"
        ..$ schema     : chr [1:6] "date" "factor_name" "value" "dataset" ...
        ..$ frequency  : chr "daily+monthly"
        ..$ description: chr "Fama-French factors (FF3, FF5, Momentum, 1926+)"

