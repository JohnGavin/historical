# non-matrix/non-data-frame returns triggers cli_abort

    Code
      hd_weight_stability_diagnostic("not_a_matrix")
    Condition
      Error in `hd_weight_stability_diagnostic()`:
      ! `returns` must be a numeric matrix or data frame.
      x Got <character>.

# non-numeric returns (after date drop) triggers cli_abort

    Code
      hd_weight_stability_diagnostic(bad)
    Condition
      Error in `hd_weight_stability_diagnostic()`:
      ! `returns` must be numeric after removing any date column.
      x Got <character>.

# too few rows triggers cli_abort

    Code
      hd_weight_stability_diagnostic(X, train_window = 10L)
    Condition
      Error in `hd_weight_stability_diagnostic()`:
      ! `returns` does not have enough rows for walk-forward evaluation.
      x Need more than 11 rows; got 11.
      i Require nrow(returns) > train_window + 1 (training window + at least 1 OOS period).

# invalid method name triggers cli_abort

    Code
      hd_weight_stability_diagnostic(X, methods = c("gmv", "not_a_method"))
    Condition
      Error in `hd_weight_stability_diagnostic()`:
      ! Unknown weight method: "not_a_method".
      i Valid methods: "raw_mvo", "gmv", "shrunk_mu", "black_litterman", "equal_weight", and "hrp".

# empty methods vector triggers cli_abort

    Code
      hd_weight_stability_diagnostic(X, methods = character(0))
    Condition
      Error in `hd_weight_stability_diagnostic()`:
      ! `methods` must be a non-empty character vector.

# function signature is stable (catches API drift)

    Code
      args(hd_weight_stability_diagnostic)
    Output
      function (returns, methods = c("raw_mvo", "gmv", "shrunk_mu", 
          "black_litterman", "equal_weight", "hrp"), train_window = 60L, 
          cov_method = "ledoit_wolf", ...) 
      NULL

