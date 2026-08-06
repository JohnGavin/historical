testthat::local_edition(3)
# Tests that the #660 partition re-cut does not break metrics targets whose
# "Validation" slice becomes EMPTY against the current data boundary.
#
# Background (#660): `val_start` (R/plan_partitions.R bt_partitions) moved to
# 2026-05-01 -- the first month past the current data boundary (2026-04-15
# equity, 2026-02-27 factor as of #660). Every `calc_metrics()` /
# `calc_backtest_metrics()`-style helper that feeds a "Validation" row must
# handle a zero-row window without erroring and without emitting a spurious
# NA-filled row.
#
# R/plan_factormax.R's `calc_metrics()` (used by the `fm_metrics` target) was
# missing this guard -- unlike every sibling helper in R/plan_drif.R,
# R/plan_stock_backtest.R, R/plan_etf_replication.R, R/plan_portfolio_opt.R,
# and R/plan_ltr_momentum.R, which all already return NULL below their
# minimum observation count. #660 added the same `if (n < 12) return(NULL)`
# guard there. This file verifies the fix end-to-end via the real
# `fm_metrics` target's own command expression (not a hand-copied re
# implementation of `calc_metrics()`, which could silently drift from the
# source).

source(here::here("R/plan_partitions.R"))
source(here::here("R/plan_factormax.R"))
source(here::here("R/plan_stock_backtest.R"))

bt_partitions <- eval(plan_partitions()[[1]]$command$expr)

.get_target_expr <- function(plan_targets, target_name) {
  nms <- vapply(plan_targets, function(t) t$settings$name, character(1))
  idx <- which(nms == target_name)
  testthat::expect_length(idx, 1L)
  plan_targets[[idx]]$command$expr
}

# ── fm_metrics (#660 fix: missing n < 12 guard) ────────────────────────────────

test_that("fm_metrics does not error when the Validation window is empty", {
  p <- bt_partitions$factor
  fm_params <- list(
    is_end = p$train_end, test_start = p$test_start, test_end = p$test_end,
    holdout_start = p$holdout_start, holdout_end = p$holdout_end,
    val_start = p$val_start, val_end = p$val_end
  )
  # Synthetic monthly data covering Training + Testing only -- nothing at or
  # past val_start (2026-05-01), mirroring the real current data boundary.
  dates <- seq(as.Date("2018-01-15"), as.Date("2023-12-15"), by = "month")
  set.seed(1)
  fm_portfolio <- tibble::tibble(
    date = dates,
    portfolio_ret = stats::rnorm(length(dates), 0.01, 0.02),
    rf_ret = 0.001,
    benchmark_ret = stats::rnorm(length(dates), 0.008, 0.02)
  )

  expr <- .get_target_expr(plan_factormax(), "fm_metrics")
  env <- new.env()
  env$fm_portfolio <- fm_portfolio
  env$fm_params <- fm_params

  expect_no_error(result <- eval(expr, envir = env))
  expect_false("Validation" %in% result$period)
  expect_setequal(result$period, c("Training", "Testing", "Full Period"))
  # No NA-filled spurious row: every numeric column on every row is finite.
  numeric_cols <- names(result)[vapply(result, is.numeric, logical(1))]
  expect_true(all(vapply(result[numeric_cols], function(x) all(is.finite(x)), logical(1))))
})

# ── calc_backtest_metrics (already guarded; regression-proofing) ─────────────
# Shared by stk_max_metrics / stk_drif_metrics / xgb_drif_metrics -- this
# top-level function already had the `n < 12` guard before #660, verified
# here directly since it is NOT a target-local closure.

test_that("calc_backtest_metrics returns NULL (not a spurious row) for an empty window", {
  empty_df <- dplyr::tibble(
    date = as.Date(character()), port_ret = numeric(),
    rf_ret = numeric(), n_long = integer(), n_short = integer()
  )
  expect_null(calc_backtest_metrics(empty_df, "Validation"))
})

test_that("calc_backtest_metrics returns NULL below the 12-observation minimum", {
  short_df <- dplyr::tibble(
    date = as.Date("2026-05-01") + 0:5 * 30, port_ret = rep(0.01, 6),
    rf_ret = rep(0.001, 6), n_long = rep(10L, 6), n_short = rep(10L, 6)
  )
  expect_null(calc_backtest_metrics(short_df, "Validation"))
})

test_that("calc_backtest_metrics returns a row when the window has >= 12 observations", {
  ok_df <- dplyr::tibble(
    date = seq(as.Date("2020-01-15"), by = "month", length.out = 12),
    port_ret = rep(0.01, 12), rf_ret = rep(0.001, 12),
    n_long = rep(10L, 12), n_short = rep(10L, 12)
  )
  result <- calc_backtest_metrics(ok_df, "Testing")
  expect_false(is.null(result))
  expect_equal(result$period, "Testing")
  expect_equal(result$months, 12L)
})
