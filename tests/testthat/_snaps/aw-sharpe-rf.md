# .aw_sharpe_rf aborts on an INTERIOR gap (not a publication lag)

    Code
      .aw_sharpe_rf(dts, r, rf, ann_factor = 252L)
    Condition
      Error in `.aw_sharpe_rf_full()`:
      x 1 day inside the daily risk-free series' own span have no rate.
      i Missing dates: "2020-02-20".
      i Fama-French daily RF spans 2020-01-02..2020-04-10, so this is a HOLE, not a publication lag.
      i Investigate hd_factors() (factor_name == "RF", frequency == "daily") before trusting this Sharpe.

# .aw_sharpe_rf aborts when aw_daily_rf lacks required columns

    Code
      .aw_sharpe_rf(dts, r, bad_rf, ann_factor = 252L)
    Condition
      Error in `.aw_sharpe_rf_full()`:
      x .aw_sharpe_rf(): aw_daily_rf is missing 1 required column: rf_ret.
      i Expected a tibble with date and rf_ret (this file's aw_daily_rf target).

