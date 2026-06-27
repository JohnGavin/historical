# non-numeric input aborts with informative cli_abort

    Code
      hd_cov_estimate("not_a_matrix")
    Condition
      Error in `hd_cov_estimate()`:
      ! `returns` must be a numeric matrix or data frame; got <character>.

# single-column input (p<2) aborts with informative cli_abort

    Code
      hd_cov_estimate(matrix(1:10, ncol = 1L))
    Condition
      Error in `hd_cov_estimate()`:
      ! `returns` must have at least 2 columns (assets); got 1.

# all-NA frame aborts after dropping NA rows

    Code
      suppressWarnings(hd_cov_estimate(X_allna, method = "sample"))
    Condition
      Error in `hd_cov_estimate()`:
      ! No complete cases remain in `returns` after dropping NA rows.

# bad method value aborts with informative error

    Code
      hd_cov_estimate(X, method = "glasso")
    Condition
      Error in `match.arg()`:
      ! 'arg' should be one of "sample", "ledoit_wolf", "rmt_denoise", "threshold"

# function signature is stable (catches API drift)

    Code
      args(hd_cov_estimate)
    Output
      function (returns, method = c("sample", "ledoit_wolf", "rmt_denoise", 
          "threshold"), lw_target = c("const_cor", "identity"), threshold = 0.1, 
          threshold_type = c("soft", "hard"), assume_centered = FALSE) 
      NULL

