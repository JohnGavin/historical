testthat::local_edition(3)
# Regression tests for #677 slice 2: canonical, risk-free-adjusted Sharpe
# for Managed Futures (R/plan_managed_futures.R) -- one of the "no rf
# deducted" family (implied rf of exactly 0.00%, a formula signature).
#
# Pattern mirrors tests/testthat/test-plan-ltr-momentum.R (#677 slice 1):
# the real shipped command expression is extracted from plan_managed_futures()
# and eval()'d against synthetic mf_portfolios data, exercising the actual
# shipped code rather than a re-implementation.

source(here::here("R/plan_managed_futures.R"))
source(here::here("R/utils_metrics.R"))

.target_command <- function(target_list, name) {
  hit <- vapply(target_list, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) {
    stop("target '", name, "' not found (or not unique) in this plan's target list")
  }
  target_list[[which(hit)]]$command$expr[[1]]
}

.eval_command <- function(expr, ...) {
  env <- list2env(list(...), envir = new.env(parent = globalenv()))
  eval(expr, envir = env)
}

# NOTE: cannot use do.call(.eval_command, c(list(cmd), args_list)) here --
# `cmd` is itself an unevaluated language object (a `{ ... }` block), and
# do.call() re-evaluates language-object arguments in the CALLING frame
# rather than passing them through as literal data, which resolves free
# variables like `mf_params` against the wrong environment and errors.
# Splicing via a plain list2env() call sidesteps the issue entirely.
.eval_command_args <- function(expr, args_list) {
  env <- list2env(args_list, envir = new.env(parent = globalenv()))
  eval(expr, envir = env)
}

.toy_mf_portfolios <- function(n_months = 260L, seed = 677L, rf_val = 0.002) {
  set.seed(seed)
  dates <- seq(as.Date("2005-01-01"), by = "month", length.out = n_months)
  tibble::tibble(
    date   = dates,
    ret_lo = stats::rnorm(n_months, mean = 0.005, sd = 0.02),
    ret_ls = stats::rnorm(n_months, mean = 0.006, sd = 0.03),
    ret_ew = stats::rnorm(n_months, mean = 0.004, sd = 0.025),
    RF     = rep(rf_val, n_months)
  )
}

.mf_env_args <- function(port) {
  list(
    mf_params = list(
      oos_start  = as.Date("2010-01-01"),
      vol_target = 0.10,
      proxy_note = "toy"
    ),
    bt_partitions = list(macro = list(test_end = as.Date("2020-12-31"))),
    mf_portfolios = port,
    sharpe_ratio_rf = sharpe_ratio_rf
  )
}

# ── mf_metrics: rf deduction actually lowers Sharpe ─────────────────────

test_that("mf_metrics: Full-period sharpe is rf-adjusted, not bare cagr/vol", {
  cmd <- .target_command(plan_managed_futures(), "mf_metrics")

  port_zero_rf <- .toy_mf_portfolios(rf_val = 0)
  port_pos_rf  <- .toy_mf_portfolios(rf_val = 0.003)

  res_zero <- .eval_command_args(cmd, .mf_env_args(port_zero_rf))
  res_pos  <- .eval_command_args(cmd, .mf_env_args(port_pos_rf))

  full_zero <- res_zero[res_zero$strategy == "Long-Short TS-Mom (MOP 2012, vol-targeted)" &
                           res_zero$period == "Full", ]
  full_pos <- res_pos[res_pos$strategy == "Long-Short TS-Mom (MOP 2012, vol-targeted)" &
                         res_pos$period == "Full", ]

  expect_equal(nrow(full_zero), 1L)
  expect_equal(nrow(full_pos), 1L)
  expect_false(is.na(full_zero$sharpe))
  expect_false(is.na(full_pos$sharpe))

  # A positive risk-free deduction must LOWER the reported Sharpe relative
  # to the zero-rf case computed on the SAME return series (#677: the
  # pre-fix formula was cagr/vol with implied rf == 0.00% always).
  expect_lt(full_pos$sharpe, full_zero$sharpe)
})

test_that("mf_metrics: Training and OOS rows are still produced", {
  cmd <- .target_command(plan_managed_futures(), "mf_metrics")
  port <- .toy_mf_portfolios()

  result <- .eval_command_args(cmd, .mf_env_args(port))

  expect_true(all(c("Full", "Training", "OOS") %in% result$period))
  expect_false(anyNA(result$sharpe))
})

# ── mf_underperformance_periods: same rf-adjusted fix ────────────────────

test_that("mf_underperformance_periods: rf deduction lowers sharpe vs zero-rf", {
  cmd <- .target_command(plan_managed_futures(), "mf_underperformance_periods")

  port_zero_rf <- .toy_mf_portfolios(rf_val = 0)
  port_pos_rf  <- .toy_mf_portfolios(rf_val = 0.003)

  res_zero <- .eval_command_args(cmd, .mf_env_args(port_zero_rf))
  res_pos  <- .eval_command_args(cmd, .mf_env_args(port_pos_rf))

  row_zero <- res_zero[res_zero$strategy == "TS-Mom L/S" &
                          res_zero$period == "2010-2019 (trend-following drought)", ]
  row_pos <- res_pos[res_pos$strategy == "TS-Mom L/S" &
                        res_pos$period == "2010-2019 (trend-following drought)", ]

  expect_equal(nrow(row_zero), 1L)
  expect_equal(nrow(row_pos), 1L)
  expect_lt(row_pos$sharpe, row_zero$sharpe)
})

test_that("mf_underperformance_periods: all documented eras are present", {
  cmd <- .target_command(plan_managed_futures(), "mf_underperformance_periods")
  port <- .toy_mf_portfolios()

  result <- .eval_command_args(cmd, .mf_env_args(port))

  expect_true(all(c(
    "Pre-2010 (GFC, high dispersion)",
    "2010-2019 (trend-following drought)",
    "2020-2022 (COVID + rates surge)",
    "2023+ (recent period)"
  ) %in% result$period))
})
