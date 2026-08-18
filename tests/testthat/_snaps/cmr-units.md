# .cmr_join_rf aborts on an INTERIOR gap (not a publication lag)

    Code
      .cmr_join_rf(df, gapped_rf, lookback = "test")
    Condition
      Error in `.cmr_join_rf()`:
      x 1 month inside stk_rf's own span have no risk-free rate (CMR test lookback).
      i Missing ym: "2020-10".
      i stk_rf spans 2020-01..2021-12, so this is a HOLE in the series, not a publication lag.
      i Investigate the FF3 source (R/plan_stock_backtest.R) before trusting any CMR Sharpe figure.

# .cmr_join_rf aborts when stk_rf lacks required columns

    Code
      .cmr_join_rf(df, bad_rf, lookback = "test")
    Condition
      Error in `.cmr_join_rf()`:
      x .cmr_join_rf(): stk_rf is missing 1 required column: rf_ret.
      i Expected a tibble with ym and rf_ret (R/plan_stock_backtest.R).

