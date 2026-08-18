testthat::local_edition(3)
# Regression tests for #677 slice 2: canonical, risk-free-adjusted Sharpe
# for EV/EBIT Value (R/plan_ev_ebit.R) -- one of the "no rf deducted"
# family (implied rf of exactly 0.00%, a formula signature).
#
# Pattern mirrors tests/testthat/test-plan-ltr-momentum.R (#677 slice 1).

source(here::here("R/plan_ev_ebit.R"))
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
# variables like `ev_params` against the wrong environment and errors.
# Splicing via a plain list2env() call sidesteps the issue entirely.
.eval_command_args <- function(expr, args_list) {
  env <- list2env(args_list, envir = new.env(parent = globalenv()))
  eval(expr, envir = env)
}

.toy_ev_portfolios <- function(n_months = 780L, seed = 677L, rf_val = 0.002) {
  set.seed(seed)
  dates <- seq(as.Date("1960-01-01"), by = "month", length.out = n_months)
  tibble::tibble(
    date           = dates,
    ret_value_hml  = stats::rnorm(n_months, mean = 0.005, sd = 0.02),
    ret_value_qual = stats::rnorm(n_months, mean = 0.006, sd = 0.025),
    ret_market     = stats::rnorm(n_months, mean = 0.007, sd = 0.03),
    RF             = rep(rf_val, n_months)
  )
}

.ev_env_args <- function(port) {
  list(
    ev_params = list(
      oos_start      = as.Date("2010-01-01"),
      quality_weight = 0.5
    ),
    bt_partitions = list(factor = list(test_end = as.Date("2020-12-31"))),
    ev_portfolios = port,
    sharpe_ratio_rf = sharpe_ratio_rf
  )
}

# ── ev_metrics: rf deduction actually lowers Sharpe ─────────────────────

test_that("ev_metrics: Full-period sharpe is rf-adjusted, not bare cagr/vol", {
  cmd <- .target_command(plan_ev_ebit(), "ev_metrics")

  port_zero_rf <- .toy_ev_portfolios(rf_val = 0)
  port_pos_rf  <- .toy_ev_portfolios(rf_val = 0.003)

  res_zero <- .eval_command_args(cmd, .ev_env_args(port_zero_rf))
  res_pos  <- .eval_command_args(cmd, .ev_env_args(port_pos_rf))

  full_zero <- res_zero[res_zero$strategy == "Value+Quality (50% HML + 50% RMW, QVAL proxy)" &
                           res_zero$period == "Full", ]
  full_pos <- res_pos[res_pos$strategy == "Value+Quality (50% HML + 50% RMW, QVAL proxy)" &
                         res_pos$period == "Full", ]

  expect_equal(nrow(full_zero), 1L)
  expect_equal(nrow(full_pos), 1L)
  expect_false(is.na(full_zero$sharpe))
  expect_false(is.na(full_pos$sharpe))
  expect_lt(full_pos$sharpe, full_zero$sharpe)
})

test_that("ev_metrics: Training and OOS rows are still produced", {
  cmd <- .target_command(plan_ev_ebit(), "ev_metrics")
  port <- .toy_ev_portfolios()

  result <- .eval_command_args(cmd, .ev_env_args(port))

  expect_true(all(c("Full", "Training", "OOS") %in% result$period))
  expect_false(anyNA(result$sharpe))
})

# ── ev_underperformance_periods: same rf-adjusted fix ────────────────────

test_that("ev_underperformance_periods: rf deduction lowers sharpe vs zero-rf", {
  cmd <- .target_command(plan_ev_ebit(), "ev_underperformance_periods")

  port_zero_rf <- .toy_ev_portfolios(rf_val = 0)
  port_pos_rf  <- .toy_ev_portfolios(rf_val = 0.003)

  res_zero <- .eval_command_args(cmd, .ev_env_args(port_zero_rf))
  res_pos  <- .eval_command_args(cmd, .ev_env_args(port_pos_rf))

  row_zero <- res_zero[res_zero$strategy == "Value+Quality" &
                          res_zero$period == "2000-2012 (Value underperformance)", ]
  row_pos <- res_pos[res_pos$strategy == "Value+Quality" &
                        res_pos$period == "2000-2012 (Value underperformance)", ]

  expect_equal(nrow(row_zero), 1L)
  expect_equal(nrow(row_pos), 1L)
  expect_lt(row_pos$sharpe, row_zero$sharpe)
})

test_that("ev_underperformance_periods: all documented eras are present", {
  cmd <- .target_command(plan_ev_ebit(), "ev_underperformance_periods")
  port <- .toy_ev_portfolios()

  result <- .eval_command_args(cmd, .ev_env_args(port))

  expect_true(all(c(
    "Pre-1966 (Value leadership)",
    "1966-1982 (Value underperformance)",
    "1983-1999 (Value recovery)",
    "2000-2012 (Value underperformance)",
    "2013+ (Recent period)"
  ) %in% result$period))
})
