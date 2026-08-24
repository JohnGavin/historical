# Tests for .bt_sortino_rf() in R/plan_backtest.R (#608)
#
# plan_backtest.R's bt_metrics_is target previously used
# (mean(rets) * 12 - rf_annual) / (sd(down) * sqrt(12)) with rf_annual
# hardcoded at 2%/yr, regardless of era. .bt_sortino_rf() replaces the
# constant with the real Fama-French monthly rf (stk_rf target), joined
# via the canonical .join_rf_series() (R/utils_metrics.R) -- the same
# helper .ltr_join_rf()/.mom_prepeak_join_rf() use, and the same
# leading/trailing/interior coverage policy .bt_sharpe_rf() (above it in
# this file) implements locally.
testthat::local_edition(3)

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_backtest.R"))

make_dates <- function(n) seq.Date(as.Date("2020-01-01"), by = "month", length.out = n)

make_stk_rf <- function(n, rf_ret = 0.0016) {
  tibble::tibble(ym = format(make_dates(n), "%Y-%m"), rf_ret = rep(rf_ret, n))
}

test_that(".bt_sortino_rf matches a hand-computed rf-adjusted Sortino", {
  set.seed(21)
  r   <- rnorm(36, mean = 0.008, sd = 0.05)
  dts <- make_dates(36)
  rf  <- make_stk_rf(36, rf_ret = 0.001)

  result <- .bt_sortino_rf(dts, r, rf, ann_factor = 12L)

  down <- r[r < 0]
  expected <- (mean(r) * 12 - mean(rf$rf_ret) * 12) / (sd(down) * sqrt(12))

  expect_equal(result, expected)
})

test_that(".bt_sortino_rf differs from the old hardcoded-2pct formula when the real rf differs from 2%/yr", {
  set.seed(22)
  r   <- rnorm(36, mean = 0.01, sd = 0.06)
  dts <- make_dates(36)
  # Real monthly rf implying ~6%/yr -- deliberately far from the old 2% constant
  rf  <- make_stk_rf(36, rf_ret = 0.005)

  new_sortino <- .bt_sortino_rf(dts, r, rf, ann_factor = 12L)

  # Old (pre-#608) formula: hardcoded 2%/yr rf_annual, applied identically
  # regardless of era.
  down <- r[r < 0]
  old_sortino <- (mean(r) * 12 - 0.02) / (sd(down) * sqrt(12))

  expect_false(isTRUE(all.equal(new_sortino, old_sortino)))
})

test_that(".bt_sortino_rf returns NA_real_ when there are no downside months", {
  dts <- make_dates(12)
  r   <- rep(0.01, 12)  # always positive -- no downside deviation to compute
  rf  <- make_stk_rf(12)

  expect_equal(.bt_sortino_rf(dts, r, rf, ann_factor = 12L), NA_real_)
})

test_that(".bt_sortino_rf returns NA_real_ with fewer than 2 observations", {
  dts <- make_dates(1)
  r   <- 0.01
  rf  <- make_stk_rf(1)

  expect_equal(.bt_sortino_rf(dts, r, rf, ann_factor = 12L), NA_real_)
})

test_that(".bt_sortino_rf trims a trailing uncovered month and warns (Fama-French publication lag)", {
  # Two distinct negative values so downside deviation is non-zero (a
  # constant downside series would give sd(down) == 0 -> NA_real_ by design).
  r   <- rep(c(0.02, -0.01, -0.03, 0.015), 6)
  dts <- make_dates(24)
  rf  <- make_stk_rf(24)[1:20, ]  # rf ends 4 months before returns

  expect_warning(result <- .bt_sortino_rf(dts, r, rf, ann_factor = 12L), regexp = "Dropped")
  expect_true(is.finite(result))
})

test_that(".bt_sortino_rf aborts on an INTERIOR gap (not a publication lag)", {
  r   <- rep(c(0.02, -0.01, -0.03, 0.015), 6)
  dts <- make_dates(24)
  rf  <- make_stk_rf(24)
  rf  <- rf[-10, ]

  expect_snapshot(error = TRUE, .bt_sortino_rf(dts, r, rf, ann_factor = 12L))
})

test_that(".bt_sortino_rf aborts when stk_rf lacks required columns", {
  r      <- rep(c(0.01, -0.005), 6)
  dts    <- make_dates(12)
  bad_rf <- tibble::tibble(ym = format(make_dates(12), "%Y-%m"))

  expect_snapshot(error = TRUE, .bt_sortino_rf(dts, r, bad_rf, ann_factor = 12L))
})
