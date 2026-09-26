# excludes trials below min_trades from the V computation and counts them

    Code
      out <- hd_trial_sharpe_var(sharpe, n_obs, min_trades = 30L)
    Condition
      Warning:
      ! hd_trial_sharpe_var(): excluded 1 of 5 trial(s) from the population used to compute V (0 missing/non-finite, 1 below min_trades = 30).
      i See backtest-robustness.md's junk-variance trap (#558 Gap G2).

# errors: sharpe/n_obs must be numeric, same length, non-empty; min_trades must be valid

    Code
      hd_trial_sharpe_var("a", 10)
    Condition
      Error in `hd_trial_sharpe_var()`:
      x `sharpe` and `n_obs` must both be numeric vectors.
      i Got <character> and <numeric>.

---

    Code
      hd_trial_sharpe_var(0.1, "a")
    Condition
      Error in `hd_trial_sharpe_var()`:
      x `sharpe` and `n_obs` must both be numeric vectors.
      i Got <numeric> and <character>.

---

    Code
      hd_trial_sharpe_var(c(0.1, 0.2), c(10))
    Condition
      Error in `hd_trial_sharpe_var()`:
      x `sharpe` and `n_obs` must be the same length.
      i Got length 2 and length 1.

---

    Code
      hd_trial_sharpe_var(numeric(0), numeric(0))
    Condition
      Error in `hd_trial_sharpe_var()`:
      x `sharpe` and `n_obs` must have at least one trial.
      i Got a zero-length vector.

---

    Code
      hd_trial_sharpe_var(c(0.1, 0.2), c(10, 20), min_trades = 0)
    Condition
      Error in `hd_trial_sharpe_var()`:
      x `min_trades` must be a single positive finite number.
      i Got 0.

---

    Code
      hd_trial_sharpe_var(c(0.1, 0.2), c(10, 20), min_trades = NA_integer_)
    Condition
      Error in `hd_trial_sharpe_var()`:
      x `min_trades` must be a single positive finite number.
      i Got NA.

---

    Code
      hd_trial_sharpe_var(c(0.1, 0.2), c(10, 20), min_trades = c(1, 2))
    Condition
      Error in `hd_trial_sharpe_var()`:
      x `min_trades` must be a single positive finite number.
      i Got 1 and 2.

# function signature is stable (catches API drift)

    Code
      args(hd_trial_sharpe_var)
    Output
      function (sharpe, n_obs, min_trades = HD_MIN_TRIAL_TRADES) 
      NULL

