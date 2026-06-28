# too-few-rows aborts with informative error

    Code
      hd_cov_oos_diagnostic(X, train_window = 60L)
    Condition
      Error in `hd_cov_oos_diagnostic()`:
      ! `returns` does not have enough rows for walk-forward evaluation.
      x Need more than 61 rows; got 61.
      i Require nrow(returns) > train_window + 1 (training window + at least 1 OOS period).

# p < 2 aborts with informative error

    Code
      hd_cov_oos_diagnostic(X, train_window = 60L)
    Condition
      Error in `hd_cov_oos_diagnostic()`:
      ! `returns` must have at least 2 asset columns.
      x Got 1 column.

# non-numeric input aborts with informative error

    Code
      hd_cov_oos_diagnostic("not_a_matrix", train_window = 60L)
    Condition
      Error in `hd_cov_oos_diagnostic()`:
      ! `returns` must be a numeric matrix or data frame.
      x Got <character>.

# function signature is stable (catches API drift)

    Code
      args(hd_cov_oos_diagnostic)
    Output
      function (returns, methods = c("sample", "ledoit_wolf", "rmt_denoise"), 
          train_window = 60L, lw_target = "const_cor") 
      NULL

