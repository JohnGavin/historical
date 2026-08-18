# .bt_sharpe_rf aborts on an INTERIOR gap (not a publication lag)

    Code
      .bt_sharpe_rf(dts, r, rf, ann_factor = 12L)
    Condition
      Error in `.bt_sharpe_rf()`:
      x 1 month inside stk_rf's own span have no risk-free rate.
      i Missing ym: "2020-10".
      i stk_rf spans 2020-01..2021-12, so this is a HOLE in the series, not a publication lag.
      i Investigate the FF3 source (R/plan_stock_backtest.R) before trusting this Sharpe.

# .bt_sharpe_rf aborts when stk_rf lacks required columns

    Code
      .bt_sharpe_rf(dts, r, bad_rf, ann_factor = 12L)
    Condition
      Error in `.bt_sharpe_rf()`:
      x .bt_sharpe_rf(): stk_rf is missing 1 required column: rf_ret.
      i Expected a tibble with ym and rf_ret (R/plan_stock_backtest.R).

