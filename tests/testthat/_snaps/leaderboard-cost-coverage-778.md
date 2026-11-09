# STRATEGY_COST_BASIS output is stable (snapshot)

    Code
      as.data.frame(dplyr::arrange(STRATEGY_COST_BASIS, code_name))
    Output
               code_name      short_name
      1      avoid_worst     Avoid Worst
      2              cmr             CMR
      3  cmr_conditioned CMR Conditioned
      4             drif     Factor DRIF
      5          ev_ebit     Value (HML)
      6          fac_max      Factor MAX
      7              ltr             LTR
      8           mf_tsm Managed Futures
      9     mom_combined        Mom 12-2
      10    mom_postpeak   Mom Post-Peak
      11     mom_prepeak    Mom Pre-Peak
      12           olmar         OLMAR-1
      13     pso_optimal     PSO Optimal
      14             rsc      Risk State
      15        stk_drif      Stock DRIF
      16         stk_max       Stock MAX
      17             tom             TOM
      18        xgb_drif        XGB DRIF
                                                                                    cost_basis
      1                                                                            leaderboard
      2                                                                            leaderboard
      3     internal: overlay series exposed only net of its own cost; no gross series exposed
      4                                                                            leaderboard
      5                                                                            leaderboard
      6                                                                            leaderboard
      7                                                                            leaderboard
      8                                                                            leaderboard
      9                                                                            leaderboard
      10                                                                           leaderboard
      11                                                                           leaderboard
      12                                                                           leaderboard
      13 internal: blend of constituents already net of their own cost; no gross blend exposed
      14                                                                           leaderboard
      15                                                                           leaderboard
      16                                                                           leaderboard
      17                                                                           leaderboard
      18                                                                           leaderboard
         leg_multiplier turnover
      1               1     0.50
      2               4     1.00
      3               4       NA
      4               2     0.30
      5               2     0.20
      6               2     0.30
      7               4     0.20
      8               4     0.25
      9               4     1.00
      10              4     1.00
      11              4     1.00
      12              2     1.00
      13              2       NA
      14              1     0.50
      15              4     1.00
      16              4     1.00
      17              1     0.10
      18              4     1.00
                                                                 turnover_basis
      1                                     hand-typed: fixture: no measurement
      2  hand-typed: measured turnover understates: exits not counted (#567 A2)
      3                                                                    <NA>
      4                                     hand-typed: fixture: no measurement
      5                                     hand-typed: fixture: no measurement
      6                                     hand-typed: fixture: no measurement
      7                                     hand-typed: fixture: no measurement
      8                                     hand-typed: fixture: no measurement
      9                                     hand-typed: fixture: no measurement
      10                                    hand-typed: fixture: no measurement
      11                                    hand-typed: fixture: no measurement
      12                                    hand-typed: fixture: no measurement
      13                                                                   <NA>
      14                                    hand-typed: fixture: no measurement
      15                                    hand-typed: fixture: no measurement
      16                                    hand-typed: fixture: no measurement
      17                                    hand-typed: fixture: no measurement
      18                                    hand-typed: fixture: no measurement
         monthly_cost
      1        0.0025
      2        0.0225
      3        0.0000
      4        0.0030
      5        0.0020
      6        0.0030
      7        0.0065
      8        0.0075
      9        0.0225
      10       0.0225
      11       0.0225
      12       0.0100
      13       0.0000
      14       0.0025
      15       0.0225
      16       0.0225
      17       0.0005
      18       0.0225

# .strategy_turnover_cost_basis() function signature is stable (catches API drift)

    Code
      args(.strategy_turnover_cost_basis)
    Output
      function (strategy_names_tbl, realised_tbl, internal_only = .HD_COST_INTERNAL_ONLY) 
      NULL

