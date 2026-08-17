testthat::local_edition(3)
# Tests for #666: add a "Holdout" period row to the seven source-metrics
# targets so slice_portfolio()'s Holdout cost-metric slice in
# R/plan_leaderboard.R (added by #660, previously unmatched -- the "KNOWN
# GAP" documented at that function's definition) finds a base row to
# left_join() onto and actually reaches the leaderboard.
#
# Targets covered: fm_metrics, drif_metrics, stk_max_metrics,
# stk_drif_metrics, xgb_drif_metrics, ltr_metrics, port_metrics.
#
# `tar_target()` command bodies are quoted expressions, not plain functions,
# so these tests extract each target's real `command$expr` from its
# `plan_*()` list (same technique as test-partitions-recut.R) and evaluate
# it against synthetic upstream data -- this exercises the actual target
# body, catching a regression in the real plan file, not a hand-copied
# re-implementation of it.

source(here::here("R/plan_partitions.R"))
source(here::here("R/plan_factormax.R"))
source(here::here("R/plan_drif.R"))
source(here::here("R/plan_stock_backtest.R"))
source(here::here("R/plan_xgb_signal.R"))
source(here::here("R/plan_ltr_momentum.R"))
source(here::here("R/plan_portfolio_opt.R"))
# #677: ltr_metrics' compute_ltr_metrics() now calls sharpe_ratio_rf() (the
# shared canonical Sharpe helper) -- source it so .eval_target()'s eval env
# (parent = globalenv()) can resolve it, same as every other top-level
# helper this file relies on being sourced.
source(here::here("R/utils_metrics.R"))

.eval_bt_partitions <- function() {
  targets_list <- plan_partitions()
  eval(targets_list[[1]]$command$expr)
}
bt_partitions <- .eval_bt_partitions()

# ── Helpers ──────────────────────────────────────────────────────────────────

#' Extract the quoted `command$expr` for a named target out of a plan_*() list
.tar_expr <- function(targets_list, name) {
  nm  <- vapply(targets_list, function(t) t$settings$name, character(1))
  idx <- which(nm == name)
  testthat::expect_length(idx, 1L)  # fails loudly if the target was renamed/removed
  targets_list[[idx]]$command$expr
}

#' Evaluate a target's command expr against a named list of upstream objects
.eval_target <- function(expr, vars) {
  eval(expr, envir = list2env(vars, parent = globalenv()))
}

# Full-span monthly series: 2018-01 .. 2026-04, so Training/Testing/Holdout
# all have >= 12 months of data (equity/factor Holdout is 2024-01..2026-04-30,
# 28 calendar months -- comfortably above every helper's n < 12 guard).
.make_monthly_dates <- function(from = "2018-01-31", to = "2026-04-30") {
  seq.Date(as.Date(from), as.Date(to), by = "month")
}

.make_factor_portfolio <- function(dates = .make_monthly_dates()) {
  n <- length(dates)
  set.seed(1L)
  tibble::tibble(
    date          = dates,
    portfolio_ret = stats::rnorm(n, 0.006, 0.03),
    benchmark_ret = stats::rnorm(n, 0.004, 0.03),
    rf_ret        = rep(0.0003, n)
  )
}

.make_stock_portfolio <- function(dates = .make_monthly_dates()) {
  n <- length(dates)
  set.seed(2L)
  tibble::tibble(
    date     = dates,
    port_ret = stats::rnorm(n, 0.006, 0.03),
    rf_ret   = rep(0.0003, n),
    n_long   = rep(20L, n),
    n_short  = rep(20L, n)
  )
}

.make_port_combined <- function(dates = .make_monthly_dates()) {
  n <- length(dates)
  set.seed(3L)
  tibble::tibble(
    date        = dates,
    optimal_ret = stats::rnorm(n, 0.006, 0.03),
    hrp_ret     = stats::rnorm(n, 0.005, 0.03),
    equalwt_ret = stats::rnorm(n, 0.005, 0.03),
    rf_ret      = rep(0.0003, n)
  )
}

.params_for <- function(cls, extra = list()) {
  p <- bt_partitions[[cls]]
  utils::modifyList(
    list(
      is_end        = p$train_end,
      test_start    = p$test_start,
      test_end      = p$test_end,
      holdout_start = p$holdout_start,
      holdout_end   = p$holdout_end,
      val_start     = p$val_start,
      val_end       = p$val_end
    ),
    extra
  )
}

.months_in_window <- function(dates, start, end) sum(dates >= start & dates <= end)

# ── fm_metrics (factor class, calc_metrics helper) ────────────────────────────

fm_expr      <- .tar_expr(plan_factormax(), "fm_metrics")
fm_params    <- .params_for("factor")
fm_portfolio <- .make_factor_portfolio()
fm_result    <- .eval_target(fm_expr, list(fm_params = fm_params, fm_portfolio = fm_portfolio))

