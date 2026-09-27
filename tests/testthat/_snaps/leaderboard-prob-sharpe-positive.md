# check_leaderboard_prob_sharpe_positive throws and names the offending strategy when single-test coverage is missing and no exemption exists

    Code
      check_leaderboard_prob_sharpe_positive(single_coverage_offender_leaderboard,
        test_exemptions)
    Condition
      Error in `check_leaderboard_prob_sharpe_positive()`:
      x Leaderboard has 1 row(s) with sharpe > 0 but no prob_sharpe_positive verdict AND no declared exemption (#851):
      i  Uncovered Strategy / Full Period -- sharpe = 0.4 (no declared exemption)
      i check_leaderboard_prob_sharpe_positive() (S40) requires prob_sharpe_positive to be non-NA for every positive-Sharpe row, or a written reason in DEFLATED_SHARPE_EXEMPTIONS (R/plan_qa_gates.R).

# check_leaderboard_prob_sharpe_positive throws and names the offending strategy when mt coverage is missing and no exemption exists

    Code
      check_leaderboard_prob_sharpe_positive(mt_coverage_offender_leaderboard,
        test_exemptions)
    Condition
      Error in `check_leaderboard_prob_sharpe_positive()`:
      x Leaderboard has 1 row(s) with sharpe > 0 and a usable k_eff_leaderboard but no multiple-testing-corrected prob_sharpe_positive_mt verdict AND no declared exemption (#851):
      i  New Strategy / Full Period -- sharpe = 0.33, k_eff_leaderboard = 4.847 (no declared exemption)
      i check_leaderboard_prob_sharpe_positive() (S40) requires prob_sharpe_positive_mt to be non-NA whenever k_eff_leaderboard is usable, or a written reason in DEFLATED_SHARPE_EXEMPTIONS (R/plan_qa_gates.R).

# check_leaderboard_prob_sharpe_positive throws and names the offending strategy when corrected > uncorrected

    Code
      check_leaderboard_prob_sharpe_positive(monotonicity_offender_leaderboard,
        test_exemptions)
    Condition
      Error in `check_leaderboard_prob_sharpe_positive()`:
      x Leaderboard has 1 row(s) where the multiple-testing-corrected P(true Sharpe > 0) is GREATER than the uncorrected one (#851):
      i  Inverted Strategy / Full Period -- prob_sharpe_positive = 0.6, prob_sharpe_positive_mt = 0.75 (corrected > uncorrected)
      i check_leaderboard_prob_sharpe_positive() (S40) requires prob_sharpe_positive_mt <= prob_sharpe_positive for every row -- a Bonferroni p-value correction can only WEAKLY INCREASE the p-value, which can only WEAKLY DECREASE the reported probability. Check for an inverted n_tests/correction, or a k_eff_leaderboard < 1 reaching the correction in R/plan_leaderboard.R's .prob_sharpe_positive_row().

# check_leaderboard_prob_sharpe_positive throws when leaderboard is missing required columns

    Code
      check_leaderboard_prob_sharpe_positive(bad, test_exemptions)
    Condition
      Error in `check_leaderboard_prob_sharpe_positive()`:
      x Leaderboard is missing 1 required column(s): prob_sharpe_positive_mt.
      i check_leaderboard_prob_sharpe_positive() (S40) requires strategy, period, sharpe, prob_sharpe_positive, prob_sharpe_positive_mt, k_eff_leaderboard.

