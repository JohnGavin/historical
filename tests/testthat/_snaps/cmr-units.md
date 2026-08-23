# .cmr_join_rf aborts on an INTERIOR gap (not a publication lag)

    Code
      .cmr_join_rf(df, gapped_rf, lookback = "test")
    Condition
      Error in `.join_rf_series()`:
      x 1 date inside daily_rf's own span have no risk-free rate (CMR test).
      i Missing date: "2020-10-01".
      i daily_rf spans 2020-01-01..2021-12-01, so this is a HOLE in the series, not a publication lag.
      i Investigate the FF3 source (the daily_rf target, R/plan_stock_backtest.R) before trusting any CMR test Sharpe figure.

# .cmr_join_rf aborts when daily_rf lacks required columns

    Code
      .cmr_join_rf(df, bad_rf, lookback = "test")
    Condition
      Error in `.join_rf_series()`:
      x .cmr_join_rf(): daily_rf is missing 1 required column: rf_ret.
      i Expected a tibble with date and rf_ret (the daily_rf target, R/plan_stock_backtest.R).

# .cmr_fill_non_trading_rf_gaps reports what it filled (#724 observability)

    Code
      .cmr_fill_non_trading_rf_gaps(df, daily_rf, lookback = "1m")
    Message
      v CMR 1m: carried daily_rf forward for 3 non-trading dates inside its own span (weekends/market holidays; longest gap to the prior available rate was 3 days).
      i Dates more than 7 days from the prior available rate are left uncovered and still abort via the #679 interior-hole guard.
    Output
      # A tibble: 6 x 2
        date        rf_ret
        <date>       <dbl>
      1 2024-08-30 0.0001 
      2 2024-08-31 0.0001 
      3 2024-09-01 0.0001 
      4 2024-09-02 0.0001 
      5 2024-09-03 0.00012
      6 2024-09-04 0.00011

# .cmr_fill_non_trading_rf_gaps leaves a gap wider than max_gap_days unfilled, and the join still aborts (real hole, not weakened)

    Code
      .cmr_join_rf(df, filled, lookback = "1m")
    Condition
      Error in `.join_rf_series()`:
      x 1 date inside daily_rf's own span have no risk-free rate (CMR 1m).
      i Missing date: "2024-01-10".
      i daily_rf spans 2024-01-01..2024-01-20, so this is a HOLE in the series, not a publication lag.
      i Investigate the FF3 source (the daily_rf target, R/plan_stock_backtest.R) before trusting any CMR 1m Sharpe figure.

# .cmr_fill_non_trading_rf_gaps does not touch a LEADING gap -- .cmr_join_rf still aborts LEADING

    Code
      .cmr_join_rf(df, filled, lookback = "1m")
    Condition
      Error in `.join_rf_series()`:
      x 1 date come before daily_rf even starts (CMR 1m).
      i Missing date: "2024-01-01".
      i daily_rf starts 2024-01-10; CMR 1m portfolio starts 2024-01-01.
      i This is LEADING coverage: the risk-free series simply does not reach this far back yet -- a different situation from a gap inside its own span.
      i Trim CMR 1m portfolio to start no earlier than 2024-01-10, or source an earlier daily_rf.

