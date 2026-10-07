# .strat_excess_wide aborts on an unmapped column

    Code
      .strat_excess_wide(toy$strat_returns_wide, c("stk_max", "value_hml"), c(
        stk_max = "Stock MAX"), toy$strat_returns_daily_native, src)
    Condition
      Error in `.strat_excess_wide()`:
      x 1 strategy code_name has no label for the return-basis registry: "value_hml".
      i Add the code_name -> leaderboard label mapping to name_map in strat_corr_augment; the label must be registered in `hd_return_basis()`.

# .strat_excess_wide aborts when a total column has no rf source

    Code
      .strat_excess_wide(toy$strat_returns_wide, c("stk_max", "value_hml"),
      .label_map, toy$strat_returns_daily_native, list(monthly = list(), daily = list()))
    Condition
      Error in `.strat_excess_one()`:
      x "Value (HML)" is total-basis but no rf series was supplied to strat_corr_augment.
      i Add it to `.strat_rf_sources()` (R/plan_strategy_correlation.R).

