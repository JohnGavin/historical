# hd_levy_area rejects mismatched lengths

    Code
      hd_levy_area(1:5, 1:6)
    Condition
      Error in `hd_levy_area()`:
      x `x` and `y` must be the same length.
      i Got 5 and 6.

# hd_levy_area rejects a series too short to enclose area

    Code
      hd_levy_area(1, 2)
    Condition
      Error in `hd_levy_area()`:
      x Need at least 2 increments to enclose an area; got 1.
      i A single step traces a straight line, which encloses nothing.

# hd_path_signature2 rejects a path with fewer than two points

    Code
      hd_path_signature2(matrix(1:2, nrow = 1))
    Condition
      Error in `hd_path_signature2()`:
      x `X` has 1 row; a path needs at least 2 points.
      i Pass path levels (e.g. `cumsum(returns)`), one row per observation.

# hd_roll_levy_area rejects a window shorter than two steps

    Code
      hd_roll_levy_area(stats::rnorm(10), stats::rnorm(10), n = 1L)
    Condition
      Error in `hd_roll_levy_area()`:
      x `n` must be at least 2; got 1.
      i A window of one step traces a straight line and encloses no area.

# path-signature function signatures are stable

    Code
      args(hd_path_signature2)
    Output
      function (X) 
      NULL

---

    Code
      args(hd_levy_area)
    Output
      function (x, y, scale = TRUE) 
      NULL

---

    Code
      args(hd_roll_levy_area)
    Output
      function (x, y, n, scale = TRUE) 
      NULL

