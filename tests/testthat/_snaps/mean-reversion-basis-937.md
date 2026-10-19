# rf coverage gaps fail loud instead of dropping days

    Code
      .mr_run(port, rf_hole)
    Condition
      Error in `.join_rf_series()`:
      x 1 date inside daily_rf's own span have no risk-free rate (Mean Reversion).
      i Missing date: "2021-06-16".
      i daily_rf spans 2020-01-01..2023-12-29, so this is a HOLE in the series, not a publication lag.
      i Investigate the FF3 source (the daily_rf target, R/plan_stock_backtest.R) before trusting any Mean Reversion Sharpe figure.

# a daily_rf without rf_ret aborts

    Code
      .mr_run(.mr_fixture_port(), tibble::tibble(date = .mr_weekdays("2020-01-01",
        "2023-12-31")))
    Condition
      Error in `.join_rf_series()`:
      x .mr_join_rf(): daily_rf is missing 1 required column: rf_ret.
      i Expected a tibble with date and rf_ret (the daily_rf target, R/plan_stock_backtest.R).

