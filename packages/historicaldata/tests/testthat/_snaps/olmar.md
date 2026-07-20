# simplex_project: output sums to 1

    Code
      args(olmar_simplex_project)
    Output
      function (v) 
      NULL

# simplex_project: errors on non-numeric input

    Code
      olmar_simplex_project("a")
    Condition
      Error in `olmar_simplex_project()`:
      x `v` must be a non-empty numeric vector.
      i Got class <character> of length 1.

# simplex_project: errors on empty vector

    Code
      olmar_simplex_project(numeric(0L))
    Condition
      Error in `olmar_simplex_project()`:
      x `v` must be a non-empty numeric vector.
      i Got class <numeric> of length 0.

# olmar_update: errors on length mismatch

    Code
      olmar_update(b, x)
    Condition
      Error in `olmar_update()`:
      x Length mismatch: `b_prev` has 2, `x_pred` has 3.

# olmar_update: errors on non-positive epsilon

    Code
      olmar_update(b, x, epsilon = 0)
    Condition
      Error in `olmar_update()`:
      x `epsilon` must be a positive scalar.
      i Got 0.

---

    Code
      olmar_update(b, x, epsilon = -1)
    Condition
      Error in `olmar_update()`:
      x `epsilon` must be a positive scalar.
      i Got -1.

# olmar_backtest: returns expected columns

    Code
      names(result)
    Output
      [1] "date"      "gross_ret" "net_ret"   "turnover" 

# olmar_backtest: errors on insufficient rows

    Code
      olmar_backtest(prices, window = 25L)
    Condition
      Error in `olmar_backtest()`:
      x `prices` has 4 rows but `window` = 25 requires at least 26.

