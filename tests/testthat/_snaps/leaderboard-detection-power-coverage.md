# check_leaderboard_detection_power_coverage throws when a strategy has no declared periodicity

    Code
      check_leaderboard_detection_power_coverage(missing_strategy_leaderboard,
        STRATEGY_OBS_ANN_FACTOR)
    Condition
      Error in `check_leaderboard_detection_power_coverage()`:
      x 1 leaderboard strategy/strategies have no declared observation periodicity for the detection-power diagnostic (#711):
      i  New Strategy
      i Add a row to STRATEGY_OBS_ANN_FACTOR (R/plan_leaderboard.R) with the strategy's true periods-per-year (12 = monthly, 252 = daily) and a source citation, verified against its calc_metrics()/compute_*() annualisation.

# check_leaderboard_detection_power_coverage throws when leaderboard is missing strategy column

    Code
      check_leaderboard_detection_power_coverage(bad, STRATEGY_OBS_ANN_FACTOR)
    Condition
      Error in `check_leaderboard_detection_power_coverage()`:
      x Leaderboard is missing required column: strategy.
      i check_leaderboard_detection_power_coverage() (S19) requires a strategy column.

