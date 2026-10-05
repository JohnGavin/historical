# a blend strategy without a cash_weight column aborts (never silently rf-deducted)

    Code
      .compute_cmr_metrics(pt, lookback = "t", daily_rf = rf, ann_factor = 12L,
        basis_strategy = "CMR Conditioned")
    Condition
      Error in `.hd_check_cash_weight()`:
      x `hd_rf_for_basis()`: "CMR Conditioned" is a "blend" strategy, so `cash_weight` must be a numeric vector (never NULL).
      i Got <NULL>.
      i The registry names the column: `hd_return_basis()$cash_weight_col`.

