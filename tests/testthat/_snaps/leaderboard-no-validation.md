# check_leaderboard_no_validation_rows throws when one strategy has a Validation row

    Code
      check_leaderboard_no_validation_rows(one_validation_row_leaderboard)
    Condition
      Error in `check_leaderboard_no_validation_rows()`:
      x Leaderboard has 1 strategy/strategies with an automatically-computed "Validation" row, #648:
      i  Stock DRIF
      i Validation metrics must NOT be computed automatically by tar_make() (.claude/rules/backtest-partitions.md). Drop the Validation row at the point it enters R/plan_leaderboard.R's `all_metrics`, or use scripts/evaluate_validation.R for a one-shot manual evaluation.

# check_leaderboard_no_validation_rows names every offending strategy

    Code
      check_leaderboard_no_validation_rows(multi_validation_leaderboard)
    Condition
      Error in `check_leaderboard_no_validation_rows()`:
      x Leaderboard has 3 strategy/strategies with an automatically-computed "Validation" row, #648:
      i  Factor MAX
      i  Stock DRIF
      i  XGB DRIF
      i Validation metrics must NOT be computed automatically by tar_make() (.claude/rules/backtest-partitions.md). Drop the Validation row at the point it enters R/plan_leaderboard.R's `all_metrics`, or use scripts/evaluate_validation.R for a one-shot manual evaluation.

# check_leaderboard_no_validation_rows throws when required columns are missing

    Code
      check_leaderboard_no_validation_rows(bad)
    Condition
      Error in `check_leaderboard_no_validation_rows()`:
      x Leaderboard is missing 1 required column(s): period.
      i check_leaderboard_no_validation_rows() (S14) requires strategy, period.

