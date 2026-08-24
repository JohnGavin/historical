# .bt_sortino_rf aborts on an INTERIOR gap (not a publication lag)

    Code
      .bt_sortino_rf(dts, r, rf, ann_factor = 12L)
    Condition
      Error in `.join_rf_series()`:
      x 1 month inside stk_rf's own span have no risk-free rate (Defense First / SPY).
      i Missing month: "2020-10".
      i stk_rf spans 2020-01..2021-12, so this is a HOLE in the series, not a publication lag.
      i Investigate the FF3 source (R/plan_stock_backtest.R) before trusting any Defense First / SPY Sharpe figure.

# .bt_sortino_rf aborts when stk_rf lacks required columns

    Code
      .bt_sortino_rf(dts, r, bad_rf, ann_factor = 12L)
    Condition
      Error in `.join_rf_series()`:
      x .bt_sortino_rf(): stk_rf is missing 1 required column: rf_ret.
      i Expected a tibble with ym and rf_ret (R/plan_stock_backtest.R).

