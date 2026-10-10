# .decay_metrics_row: an unmapped strategy name aborts (never a silent default)

    Code
      .decay_metrics_row(port, "not_a_strategy", 1L)
    Condition
      Error in `.decay_metrics_row()`:
      x `.decay_metrics_row()`: `strategy_name` "not_a_strategy" has no registered return-basis label.
      i Known: "stk_max" and "stk_drif".
      i Map it to a `hd_return_basis()` strategy; a silent default would put its Sharpe on an unknown basis.

# market_impact_sensitivity: rf supplied without a registered label aborts

    Code
      local_env_stk$market_impact_sensitivity(fx$df, fx$returns_wide, eta_grid = 1,
      lookback_months = 1L, adv_monthly = fx$adv_monthly, adv_pct_cap = 1,
      impact_aum = 1e+07, impact_sigma = 0.02, rf = fx$rf)
    Condition
      Error in `.require_basis_label()`:
      x `market_impact_sensitivity()`: `strategy` is required and must be one registered return-basis label (got <NULL>).
      i Registered strategies: "Value (HML)", "Managed Futures", "Risk State", "Avoid Worst", "TOM", "OLMAR-1", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "LTR", "CMR", "CMR Conditioned", "Stock MAX", "Stock DRIF", "XGB DRIF", "Factor MAX", "Factor DRIF", "PSO Optimal", and "PSO Regime-Adjusted".
      i A missing label would silently keep the legacy rf-deducted Sharpe, which is wrong for an excess-basis series (#919, fail-loud-not-null).

