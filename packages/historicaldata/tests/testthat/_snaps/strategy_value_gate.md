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
      hd_strategy_value_gate(candidate, existing)
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
              "bonferroni"), target_power = 0.8, crowding = NA, robustness_pass = NA) 
      NULL

