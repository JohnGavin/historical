# Mom: an unregistered label still aborts (no silent default)

    Code
      .mom_prepeak_join_rf(.mom_rets(12), .mom_rf(12), strategy = "Nope")
    Condition
      Error in `hd_return_basis_of()`:
      x Strategy "Nope" is not registered in `hd_return_basis()`.
      i Registered strategies: "Value (HML)", "Managed Futures", "Risk State", "Avoid Worst", "TOM", "OLMAR-1", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "LTR", "CMR", "CMR Conditioned", "Stock MAX", "Stock DRIF", "XGB DRIF", "Factor MAX", "Factor DRIF", "PSO Optimal", and "PSO Regime-Adjusted".
      i Add it to 'packages/historicaldata/R/hd_return_basis.R' with a file:line evidence string; a silent default would put its Sharpe on an unknown basis.

