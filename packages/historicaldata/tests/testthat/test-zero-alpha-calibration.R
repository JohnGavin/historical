# Tests for hd_zero_alpha_calibration() -- #839 item 2
#
# A minimal, real, tested implementation of the mechanism the article
# (Kinlay 2026, cited in issue #839) demonstrates: selecting the
# best-looking result out of many zero-alpha trials, then equal-weight
# blending several of the top results into one "book", manufactures
# Sharpe on data with NO true signal by construction. This does NOT
# calibrate against the real strategy grammar (deferred -- see the PR
# body) -- it proves the mechanism works and is reproducible.

test_that("hd_zero_alpha_calibration returns one row per grid point with expected columns", {
  grid <- tibble::tibble(n_trials = c(10L, 20L), n_legs = c(1L, 3L))
  out <- hd_zero_alpha_calibration(grid, T_obs = 24L, n_reps = 5L, seed = 1L)

  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 2L)
  expect_true(all(c(
    "n_trials", "n_legs", "rho_bar", "n_reps",
    "mean_sharpe", "median_sharpe", "sd_sharpe", "q05_sharpe", "q95_sharpe"
  ) %in% names(out)))
  expect_equal(out$n_trials, c(10L, 20L))
  expect_equal(out$n_legs, c(1L, 3L))
})

test_that("hd_zero_alpha_calibration is reproducible given the same seed", {
  grid <- tibble::tibble(n_trials = 15L, n_legs = 2L)
  out1 <- hd_zero_alpha_calibration(grid, T_obs = 24L, n_reps = 10L, seed = 7L)
  out2 <- hd_zero_alpha_calibration(grid, T_obs = 24L, n_reps = 10L, seed = 7L)
  expect_equal(out1, out2)
})

test_that("hd_zero_alpha_calibration manufactures positive Sharpe under selection bias (zero true alpha)", {
  # This is the core mechanism claim: selecting the best of many zero-alpha
  # trials and blending the top few manufactures a POSITIVE mean Sharpe on
  # data that has, by construction, no true signal at all.
  grid <- tibble::tibble(n_trials = 60L, n_legs = 6L)
  out <- hd_zero_alpha_calibration(grid, T_obs = 36L, n_reps = 300L, seed = 42L)
  expect_gt(out$mean_sharpe, 0)
})

test_that("hd_zero_alpha_calibration rejects a grid missing required columns", {
  expect_snapshot(
    error = TRUE,
    hd_zero_alpha_calibration(tibble::tibble(n_trials = 10L))
  )
})

test_that("hd_zero_alpha_calibration rejects an empty grid", {
  expect_snapshot(
    error = TRUE,
    hd_zero_alpha_calibration(tibble::tibble(n_trials = integer(0), n_legs = integer(0)))
  )
})

test_that("hd_zero_alpha_calibration rejects n_legs > n_trials", {
  expect_snapshot(
    error = TRUE,
    hd_zero_alpha_calibration(tibble::tibble(n_trials = 5L, n_legs = 10L))
  )
})

test_that("hd_zero_alpha_calibration rejects n_legs < 1 or n_trials < 1", {
  expect_snapshot(
    error = TRUE,
    hd_zero_alpha_calibration(tibble::tibble(n_trials = 5L, n_legs = 0L))
  )
})

test_that("hd_zero_alpha_calibration rejects rho_bar outside [0, 1)", {
  grid <- tibble::tibble(n_trials = 10L, n_legs = 2L)
  expect_snapshot(
    error = TRUE,
    hd_zero_alpha_calibration(grid, rho_bar = 1)
  )
  expect_snapshot(
    error = TRUE,
    hd_zero_alpha_calibration(grid, rho_bar = -0.1)
  )
})

test_that("hd_zero_alpha_calibration's function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_zero_alpha_calibration))
})

test_that("rho_bar affects the manufactured-Sharpe distribution when legs are blended", {
  # Not a precise calibration test (correlation-structure fitting is out of
  # scope for this PR) -- just proof that the rho_bar parameter is wired
  # through and changes output, which any real caller will need.
  grid <- tibble::tibble(n_trials = 40L, n_legs = 8L)
  out_indep <- hd_zero_alpha_calibration(grid, T_obs = 36L, n_reps = 200L, rho_bar = 0, seed = 99L)
  out_corr  <- hd_zero_alpha_calibration(grid, T_obs = 36L, n_reps = 200L, rho_bar = 0.8, seed = 99L)
  expect_false(isTRUE(all.equal(out_indep$mean_sharpe, out_corr$mean_sharpe)))
})
