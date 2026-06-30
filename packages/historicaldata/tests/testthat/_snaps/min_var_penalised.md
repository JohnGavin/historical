# non-square Sigma aborts with informative error

    Code
      hd_min_var_weights_penalised(matrix(1:6, 2, 3))
    Condition
      Error in `hd_min_var_weights_penalised()`:
      ! `Sigma` must be square.
      x Got 2 rows and 3 columns.

# negative lambda_ridge aborts with informative error

    Code
      hd_min_var_weights_penalised(S, lambda_ridge = -0.1)
    Condition
      Error in `hd_min_var_weights_penalised()`:
      ! `lambda_ridge` must be a single non-negative numeric scalar.
      x Got -0.1.

# negative lambda_turnover aborts with informative error

    Code
      hd_min_var_weights_penalised(S, lambda_turnover = -1)
    Condition
      Error in `hd_min_var_weights_penalised()`:
      ! `lambda_turnover` must be a single non-negative numeric scalar.
      x Got -1.

# lambda_turnover > 0 without w_prev aborts with informative error

    Code
      hd_min_var_weights_penalised(S, lambda_turnover = 0.5)
    Condition
      Error in `hd_min_var_weights_penalised()`:
      ! `w_prev` must be supplied when `lambda_turnover` > 0.
      i Provide the prior portfolio weights as a numeric vector of length 3.

# w_prev of wrong length aborts with informative error

    Code
      hd_min_var_weights_penalised(S, w_prev = c(0.5, 0.5), lambda_turnover = 0.1)
    Condition
      Error in `hd_min_var_weights_penalised()`:
      ! `w_prev` must be a numeric vector of length 3 (matching `Sigma` dimension).
      x Got <numeric> of length 2.

# function signature is stable (catches API drift)

    Code
      args(hd_min_var_weights_penalised)
    Output
      function (Sigma, lambda_ridge = 0, w_prev = NULL, lambda_turnover = 0, 
          normalize = TRUE) 
      NULL

