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

# bdbb_fit output column schema is stable

    Code
      names(result)
    Output
      [1] "window_end"       "R"                "theta"            "half_life_hours" 
      [5] "signed_flow_mean" "amihud_mean"      "kyle_mean"        "n_obs"           
      [9] "regime"          

# bdbb_half_life and bdbb_tail_predict signatures are stable

    Code
      args(bdbb_half_life)
    Output
      function (theta) 
      NULL

---

    Code
      args(bdbb_tail_predict)
    Output
      function (diagnostics_df, returns_df) 
      NULL

