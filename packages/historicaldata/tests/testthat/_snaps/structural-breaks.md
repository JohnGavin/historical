# NA in returns aborts with informative error

    Code
      hd_structural_breaks(c(0.1, NA, 0.2))
    Condition
      Error in `hd_structural_breaks()`:
      x `returns` must not contain `NA` values.
      i Filter NAs before calling: `returns[!is.na(returns)]`.
      i See the NA-propagation discipline in the package conventions.

# alpha out of range aborts with informative error

    Code
      hd_structural_breaks(rnorm(100), alpha = 1.5)
    Condition
      Error in `hd_structural_breaks()`:
      x `alpha` must be a single numeric value in (0, 1).
      i Got 1.5.

# function signature is stable (catches API drift)

    Code
      args(hd_structural_breaks)
    Output
      function (returns, alpha = 0.01, min_years = 5, periods_per_year = 252L) 
      NULL

