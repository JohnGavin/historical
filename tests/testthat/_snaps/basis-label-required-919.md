# calc_backtest_metrics aborts on a NULL / omitted label

    Code
      calc_backtest_metrics(.bt_df, "Full")
    Condition
      Error in `.require_basis_label()`:
      x `calc_backtest_metrics()`: `strategy` is required and must be one registered return-basis label (got <NULL>).
      i Registered strategies: "Value (HML)", "Managed Futures", "Risk State", "Avoid Worst", "TOM", "OLMAR-1", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "LTR", "CMR", "CMR Conditioned", "Stock MAX", "Stock DRIF", "XGB DRIF", "Factor MAX", "Factor DRIF", "PSO Optimal", ..., "Momentum Decomposition L/S", and "Regime Momentum".
      i A missing label would silently keep the legacy rf-deducted Sharpe, which is wrong for an excess-basis series (#919, fail-loud-not-null).

---

    Code
      calc_backtest_metrics(.bt_df, "Full", strategy = NULL)
    Condition
      Error in `.require_basis_label()`:
      x `calc_backtest_metrics()`: `strategy` is required and must be one registered return-basis label (got <NULL>).
      i Registered strategies: "Value (HML)", "Managed Futures", "Risk State", "Avoid Worst", "TOM", "OLMAR-1", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "LTR", "CMR", "CMR Conditioned", "Stock MAX", "Stock DRIF", "XGB DRIF", "Factor MAX", "Factor DRIF", "PSO Optimal", ..., "Momentum Decomposition L/S", and "Regime Momentum".
      i A missing label would silently keep the legacy rf-deducted Sharpe, which is wrong for an excess-basis series (#919, fail-loud-not-null).

# calc_backtest_metrics aborts on an unregistered / non-string label

    Code
      calc_backtest_metrics(.bt_df, "Full", strategy = "Not A Strategy")
    Condition
      Error in `hd_return_basis_of()`:
      x Strategy "Not A Strategy" is not registered in `hd_return_basis()`.
      i Registered strategies: "Value (HML)", "Managed Futures", "Risk State", "Avoid Worst", "TOM", "OLMAR-1", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "LTR", "CMR", "CMR Conditioned", "Stock MAX", "Stock DRIF", "XGB DRIF", "Factor MAX", "Factor DRIF", "PSO Optimal", ..., "Momentum Decomposition L/S", and "Regime Momentum".
      i Add it to 'packages/historicaldata/R/hd_return_basis.R' with a file:line evidence string; a silent default would put its Sharpe on an unknown basis.

---

    Code
      calc_backtest_metrics(.bt_df, "Full", strategy = 1)
    Condition
      Error in `.require_basis_label()`:
      x `calc_backtest_metrics()`: `strategy` is required and must be one registered return-basis label (got <numeric>).
      i Registered strategies: "Value (HML)", "Managed Futures", "Risk State", "Avoid Worst", "TOM", "OLMAR-1", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "LTR", "CMR", "CMR Conditioned", "Stock MAX", "Stock DRIF", "XGB DRIF", "Factor MAX", "Factor DRIF", "PSO Optimal", ..., "Momentum Decomposition L/S", and "Regime Momentum".
      i A missing label would silently keep the legacy rf-deducted Sharpe, which is wrong for an excess-basis series (#919, fail-loud-not-null).

# .compute_cmr_metrics aborts on a NULL / omitted label

    Code
      .compute_cmr_metrics(.cmr_pt, "1m", .cmr_rf, ann_factor = 12L)
    Condition
      Error in `.require_basis_label()`:
      x `.compute_cmr_metrics()`: `basis_strategy` is required and must be one registered return-basis label (got <NULL>).
      i Registered strategies: "Value (HML)", "Managed Futures", "Risk State", "Avoid Worst", "TOM", "OLMAR-1", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "LTR", "CMR", "CMR Conditioned", "Stock MAX", "Stock DRIF", "XGB DRIF", "Factor MAX", "Factor DRIF", "PSO Optimal", ..., "Momentum Decomposition L/S", and "Regime Momentum".
      i A missing label would silently keep the legacy rf-deducted Sharpe, which is wrong for an excess-basis series (#919, fail-loud-not-null).

---

    Code
      .compute_cmr_metrics(.cmr_pt, "1m", .cmr_rf, ann_factor = 12L, basis_strategy = NULL)
    Condition
      Error in `.require_basis_label()`:
      x `.compute_cmr_metrics()`: `basis_strategy` is required and must be one registered return-basis label (got <NULL>).
      i Registered strategies: "Value (HML)", "Managed Futures", "Risk State", "Avoid Worst", "TOM", "OLMAR-1", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "LTR", "CMR", "CMR Conditioned", "Stock MAX", "Stock DRIF", "XGB DRIF", "Factor MAX", "Factor DRIF", "PSO Optimal", ..., "Momentum Decomposition L/S", and "Regime Momentum".
      i A missing label would silently keep the legacy rf-deducted Sharpe, which is wrong for an excess-basis series (#919, fail-loud-not-null).

# .compute_cmr_metrics aborts on an unregistered label

    Code
      .compute_cmr_metrics(.cmr_pt, "1m", .cmr_rf, ann_factor = 12L, basis_strategy = "Not A Strategy")
    Condition
      Error in `hd_return_basis_of()`:
      x Strategy "Not A Strategy" is not registered in `hd_return_basis()`.
      i Registered strategies: "Value (HML)", "Managed Futures", "Risk State", "Avoid Worst", "TOM", "OLMAR-1", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "LTR", "CMR", "CMR Conditioned", "Stock MAX", "Stock DRIF", "XGB DRIF", "Factor MAX", "Factor DRIF", "PSO Optimal", ..., "Momentum Decomposition L/S", and "Regime Momentum".
      i Add it to 'packages/historicaldata/R/hd_return_basis.R' with a file:line evidence string; a silent default would put its Sharpe on an unknown basis.

