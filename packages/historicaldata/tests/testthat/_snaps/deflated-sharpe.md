# input validation: non-positive trial_sharpe_var aborts with informative message

    Code
      hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = 0)
    Condition
      Error in `hd_deflated_sharpe()`:
      x `trial_sharpe_var` must be a single positive finite number.
      i Got 0.
      i It is the variance of the Sharpe ratios across the `K_trials` trial population (V); see `hd_deflated_sharpe()` Details.

---

    Code
      hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = -1)
    Condition
      Error in `hd_deflated_sharpe()`:
      x `trial_sharpe_var` must be a single positive finite number.
      i Got -1.
      i It is the variance of the Sharpe ratios across the `K_trials` trial population (V); see `hd_deflated_sharpe()` Details.

---

    Code
      hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = NA_real_)
    Condition
      Error in `hd_deflated_sharpe()`:
      x `trial_sharpe_var` must be a single positive finite number.
      i Got NA.
      i It is the variance of the Sharpe ratios across the `K_trials` trial population (V); see `hd_deflated_sharpe()` Details.

---

    Code
      hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = Inf)
    Condition
      Error in `hd_deflated_sharpe()`:
      x `trial_sharpe_var` must be a single positive finite number.
      i Got Inf.
      i It is the variance of the Sharpe ratios across the `K_trials` trial population (V); see `hd_deflated_sharpe()` Details.

---

    Code
      hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = c(1, 2))
    Condition
      Error in `hd_deflated_sharpe()`:
      x `trial_sharpe_var` must be a single positive finite number.
      i Got 1 and 2.
      i It is the variance of the Sharpe ratios across the `K_trials` trial population (V); see `hd_deflated_sharpe()` Details.

# function signature is stable (catches API drift)

    Code
      args(hd_deflated_sharpe)
    Output
      function (r, K_trials = 1L, ann_factor = 252L, trial_sharpe_var = 1) 
      NULL

