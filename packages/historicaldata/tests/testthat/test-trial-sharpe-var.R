# Tests for hd_trial_sharpe_var() -- the min_trades population screen (#558
# Gap G2).
#
# backtest-robustness.md: "Screen the trial population for low-trade
# strategies (a min_trades gate) BEFORE computing V from it -- junk
# strategies inflate V by definition, so they must be excluded from the
# population the hurdle is calibrated against, not merely from the survivor
# list reported afterward." This function is that screen + the V
# computation, wired for use as hd_deflated_sharpe()'s trial_sharpe_var
# argument.

test_that("computes var() of the surviving population when everyone clears the floor", {
  sharpe <- c(0.1, 0.3, -0.2, 0.5)
  n_obs  <- c(40, 50, 60, 70)
  out <- hd_trial_sharpe_var(sharpe, n_obs, min_trades = 30L)

  expect_equal(out$trial_sharpe_var, stats::var(sharpe))
  expect_identical(out$n_total, 4L)
  expect_identical(out$n_included, 4L)
  expect_identical(out$n_excluded, 0L)
  expect_identical(out$n_excluded_na, 0L)
  expect_identical(out$n_excluded_min_trades, 0L)
  expect_identical(out$included, rep(TRUE, 4L))
  expect_identical(out$min_trades, 30L)
})

test_that("excludes trials below min_trades from the V computation and counts them", {
  sharpe <- c(0.1, 0.3, -0.2, 0.5, 5.0)
  n_obs  <- c(40, 50, 60, 70, 5)   # last trial: 5 obs, "junk"

  expect_snapshot(out <- hd_trial_sharpe_var(sharpe, n_obs, min_trades = 30L))

  expect_equal(out$trial_sharpe_var, stats::var(sharpe[1:4]))
  expect_identical(out$n_total, 5L)
  expect_identical(out$n_included, 4L)
  expect_identical(out$n_excluded, 1L)
  expect_identical(out$n_excluded_min_trades, 1L)
  expect_identical(out$n_excluded_na, 0L)
  expect_identical(out$included, c(TRUE, TRUE, TRUE, TRUE, FALSE))
})

test_that("the junk-variance trap: a 'junk' trial can only ever raise V, never lower the reported hurdle silently", {
  # Same as backtest-robustness.md's description: a wide-dispersion outlier
  # in the pool (here driven by a low-trade trial) inflates var() when
  # included, so excluding it must not accidentally raise V above the
  # unfiltered value.
  sharpe_clean <- c(0.10, 0.12, 0.11, 0.09)
  sharpe_junk  <- c(sharpe_clean, 4.5)         # one wild outlier
  n_obs_junk   <- c(100, 100, 100, 100, 3)     # outlier has almost no data

  out <- hd_trial_sharpe_var(sharpe_junk, n_obs_junk, min_trades = 30L)
  expect_equal(out$trial_sharpe_var, stats::var(sharpe_clean))
  expect_lt(out$trial_sharpe_var, stats::var(sharpe_junk))
})

test_that("NA/non-finite sharpe or n_obs are excluded and counted separately from min_trades", {
  sharpe <- c(0.1, NA_real_, 0.3, Inf, 0.4)
  n_obs  <- c(40, 50, 60, 70, 5)   # last one also below min_trades

  out <- hd_trial_sharpe_var(sharpe, n_obs, min_trades = 30L)
  expect_identical(out$n_total, 5L)
  expect_identical(out$n_excluded_na, 2L)          # NA sharpe, Inf sharpe
  expect_identical(out$n_excluded_min_trades, 1L)  # the n_obs=5 trial
  expect_identical(out$n_included, 2L)
  expect_equal(out$trial_sharpe_var, stats::var(c(0.1, 0.3)))
})

test_that("fewer than 2 surviving trials returns NA_real_ for trial_sharpe_var (explicit, documented default)", {
  sharpe <- c(0.1, 0.2)
  n_obs  <- c(5, 6)   # both below the floor
  out <- hd_trial_sharpe_var(sharpe, n_obs, min_trades = 30L)
  expect_identical(out$n_included, 0L)
  expect_true(is.na(out$trial_sharpe_var))

  sharpe2 <- c(0.1, 0.2)
  n_obs2  <- c(5, 40)   # exactly one survivor
  out2 <- hd_trial_sharpe_var(sharpe2, n_obs2, min_trades = 30L)
  expect_identical(out2$n_included, 1L)
  expect_true(is.na(out2$trial_sharpe_var))
})

test_that("default min_trades is HD_MIN_TRIAL_TRADES (30)", {
  sharpe <- c(0.1, 0.2, 0.3)
  n_obs  <- c(29, 30, 31)
  out <- hd_trial_sharpe_var(sharpe, n_obs)
  expect_identical(out$min_trades, 30L)
  expect_identical(out$n_included, 2L)   # 29 excluded, 30 and 31 included
})

test_that("output of hd_trial_sharpe_var() is directly usable as hd_deflated_sharpe()'s trial_sharpe_var", {
  sharpe <- c(0.2, 0.3, 0.25, 0.4)
  n_obs  <- c(40, 45, 50, 60)
  v <- hd_trial_sharpe_var(sharpe, n_obs, min_trades = 30L)

  set.seed(42)
  r <- stats::rnorm(120, mean = 0.001, sd = 0.01)
  out <- hd_deflated_sharpe(r, K_trials = v$n_included, ann_factor = 252L,
                             trial_sharpe_var = v$trial_sharpe_var)
  expect_true(is.finite(out$dsr))
  expect_identical(out$trial_sharpe_var, v$trial_sharpe_var)
})

test_that("errors: sharpe/n_obs must be numeric, same length, non-empty; min_trades must be valid", {
  expect_snapshot(error = TRUE, hd_trial_sharpe_var("a", 10))
  expect_snapshot(error = TRUE, hd_trial_sharpe_var(0.1, "a"))
  expect_snapshot(error = TRUE, hd_trial_sharpe_var(c(0.1, 0.2), c(10)))
  expect_snapshot(error = TRUE, hd_trial_sharpe_var(numeric(0), numeric(0)))
  expect_snapshot(error = TRUE, hd_trial_sharpe_var(c(0.1, 0.2), c(10, 20), min_trades = 0))
  expect_snapshot(error = TRUE, hd_trial_sharpe_var(c(0.1, 0.2), c(10, 20), min_trades = NA_integer_))
  expect_snapshot(error = TRUE, hd_trial_sharpe_var(c(0.1, 0.2), c(10, 20), min_trades = c(1, 2)))
})

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_trial_sharpe_var))
})
