# check_leaderboard_period_vocab throws when a strategy is missing its Full Period row

    Code
      check_leaderboard_period_vocab(missing_full_period_leaderboard)
    Condition
      Error in `check_leaderboard_period_vocab()`:
      x Leaderboard has 1 strategy/strategies missing a canonical "Full Period" row:
      i  Value (HML)
      i Every consumer of the leaderboard (docs/leaderboard.qmd headline table, correlation/redundancy join in R/plan_leaderboard.R) filters on period == "Full Period" -- a strategy using a different label (e.g. "Full") for its full-sample row is silently dropped (#643).
      i Normalise the label in the strategy's .norm_* helper in R/plan_leaderboard.R.

# check_leaderboard_period_vocab throws when a period value is outside the canonical vocabulary

    Code
      check_leaderboard_period_vocab(bad_vocab_leaderboard)
    Condition
      Error in `check_leaderboard_period_vocab()`:
      x Leaderboard period column has 1 value(s) outside the canonical vocabulary:
      i  Full-Sample -- used by: Managed Futures
      i Allowed values (R/plan_partitions.R PERIOD_LABELS_ALLOWED): Training, Testing, Validation, Full Period, OOS.
      i Normalise the label in the strategy's .norm_* helper in R/plan_leaderboard.R (#643).

# check_leaderboard_period_vocab throws when required columns are missing

    Code
      check_leaderboard_period_vocab(bad)
    Condition
      Error in `check_leaderboard_period_vocab()`:
      x Leaderboard is missing 1 required column(s): period.
      i check_leaderboard_period_vocab() (S10) requires strategy, period.

