# check_leaderboard_metric_ranges throws when required columns are missing

    Code
      check_leaderboard_metric_ranges(bad)
    Condition
      Error in `check_leaderboard_metric_ranges()`:
      x Leaderboard is missing 1 required column(s): max_dd.
      i check_leaderboard_metric_ranges() (S9) requires strategy, period, cagr, vol, max_dd.

# check_leaderboard_metric_ranges catches a percent-scale cagr (#637 regression)

    Code
      check_leaderboard_metric_ranges(bad)
    Condition
      Error in `check_leaderboard_metric_ranges()`:
      x Leaderboard metric(s) out of plausible fractional range in 1 place(s) (likely a percent-vs-fraction unit bug, #637):
      i  LTR / Full Period -- cagr = 7.7 (expected [-1, 3])
      i Check the source metrics target's convention and convert in its .norm_* helper in R/plan_leaderboard.R.

