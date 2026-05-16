# input validation: non-matrix input aborts with informative message

    Code
      hd_strat_keff_vertox(c(1, 0.5, 0.5, 1))
    Condition
      Error in `hd_strat_keff_vertox()`:
      ! `sigma` must be a matrix; got <numeric>.

# input validation: non-square matrix aborts

    Code
      hd_strat_keff_vertox(matrix(1:6, 2, 3))
    Condition
      Error in `hd_strat_keff_vertox()`:
      ! `sigma` must be square; got 2 x 3.

# input validation: empty matrix aborts

    Code
      hd_strat_keff_vertox(matrix(numeric(0), 0, 0))
    Condition
      Error in `hd_strat_keff_vertox()`:
      ! `sigma` must have at least one row/column.

# input validation: non-symmetric matrix aborts

    Code
      hd_strat_keff_vertox(bad)
    Condition
      Error in `hd_strat_keff_vertox()`:
      ! `sigma` must be symmetric.

# function signature is stable (catches API drift)

    Code
      args(hd_strat_keff_vertox)
    Output
      function (sigma, n_sim = 20000L, seed = NULL, tol = 0.001) 
      NULL

