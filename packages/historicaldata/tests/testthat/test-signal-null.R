# Tests for hd_signal_null_rank() -- the generic signal-null rank statistic
# generalised from the mom_prepeak-only placebo test (#718).

testthat::local_edition(3)

test_that("perfect strategy: no null variant beats it", {
  rank <- hd_signal_null_rank(actual_metric = 1.5, null_metrics = rep(0.1, 80))

  expect_identical(rank$n_beat, 0L)
  expect_identical(rank$n_valid, 80L)
  expect_identical(rank$n_total, 80L)
  expect_equal(rank$rank_pct, 0)
  expect_false(rank$null_dominates)
})

test_that("dominated strategy: every null variant beats it", {
  rank <- hd_signal_null_rank(actual_metric = 0.1, null_metrics = rep(1.5, 80))

  expect_identical(rank$n_beat, 80L)
  expect_identical(rank$n_valid, 80L)
  expect_equal(rank$rank_pct, 1)
  expect_true(rank$null_dominates)
})

test_that("ties count as beating (>=), matching the article's rank convention", {
  rank <- hd_signal_null_rank(actual_metric = 1.0, null_metrics = c(1.0, 0.5, 1.5))

  expect_identical(rank$n_beat, 2L)  # 1.0 (tie) and 1.5 beat; 0.5 does not
  expect_equal(rank$rank_pct, 2 / 3)
})

test_that("dominance_threshold controls the null_dominates cutoff", {
  # 40% of nulls beat actual -- below default 0.5 threshold, above a 0.3 threshold
  null_metrics <- c(2, 2, 0.1, 0.1, 0.1)  # 2 of 5 beat actual = 1
  below_default <- hd_signal_null_rank(1, null_metrics)
  expect_false(below_default$null_dominates)

  above_lower <- hd_signal_null_rank(1, null_metrics, dominance_threshold = 0.3)
  expect_true(above_lower$null_dominates)
})

test_that("NA null_metrics are excluded from n_valid but counted in n_total", {
  rank <- hd_signal_null_rank(1.0, c(0.5, NA, NA, 2.0))

  expect_identical(rank$n_valid, 2L)
  expect_identical(rank$n_total, 4L)
  expect_identical(rank$n_beat, 1L)  # only 2.0 beats
})

test_that("single-replicate case matches the pre-#718 mom_prepeak comparison", {
  # mom_prepeak_random_peak_test's old logic: random_sharpe >= actual_sharpe
  rank_beats <- hd_signal_null_rank(0.3, 0.5)
  expect_true(rank_beats$null_dominates)
  expect_identical(rank_beats$n_beat, 1L)

  rank_survives <- hd_signal_null_rank(0.5, 0.3)
  expect_false(rank_survives$null_dominates)
  expect_identical(rank_survives$n_beat, 0L)
})

test_that("NA actual_metric returns an indeterminate verdict, not FALSE", {
  rank <- hd_signal_null_rank(NA_real_, c(0.1, 0.2))

  expect_true(is.na(rank$null_dominates))
  expect_identical(rank$n_beat, NA_integer_)
  expect_true(is.na(rank$rank_pct))
})

test_that("all-NA null_metrics returns an indeterminate verdict, not FALSE", {
  rank <- hd_signal_null_rank(1.0, c(NA_real_, NA_real_))

  expect_identical(rank$n_valid, 0L)
  expect_true(is.na(rank$null_dominates))
})

test_that("actual_metric must be a numeric scalar", {
  expect_snapshot(
    error = TRUE,
    hd_signal_null_rank(c(1, 2), c(0.1, 0.2))
  )
  expect_snapshot(
    error = TRUE,
    hd_signal_null_rank("not numeric", c(0.1, 0.2))
  )
})

test_that("null_metrics must be numeric", {
  expect_snapshot(
    error = TRUE,
    hd_signal_null_rank(1.0, c("a", "b"))
  )
})

test_that("dominance_threshold must be a single numeric in [0, 1]", {
  expect_snapshot(
    error = TRUE,
    hd_signal_null_rank(1.0, c(0.1, 0.2), dominance_threshold = 1.5)
  )
  expect_snapshot(
    error = TRUE,
    hd_signal_null_rank(1.0, c(0.1, 0.2), dominance_threshold = c(0.1, 0.2))
  )
})

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_signal_null_rank))
})
