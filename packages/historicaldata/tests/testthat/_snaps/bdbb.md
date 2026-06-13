# bdbb_fit aborts informatively on missing column

    Code
      bdbb_fit(df)
    Condition
      Error in `bdbb_fit()`:
      x `df` is missing required columns: open, high, low, and trades.
      i Required columns: time, open, high, low, close, volume, and trades.
      i Did you pass output from `hd_kraken_ohlcvt()`?

# bdbb_fit signature is stable

    Code
      args(bdbb_fit)
    Output
      function (df, window_days = 30L, min_frac = 0.7) 
      NULL

