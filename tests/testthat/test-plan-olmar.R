testthat::local_edition(3)
# Regression tests for #677 slice 3b: OLMAR-1's Sharpe migrated from an
# arithmetic-numerator, NO-risk-free-deduction formula
# (`mean(ret) * 252 / vol`) onto the canonical sharpe_ratio_rf()
# (geometric numerator, rf-deducted, periods_per_year = 252L). OLMAR-1 was
# the last unmigrated strategy in issue #677 and sat at the top of the
# leaderboard (0.883) while every strategy it was ranked against had
# already been corrected downward by slices 1-3. It also fixes an
# inconsistency WITHIN olmar_metrics itself: cagr was already geometric,
# so the pre-fix sharpe was not the Sharpe of the reported CAGR.
#
# These tests cover two things: (1) .olmar_join_rf() -- the fifth caller of
# the shared .join_rf_series() coverage policy (R/utils_metrics.R), mirroring
# .tom_join_rf_daily() (R/plan_turn_of_month.R); and (2) olmar_metrics'
# sharpe/cagr/vol values, evaluated by extracting the target's command
# expression and running it against toy fixtures (mirrors
# tests/testthat/test-plan-turn-of-month.R's approach for tom_metrics).

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_olmar.R"))

.target_command <- function(target_list, name) {
  hit <- vapply(target_list, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) {
    stop("target '", name, "' not found (or not unique) in this plan's target list")
  }
  target_list[[which(hit)]]$command$expr[[1]]
}

.eval_command_args <- function(expr, args_list) {
  env <- list2env(args_list, envir = new.env(parent = globalenv()))
  eval(expr, envir = env)
}

# ── .olmar_join_rf(): coverage policy (mirrors .tom_join_rf_daily tests) ──

.mk_port_daily <- function(dates) {
  tibble::tibble(
    date      = as.Date(dates),
    gross_ret = seq_along(dates) / 10000,
    net_ret   = seq_along(dates) / 10000,
    turnover  = 0.1
  )
}
.mk_rf_daily <- function(dates) {
  tibble::tibble(date = as.Date(dates), rf_ret = rep(0.0001, length(dates)))
}

test_that(".olmar_join_rf attaches rf_ret with no NA when coverage is complete", {
  out <- .olmar_join_rf(
    .mk_port_daily(c("2026-01-05", "2026-01-06")),
    .mk_rf_daily(c("2026-01-05", "2026-01-06"))
  )
  expect_equal(nrow(out), 2L)
  expect_false(anyNA(out$rf_ret))
})

test_that(".olmar_join_rf trims a trailing uncovered date and warns", {
  port <- .mk_port_daily(c("2026-01-05", "2026-01-06", "2026-01-07"))
  rf   <- .mk_rf_daily(c("2026-01-05", "2026-01-06"))

  expect_warning(out <- .olmar_join_rf(port, rf), regexp = "2026-01-07")
  expect_equal(nrow(out), 2L)
  expect_false(anyNA(out$rf_ret))
})

test_that(".olmar_join_rf still aborts on an INTERIOR hole -- a real FF3 gap, not a lag", {
  port <- .mk_port_daily(c("2026-01-05", "2026-01-06", "2026-01-07"))
  rf   <- .mk_rf_daily(c("2026-01-05", "2026-01-07"))  # 2026-01-06 missing, inside span

  expect_error(.olmar_join_rf(port, rf), regexp = "2026-01-06")
  expect_error(.olmar_join_rf(port, rf), regexp = "HOLE")
})

test_that(".olmar_join_rf aborts when rf lacks required columns", {
  expect_error(
    .olmar_join_rf(.mk_port_daily("2026-01-05"), tibble::tibble(date = as.Date("2026-01-05"))),
    regexp = "rf_ret"
  )
})

