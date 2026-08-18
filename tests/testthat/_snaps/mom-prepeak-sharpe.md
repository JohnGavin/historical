# .mom_prepeak_join_rf aborts on an INTERIOR gap (not a publication lag)

    Code
      .mom_prepeak_join_rf(rets, rf)
    Condition
      Error in `.join_rf_series()`:
      x 1 month inside stk_rf's own span have no risk-free rate (mom_prepeak).
      i Missing month: "2020-10".
      i stk_rf spans 2020-01..2021-12, so this is a HOLE in the series, not a publication lag.
      i Investigate the FF3 source (R/plan_stock_backtest.R) before trusting any mom_prepeak Sharpe figure.

# .mom_prepeak_join_rf aborts when stk_rf is missing required columns

    Code
      .mom_prepeak_join_rf(rets, bad_rf)
    Condition
      Error in `.join_rf_series()`:
      x .mom_prepeak_join_rf(): stk_rf is missing 1 required column: rf_ret.
      i Expected a tibble with ym and rf_ret (R/plan_stock_backtest.R).

# .mom_prepeak_join_rf aborts when returns_tbl has no exec_date column

    Code
      .mom_prepeak_join_rf(bad_rets, rf)
    Condition
      Error in `.mom_prepeak_join_rf()`:
      x .mom_prepeak_join_rf(): returns_tbl has no exec_date column to join on.

# .mom_prepeak_sharpe aborts when rf_ret column is missing

    Code
      .mom_prepeak_sharpe(rets, metrics_row)
    Condition
      Error in `.mom_prepeak_sr()`:
      x .mom_prepeak_sharpe(): `returns_tbl` has no rf_ret column.
      i Join a risk-free series onto returns_tbl first -- see `.mom_prepeak_join_rf()`.

