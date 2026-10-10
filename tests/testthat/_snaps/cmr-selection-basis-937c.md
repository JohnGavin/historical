# .cmr_ssr_returns aborts on an unknown strategy_id and on a blend without rf / cash weight

    Code
      .cmr_ssr_returns(port, "cmr_other", .ssr_rf, "1m")
    Condition
      Error in `.cmr_ssr_returns()`:
      x .cmr_ssr_returns(): `strategy_id` must be one of "cmr" and "cmr_conditioned".
      i Got "cmr_other". Add the code_name -> hd_return_basis() label mapping here before registering another CMR variant.

---

    Code
      .cmr_ssr_returns(port, "cmr_conditioned", NULL, "1m")
    Condition
      Error in `.cmr_ssr_returns()`:
      x "CMR Conditioned" is a blend-basis strategy: its SSR needs `daily_rf` and a cash_weight column.
      i Without them its SSR would silently stay on the total-return basis (#937).

---

    Code
      .cmr_ssr_returns(port[, c("date", "net_ret")], "cmr_conditioned", .ssr_rf, "1m")
    Condition
      Error in `.cmr_ssr_returns()`:
      x "CMR Conditioned" is a blend-basis strategy: its SSR needs `daily_rf` and a cash_weight column.
      i Without them its SSR would silently stay on the total-return basis (#937).

