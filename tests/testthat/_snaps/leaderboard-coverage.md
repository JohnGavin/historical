# check_leaderboard_coverage throws when a strategy is missing

    Code
      check_leaderboard_coverage(minimal_strategy_names, missing_strategy_leaderboard)
    Condition
      Error in `check_leaderboard_coverage()`:
      x Leaderboard missing 1/2 strategy/strategies:
      i  Factor DRIF (code_name: fac_drif)
      i Add the corresponding add_meta() calls in R/plan_leaderboard.R.

# check_leaderboard_coverage throws when ssr column absent

    Code
      check_leaderboard_coverage(minimal_strategy_names, no_ssr_leaderboard)
    Condition
      Error in `check_leaderboard_coverage()`:
      x Leaderboard is missing required column ssr.
      i Add the SSR computation block to R/plan_leaderboard.R (#400).

