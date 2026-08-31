# compute_vol_per_unit_gross: errors on non-data-frame input

    Code
      compute_vol_per_unit_gross(list(a = 1))
    Condition
      Error in `compute_vol_per_unit_gross()`:
      x `leaderboard_df` must be a data frame, not <list>.
      i compute_vol_per_unit_gross() expects the leaderboard target.

# compute_vol_per_unit_gross: errors on missing required columns

    Code
      compute_vol_per_unit_gross(bad)
    Condition
      Error in `compute_vol_per_unit_gross()`:
      x `leaderboard_df` is missing required column: gross_convention.
      i compute_vol_per_unit_gross() needs strategy, period, vol, gross_convention, and is_cap.

# compute_vol_per_unit_gross: function signature is stable (catches API drift)

    Code
      args(compute_vol_per_unit_gross)
    Output
      function (leaderboard_df, periods = c("Training", "Testing", 
          "Full Period")) 
      NULL

# compute_budget_neutral_sigma: errors on missing required columns

    Code
      compute_budget_neutral_sigma(tibble::tibble(period = "Full Period"))
    Condition
      Error in `compute_budget_neutral_sigma()`:
      x `vpug_df` is missing required columns: vol, gross_convention, and vol_per_unit_gross.
      i compute_budget_neutral_sigma() needs period, vol, gross_convention, and vol_per_unit_gross (see compute_vol_per_unit_gross()).

# compute_budget_neutral_sigma: errors on zero-row input

    Code
      compute_budget_neutral_sigma(empty)
    Condition
      Error in `compute_budget_neutral_sigma()`:
      x `vpug_df` has zero rows.
      i No strategy has a measurable gross_convention -- check the leaderboard and strategy_gross_convention targets.

# compute_budget_neutral_sigma: function signature is stable (catches API drift)

    Code
      args(compute_budget_neutral_sigma)
    Output
      function (vpug_df) 
      NULL

# compute_regime_stress_ratio: errors when Training/Testing partitions are entirely absent

    Code
      compute_regime_stress_ratio(vpug)
    Condition
      Error in `compute_regime_stress_ratio()`:
      x leaderboard has no Training and Testing rows with a measurable gross_convention.
      i compute_regime_stress_ratio() needs at least one strategy with both a Training and a Testing row.

# compute_regime_stress_ratio: function signature is stable (catches API drift)

    Code
      args(compute_regime_stress_ratio)
    Output
      function (vpug_df) 
      NULL

# .leverage_gross_backstop: errors on a non-numeric override

    Code
      .leverage_gross_backstop("banana")
    Condition
      Error in `.leverage_gross_backstop()`:
      x HD_LEVERAGE_GROSS_BACKSTOP = "banana" is not a positive number.
      i Unset it to use the default 2x (PROVISIONAL, #626 D1), or set a positive numeric override.

# .leverage_gross_backstop: errors on a non-positive override

    Code
      .leverage_gross_backstop("0")
    Condition
      Error in `.leverage_gross_backstop()`:
      x HD_LEVERAGE_GROSS_BACKSTOP = "0" is not a positive number.
      i Unset it to use the default 2x (PROVISIONAL, #626 D1), or set a positive numeric override.

---

    Code
      .leverage_gross_backstop("-1.5")
    Condition
      Error in `.leverage_gross_backstop()`:
      x HD_LEVERAGE_GROSS_BACKSTOP = "-1.5" is not a positive number.
      i Unset it to use the default 2x (PROVISIONAL, #626 D1), or set a positive numeric override.

# compute_allocator_gross: errors on missing required columns

    Code
      compute_allocator_gross(bad, sigma_target = 0.11)
    Condition
      Error in `compute_allocator_gross()`:
      x `vpug_df` is missing required column: is_cap.
      i compute_allocator_gross() needs strategy, period, vol_per_unit_gross, and is_cap (see compute_vol_per_unit_gross()).

# compute_allocator_gross: errors on a non-positive sigma_target

    Code
      compute_allocator_gross(vpug, sigma_target = -0.1)
    Condition
      Error in `compute_allocator_gross()`:
      x `sigma_target` must be a single positive number, not -0.1.
      i compute_allocator_gross() expects the Full Period sigma_target_budget_neutral from compute_budget_neutral_sigma().

---

    Code
      compute_allocator_gross(vpug, sigma_target = NA_real_)
    Condition
      Error in `compute_allocator_gross()`:
      x `sigma_target` must be a single positive number, not NA.
      i compute_allocator_gross() expects the Full Period sigma_target_budget_neutral from compute_budget_neutral_sigma().

# compute_allocator_gross: errors on a non-positive backstop

    Code
      compute_allocator_gross(vpug, sigma_target = 0.11, backstop = 0)
    Condition
      Error in `compute_allocator_gross()`:
      x `backstop` must be a single positive number, not 0.
      i compute_allocator_gross() expects a positive gross-exposure ceiling -- see LEVERAGE_GROSS_BACKSTOP_DEFAULT (PROVISIONAL, #626 D1).

# compute_allocator_gross: errors when no Full Period rows are present

    Code
      compute_allocator_gross(no_full, sigma_target = 0.11)
    Condition
      Error in `compute_allocator_gross()`:
      x `vpug_df` has no Full Period rows.
      i compute_allocator_gross() sizes against the whole available sample, not a sub-partition.

# compute_allocator_gross: function signature is stable (catches API drift)

    Code
      args(compute_allocator_gross)
    Output
      function (vpug_df, sigma_target, backstop = .leverage_gross_backstop()) 
      NULL

