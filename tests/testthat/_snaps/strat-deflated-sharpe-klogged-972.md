# a non-positive or non-scalar logged K aborts instead of being used

    Code
      .run(.toy(k_logged = 0L))
    Condition
      Error:
      x The logged trial count k_trials_logged must be a single positive whole number.
      i Got 0 (class <integer>, length 1).
      i It comes from `hd_strategy_spec_trial_count()` (target `strat_k_trials_logged`).

---

    Code
      .run(.toy(k_logged = c(3L, 4L)))
    Condition
      Error:
      x The logged trial count k_trials_logged must be a single positive whole number.
      i Got 3 and 4 (class <integer>, length 2).
      i It comes from `hd_strategy_spec_trial_count()` (target `strat_k_trials_logged`).

---

    Code
      .run(.toy(k_logged = NA_integer_))
    Condition
      Error:
      x The logged trial count k_trials_logged must be a single positive whole number.
      i Got NA (class <integer>, length 1).
      i It comes from `hd_strategy_spec_trial_count()` (target `strat_k_trials_logged`).

