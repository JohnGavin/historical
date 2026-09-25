# STRATEGY_COST_BASIS output is stable (snapshot)

    Code
      as.data.frame(dplyr::arrange(STRATEGY_COST_BASIS, code_name))
    Output
               code_name      short_name leg_multiplier monthly_cost
      1      avoid_worst     Avoid Worst              2       0.0050
      2              cmr             CMR              4       0.0225
      3  cmr_conditioned CMR Conditioned              4       0.0225
      4             drif     Factor DRIF              2       0.0030
      5          ev_ebit     Value (HML)              2       0.0020
      6          fac_max      Factor MAX              2       0.0030
      7              ltr             LTR              4       0.0065
      8           mf_tsm Managed Futures              4       0.0075
      9     mom_combined        Mom 12-2              4       0.0225
      10    mom_postpeak   Mom Post-Peak              4       0.0225
      11     mom_prepeak    Mom Pre-Peak              4       0.0225
      12           olmar         OLMAR-1              2       0.0100
      13     pso_optimal     PSO Optimal              2       0.0010
      14             rsc      Risk State              2       0.0050
      15        stk_drif      Stock DRIF              4       0.0225
      16         stk_max       Stock MAX              4       0.0225
      17             tom             TOM              2       0.0010
      18        xgb_drif        XGB DRIF              4       0.0225

# .strategy_turnover_cost_basis() function signature is stable (catches API drift)

    Code
      args(.strategy_turnover_cost_basis)
    Output
      function (strategy_names_tbl) 
      NULL

