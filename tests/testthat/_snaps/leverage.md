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

