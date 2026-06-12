# parse_ohlcvt_from_zip snapshot — column names and type summary

    Code
      cat(summary_str)
    Output
      ticker:character, pair:character, interval_min:integer, time:POSIXct, open:numeric, high:numeric, low:numeric, close:numeric, volume:numeric, trades:integer

# dv_kraken_ohlcvt error message snapshot — missing column

    Code
      dv_kraken_ohlcvt(df_bad)
    Condition
      Error in `dv_kraken_ohlcvt()`:
      x kraken_ohlcvt: missing columns: volume, trades
      i Expected: ticker, pair, interval_min, time, open, high, low, close, volume, trades

# PAIRS snapshot — ticker list is stable

    Code
      cat(paste(tickers, collapse = ", "))
    Output
      BTC, ETH, SOL, XRP, ADA, LINK

