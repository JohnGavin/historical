# .tom_join_rf_daily abort messages are stable

    Code
      .tom_join_rf_daily(port, .mk_rf_daily(c("2026-01-05", "2026-01-07")))
    Condition
      Error in `.tom_join_rf_daily()`:
      x 1 date inside tom_rf_daily's own span have no risk-free rate.
      i Missing date: "2026-01-06".
      i tom_rf_daily spans 2026-01-05..2026-01-07, so this is a HOLE in the series, not a publication lag.
      i Investigate the FF3 source (R/plan_stock_backtest.R's stk_rf pattern) before trusting any TOM Sharpe figure.

---

    Code
      .tom_join_rf_daily(.mk_port_daily("2026-01-05"), tibble::tibble(date = as.Date(
        "2026-01-05")))
    Condition
      Error in `.tom_join_rf_daily()`:
      x .tom_join_rf_daily(): rf is missing 1 required column: rf_ret.
      i Expected a tibble with date and rf_ret (the tom_rf_daily target).

