testthat::local_edition(3)

# Tests for interval-calibration helpers (#597).
#
# These back the qa_interval_coverage QA gate, which asks whether the
# intervals we publish on the leaderboard actually contain outcomes at the
# stated rate.  See R/plan_interval_coverage.R.

# ── hd_interval_score ───────────────────────────────────────────────────────

test_that("interval score equals width when the outcome is inside", {
  # Gneiting & Raftery (2007): IS = (u - l) with no penalty term when l <= y <= u
  expect_equal(hd_interval_score(2, lower = 1, upper = 3, alpha = 0.1), 2)
  expect_equal(hd_interval_score(1, lower = 1, upper = 3, alpha = 0.1), 2)  # on boundary
  expect_equal(hd_interval_score(3, lower = 1, upper = 3, alpha = 0.1), 2)  # on boundary
})

test_that("interval score penalises misses by 2/alpha times the shortfall", {
  # y = 0 is 1 below the lower bound: 2 + (2/0.1) * 1 = 22
  expect_equal(hd_interval_score(0, lower = 1, upper = 3, alpha = 0.1), 22)
  # y = 5 is 2 above the upper bound: 2 + (2/0.1) * 2 = 42
  expect_equal(hd_interval_score(5, lower = 1, upper = 3, alpha = 0.1), 42)
})

test_that("interval score is vectorised and NA-preserving", {
  res <- hd_interval_score(
    y     = c(2, 0, 5, NA),
    lower = c(1, 1, 1, 1),
    upper = c(3, 3, 3, 3),
    alpha = 0.1
  )
  expect_equal(res, c(2, 22, 42, NA_real_))
})

test_that("a wider interval scores worse than a tight one that also covers", {
  # This is the property coverage alone cannot see: an interval of +/- Inf
  # has perfect coverage.  The score must prefer the tighter interval.
  tight <- hd_interval_score(0, lower = -1, upper = 1, alpha = 0.1)
  wide  <- hd_interval_score(0, lower = -50, upper = 50, alpha = 0.1)
  expect_lt(tight, wide)
})

test_that("hd_interval_score rejects invalid alpha", {
  expect_snapshot(error = TRUE, hd_interval_score(2, 1, 3, alpha = 0))
  expect_snapshot(error = TRUE, hd_interval_score(2, 1, 3, alpha = 1.5))
})

test_that("hd_interval_score rejects crossed bounds", {
  expect_snapshot(error = TRUE, hd_interval_score(2, lower = 3, upper = 1, alpha = 0.1))
})

# ── hd_fpr_equipoise ────────────────────────────────────────────────────────

test_that("FPR at equipoise matches the Sellke-Berger calibration", {
  # statistical-reporting rule: p = 0.05 -> FPR ~ 26-30%, p = 0.01 -> ~11%
  expect_equal(hd_fpr_equipoise(0.05), 0.2893, tolerance = 1e-3)
  expect_equal(hd_fpr_equipoise(0.01), 0.1113, tolerance = 1e-3)
  expect_equal(hd_fpr_equipoise(0.001), 0.018431, tolerance = 1e-3)
})

test_that("FPR is undefined above the 1/e bound", {
  expect_true(is.na(hd_fpr_equipoise(0.5)))
  expect_true(is.na(hd_fpr_equipoise(exp(-1))))
  expect_false(is.na(hd_fpr_equipoise(0.3)))
})

# ── hd_interval_coverage ────────────────────────────────────────────────────

test_that("coverage counts outcomes inside the stated bounds", {
  res <- hd_interval_coverage(
    y       = c(0, 0, 0, 10),
    lower   = rep(-1, 4),
    upper   = rep(1, 4),
    nominal = 0.90
  )
  expect_equal(res$n, 4L)
  expect_equal(res$n_covered, 3L)
  expect_equal(res$coverage, 0.75)
  expect_equal(res$excess, 0.75 - 0.90)
  expect_equal(res$mean_width, 2)
})

