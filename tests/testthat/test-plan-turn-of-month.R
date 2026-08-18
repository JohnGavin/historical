testthat::local_edition(3)
# Regression tests for #677 slice 2: canonical, risk-free-adjusted Sharpe
# for Turn-of-the-Month (R/plan_turn_of_month.R) -- one of the "no rf
# deducted" family (implied rf of exactly 0.00%, a formula signature). TOM
# is a DAILY strategy, so it gets its own daily rf join
# (.tom_join_rf_daily(), mirroring .ltr_join_rf() from plan_ltr_momentum.R
# but keyed on `date` instead of `ym`) and periods_per_year = 252L.

source(here::here("R/plan_turn_of_month.R"))
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
# variables like `tom_params` against the wrong environment and errors.
# Splicing via a plain list2env() call sidesteps the issue entirely.
.eval_command_args <- function(expr, args_list) {
  env <- list2env(args_list, envir = new.env(parent = globalenv()))
  eval(expr, envir = env)
}

# ── .tom_join_rf_daily() coverage policy (mirrors .ltr_join_rf tests) ────

.mk_port_daily <- function(dates) {
  tibble::tibble(date = as.Date(dates), ret = seq_along(dates) / 10000)
}
.mk_rf_daily <- function(dates) {
  tibble::tibble(date = as.Date(dates), rf_ret = rep(0.0001, length(dates)))
}

test_that(".tom_join_rf_daily attaches rf_ret with no NA when coverage is complete", {
  out <- .tom_join_rf_daily(
    .mk_port_daily(c("2026-01-05", "2026-01-06")),
    .mk_rf_daily(c("2026-01-05", "2026-01-06"))
  )
  expect_equal(nrow(out), 2L)
  expect_false(anyNA(out$rf_ret))
})

test_that(".tom_join_rf_daily trims a trailing uncovered date and warns", {
  port <- .mk_port_daily(c("2026-01-05", "2026-01-06", "2026-01-07"))
  rf   <- .mk_rf_daily(c("2026-01-05", "2026-01-06"))

  expect_warning(out <- .tom_join_rf_daily(port, rf), regexp = "2026-01-07")
  expect_equal(nrow(out), 2L)
  expect_false(anyNA(out$rf_ret))
  expect_false(as.Date("2026-01-07") %in% out$date)
})

test_that(".tom_join_rf_daily still aborts on an INTERIOR hole -- a real FF3 gap, not a lag", {
  port <- .mk_port_daily(c("2026-01-05", "2026-01-06", "2026-01-07"))
  rf   <- .mk_rf_daily(c("2026-01-05", "2026-01-07"))  # 2026-01-06 missing, inside span

  expect_error(.tom_join_rf_daily(port, rf), regexp = "2026-01-06")
  expect_error(.tom_join_rf_daily(port, rf), regexp = "HOLE")
})

test_that(".tom_join_rf_daily aborts when rf lacks required columns", {
  expect_error(
    .tom_join_rf_daily(.mk_port_daily("2026-01-05"), tibble::tibble(date = as.Date("2026-01-05"))),
    regexp = "rf_ret"
  )
})

test_that(".tom_join_rf_daily abort messages are stable", {
  port <- .mk_port_daily(c("2026-01-05", "2026-01-06", "2026-01-07"))
  expect_snapshot(error = TRUE, .tom_join_rf_daily(port, .mk_rf_daily(c("2026-01-05", "2026-01-07"))))
  expect_snapshot(
    error = TRUE,
    .tom_join_rf_daily(.mk_port_daily("2026-01-05"), tibble::tibble(date = as.Date("2026-01-05")))
  )
})

# ── tom_metrics: rf deduction actually lowers Sharpe ─────────────────────

.toy_tom_portfolio <- function(n_days = 3000L, seed = 677L, rf_val = 0.0001) {
  set.seed(seed)
  dates <- seq(as.Date("2000-01-01"), by = "day", length.out = n_days)
  tibble::tibble(
    date    = dates,
    ret     = stats::rnorm(n_days, mean = 0.0002, sd = 0.012),
    ret_net = stats::rnorm(n_days, mean = 0.0003, sd = 0.006),
    in_tom  = sample(c(TRUE, FALSE), n_days, replace = TRUE, prob = c(0.2, 0.8)),
    rf_ret  = rep(rf_val, n_days)
  )
}

