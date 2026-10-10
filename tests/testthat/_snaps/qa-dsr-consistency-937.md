# S43 RED: the pre-fix Factor MAX shape (193 vs 740) is a FAIL naming the strategy and both counts

    Code
      check_dsr_coverage(tbl, allowlist = .allow)
    Condition
      Error in `check_dsr_coverage()`:
      x qa_dsr_window_coverage (S43) FAILED: 1 fail, 0 indeterminate, 2 pass of 3 row(s).
      i  Factor MAX -- FAIL: DSR path scored 193 observations, leaderboard row 740 (offset -547)
      i strat_deflated_sharpe must score each strategy over the SAME observations as its leaderboard Full-Period row (Refs #937, #919).

# S43: a strategy in only one table, or an NA count, is INDETERMINATE (distinct class), never PASS or FAIL

    Code
      check_dsr_coverage(tbl, allowlist = .allow)
    Condition
      Error in `check_dsr_coverage()`:
      x qa_dsr_window_coverage (S43) is INDETERMINATE: 0 fail, 1 indeterminate, 2 pass of 3 row(s).
      i  Stock MAX -- INDETERMINATE: missing_in_dsr: no strat_deflated_sharpe row for this strategy
      i A row or count could not be compared; this is NOT a pass (checks-must-distinguish-unknown).

# S43: every allow-list entry must carry a written reason (no blank exemptions)

    Code
      build_dsr_coverage_table(.lb(), .dsr(), allowlist = bad, excluded = "PSO Optimal")
    Condition
      Error in `.s43_check_allowlist()`:
      x S43 allow-list entry without a written reason: "Mom Pre-Peak".
      i An exemption without a reason is indistinguishable from an oversight (Refs #937).

# S43 NON-VACUOUS: a gate that examined zero rows is INDETERMINATE, not a pass

    Code
      check_dsr_coverage(build_dsr_coverage_table(empty_lb, .dsr()[0, ], allowlist = .allow,
      excluded = "PSO Optimal"), allowlist = .allow)
    Condition
      Error in `check_dsr_coverage()`:
      x qa_dsr_window_coverage (S43) is INDETERMINATE: 0 fail, 0 indeterminate, 0 pass of 0 row(s).
      i Zero rows were examined -- a gate that checked nothing cannot report a pass.

# S44 RED: a #919-style violation (DSR more confident than the plain PSR) FAILs and names the numbers

    Code
      check_psr_vs_dsr(tbl)
    Condition
      Error in `check_psr_vs_dsr()`:
      x qa_psr_vs_dsr (S44) FAILED: 1 pass, 1 fail, 0 NOT_COMPUTED, 1 not applicable, 0 indeterminate; 2 row(s) examined.
      i  Factor MAX -- FAIL: 1 - dsr_pvalue = 0.9500 exceeds prob_sharpe_positive = 0.2000
      i The DSR can never be more confident than the plain probabilistic Sharpe on the same Sharpe and n (Refs #919, #937).

# S44: missing dsr_pvalue (outside the documented exclusion) is INDETERMINATE with its own class

    Code
      check_psr_vs_dsr(tbl)
    Condition
      Error in `check_psr_vs_dsr()`:
      x qa_psr_vs_dsr (S44) is INDETERMINATE: 1 pass, 0 fail, 0 NOT_COMPUTED, 1 not applicable, 1 indeterminate; 1 row(s) examined.
      i  Factor MAX -- INDETERMINATE: dsr_pvalue_missing: no DSR p-value to compare against
      i A row could not be compared; this is NOT a pass (checks-must-distinguish-unknown).

# S44 NON-VACUOUS: zero Full-Period rows examined is INDETERMINATE

    Code
      check_psr_vs_dsr(build_psr_vs_dsr_table(lb, excluded = "PSO Optimal"))
    Condition
      Error in `check_psr_vs_dsr()`:
      x qa_psr_vs_dsr (S44) is INDETERMINATE: 0 pass, 0 fail, 0 NOT_COMPUTED, 0 not applicable, 0 indeterminate; 0 row(s) examined.
      i Zero Full-Period rows were examined -- a gate that checked nothing cannot report a pass.

