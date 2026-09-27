# .aw_strategy_period_metrics computes cagr/vol/sharpe from the return series it is given, not any other series

    list(period = "Full Period", years = 5, n_days = 1260L, cagr = 1.6, 
        vol = 14.3, max_dd = -27.6, sharpe = 0.02, ann_rf = 1.26, 
        window_start = structure(16437L, class = "Date"), window_end = structure(17696L, class = "Date"))

# .aw_strategy_period_metrics on ret_strategy differs from the same calculation on a divergent ret_market series (#813 regression)

    Code
      cat("strategy_row: cagr=", strategy_row$cagr, " sharpe=", strategy_row$sharpe,
      "\n")
    Output
      strategy_row: cagr= -13.1  sharpe= -1.36 
    Code
      cat("market_row:   cagr=", market_row$cagr, " sharpe=", market_row$sharpe, "\n")
    Output
      market_row:   cagr= 22.7  sharpe= 1.42 

