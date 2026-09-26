# check_leaderboard_detection_power_correction throws and names the offending strategy when no exemption exists

    Code
      check_leaderboard_detection_power_correction(coverage_offender_leaderboard,
        test_exemptions)
    Condition
      Error in `check_leaderboard_detection_power_correction()`:
      x Leaderboard has 1 row(s) with sharpe > 0 and a usable k_eff_leaderboard but no multiple-testing-corrected detection-power verdict AND no declared exemption (#903):
      i  New Strategy / Full Period -- sharpe = 0.33, k_eff_leaderboard = 4.847 (no declared exemption)
      i check_leaderboard_detection_power_correction() (S37) requires detection_min_n_years_mt/detection_underpowered_mt to be non-NA whenever k_eff_leaderboard is usable, or a written reason in DEFLATED_SHARPE_EXEMPTIONS (R/plan_qa_gates.R).

# check_leaderboard_detection_power_correction throws and names the offending strategy when corrected < uncorrected

    Code
      check_leaderboard_detection_power_correction(monotonicity_offender_leaderboard,
        test_exemptions)
    Condition
      Error in `check_leaderboard_detection_power_correction()`:
      x Leaderboard has 1 row(s) where the multiple-testing-corrected detection-power requirement is LESS demanding than the uncorrected one (#903):
      i  Inverted Strategy / Full Period -- detection_min_n_years = 100, detection_min_n_years_mt = 80 (corrected < uncorrected)
      i check_leaderboard_detection_power_correction() (S37) requires detection_min_n_years_mt >= detection_min_n_years for every row -- a Bonferroni correction tightens alpha and can only WEAKLY INCREASE the sample required. Check for an inverted alpha/alpha_corrected, or a k_eff_leaderboard < 1 reaching the correction in R/plan_leaderboard.R's .detection_diag_row().

# check_leaderboard_detection_power_correction throws when leaderboard is missing required columns

    Code
      check_leaderboard_detection_power_correction(bad, test_exemptions)
    Condition
      Error in `check_leaderboard_detection_power_correction()`:
      x Leaderboard is missing 1 required column(s): detection_min_n_years_mt.
      i check_leaderboard_detection_power_correction() (S37) requires strategy, period, sharpe, detection_min_n_years, detection_min_n_years_mt, detection_underpowered_mt, k_eff_leaderboard.

