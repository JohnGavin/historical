# .olmar_join_rf abort messages are stable

    Code
      .olmar_join_rf(port, .mk_rf_daily(c("2026-01-05", "2026-01-07")))
    Condition
      Error in `.join_rf_series()`:
      x 1 date inside daily_rf's own span have no risk-free rate (OLMAR-1).
      i Missing date: "2026-01-06".
      i daily_rf spans 2026-01-05..2026-01-07, so this is a HOLE in the series, not a publication lag.
      i Investigate the FF3 source (the daily_rf target, R/plan_stock_backtest.R) before trusting any OLMAR-1 Sharpe figure.

