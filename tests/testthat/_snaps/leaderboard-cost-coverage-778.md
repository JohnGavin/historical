# STRATEGY_COST_BASIS output is stable (snapshot)

    Code
      as.data.frame(dplyr::arrange(STRATEGY_COST_BASIS, code_name))
    Output
               code_name      short_name leg_multiplier turnover
      1      avoid_worst     Avoid Worst              2     0.50
      2              cmr             CMR              4     1.00
      3  cmr_conditioned CMR Conditioned              4     1.00
      4             drif     Factor DRIF              2     0.30
      5          ev_ebit     Value (HML)              2     0.20
      6          fac_max      Factor MAX              2     0.30
      7              ltr             LTR              4     0.20
      8           mf_tsm Managed Futures              4     0.25
      9     mom_combined        Mom 12-2              4     1.00
      10    mom_postpeak   Mom Post-Peak              4     1.00
      11     mom_prepeak    Mom Pre-Peak              4     1.00
      12           olmar         OLMAR-1              2     1.00
      13     pso_optimal     PSO Optimal              2     0.10
      14             rsc      Risk State              2     0.50
      15        stk_drif      Stock DRIF              4     1.00
      16         stk_max       Stock MAX              4     1.00
      17             tom             TOM              2     0.10
      18        xgb_drif        XGB DRIF              4     1.00
                                                                 turnover_basis
      1                                     hand-typed: fixture: no measurement
      2  hand-typed: measured turnover understates: exits not counted (#567 A2)
      3                                     hand-typed: fixture: no measurement
      4                                     hand-typed: fixture: no measurement
      5                                     hand-typed: fixture: no measurement
      6                                     hand-typed: fixture: no measurement
      7                                     hand-typed: fixture: no measurement
      8                                     hand-typed: fixture: no measurement
      9                                     hand-typed: fixture: no measurement
      10                                    hand-typed: fixture: no measurement
      11                                    hand-typed: fixture: no measurement
      12                                    hand-typed: fixture: no measurement
      13                                    hand-typed: fixture: no measurement
      14                                    hand-typed: fixture: no measurement
      15                                    hand-typed: fixture: no measurement
      16                                    hand-typed: fixture: no measurement
      17                                    hand-typed: fixture: no measurement
      18                                    hand-typed: fixture: no measurement
         monthly_cost
      1        0.0050
      2        0.0225
      3        0.0225
      4        0.0030
      5        0.0020
      6        0.0030
      7        0.0065
      8        0.0075
      9        0.0225
      10       0.0225
      11       0.0225
      12       0.0100
      13       0.0010
      14       0.0050
      15       0.0225
      16       0.0225
      17       0.0010
      18       0.0225

# .strategy_turnover_cost_basis() function signature is stable (catches API drift)

    Code
      args(.strategy_turnover_cost_basis)
    Output
      function (strategy_names_tbl, realised_tbl) 
      NULL

