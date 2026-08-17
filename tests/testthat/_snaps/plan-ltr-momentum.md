# .ltr_join_rf abort messages are stable

    Code
      .ltr_join_rf(port, .mk_rf(c("2026-01", "2026-03")))
    Condition
      Error in `.ltr_join_rf()`:
      x 1 month inside stk_rf's own span have no risk-free rate.
      i Missing ym: "2026-02".
      i stk_rf spans 2026-01..2026-03, so this is a HOLE in the series, not a publication lag.
      i Investigate the FF3 source (R/plan_stock_backtest.R) before trusting any LTR Sharpe figure.

---

    Code
      .ltr_join_rf(.mk_port("2026-01"), tibble::tibble(ym = "2026-01"))
    Condition
      Error in `.ltr_join_rf()`:
      x .ltr_join_rf(): stk_rf is missing 1 required column: rf_ret.
      i Expected a tibble with ym and rf_ret (R/plan_stock_backtest.R).

