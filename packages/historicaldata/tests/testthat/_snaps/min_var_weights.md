# singular Sigma aborts with informative error suggesting hd_cov_estimate

    Code
      hd_min_var_weights(S_sing)
    Condition
      Error in `value[[3L]]()`:
      ! Cannot compute minimum-variance weights: the covariance matrix is
      singular or numerically ill-conditioned.
      x solve() error: system is computationally singular: reciprocal condition number = 1.38296e-18
      i In the wide regime (p ≥ n), the sample covariance matrix is rank-deficient. Use a regularised estimator via `hd_cov_estimate()` with `method = "ledoit_wolf"` or `method = "rmt_denoise"`.

# non-matrix input aborts with informative error

    Code
      hd_min_var_weights("not_a_matrix")
    Condition
      Error in `hd_min_var_weights()`:
      ! `Sigma` must be a numeric matrix.
      x Got <character>.

# 1x1 matrix aborts with informative error

    Code
      hd_min_var_weights(matrix(1, 1, 1))
    Condition
      Error in `hd_min_var_weights()`:
      ! `Sigma` must have at least 2 rows/columns.
      x Got 1.

# function signature is stable (catches API drift)

    Code
      args(hd_min_var_weights)
    Output
      function (Sigma, normalize = TRUE) 
      NULL

