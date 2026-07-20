# filter_liquidity aborts with an informative error when adv_usd is missing

    Code
      filter_liquidity(tibble::tibble(ticker = "AAA"))
    Condition
      Error in `filter_liquidity()`:
      ! adv_usd column missing. Run calculate_adv() first.

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
      function (df, min_adv_usd = 1e+06, filter_mode = "warn") 
      NULL

---

    Code
      args(liquidity_summary)
    Output
      function (df) 
      NULL