.tom_env_args <- function(port) {
  list(
    tom_portfolio = port,
    tom_params = list(
      oos_start = as.Date("2004-01-01"),
      oos_end   = as.Date("2006-12-31")
    ),
    sharpe_ratio_rf = sharpe_ratio_rf
  )
}

test_that("tom_metrics: Full Period sharpe_tom/sharpe_bh are rf-adjusted, not bare cagr/vol", {
  cmd <- .target_command(plan_turn_of_month(), "tom_metrics")

  port_zero_rf <- .toy_tom_portfolio(rf_val = 0)
  port_pos_rf  <- .toy_tom_portfolio(rf_val = 0.0002)

  res_zero <- .eval_command_args(cmd, .tom_env_args(port_zero_rf))
  res_pos  <- .eval_command_args(cmd, .tom_env_args(port_pos_rf))

  full_zero <- res_zero[res_zero$period == "Full Period", ]
  full_pos  <- res_pos[res_pos$period == "Full Period", ]

  expect_equal(nrow(full_zero), 1L)
  expect_equal(nrow(full_pos), 1L)
  expect_false(is.na(full_zero$sharpe_tom))
  expect_false(is.na(full_pos$sharpe_tom))
  expect_false(is.na(full_zero$sharpe_bh))
  expect_false(is.na(full_pos$sharpe_bh))

  # A positive risk-free deduction must LOWER both the strategy and
  # benchmark Sharpe relative to the zero-rf case (#677: the pre-fix
  # formula was cagr/vol with implied rf == 0.00% always).
  expect_lt(full_pos$sharpe_tom, full_zero$sharpe_tom)
  expect_lt(full_pos$sharpe_bh, full_zero$sharpe_bh)
})

test_that("tom_metrics: Training and Testing rows are still produced", {
  cmd <- .target_command(plan_turn_of_month(), "tom_metrics")
  port <- .toy_tom_portfolio()

  result <- .eval_command_args(cmd, .tom_env_args(port))

  expect_true(all(c("Training", "Testing", "Full Period") %in% result$period))
  expect_false(anyNA(result$sharpe_tom))
  expect_false(anyNA(result$sharpe_bh))
})

# ── tom_param_sweep: same rf-adjusted fix ─────────────────────────────────

.toy_tom_daily <- function(n_days = 3000L, seed = 677L, rf_val = 0.0001) {
  set.seed(seed)
  dates <- seq(as.Date("2000-01-01"), by = "day", length.out = n_days)
  tibble::tibble(
    date   = dates,
    ret    = stats::rnorm(n_days, mean = 0.0003, sd = 0.012),
    rf_ret = rep(rf_val, n_days)
  )
}

test_that("tom_param_sweep: sharpe is rf-adjusted, positive rf lowers sharpe vs zero-rf", {
  cmd <- .target_command(plan_turn_of_month(), "tom_param_sweep")

  base_args <- function(daily) {
    list(
      tom_daily = daily,
      tom_params = list(rf_annual = 0.00, cost_bps = 5L),
      sharpe_ratio_rf = sharpe_ratio_rf
    )
  }

  res_zero <- .eval_command_args(cmd, base_args(.toy_tom_daily(rf_val = 0)))
  res_pos  <- .eval_command_args(cmd, base_args(.toy_tom_daily(rf_val = 0.0002)))

  # Same (n_tail=1, n_head=3) row -- matches tom_params defaults -- compared
  # across the two rf scenarios.
  row_zero <- res_zero[res_zero$n_tail == 1L & res_zero$n_head == 3L, ]
  row_pos  <- res_pos[res_pos$n_tail == 1L & res_pos$n_head == 3L, ]

  expect_equal(nrow(row_zero), 1L)
  expect_equal(nrow(row_pos), 1L)
  expect_false(is.na(row_zero$sharpe))
  expect_false(is.na(row_pos$sharpe))
  expect_lt(row_pos$sharpe, row_zero$sharpe)
})
