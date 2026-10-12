# ann_factor missing / invalid aborts naming the series

    Code
      compute_borrow_sensitivity(r, series_label = "CMR")
    Condition
      Error in `compute_borrow_sensitivity()`:
      x compute_borrow_sensitivity(): `ann_factor` for "CMR" must be a single positive finite number.
      i Pass the series' own periods per year (12 monthly, 252 daily); it is never guessed from n (#936).

---

    Code
      compute_borrow_sensitivity(r, ann_factor = 0, series_label = "CMR")
    Condition
      Error in `compute_borrow_sensitivity()`:
      x compute_borrow_sensitivity(): `ann_factor` for "CMR" must be a single positive finite number.
      i Pass the series' own periods per year (12 monthly, 252 daily); it is never guessed from n (#936).

# build_borrow_sensitivity_table aborts naming a strategy with no ann_factor

    Code
      build_borrow_sensitivity_table(list(CMR = r, LTR = r), c(LTR = 12))
    Condition
      Error in `build_borrow_sensitivity_table()`:
      x build_borrow_sensitivity_table(): no ann_factor for 1 strategy: "CMR".
      i Never guessed from series length (#936).

---

    Code
      build_borrow_sensitivity_table(list(CMR = r), 252)
    Condition
      Error in `build_borrow_sensitivity_table()`:
      x build_borrow_sensitivity_table(): ann_factor_by_strategy must be a NAMED numeric vector.
      i One periods-per-year entry per strategy (#936).

