# hd_kraken_ohlcvt rejects unsupported intervals and future dates

    Code
      hd_kraken_ohlcvt("SOL", interval_min = 5L, local = TRUE)
    Condition
      Error in `hd_kraken_ohlcvt()`:
      x `interval_min` must be 60 (hourly) or 1440 (daily), not 5.
      i The kraken_ohlcvt dataset ships only these two intervals (#436).

# hd_kraken_ohlcvt errors helpfully when local cache is absent

    Code
      hd_kraken_ohlcvt("SOL", local = TRUE)
    Condition
      Error in `hd_kraken_ohlcvt()`:
      ! Local cache not found for kraken_ohlcvt
      i Run 'scripts/fetch_kraken_ohlcvt.R' first, or use `local = FALSE`.

# hd_kraken_ohlcvt API signature is stable

    Code
      args(hd_kraken_ohlcvt)
    Output
      function (ticker = NULL, interval_min = 60L, from = NULL, to = NULL, 
          local = FALSE, collect = TRUE) 
      NULL

# kraken_ohlcvt registry entry has the canonical schema

    Code
      cat("schema:", paste(ds$schema, collapse = ", "), "\n")
    Output
      schema: ticker, pair, interval_min, time, open, high, low, close, volume, trades 
    Code
      cat("frequency:", ds$frequency, "\n")
    Output
      frequency: 60min+1440min 

