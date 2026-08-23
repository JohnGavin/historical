# check_leaderboard_deflated_sharpe_coverage throws and names the offending strategy when no exemption exists

    Code
      check_leaderboard_deflated_sharpe_coverage(offender_leaderboard,
        test_exemptions)
    Condition
      Error in `check_leaderboard_deflated_sharpe_coverage()`:
      x Leaderboard has 1 Full Period row(s) with sharpe > 0 but no deflated_sharpe/dsr_pvalue/k_eff_leaderboard verdict AND no declared exemption (#728 item 4):
      i  New Strategy / Full Period -- sharpe = 0.33 (no declared exemption in DEFLATED_SHARPE_EXEMPTIONS)
      i check_leaderboard_deflated_sharpe_coverage() (S21) requires every positive-Sharpe Full Period row to have a non-NA deflated_sharpe/dsr_pvalue/k_eff_leaderboard verdict, or a written reason in DEFLATED_SHARPE_EXEMPTIONS (R/plan_qa_gates.R) -- fix the offending strategy's coverage in STRAT_RETURNS_WIDE_CODES (R/plan_strategy_correlation.R) or add a documented exemption. Per fail-loud-not-null.md, the absence of a reason is what fails, not the NA itself.

# check_leaderboard_deflated_sharpe_coverage throws when leaderboard is missing required columns

    Code
      check_leaderboard_deflated_sharpe_coverage(bad, test_exemptions)
    Condition
      Error in `check_leaderboard_deflated_sharpe_coverage()`:
      x Leaderboard is missing 1 required column(s): deflated_sharpe.
      i check_leaderboard_deflated_sharpe_coverage() (S21) requires strategy, period, sharpe, deflated_sharpe, dsr_pvalue, k_eff_leaderboard.

