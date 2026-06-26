# .pick_price_col snapshot of priority table is stable

    Code
      results
    Output
             all_three      adj_missing       close_only 
      "adjusted_close"       "adjusted"          "close" 

# hd_top_by rejects invalid metric with informative error

    Code
      hd_top_by("equity_daily", "not_a_metric", 3)
    Condition
      Error in `hd_top_by()`:
      ! Invalid metric: not_a_metric. Valid: market_cap, volume_avg, total_obs, missing_pct, fifty_two_week_high, fifty_two_week_low, expense_ratio, yield_pct, beta_3yr, ytd_return, three_yr_return