test_that(".olmar_join_rf abort messages are stable", {
  port <- .mk_port_daily(c("2026-01-05", "2026-01-06", "2026-01-07"))
  expect_snapshot(error = TRUE, .olmar_join_rf(port, .mk_rf_daily(c("2026-01-05", "2026-01-07"))))
})

# ── olmar_metrics: rf-adjusted, geometric Sharpe ──────────────────────────

.toy_olmar_portfolio <- function(n_days = 800L, seed = 677L, rf_val = 0.0002, ret_sd = 0.03) {
  set.seed(seed)
  dates <- seq(as.Date("2010-01-04"), by = "day", length.out = n_days)
  ret   <- stats::rnorm(n_days, mean = 0.0006, sd = ret_sd)  # deliberately volatile fixture
  tibble::tibble(
    date      = dates,
    gross_ret = ret,
    net_ret   = ret,
    turnover  = 0.15,
    rf_ret    = rep(rf_val, n_days)
  )
}

.olmar_env_args <- function(port, test_start = "2011-01-01", test_end = "2011-06-30") {
  list(
    olmar_portfolio = port,
    olmar_params    = list(test_start = as.Date(test_start), test_end = as.Date(test_end)),
    sharpe_ratio_rf = sharpe_ratio_rf
  )
}

test_that("olmar_metrics Full Period sharpe/cagr/vol match sharpe_ratio_rf() exactly", {
  cmd  <- .target_command(plan_olmar(), "olmar_metrics")
  port <- .toy_olmar_portfolio()

  result <- .eval_command_args(cmd, .olmar_env_args(port))
  full   <- result[result$period == "Full Period", ]

  expected <- sharpe_ratio_rf(port$net_ret, port$rf_ret, periods_per_year = 252L)

  expect_equal(nrow(full), 1L)
  expect_equal(full$sharpe, round(expected$sharpe, 3))
  expect_equal(full$cagr, round(expected$ann_ret * 100, 2))
  expect_equal(full$vol, round(expected$ann_vol * 100, 2))
})

test_that("olmar_metrics sharpe differs from the old arithmetic no-rf formula on a volatile fixture", {
  cmd  <- .target_command(plan_olmar(), "olmar_metrics")
  port <- .toy_olmar_portfolio(ret_sd = 0.04)  # high vol -> arithmetic/geometric gap is large

  result <- .eval_command_args(cmd, .olmar_env_args(port))
  full   <- result[result$period == "Full Period", ]

  # Old (pre-#677) formula: arithmetic mean numerator, NO risk-free deduction.
  old_vol    <- sd(port$net_ret) * sqrt(252)
  old_sharpe <- if (old_vol > 0) mean(port$net_ret) * 252 / old_vol else NA_real_

  expect_false(isTRUE(all.equal(full$sharpe, round(old_sharpe, 3))))
})

test_that("a positive risk-free rate lowers olmar_metrics sharpe relative to zero-rf", {
  cmd <- .target_command(plan_olmar(), "olmar_metrics")

  port_zero_rf <- .toy_olmar_portfolio(rf_val = 0)
  port_pos_rf  <- .toy_olmar_portfolio(rf_val = 0.0003)

  res_zero <- .eval_command_args(cmd, .olmar_env_args(port_zero_rf))
  res_pos  <- .eval_command_args(cmd, .olmar_env_args(port_pos_rf))

  full_zero <- res_zero[res_zero$period == "Full Period", ]
  full_pos  <- res_pos[res_pos$period == "Full Period", ]

  expect_lt(full_pos$sharpe, full_zero$sharpe)
})

test_that("olmar_metrics still produces Training/Testing/Full Period rows", {
  cmd    <- .target_command(plan_olmar(), "olmar_metrics")
  port   <- .toy_olmar_portfolio()
  result <- .eval_command_args(cmd, .olmar_env_args(port))

  expect_true(all(c("Training", "Testing", "Full Period") %in% result$period))
  expect_false(anyNA(result$sharpe))
})
