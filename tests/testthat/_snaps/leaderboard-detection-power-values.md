# check_leaderboard_detection_power_values throws and names path (b) when months is NA/<2

    Code
      check_leaderboard_detection_power_values(months_na_leaderboard)
    Condition
      Error in `check_leaderboard_detection_power_values()`:
      x Leaderboard has 1 row(s) with sharpe > 0 but no detection-power verdict (#726):
      i  Risk State / Full Period -- sharpe = 0.252, months = NA -- months is NA or < 2 (path b: unusable sample length)
      i check_leaderboard_detection_power_values() (S20) requires every positive-Sharpe row to have a non-NA detection_min_n_years/detection_underpowered -- fix the offending strategy's source metrics target (path b: publish a real months/n_days/n_obs column) or investigate the hd_detection_power() error (path c).

# check_leaderboard_detection_power_values throws and names path (c) when months is usable but the verdict is still NA

    Code
      check_leaderboard_detection_power_values(power_fail_leaderboard)
    Condition
      Error in `check_leaderboard_detection_power_values()`:
      x Leaderboard has 1 row(s) with sharpe > 0 but no detection-power verdict (#726):
      i  LTR / Full Period -- sharpe = 0.33, months = 254 -- hd_detection_power() produced no value despite a usable months (path c: the tryCatch in R/plan_leaderboard.R's .detection_diag_row() caught an error)
      i check_leaderboard_detection_power_values() (S20) requires every positive-Sharpe row to have a non-NA detection_min_n_years/detection_underpowered -- fix the offending strategy's source metrics target (path b: publish a real months/n_days/n_obs column) or investigate the hd_detection_power() error (path c).

# check_leaderboard_detection_power_values throws when k_eff_leaderboard is usable but the mt verdict is NA

    Code
      check_leaderboard_detection_power_values(mt_missing_leaderboard)
    Condition
      Error in `check_leaderboard_detection_power_values()`:
      x Leaderboard has 1 row(s) with sharpe > 0 and a usable k_eff_leaderboard but no multiple-testing-corrected detection-power verdict (#726 item 4):
      i  Factor DRIF / Full Period -- sharpe = 0.076, k_eff_leaderboard = 4.847
      i check_leaderboard_detection_power_values() (S20) requires detection_min_n_years_mt/detection_underpowered_mt to be non-NA whenever k_eff_leaderboard is non-NA and >= 1 -- see the alpha = 0.05 / keff tryCatch in R/plan_leaderboard.R's .detection_diag_row().

# check_leaderboard_detection_power_values throws when leaderboard is missing required columns

    Code
      check_leaderboard_detection_power_values(bad)
    Condition
      Error in `check_leaderboard_detection_power_values()`:
      x Leaderboard is missing 1 required column(s): months.
      i check_leaderboard_detection_power_values() (S20) requires strategy, period, sharpe, months, detection_min_n_years, detection_underpowered, detection_min_n_years_mt, detection_underpowered_mt, k_eff_leaderboard.