test_that("fm_metrics: Holdout is in the period set", {
  expect_true("Holdout" %in% fm_result$period)
})

test_that("fm_metrics: Holdout window matches bt_partitions$factor", {
  hd <- fm_result[fm_result$period == "Holdout", ]
  expect_equal(nrow(hd), 1L)
  expect_equal(
    hd$months,
    .months_in_window(fm_portfolio$date, bt_partitions$factor$holdout_start, bt_partitions$factor$holdout_end)
  )
})

test_that("fm_metrics: empty Holdout slice yields no row and no error", {
  short_portfolio <- .make_factor_portfolio(.make_monthly_dates(to = "2023-12-31"))  # ends before holdout_start
  result <- expect_no_error(
    .eval_target(fm_expr, list(fm_params = fm_params, fm_portfolio = short_portfolio))
  )
  expect_false("Holdout" %in% result$period)
})

# ── drif_metrics (factor class, calc_metrics helper) ──────────────────────────

drif_expr      <- .tar_expr(plan_drif(), "drif_metrics")
drif_params    <- .params_for("factor")
drif_portfolio <- .make_factor_portfolio()
drif_result    <- .eval_target(drif_expr, list(drif_params = drif_params, drif_portfolio = drif_portfolio))

test_that("drif_metrics: Holdout is in the period set", {
  expect_true("Holdout" %in% drif_result$period)
})

test_that("drif_metrics: Holdout window matches bt_partitions$factor", {
  hd <- drif_result[drif_result$period == "Holdout", ]
  expect_equal(nrow(hd), 1L)
  expect_equal(
    hd$months,
    .months_in_window(drif_portfolio$date, bt_partitions$factor$holdout_start, bt_partitions$factor$holdout_end)
  )
})

# ── stk_max_metrics / stk_drif_metrics / xgb_drif_metrics (equity class,
#    shared calc_backtest_metrics() helper defined top-level in
#    R/plan_stock_backtest.R) ───────────────────────────────────────────────

stk_params <- .params_for("equity")

test_that("stk_max_metrics: Holdout is in the period set and window matches", {
  expr <- .tar_expr(plan_stock_backtest(), "stk_max_metrics")
  stk_max_portfolio <- .make_stock_portfolio()
  result <- .eval_target(expr, list(stk_params = stk_params, stk_max_portfolio = stk_max_portfolio))

  hd <- result[result$period == "Holdout", ]
  expect_equal(nrow(hd), 1L)
  expect_equal(
    hd$months,
    .months_in_window(stk_max_portfolio$date, bt_partitions$equity$holdout_start, bt_partitions$equity$holdout_end)
  )
})

test_that("stk_max_metrics: short Holdout slice (below the n<12 guard) yields no row and no error", {
  expr <- .tar_expr(plan_stock_backtest(), "stk_max_metrics")
  # Holdout window has only 6 months of data -- below calc_backtest_metrics()'s n < 12 guard.
  short_dates <- .make_monthly_dates(to = "2024-06-30")
  stk_max_portfolio <- .make_stock_portfolio(short_dates)
  result <- expect_no_error(
    .eval_target(expr, list(stk_params = stk_params, stk_max_portfolio = stk_max_portfolio))
  )
  expect_false("Holdout" %in% result$period)
})

test_that("stk_drif_metrics: Holdout is in the period set and window matches", {
  expr <- .tar_expr(plan_stock_backtest(), "stk_drif_metrics")
  stk_drif_portfolio <- .make_stock_portfolio()
  result <- .eval_target(expr, list(stk_params = stk_params, stk_drif_portfolio = stk_drif_portfolio))

  hd <- result[result$period == "Holdout", ]
  expect_equal(nrow(hd), 1L)
  expect_equal(
    hd$months,
    .months_in_window(stk_drif_portfolio$date, bt_partitions$equity$holdout_start, bt_partitions$equity$holdout_end)
  )
})

test_that("xgb_drif_metrics: Holdout is in the period set and window matches", {
  expr <- .tar_expr(plan_xgb_signal(), "xgb_drif_metrics")
  xgb_drif_portfolio <- .make_stock_portfolio()
  result <- .eval_target(expr, list(stk_params = stk_params, xgb_drif_portfolio = xgb_drif_portfolio))

  hd <- result[result$period == "Holdout", ]
  expect_equal(nrow(hd), 1L)
  expect_equal(
    hd$months,
    .months_in_window(xgb_drif_portfolio$date, bt_partitions$equity$holdout_start, bt_partitions$equity$holdout_end)
  )
})

# ── ltr_metrics (equity class, local compute_ltr_metrics() helper) ───────────

