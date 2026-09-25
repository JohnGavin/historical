# centre must appear exactly once in param_values

    Code
      hd_param_neighbourhood(c(20, 20, 21, 22, 23, 24), rep(1, 6), centre = 20)
    Condition
      Error in `hd_param_neighbourhood()`:
      x `centre` (20) must appear exactly once in `param_values`.
      i Found it 2 times.
      i hd_param_neighbourhood() (S39, #849) needs an unambiguous centre point.

---

    Code
      hd_param_neighbourhood(16:19, rep(1, 4), centre = 20)
    Condition
      Error in `hd_param_neighbourhood()`:
      x `centre` (20) must appear exactly once in `param_values`.
      i Found it 0 times.
      i hd_param_neighbourhood() (S39, #849) needs an unambiguous centre point.

# param_values and metric_values must be the same length

    Code
      hd_param_neighbourhood(16:24, rep(1, 5), centre = 20)
    Condition
      Error in `hd_param_neighbourhood()`:
      x `param_values` and `metric_values` must be the same length.
      i Got 9 and 5.

# min_retention must be in (0, 1]

    Code
      hd_param_neighbourhood(16:24, rep(1, 9), centre = 20, min_retention = 0)
    Condition
      Error in `hd_param_neighbourhood()`:
      x `min_retention` must be a single number in (0, 1].
      i Got 0.

---

    Code
      hd_param_neighbourhood(16:24, rep(1, 9), centre = 20, min_retention = 1.5)
    Condition
      Error in `hd_param_neighbourhood()`:
      x `min_retention` must be a single number in (0, 1].
      i Got 1.5.

# max_cv must be a positive scalar

    Code
      hd_param_neighbourhood(16:24, rep(1, 9), centre = 20, max_cv = 0)
    Condition
      Error in `hd_param_neighbourhood()`:
      x `max_cv` must be a single positive number.
      i Got 0.

---

    Code
      hd_param_neighbourhood(16:24, rep(1, 9), centre = 20, max_cv = -1)
    Condition
      Error in `hd_param_neighbourhood()`:
      x `max_cv` must be a single positive number.
      i Got -1.

# min_neighbours must be a positive integer scalar

    Code
      hd_param_neighbourhood(16:24, rep(1, 9), centre = 20, min_neighbours = 0)
    Condition
      Error in `hd_param_neighbourhood()`:
      x `min_neighbours` must be a single positive integer.
      i Got 0.

---

    Code
      hd_param_neighbourhood(16:24, rep(1, 9), centre = 20, min_neighbours = 2.5)
    Condition
      Error in `hd_param_neighbourhood()`:
      x `min_neighbours` must be a single positive integer.
      i Got 2.5.

# non-numeric param_values/metric_values abort

    Code
      hd_param_neighbourhood(letters[1:9], rep(1, 9), centre = "e")
    Condition
      Error in `hd_param_neighbourhood()`:
      x `param_values` must be a numeric vector of length >= 2.
      i Got <character> of length 9.

---

    Code
      hd_param_neighbourhood(16:24, letters[1:9], centre = 20)
    Condition
      Error in `hd_param_neighbourhood()`:
      x `metric_values` must be a numeric vector.
      i Got <character>.

# function signature is stable (catches API drift)

    Code
      args(hd_param_neighbourhood)
    Output
      function (param_values, metric_values, centre, min_retention = HD_PARAM_NEIGHBOURHOOD_MIN_RETENTION, 
          max_cv = HD_PARAM_NEIGHBOURHOOD_MAX_CV, min_neighbours = HD_PARAM_NEIGHBOURHOOD_MIN_N) 
      NULL

