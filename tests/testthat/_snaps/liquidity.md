# filter_liquidity aborts with an informative error when adv_usd is missing

    Code
      filter_liquidity(tibble::tibble(ticker = "AAA"))
    Condition
      Error in `filter_liquidity()`:
      ! adv_usd column missing. Run calculate_adv() first.

# filter_liquidity threshold_mode='percentile' aborts when the `by` column is absent

    Code
      filter_liquidity(tibble::tibble(ticker = "AAA", adv_usd = 1e+06),
      threshold_mode = "percentile", by = "date")
    Condition
      Error in `filter_liquidity()`:
      ! Column "date" (threshold_mode = 'percentile' cross-section key, `by`) not found in df.

# liquidity function signatures are stable (catches API drift)

    Code
      args(calculate_adv)
    Output
      function (df, window_days = 20) 
      NULL

---

    Code
      args(filter_liquidity)
    Output
      function (df, min_adv_usd = 1e+06, filter_mode = "warn", threshold_mode = c("nominal", 
          "percentile"), min_adv_percentile = 0.3, by = "date") 
      NULL

---

    Code
      args(liquidity_summary)
    Output
      function (df) 
      NULL

