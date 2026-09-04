# hd_zero_alpha_calibration rejects a grid missing required columns

    Code
      hd_zero_alpha_calibration(tibble::tibble(n_trials = 10L))
    Condition
      Error in `hd_zero_alpha_calibration()`:
      x `grid` must be a data frame with columns n_trials and n_legs.
      i Got columns: "n_trials".

# hd_zero_alpha_calibration rejects an empty grid

    Code
      hd_zero_alpha_calibration(tibble::tibble(n_trials = integer(0), n_legs = integer(
        0)))
    Condition
      Error in `hd_zero_alpha_calibration()`:
      ! `grid` must have at least one row.

# hd_zero_alpha_calibration rejects n_legs > n_trials

    Code
      hd_zero_alpha_calibration(tibble::tibble(n_trials = 5L, n_legs = 10L))
    Condition
      Error in `hd_zero_alpha_calibration()`:
      x `grid` has 1 row(s) that violate 1 <= n_legs <= n_trials: 1.
      i n_trials: 5; n_legs: 10.

# hd_zero_alpha_calibration rejects n_legs < 1 or n_trials < 1

    Code
      hd_zero_alpha_calibration(tibble::tibble(n_trials = 5L, n_legs = 0L))
    Condition
      Error in `hd_zero_alpha_calibration()`:
      x `grid` has 1 row(s) that violate 1 <= n_legs <= n_trials: 1.
      i n_trials: 5; n_legs: 0.

# hd_zero_alpha_calibration rejects rho_bar outside [0, 1)

    Code
      hd_zero_alpha_calibration(grid, rho_bar = 1)
    Condition
      Error in `hd_zero_alpha_calibration()`:
      ! `rho_bar` must be in [0, 1); got 1.

---

    Code
      hd_zero_alpha_calibration(grid, rho_bar = -0.1)
    Condition
      Error in `hd_zero_alpha_calibration()`:
      ! `rho_bar` must be in [0, 1); got -0.1.

# hd_zero_alpha_calibration's function signature is stable (catches API drift)

    Code
      args(hd_zero_alpha_calibration)
    Output
      function (grid, T_obs = 60L, n_reps = 200L, rho_bar = 0, sigma_annual = 0.2, 
          ann_factor = 12, seed = 42L) 
      NULL

