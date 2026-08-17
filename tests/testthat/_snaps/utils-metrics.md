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

# sharpe_ratio_rf: NULL rf aborts loud rather than defaulting to zero (#677 defect B)

    Code
      sharpe_ratio_rf(c(0.01, 0.02, 0.03), NULL)
    Condition
      Error in `sharpe_ratio_rf()`:
      x `rf` must not be NULL.
      i A missing risk-free series must never be treated as zero -- see fail-loud-not-null.md (#677 defect B).
      i Join a risk-free series (e.g. the `stk_rf` target: ym, rf_ret) onto your data before calling `sharpe_ratio_rf()`.

# sharpe_ratio_rf: non-numeric rf aborts

    Code
      sharpe_ratio_rf(c(0.01, 0.02, 0.03), c("a", "b", "c"))
    Condition
      Error in `sharpe_ratio_rf()`:
      x `rf` must be a numeric vector.
      i Got <character>.

# sharpe_ratio_rf: non-numeric ret aborts

    Code
      sharpe_ratio_rf(c("a", "b"), c(0.001, 0.001))
    Condition
      Error in `sharpe_ratio_rf()`:
      x `ret` must be a numeric vector.
      i Got <character>.

# sharpe_ratio_rf: length mismatch between ret and rf aborts

    Code
      sharpe_ratio_rf(c(0.01, 0.02, 0.03), c(0.001, 0.001))
    Condition
      Error in `sharpe_ratio_rf()`:
      x `ret` and `rf` must be the same length.
      i Got length 3 and 2.

# sharpe_ratio_rf: invalid periods_per_year aborts

    Code
      sharpe_ratio_rf(c(0.01, 0.02), c(0.001, 0.001), periods_per_year = 0)
    Condition
      Error in `sharpe_ratio_rf()`:
      x `periods_per_year` must be a single positive number.
      i Got 0.

# sharpe_ratio_rf: non-finite ret aborts on non-finite volatility

    Code
      sharpe_ratio_rf(c(0.01, Inf, 0.02), c(0.001, 0.001, 0.001))
    Condition
      Error in `sharpe_ratio_rf()`:
      x Computed annualised volatility is not finite.
      i Got NaN.
      i Check `ret` for Inf/-Inf values before calling `sharpe_ratio_rf()`.

# sharpe_ratio_rf: function signature is stable (catches API drift)

    Code
      args(sharpe_ratio_rf)
    Output
      function (ret, rf, periods_per_year = 12L, na.rm = TRUE) 
      NULL

