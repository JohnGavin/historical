# non-positive sharpe_annual aborts with informative message

    Code
      hd_detection_power(sharpe_annual = 0)
    Condition
      Error in `hd_detection_power()`:
      x `sharpe_annual` must be a single positive number.
      i Got 0.
      i hd_detection_power() tests a one-sided H1: SR > 0 -- a non-positive or missing claimed effect has no power to compute.

---

    Code
      hd_detection_power(sharpe_annual = -0.5)
    Condition
      Error in `hd_detection_power()`:
      x `sharpe_annual` must be a single positive number.
      i Got -0.5.
      i hd_detection_power() tests a one-sided H1: SR > 0 -- a non-positive or missing claimed effect has no power to compute.

# NA sharpe_annual aborts

    Code
      hd_detection_power(sharpe_annual = NA_real_)
    Condition
      Error in `hd_detection_power()`:
      x `sharpe_annual` must be a single positive number.
      i Got NA.
      i hd_detection_power() tests a one-sided H1: SR > 0 -- a non-positive or missing claimed effect has no power to compute.

# non-positive ann_factor aborts

    Code
      hd_detection_power(sharpe_annual = 0.5, ann_factor = 0)
    Condition
      Error in `hd_detection_power()`:
      x `ann_factor` must be a single positive number.
      i Got 0.

# alpha outside (0, 1) aborts

    Code
      hd_detection_power(sharpe_annual = 0.5, alpha = 0)
    Condition
      Error in `hd_detection_power()`:
      x `alpha` must be a single number strictly between 0 and 1.
      i Got 0.

---

    Code
      hd_detection_power(sharpe_annual = 0.5, alpha = 1)
    Condition
      Error in `hd_detection_power()`:
      x `alpha` must be a single number strictly between 0 and 1.
      i Got 1.

# target_power outside (0, 1) aborts

    Code
      hd_detection_power(sharpe_annual = 0.5, target_power = 1)
    Condition
      Error in `hd_detection_power()`:
      x `target_power` must be a single number strictly between 0 and 1.
      i Got 1.

# n_obs < 2 aborts

    Code
      hd_detection_power(sharpe_annual = 0.5, n_obs = 1)
    Condition
      Error in `hd_detection_power()`:
      x `n_obs` must be NULL or a single number >= 2.
      i Got 1.

# function signature is stable (catches API drift)

    Code
      args(hd_detection_power)
    Output
      function (sharpe_annual, n_obs = NULL, ann_factor = 12, alpha = 0.05, 
          target_power = 0.8) 
      NULL

