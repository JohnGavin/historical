# actual_metric must be a numeric scalar

    Code
      hd_signal_null_rank(c(1, 2), c(0.1, 0.2))
    Condition
      Error in `hd_signal_null_rank()`:
      x `actual_metric` must be a numeric scalar.
      i Got <numeric> of length 2.

---

    Code
      hd_signal_null_rank("not numeric", c(0.1, 0.2))
    Condition
      Error in `hd_signal_null_rank()`:
      x `actual_metric` must be a numeric scalar.
      i Got <character> of length 1.

# null_metrics must be numeric

    Code
      hd_signal_null_rank(1, c("a", "b"))
    Condition
      Error in `hd_signal_null_rank()`:
      x `null_metrics` must be a numeric vector.
      i Got <character>.

# dominance_threshold must be a single numeric in [0, 1]

    Code
      hd_signal_null_rank(1, c(0.1, 0.2), dominance_threshold = 1.5)
    Condition
      Error in `hd_signal_null_rank()`:
      x `dominance_threshold` must be a single numeric in [0, 1].
      i Got 1.5.

---

    Code
      hd_signal_null_rank(1, c(0.1, 0.2), dominance_threshold = c(0.1, 0.2))
    Condition
      Error in `hd_signal_null_rank()`:
      x `dominance_threshold` must be a single numeric in [0, 1].
      i Got 0.1 and 0.2.

# function signature is stable (catches API drift)

    Code
      args(hd_signal_null_rank)
    Output
      function (actual_metric, null_metrics, dominance_threshold = 0.5) 
      NULL