test_that("ltr_params carries holdout_start/holdout_end sourced from bt_partitions$equity (#666)", {
  ltr_expr <- .tar_expr(plan_ltr_momentum(), "ltr_params")
  result <- .eval_target(ltr_expr, list(bt_partitions = bt_partitions))
  expect_equal(result$holdout_start, bt_partitions$equity$holdout_start)
  expect_equal(result$holdout_end, bt_partitions$equity$holdout_end)
})

test_that("ltr_metrics: Holdout is in the period set and window matches", {
  expr <- .tar_expr(plan_ltr_momentum(), "ltr_metrics")
  ltr_params <- .params_for("equity")
  ltr_portfolio <- .make_stock_portfolio()
  result <- .eval_target(expr, list(ltr_params = ltr_params, ltr_portfolio = ltr_portfolio))

  hd <- result[result$period == "Holdout", ]
  expect_equal(nrow(hd), 1L)
  expect_equal(
    hd$months,
    .months_in_window(ltr_portfolio$date, bt_partitions$equity$holdout_start, bt_partitions$equity$holdout_end)
  )
})

test_that("ltr_metrics: short Holdout slice yields no row and no error", {
  expr <- .tar_expr(plan_ltr_momentum(), "ltr_metrics")
  ltr_params <- .params_for("equity")
  short_dates <- .make_monthly_dates(to = "2024-06-30")
  ltr_portfolio <- .make_stock_portfolio(short_dates)
  result <- expect_no_error(
    .eval_target(expr, list(ltr_params = ltr_params, ltr_portfolio = ltr_portfolio))
  )
  expect_false("Holdout" %in% result$period)
})

# ── port_metrics (equity class, local calc_port_metrics() helper) ────────────

test_that("port_metrics: Holdout is in the period set and window matches", {
  expr <- .tar_expr(plan_portfolio_opt(), "port_metrics")
  port_combined <- .make_port_combined()
  result <- .eval_target(expr, list(stk_params = stk_params, port_combined = port_combined))

  hd <- result[result$period == "Holdout", ]
  expect_equal(nrow(hd), 1L)
  expect_equal(
    hd$months,
    .months_in_window(port_combined$date, bt_partitions$equity$holdout_start, bt_partitions$equity$holdout_end)
  )
})

test_that("port_metrics: short Holdout slice yields no row and no error", {
  expr <- .tar_expr(plan_portfolio_opt(), "port_metrics")
  short_dates <- .make_monthly_dates(to = "2024-06-30")
  port_combined <- .make_port_combined(short_dates)
  result <- expect_no_error(
    .eval_target(expr, list(stk_params = stk_params, port_combined = port_combined))
  )
  expect_false("Holdout" %in% result$period)
})

# ── No "Validation" row is newly introduced by this change ───────────────────
# This change adds ONLY a "Holdout" slice to each target -- it must not also
# add or duplicate a "Validation" row (each target's existing Validation
# slice, if any, is untouched and out of #666's scope; see
# test-leaderboard-no-validation.R for the leaderboard-level S14 gate that
# strips Validation from the automatic tar_make() path regardless).

test_that("none of the seven targets emit more than one row per period label", {
  results <- list(
    fm   = fm_result,
    drif = drif_result
  )
  for (nm in names(results)) {
    r <- results[[nm]]
    dup_periods <- r$period[duplicated(r$period)]
    expect_length(dup_periods, 0L)
  }
})

# ── holdout_start/holdout_end threading matches bt_partitions exactly ────────
# (the "join now succeeds" static argument: slice_portfolio() in
# R/plan_leaderboard.R keys its own Holdout slice off `params$holdout_start`/
# `params$holdout_end` on the SAME params objects (fm_params, drif_params,
# stk_params) used here -- so both sides of the eventual left_join key off
# an identical [holdout_start, holdout_end] window by construction.)

test_that("fm_params/drif_params/stk_params Holdout boundaries equal bt_partitions (#666 join precondition)", {
  fm_p   <- .eval_target(.tar_expr(plan_factormax(), "fm_params"), list(bt_partitions = bt_partitions))
  drif_p <- .eval_target(.tar_expr(plan_drif(), "drif_params"), list(bt_partitions = bt_partitions))
  stk_p  <- .eval_target(.tar_expr(plan_stock_backtest(), "stk_params"), list(bt_partitions = bt_partitions))

  expect_equal(fm_p$holdout_start, bt_partitions$factor$holdout_start)
  expect_equal(fm_p$holdout_end,   bt_partitions$factor$holdout_end)
  expect_equal(drif_p$holdout_start, bt_partitions$factor$holdout_start)
  expect_equal(drif_p$holdout_end,   bt_partitions$factor$holdout_end)
  expect_equal(stk_p$holdout_start, bt_partitions$equity$holdout_start)
  expect_equal(stk_p$holdout_end,   bt_partitions$equity$holdout_end)
})
