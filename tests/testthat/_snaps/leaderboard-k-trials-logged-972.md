# FALSIFICATION: each way of being wrong aborts

    Code
      check_leaderboard_k_trials_logged(bad_zero)
    Condition
      Error in `check_leaderboard_k_trials_logged()`:
      x Leaderboard k_trials_logged must be one positive whole number on every row.
      i Got distinct value(s): 0 across 3 row(s).
      i check_leaderboard_k_trials_logged() (#972): K comes from `hd_strategy_spec_trial_count()` via the strat_deflated_sharpe target; a wrong K silently mis-deflates the K-logged Sharpe.

---

    Code
      check_leaderboard_k_trials_logged(bad_na)
    Condition
      Error in `check_leaderboard_k_trials_logged()`:
      x Leaderboard k_trials_logged must be one positive whole number on every row.
      i Got distinct value(s): 13 and NA across 3 row(s).
      i check_leaderboard_k_trials_logged() (#972): K comes from `hd_strategy_spec_trial_count()` via the strat_deflated_sharpe target; a wrong K silently mis-deflates the K-logged Sharpe.

---

    Code
      check_leaderboard_k_trials_logged(bad_two)
    Condition
      Error in `check_leaderboard_k_trials_logged()`:
      x Leaderboard k_trials_logged must be one positive whole number on every row.
      i Got distinct value(s): 13 and 14 across 3 row(s).
      i check_leaderboard_k_trials_logged() (#972): K comes from `hd_strategy_spec_trial_count()` via the strat_deflated_sharpe target; a wrong K silently mis-deflates the K-logged Sharpe.

---

    Code
      check_leaderboard_k_trials_logged(bad_frac)
    Condition
      Error in `check_leaderboard_k_trials_logged()`:
      x Leaderboard k_trials_logged must be one positive whole number on every row.
      i Got distinct value(s): 13.5 across 3 row(s).
      i check_leaderboard_k_trials_logged() (#972): K comes from `hd_strategy_spec_trial_count()` via the strat_deflated_sharpe target; a wrong K silently mis-deflates the K-logged Sharpe.

