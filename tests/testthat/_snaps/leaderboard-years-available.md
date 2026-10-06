# check_leaderboard_years_available throws and names the offender when years is NA (#726/#927)

    Code
      check_leaderboard_years_available(years_na_leaderboard, obs_ann_factor_tbl)
    Condition
      Error in `check_leaderboard_years_available()`:
      x Leaderboard has 1 row(s) with sharpe > 0 but no usable years-available figure (#726, #927):
      i  Risk State / Full Period -- sharpe = 0.252, months = 8365, years = NA
      i check_leaderboard_years_available() (S43) requires every positive-Sharpe row to have a non-NA, strictly positive years -- fix the offending strategy's months/obs_ann_factor source (STRATEGY_OBS_ANN_FACTOR, R/plan_leaderboard.R) rather than adding a per-strategy years column.

# check_leaderboard_years_available throws when years is non-NA but not strictly positive

    Code
      check_leaderboard_years_available(years_zero_leaderboard, obs_ann_factor_tbl)
    Condition
      Error in `check_leaderboard_years_available()`:
      x Leaderboard has 1 row(s) with sharpe > 0 but no usable years-available figure (#726, #927):
      i  LTR / Full Period -- sharpe = 0.33, months = 254, years = 0
      i check_leaderboard_years_available() (S43) requires every positive-Sharpe row to have a non-NA, strictly positive years -- fix the offending strategy's months/obs_ann_factor source (STRATEGY_OBS_ANN_FACTOR, R/plan_leaderboard.R) rather than adding a per-strategy years column.

# check_leaderboard_years_available throws when years drifts from months / obs_ann_factor

    Code
      check_leaderboard_years_available(years_drift_leaderboard, obs_ann_factor_tbl)
    Condition
      Error in `check_leaderboard_years_available()`:
      x Leaderboard has 1 row(s) where years disagrees with months / obs_ann_factor -- the SAME sample length hd_detection_power() uses (#726, #927):
      i  Value (HML) / Full Period -- years = 99.9, months / obs_ann_factor = 62.5
      i check_leaderboard_years_available() (S43) requires years to be derived from months / obs_ann_factor in ONE place (R/plan_leaderboard.R, immediately after the STRATEGY_OBS_ANN_FACTOR join) -- a second, independently-computed years column (e.g. reintroduced by a `.norm_*()` helper) can silently drift from the Detection column's own sample-length figure.

# check_leaderboard_years_available throws when leaderboard is missing required columns

    Code
      check_leaderboard_years_available(bad, obs_ann_factor_tbl)
    Condition
      Error in `check_leaderboard_years_available()`:
      x Leaderboard is missing 1 required column(s): years.
      i check_leaderboard_years_available() (S43) requires strategy, period, sharpe, months, years.

# check_leaderboard_years_available throws when obs_ann_factor_tbl is missing required columns

    Code
      check_leaderboard_years_available(good_leaderboard, bad_tbl)
    Condition
      Error in `check_leaderboard_years_available()`:
      x obs_ann_factor_tbl is missing required column(s): strategy, obs_ann_factor.
      i check_leaderboard_years_available() (S43) requires STRATEGY_OBS_ANN_FACTOR's strategy/obs_ann_factor columns.

