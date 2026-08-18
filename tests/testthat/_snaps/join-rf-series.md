# .join_rf_series abort messages are stable (monthly)

    Code
      .call_join(.mk_df_ym(c("2026-01", "2026-02", "2026-03")), .mk_rf_ym(c("2026-01",
        "2026-03")), .args_ym)
    Condition
      Error:
      x 1 month inside test_rf's own span have no risk-free rate (TEST).
      i Missing month: "2026-02".
      i test_rf spans 2026-01..2026-03, so this is a HOLE in the series, not a publication lag.
      i Investigate the FF3 source (test source) before trusting any TEST Sharpe figure.

---

    Code
      .call_join(.mk_df_ym(c("2025-11", "2025-12", "2026-01")), .mk_rf_ym(c("2025-12",
        "2026-01")), .args_ym)
    Condition
      Error:
      x 1 month come before test_rf even starts (TEST).
      i Missing month: "2025-11".
      i test_rf starts 2025-12; test_df starts 2025-11.
      i This is LEADING coverage: the risk-free series simply does not reach this far back yet -- a different situation from a gap inside its own span.
      i Trim test_df to start no earlier than 2025-12, or source an earlier test_rf.

---

    Code
      .call_join(.mk_df_ym("2026-01"), tibble::tibble(ym = "2026-01"), .args_ym)
    Condition
      Error:
      x .test_join(): test_rf is missing 1 required column: rf_ret.
      i Expected a tibble with ym and rf_ret (test source).

# .join_rf_series abort messages are stable (daily)

    Code
      .call_join(.mk_df_date(c("2026-01-05", "2026-01-06", "2026-01-07")),
      .mk_rf_date(c("2026-01-05", "2026-01-07")), .args_date)
    Condition
      Error:
      x 1 date inside test_daily_rf's own span have no risk-free rate (TEST-DAILY).
      i Missing date: "2026-01-06".
      i test_daily_rf spans 2026-01-05..2026-01-07, so this is a HOLE in the series, not a publication lag.
      i Investigate the FF3 source (test daily source) before trusting any TEST-DAILY Sharpe figure.

