# non-square sigma aborts with informative error

    Code
      hd_black_litterman(matrix(1:6, nrow = 2L, ncol = 3L), w_mkt)
    Condition
      Error in `hd_black_litterman()`:
      ! `sigma` must be a square matrix.
      x Got a 2 × 3 matrix.

# w_mkt length != ncol(sigma) aborts with informative error

    Code
      hd_black_litterman(sigma, w_mkt = c(A1 = 0.5, A2 = 0.5), risk_aversion = 2.5)
    Condition
      Error in `hd_black_litterman()`:
      ! `w_mkt` must be a numeric vector of length 5 (matching `sigma`).
      x Got length 2.

# P with wrong number of columns aborts with informative error

    Code
      hd_black_litterman(sigma, w_mkt, P = P_bad, Q = 0.03, risk_aversion = 2.5)
    Condition
      Error in `hd_black_litterman()`:
      ! `P` must have 5 columns (one per asset), matching `sigma`.
      x Got 3 columns.

# Q length != nrow(P) aborts with informative error

    Code
      hd_black_litterman(sigma, w_mkt, P = P, Q = c(0.03, 0.05), risk_aversion = 2.5)
    Condition
      Error in `hd_black_litterman()`:
      ! `Q` must have length 1 (one return per view row of `P`).
      x Got length 2.

# tau <= 0 aborts with informative error

    Code
      hd_black_litterman(sigma, w_mkt, tau = -0.01, risk_aversion = 2.5)
    Condition
      Error in `hd_black_litterman()`:
      ! `tau` must be a single positive scalar; got -0.01.

# risk_aversion <= 0 aborts with informative error

    Code
      hd_black_litterman(sigma, w_mkt, risk_aversion = 0)
    Condition
      Error in `hd_black_litterman()`:
      ! `risk_aversion` must be a positive scalar; got 0.

# omega with wrong dimensions aborts with informative error

    Code
      hd_black_litterman(sigma, w_mkt, P = P, Q = Q, omega = omega_bad,
        risk_aversion = 2.5)
    Condition
      Error in `hd_black_litterman()`:
      ! `omega` must be a 1 × 1 matrix (one row/col per view).
      x Got a 2 × 2 matrix.

# function signature is stable (catches API drift)

    Code
      args(hd_black_litterman)
    Output
      function (sigma, w_mkt, P = NULL, Q = NULL, tau = 0.05, omega = NULL, 
          risk_aversion = NULL) 
      NULL

