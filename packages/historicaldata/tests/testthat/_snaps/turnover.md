# bad side aborts

    Code
      hd_turnover(c(A = 1), side = "both")
    Condition
      Error in `hd_turnover()`:
      ! `side` must be "one" or "two".
      x Got "both".

# non-numeric w aborts

    Code
      hd_turnover(c("a", "b"))
    Condition
      Error in `hd_turnover()`:
      ! `w` must be a numeric vector.
      x Got <character>.

# NA in w aborts

    Code
      hd_turnover(c(A = 0.5, B = NA_real_))
    Condition
      Error in `hd_turnover()`:
      ! `w` must not contain "NA", "NaN" or infinite values.
      x Found 1 at position 2.
      i Resolve missingness upstream; `hd_turnover()` does not `na.rm`.

# mixed named / unnamed aborts

    Code
      hd_turnover(c(A = 0.5, B = 0.5), c(0.5, 0.5))
    Condition
      Error in `hd_turnover()`:
      ! `w` and `w_prev` must both be named or both be unnamed.
      x `w` is named; `w_prev` is unnamed.

# unnamed vectors of different length abort

    Code
      hd_turnover(c(0.5, 0.5), c(1, 0, 0))
    Condition
      Error in `hd_turnover()`:
      ! Unnamed `w` and `w_prev` must have the same length.
      x Got 2 and 3.
      i Name the weights to align them over the union of names.

# duplicate names abort

    Code
      hd_turnover(c(A = 0.5, A = 0.5))
    Condition
      Error in `hd_turnover()`:
      ! Names of `w` must be unique and non-empty.
      i Either name every element or none.

# drift_ret without a previous book aborts

    Code
      hd_turnover(c(A = 1), NULL, drift_ret = c(A = 0.1))
    Condition
      Error in `hd_turnover()`:
      ! `drift_ret` needs a previous book to drift.
      x `w_prev` is `NULL` or empty, but `drift_ret` was supplied.
      i For the first period pass `drift_ret = NULL`.

# drift_ret missing a held name aborts

    Code
      hd_turnover(c(A = 1), c(A = 0.5, B = 0.5), drift_ret = c(A = 0.1))
    Condition
      Error in `hd_turnover()`:
      ! `drift_ret` must be named and cover every name in `w_prev`.
      x Missing: "B".

# drift_ret with NA aborts

    Code
      hd_turnover(c(A = 1), c(A = 1), drift_ret = c(A = NA_real_))
    Condition
      Error in `hd_turnover()`:
      ! `drift_ret` must be a numeric vector of finite returns.
      i Resolve missingness upstream; `hd_turnover()` does not `na.rm`.

# a previous book wiped out by its returns aborts

    Code
      hd_turnover(c(A = 1), c(A = 1), drift_ret = c(A = -1.5))
    Condition
      Error in `hd_turnover()`:
      ! The previous book's gross return leaves no positive value to drift.
      x `1 + sum(w_prev * drift_ret)` is -0.5.
      i Check `drift_ret` is a per-period return (0.02 = +2%), not a level or a percentage.

# series: missing columns abort

    Code
      hd_turnover_series(data.frame(date = d[1], name = "A"))
    Condition
      Error in `hd_turnover_series()`:
      ! `weights` is missing required column weight.
      i Required: date, name, and weight.

# series: duplicated (date, name) aborts

    Code
      hd_turnover_series(data.frame(date = d[c(1, 1)], name = c("A", "A"), weight = c(
        0.5, 0.5)))
    Condition
      Error in `hd_turnover_series()`:
      ! `weights` must have at most one row per date and name.
      x Found 1 duplicated pair.

# series: returns missing a held name aborts

    Code
      hd_turnover_series(w, returns = r)
    Condition
      Error in `hd_turnover_series()`:
      ! `returns` is missing 1 held name for period 2024-01-31.
      x Missing: "A".
      i Drift needs a return for every name with non-zero weight in the previous period.

# series: periods that omit a weights date abort

    Code
      hd_turnover_series(w, periods = d[1])
    Condition
      Error in `hd_turnover_series()`:
      ! `periods` must contain every date in `weights`.
      x 1 date in `weights` not in `periods`.

# series: bad `first` aborts

    Code
      hd_turnover_series(w, first = "zero")
    Condition
      Error in `hd_turnover_series()`:
      ! `first` must be "entry" or "na".
      x Got "zero".

# function signatures are stable (catches API drift)

    Code
      args(hd_turnover)
    Output
      function (w, w_prev = NULL, drift_ret = NULL, side = c("one", 
          "two")) 
      NULL

---

    Code
      args(hd_turnover_series)
    Output
      function (weights, returns = NULL, side = c("one", "two"), first = c("entry", 
          "na"), periods = NULL) 
      NULL

