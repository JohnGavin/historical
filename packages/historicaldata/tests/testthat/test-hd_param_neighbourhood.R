# Tests for hd_param_neighbourhood() — dense parameter-neighbourhood
# plateau-vs-peak check (#849, Bollinger's stated practice: "if a 20-day
# moving average works but 16-19 and 21-24 don't produce broadly similar
# behaviour, the system gets thrown out").
#
# TDD RED: written before the implementation exists (packages/historicaldata/
# R/param_neighbourhood.R is not yet on disk when this file is first run).

test_that("a broadly-similar dense neighbourhood is a plateau", {
  params  <- 16:24
  metrics <- c(0.97, 1.00, 0.98, 1.02, 1.00, 0.99, 1.01, 0.98, 1.00)

  out <- hd_param_neighbourhood(params, metrics, centre = 20)

  expect_equal(out$verdict, "plateau")
  expect_equal(out$reason, "broadly_similar")
  expect_equal(out$n_neighbours, 8L)
  expect_equal(out$centre_metric, 1.00)
})

test_that("an isolated spike surrounded by collapsed neighbours is a peak (floor breach)", {
  params  <- 16:24
  # centre (20) is the only good value; every neighbour collapses to 0.1
  metrics <- c(0.1, 0.1, 0.1, 0.1, 2.0, 0.1, 0.1, 0.1, 0.1)

  out <- hd_param_neighbourhood(params, metrics, centre = 20)

  expect_equal(out$verdict, "peak")
  expect_equal(out$reason, "floor")
  expect_lt(out$min_retention_ratio, 0.5)
})

test_that("a wobbly neighbourhood that never breaches the floor is still a peak (dispersion)", {
  params  <- 16:24
  # centre = 1.0; neighbours alternate high/low but each individually clears
  # the 0.5 retention floor -- only the aggregate CV should catch this.
  metrics <- c(1.40, 0.60, 1.30, 0.55, 1.00, 1.35, 0.58, 1.25, 0.65)
  centre_idx <- 5L
  expect_equal(params[centre_idx], 20L)
  expect_equal(metrics[centre_idx], 1.00)

  out <- hd_param_neighbourhood(params, metrics, centre = 20)

  expect_gte(out$min_retention_ratio, 0.5)
  expect_equal(out$verdict, "peak")
  expect_equal(out$reason, "dispersion")
  expect_gt(out$cv, 0.30)
})

test_that("too few neighbours is indeterminate, not a pass or a fail", {
  params  <- c(18, 19, 20, 21)
  metrics <- c(1.0, 1.0, 1.0, 1.0)

  out <- hd_param_neighbourhood(params, metrics, centre = 20)

  expect_equal(out$verdict, "indeterminate")
  expect_equal(out$reason, "too_few_neighbours")
  expect_equal(out$n_neighbours, 3L)
})

test_that("NA in the metric vector is indeterminate, never silently dropped", {
  params  <- 16:24
  metrics <- c(1.0, 1.0, NA_real_, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)

  out <- hd_param_neighbourhood(params, metrics, centre = 20)

  expect_equal(out$verdict, "indeterminate")
  expect_equal(out$reason, "na_metric_values")
})

test_that("a non-positive centre metric is indeterminate (retention ratio undefined)", {
  params  <- 16:24
  metrics <- c(1.0, 1.0, 1.0, 1.0, 0, 1.0, 1.0, 1.0, 1.0)

  out <- hd_param_neighbourhood(params, metrics, centre = 20)

  expect_equal(out$verdict, "indeterminate")
  expect_equal(out$reason, "centre_not_positive")
})

test_that("indeterminate never satisfies a plateau-only pass check", {
  # Defence against fail-loud-not-null.md Pattern: an indeterminate result
  # must never be usable as if it were a passing plateau.
  params  <- c(19, 20, 21)
  metrics <- c(1.0, 1.0, 1.0)
  out <- hd_param_neighbourhood(params, metrics, centre = 20)
  expect_false(identical(out$verdict, "plateau"))
  expect_false(identical(out$verdict, "peak"))
})

test_that("verdict is exactly one of plateau/peak/indeterminate", {
  out <- hd_param_neighbourhood(16:24, rep(1.0, 9), centre = 20)
  expect_true(out$verdict %in% c("plateau", "peak", "indeterminate"))
})

test_that("centre must appear exactly once in param_values", {
  expect_snapshot(error = TRUE, hd_param_neighbourhood(c(20, 20, 21, 22, 23, 24), rep(1, 6), centre = 20))
  expect_snapshot(error = TRUE, hd_param_neighbourhood(16:19, rep(1, 4), centre = 20))
})

test_that("param_values and metric_values must be the same length", {
  expect_snapshot(error = TRUE, hd_param_neighbourhood(16:24, rep(1, 5), centre = 20))
})

test_that("min_retention must be in (0, 1]", {
  expect_snapshot(error = TRUE, hd_param_neighbourhood(16:24, rep(1, 9), centre = 20, min_retention = 0))
  expect_snapshot(error = TRUE, hd_param_neighbourhood(16:24, rep(1, 9), centre = 20, min_retention = 1.5))
})

test_that("max_cv must be a positive scalar", {
  expect_snapshot(error = TRUE, hd_param_neighbourhood(16:24, rep(1, 9), centre = 20, max_cv = 0))
  expect_snapshot(error = TRUE, hd_param_neighbourhood(16:24, rep(1, 9), centre = 20, max_cv = -1))
})

test_that("min_neighbours must be a positive integer scalar", {
  expect_snapshot(error = TRUE, hd_param_neighbourhood(16:24, rep(1, 9), centre = 20, min_neighbours = 0))
  expect_snapshot(error = TRUE, hd_param_neighbourhood(16:24, rep(1, 9), centre = 20, min_neighbours = 2.5))
})

test_that("non-numeric param_values/metric_values abort", {
  expect_snapshot(error = TRUE, hd_param_neighbourhood(letters[1:9], rep(1, 9), centre = "e"))
  expect_snapshot(error = TRUE, hd_param_neighbourhood(16:24, letters[1:9], centre = 20))
})

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_param_neighbourhood))
})
