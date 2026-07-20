# annualise_returns: non-numeric ret aborts with cli_abort

    Code
      annualise_returns(c("a", "b", "c"))
    Condition
      Error in `annualise_returns()`:
      x `ret` must be a numeric vector.
      i Got <character>.

# annualise_returns: invalid periods_per_year aborts

    Code
      annualise_returns(c(0.01, 0.02), periods_per_year = -1)
    Condition
      Error in `annualise_returns()`:
      x `periods_per_year` must be a single positive number.
      i Got -1.

# annualise_returns: function signature is stable (catches API drift)

    Code
      args(annualise_returns)
    Output
      function (ret, periods_per_year = 12L, na.rm = TRUE) 
      NULL

