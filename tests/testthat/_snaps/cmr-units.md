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

