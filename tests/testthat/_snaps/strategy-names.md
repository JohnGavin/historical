# full strategy_names tuple table is stable (parallel-vector alignment snapshot)

    Code
      print(tuple_tbl, width = 200)
    Output
            code_name      short_name                                                long_name frequency ann_factor
      1   avoid_worst     Avoid Worst                        Avoid Worst Days (VIX Protection)     daily        252
      2          drif     Factor DRIF                            Factor DRIF (Factor Rotation)   monthly         12
      3       fac_max      Factor MAX                             Factor MAX (Factor Momentum)   monthly         12
      4           rsc      Risk State                                 Risk State (VIX Overlay)     daily        252
      5           ltr             LTR                           LTR (Cross-Sectional Momentum)   monthly         12
      6           tom             TOM                          Turn-of-the-Month (TOM Overlay)     daily        252
      7       stk_max       Stock MAX                         Stock MAX (Daily Return Sorting)   monthly         12
      8      stk_drif      Stock DRIF                 Stock DRIF (Elastic Net Stock Selection)   monthly         12
      9      xgb_drif        XGB DRIF                       XGB DRIF (XGBoost Stock Selection)   monthly         12
      10  pso_optimal     PSO Optimal                     PSO Optimal (Portfolio Optimisation)   monthly         12
      11          cmr             CMR                               Commodities Mean Reversion     daily        252
      12  mom_prepeak    Mom Pre-Peak                     Pre-Peak 12-2 Momentum (Büsing 2022)   monthly         12
      13 mom_postpeak   Mom Post-Peak                    Post-Peak 12-2 Momentum (Büsing 2022)   monthly         12
      14 mom_combined        Mom 12-2                 Standard 12-2 Momentum (Büsing baseline)   monthly         12
      15      ev_ebit     Value (HML)                 EV/EBIT Value Sleeve (HML+RMW Proxy, v0)   monthly         12
      16       mf_tsm Managed Futures      Cross-Asset TS-Momentum (MOP 2012, ETF Proxies, v0)   monthly         12
      17        olmar         OLMAR-1 OLMAR-1 (Online Moving Average Reversion, Li & Hoi 2012)     daily        252

# .build_strategy_obs_ann_factor() aborts loudly when a strategy has no source citation

    Code
      .build_strategy_obs_ann_factor(strategy_names_tbl, incomplete_source)
    Condition
      Error in `.build_strategy_obs_ann_factor()`:
      x 1 strategy/strategies in strategy_names have no obs_ann_factor_source citation:
      i  OLMAR-1
      i Add a row to .strategy_obs_ann_factor_source (R/plan_leaderboard.R) keyed by code_name, citing the strategy's calc_metrics()/compute_*() annualisation source.

