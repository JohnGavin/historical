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
      function (r, K_trials = 1L, ann_factor = 252L, trial_sharpe_var = 1, 
          trial_sharpe_var_stat = NULL) 
      NULL

# supplying both V arguments aborts with a classed error

    Code
      hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = 4,
        trial_sharpe_var_stat = 0.01)
    Condition
      Error in `hd_deflated_sharpe()`:
      x Supply either `trial_sharpe_var` or `trial_sharpe_var_stat`, not both.
      i Got `trial_sharpe_var` = 4 and `trial_sharpe_var_stat` = 0.01.
      i They are two conventions for the same V; see the Two conventions for V section of `hd_deflated_sharpe()`.

# trial_sharpe_var_stat input validation

    Code
      hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var_stat = 0)
    Condition
      Error in `hd_deflated_sharpe()`:
      x `trial_sharpe_var_stat` must be NULL or a single positive finite number.
      i Got 0.
      i It is V in the statistic's units; see the Two conventions for V section of `hd_deflated_sharpe()`.

---

    Code
      hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var_stat = NA_real_)
    Condition
      Error in `hd_deflated_sharpe()`:
      x `trial_sharpe_var_stat` must be NULL or a single positive finite number.
      i Got NA.
      i It is V in the statistic's units; see the Two conventions for V section of `hd_deflated_sharpe()`.

---

    Code
      hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var_stat = c(1, 2))
    Condition
      Error in `hd_deflated_sharpe()`:
      x `trial_sharpe_var_stat` must be NULL or a single positive finite number.
      i Got 1 and 2.
      i It is V in the statistic's units; see the Two conventions for V section of `hd_deflated_sharpe()`.

