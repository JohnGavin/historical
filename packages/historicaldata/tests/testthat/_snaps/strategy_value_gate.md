# non-numeric candidate triggers cli_abort

    Code
      hd_strategy_value_gate("not_a_vector", existing)
    Condition
      Error in `hd_strategy_value_gate()`:
      x `candidate` must be a numeric vector.
      i Got <character>.

# non-numeric existing triggers cli_abort

    Code
      hd_strategy_value_gate(candidate, "not_a_matrix")
    Condition
      Error in `hd_strategy_value_gate()`:
      x `existing` must be a numeric matrix or data frame of numeric columns.
      i Got <character>.

# candidate all-NA yields cli_abort for no overlapping rows

    Code
      .gate(candidate, existing)
    Condition
      Error in `hd_strategy_value_gate()`:
      x Fewer than 2 complete overlapping rows between `candidate`
        and `existing` after dropping NAs.
      i Got 0 complete row(s).

# hd_strategy_value_gate() signature is stable (catches API drift)

    Code
      args(hd_strategy_value_gate)
    Output
      function (candidate, existing, candidate_name = "candidate", 
          corr_threshold = HD_REDUNDANCY_THRESH, min_incr_sharpe = 0, 
          periods_per_year = 12L, n_tests = 1, correction = c("none", 
              "bonferroni"), target_power = 0.8, crowding = NA, robustness_pass = NA, 
          candidate_basis = NULL, existing_basis = NULL) 
      NULL

# candidate and existing on DIFFERENT bases abort with class hd_error_mixed_basis

    Code
      hd_strategy_value_gate(candidate, existing, candidate_basis = "Value (HML)",
        existing_basis = c("Mom 12-2", "LTR"))
    Condition
      Error in `hd_strategy_value_gate()`:
      x Candidate and existing series are on different return bases.
      i Candidate "Value (HML)": "total".
      i Existing "Mom 12-2" and "LTR": "excess" and "excess".
      i CAGR/vol with no rf is only comparable within one basis; convert with `hd_excess_returns()` first.

# an UNLABELLED candidate or existing set aborts with class hd_error_mixed_basis

    Code
      hd_strategy_value_gate(candidate, existing)
    Condition
      Error in `hd_strategy_value_gate()`:
      x `candidate_basis` must be one registered `hd_return_basis()` label.
      i Got <NULL> of length 0.
      i The gate compares CAGR/vol with no rf, so it must know the candidate's return basis; it never guesses one.

# existing_basis of the wrong length, or an unclassified basis, also aborts

    Code
      hd_strategy_value_gate(candidate, existing, candidate_basis = "Mom 12-2",
        existing_basis = rep("Mom 12-2", 3L))
    Condition
      Error in `hd_strategy_value_gate()`:
      x `existing_basis` must be one registered `hd_return_basis()` label per existing column (or a single label for all).
      i Got <character> of length 3 for 2 existing columns.
      i The gate compares CAGR/vol with no rf, so it must know every column's return basis; it never guesses one.

