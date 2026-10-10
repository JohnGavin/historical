# strat_deflated_sharpe output schema and row order are stable

    list(names = c("strategy", "naive_sharpe", "T_obs", "deflated_sharpe", 
    "dsr_pvalue", "dsr_haircut_pct", "sharpe_haircut", "sharpe_haircut_pct", 
    "k_eff_leaderboard", "k_raw_leaderboard", "k_eff_family", "k_raw_family"
    ), strategy = c("Stock MAX", "Stock DRIF", "Factor MAX", "Factor DRIF", 
    "LTR", "XGB DRIF", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", 
    "Value (HML)", "Managed Futures", "CMR", "CMR Conditioned", "OLMAR-1", 
    "TOM", "Risk State", "Avoid Worst"))

---

    Code
      args(hd_rf_for_basis)
    Output
      function (rf, strategy, cash_weight = NULL) 
      NULL