test_that("effective n divides by the overlap factor", {
  res <- hd_interval_coverage(
    y       = rep(0, 24),
    lower   = rep(-1, 24),
    upper   = rep(1, 24),
    nominal = 0.90,
    overlap = 12
  )
  expect_equal(res$n, 24L)
  expect_equal(res$n_eff, 2)
  # The naive n would give a far smaller p-value than the effective n.
  expect_true(res$p_binom_eff > 0.05)
})

test_that("over-coverage is flagged, not silently accepted", {
  # 20/20 inside a stated 50% interval - the failure mode from the source post
  res <- hd_interval_coverage(
    y       = rep(0, 20),
    lower   = rep(-1, 20),
    upper   = rep(1, 20),
    nominal = 0.50
  )
  expect_equal(res$coverage, 1)
  expect_gt(res$excess, 0)
  expect_equal(res$verdict, "over_covered")
})

test_that("under-coverage is flagged", {
  res <- hd_interval_coverage(
    y       = rep(10, 20),
    lower   = rep(-1, 20),
    upper   = rep(1, 20),
    nominal = 0.90
  )
  expect_equal(res$coverage, 0)
  expect_equal(res$verdict, "under_covered")
})

test_that("coverage consistent with nominal is not flagged", {
  y <- c(rep(0, 9), 10)  # 9 of 10 inside a stated 90% interval
  res <- hd_interval_coverage(
    y       = y,
    lower   = rep(-1, 10),
    upper   = rep(1, 10),
    nominal = 0.90
  )
  expect_equal(res$coverage, 0.9)
  expect_equal(res$verdict, "consistent")
})

test_that("NA outcomes are dropped from the denominator", {
  res <- hd_interval_coverage(
    y       = c(0, 0, NA, NA),
    lower   = rep(-1, 4),
    upper   = rep(1, 4),
    nominal = 0.90
  )
  expect_equal(res$n, 2L)
  expect_equal(res$coverage, 1)
})

test_that("hd_interval_coverage rejects an out-of-range nominal", {
  expect_snapshot(error = TRUE, hd_interval_coverage(0, -1, 1, nominal = 1.2))
})

test_that("hd_interval_coverage rejects a non-positive overlap", {
  expect_snapshot(error = TRUE, hd_interval_coverage(0, -1, 1, nominal = 0.9, overlap = 0))
})

# ── hd_block_boot_sharpe_ci ─────────────────────────────────────────────────

test_that("block bootstrap CI brackets the point estimate and is reproducible", {
  set.seed(1)
  ret <- stats::rnorm(120, mean = 0.008, sd = 0.04)

  a <- hd_block_boot_sharpe_ci(ret, n_draws = 200L, block_size = 3L, seed = 42L)
  b <- hd_block_boot_sharpe_ci(ret, n_draws = 200L, block_size = 3L, seed = 42L)

  expect_equal(a, b)                      # same seed -> same interval
  expect_lt(a$sharpe_lo, a$sharpe_hi)
  expect_equal(a$n_obs, 120L)
  expect_equal(a$block_size, 3L)
})

test_that("block bootstrap rejects a series shorter than one block", {
  expect_snapshot(error = TRUE, hd_block_boot_sharpe_ci(c(0.01, 0.02), block_size = 3L))
})

test_that("block bootstrap rejects returns at or below -100%", {
  # prod(1 + ret) goes non-positive and the geometric Sharpe becomes NaN.
  # A -100% monthly return is a data defect, not a number to silently absorb.
  expect_snapshot(error = TRUE, hd_block_boot_sharpe_ci(c(0.01, -1.0, 0.02, 0.01, 0.03)))
})

# ── API stability ───────────────────────────────────────────────────────────

test_that("calibration function signatures are stable", {
  expect_snapshot(args(hd_interval_score))
  expect_snapshot(args(hd_interval_coverage))
  expect_snapshot(args(hd_fpr_equipoise))
  expect_snapshot(args(hd_block_boot_sharpe_ci))
})
