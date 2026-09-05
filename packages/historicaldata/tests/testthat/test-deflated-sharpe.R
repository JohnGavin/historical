# Tests for hd_deflated_sharpe() — variance-aware hurdle (#558)
#
# #558's complaint: the pre-existing E[max SR] hurdle depended only on
# K_trials (the trial COUNT), never on the DISPERSION of the trial Sharpes
# (V). A pool containing low-trade "junk" strategies has a wide Sharpe
# dispersion and a correspondingly higher honest hurdle, even at identical
# K_trials -- the "junk-variance trap" the two source articles (rulyfi.com)
# demonstrate with an identical Bollinger strategy scoring DSR 0.03 in a
# noisy pool vs 0.92 after dropping two junk indicators.
#
# These tests establish: (1) trial_sharpe_var = 1 (the default) reproduces
# pre-#558 output exactly for every K_trials -- "nothing breaks"; (2) raising
# trial_sharpe_var for the SAME underlying returns widens the hurdle and so
# lowers dsr / raises dsr_pvalue -- the qualitative flip the issue asks for.

test_that("trial_sharpe_var defaults to 1 and is echoed in the return list", {
  set.seed(1)
  r <- stats::rnorm(100, mean = 0.001, sd = 0.01)
  out <- hd_deflated_sharpe(r, K_trials = 5L, ann_factor = 252L)
  expect_identical(out$trial_sharpe_var, 1)
})

test_that("trial_sharpe_var = 1 reproduces the pre-#558 (unit-variance) hurdle exactly", {
  # Same formula, computed inline, pre-#558 (no V scaling)
  legacy_dsr <- function(r, K_trials, ann_factor) {
    r <- r[!is.na(r)]
    T_obs <- length(r)
    mu <- mean(r); sigma <- stats::sd(r)
    sr <- if (sigma > 0) mu / sigma else 0
    naive_sr <- sr * sqrt(ann_factor)
    n <- T_obs
    m3 <- sum((r - mu)^3) / n / sigma^3
    m4 <- sum((r - mu)^4) / n / sigma^4
    ek <- m4 - 3
    var_sr <- (1 - m3 * sr + (m4 - 1) / 4 * sr^2) / T_obs
    if (K_trials > 1L) {
      z <- sqrt(2 * log(K_trials))
      gamma <- 0.5772156649
      e_max_sr <- (z - (gamma + log(pi / 2)) / (2 * z)) / sqrt(T_obs)
    } else {
      e_max_sr <- 0
    }
    se_sr <- sqrt(max(var_sr, .Machine$double.eps))
    dsr_stat <- (sr - e_max_sr) / se_sr
    dsr_ann <- dsr_stat * sqrt(ann_factor / T_obs)
    dsr_ann
  }

  set.seed(2)
  r <- stats::rnorm(240, mean = 0.0008, sd = 0.012)
  for (K in c(1L, 2L, 5L, 20L, 100L)) {
    got <- hd_deflated_sharpe(r, K_trials = K, ann_factor = 252L, trial_sharpe_var = 1)
    want <- legacy_dsr(r, K, 252L)
    expect_equal(got$dsr, want, tolerance = 1e-10)
  }
})

test_that("K_trials = 1 gives zero hurdle regardless of trial_sharpe_var", {
  set.seed(3)
  r <- stats::rnorm(120, mean = 0.001, sd = 0.01)
  d1 <- hd_deflated_sharpe(r, K_trials = 1L, ann_factor = 252L, trial_sharpe_var = 1)
  d9 <- hd_deflated_sharpe(r, K_trials = 1L, ann_factor = 252L, trial_sharpe_var = 9)
  expect_equal(d1$dsr, d9$dsr)
})

test_that("junk-variance trap: same returns, wider trial-pool variance lowers DSR and raises its p-value", {
  set.seed(4)
  r <- stats::rnorm(500, mean = 0.001, sd = 0.01)
  K <- 100L

  clean_pool <- hd_deflated_sharpe(r, K_trials = K, ann_factor = 252L, trial_sharpe_var = 1)
  junk_pool  <- hd_deflated_sharpe(r, K_trials = K, ann_factor = 252L, trial_sharpe_var = 9)

  # Same K_trials, same underlying returns -- only the trial-pool dispersion
  # differs. The wider (junkier) pool must produce a MORE conservative
  # verdict: lower deflated Sharpe, higher (less significant) p-value.
  expect_lt(junk_pool$dsr, clean_pool$dsr)
  expect_gt(junk_pool$dsr_pvalue, clean_pool$dsr_pvalue)

  # Everything upstream of the hurdle (naive Sharpe, moments, T) is
  # unaffected by V -- only the deflation itself moves.
  expect_equal(junk_pool$naive_sharpe, clean_pool$naive_sharpe)
  expect_equal(junk_pool$T, clean_pool$T)
})

test_that("larger trial_sharpe_var monotonically widens the hurdle (dsr is non-increasing in V)", {
  set.seed(5)
  r <- stats::rnorm(300, mean = 0.0015, sd = 0.009)
  vs <- c(1, 2, 4, 8, 16)
  dsrs <- vapply(vs, function(v) {
    hd_deflated_sharpe(r, K_trials = 50L, ann_factor = 252L, trial_sharpe_var = v)$dsr
  }, numeric(1))
  expect_true(all(diff(dsrs) <= 0))
})

test_that("input validation: non-positive trial_sharpe_var aborts with informative message", {
  r <- stats::rnorm(50)
  expect_snapshot(error = TRUE, hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = 0))
  expect_snapshot(error = TRUE, hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = -1))
  expect_snapshot(error = TRUE, hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = NA_real_))
  expect_snapshot(error = TRUE, hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = Inf))
  expect_snapshot(error = TRUE, hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = c(1, 2)))
})

test_that("short series (T < 10) returns NA list including trial_sharpe_var echo, no error", {
  out <- hd_deflated_sharpe(c(0.01, -0.02, 0.005), K_trials = 5L, trial_sharpe_var = 3)
  expect_true(is.na(out$dsr))
  expect_identical(out$trial_sharpe_var, 3)
})

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_deflated_sharpe))
})
