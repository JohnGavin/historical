testthat::local_edition(3)
# Regression tests for #677 slice 1: canonical, risk-free-adjusted Sharpe
# for Risk State's SPY_overlay row (R/plan_risk_state.R). Complements
# test-bound-testing-windows.R, which already extracts/eval()'s the
# `rsc_metrics` command for the #667 window-bound regression -- this file
# adds the same extraction pattern with an `rf_daily` column present, since
# #667's synthetic `port` tibble does not include one (and does not need
# to: it doesn't assert on sharpe).

source(here::here("R/plan_risk_state.R"))
source(here::here("R/utils_metrics.R"))

# ── Helpers (mirrors test-bound-testing-windows.R) ──────────────────────

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

# Minimal stand-in for historicaldata::hd_hac_sharpe() -- rsc_metrics calls
# it for hac_tstat/hac_sharpe columns this test does not assert on.
# Deliberately NOT rf-adjusted, so it differs from the canonical sharpe.
# ann_factor mirrors the real function's signature (default 252, but
# rsc_metrics' calc_metrics() now calls it with ann_factor = periods_per_year
# for the monthly DRIF/FacMAX rows too -- #677 slice 2 -- so the mock must
# accept it or those calls error with "unused argument").
.mock_hac_sharpe <- function(ret_vec, ann_factor = 252) {
  list(hac_tstat = 0, naive_sharpe = mean(ret_vec) / stats::sd(ret_vec) * sqrt(ann_factor))
}

.toy_rsc_inputs <- function(n_days = 500L, seed = 677L, rf_val = 0.0001) {
  set.seed(seed)
  dates <- seq(as.Date("2018-01-01"), by = "day", length.out = n_days)
  port <- tibble::tibble(
    date         = dates,
    ret_buyhold  = stats::rnorm(n_days, 0.0003, 0.01),
    ret_strategy = stats::rnorm(n_days, 0.0003, 0.008),
    rf_daily     = rep(rf_val, n_days)
  )
  # rf_ret (#677 slice 2): stands in for drif_portfolio$rf_ret / fm_portfolio$
  # rf_ret, which rsc_overlay_drif/rsc_overlay_fac_max now carry through so
  # DRIF_raw/DRIF_overlay/FacMAX_raw/FacMAX_overlay get a real Sharpe.
  overlay <- tibble::tibble(
    date        = dates,
    ret_raw     = stats::rnorm(n_days, 0.0003, 0.01),
    ret_overlay = stats::rnorm(n_days, 0.0003, 0.008),
    rf_ret      = rep(rf_val, n_days)
  )
  list(port = port, overlay = overlay)
}

test_that("rsc_metrics: SPY_overlay Full Period row has both sharpe and hac_sharpe, and they differ", {
  cmd <- .target_command(plan_risk_state(), "rsc_metrics")
  inputs <- .toy_rsc_inputs(n_days = 500L, rf_val = 0.0001)

  result <- .eval_command(
    cmd,
    hd_hac_sharpe       = .mock_hac_sharpe,
    sharpe_ratio_rf     = sharpe_ratio_rf,
    rsc_params          = list(oos_start = as.Date("2019-01-01"), test_end = as.Date("2019-06-30")),
    rsc_portfolio       = inputs$port,
    rsc_overlay_drif    = inputs$overlay,
    rsc_overlay_fac_max = inputs$overlay
  )

  full_row <- result[result$strategy == "SPY_overlay" & result$period == "Full Period", ]
  expect_equal(nrow(full_row), 1L)
  expect_true("sharpe" %in% names(full_row))
  expect_true("hac_sharpe" %in% names(full_row))
  expect_false(is.na(full_row$sharpe))
  expect_false(is.na(full_row$hac_sharpe))
  expect_false(isTRUE(all.equal(full_row$sharpe, full_row$hac_sharpe)))
})

test_that("rsc_metrics: calc_metrics() now publishes n_obs, the raw observation count (#726 item 3)", {
  # #726: rsc_metrics had no months/n_obs/n_days column at all, so
  # R/plan_leaderboard.R's .norm_rsc() had nothing to rename into `months`
  # and the SPY_overlay row's detection-power diagnostic
  # (.detection_diag_row(), R/plan_leaderboard.R) was silently NA forever
  # regardless of sharpe -- QA gate S20 (check_leaderboard_detection_power_
  # values(), R/plan_qa_gates.R) now catches that gap at pipeline time. This
  # test guards the root-cause fix: n_obs must equal the actual number of
  # non-NA return observations backing each row, for every strategy variant
  # calc_metrics() produces (not just SPY_overlay).
  cmd <- .target_command(plan_risk_state(), "rsc_metrics")
  inputs <- .toy_rsc_inputs(n_days = 500L, rf_val = 0.0001)

  result <- .eval_command(
    cmd,
    hd_hac_sharpe       = .mock_hac_sharpe,
    sharpe_ratio_rf     = sharpe_ratio_rf,
    rsc_params          = list(oos_start = as.Date("2019-01-01"), test_end = as.Date("2019-06-30")),
    rsc_portfolio       = inputs$port,
    rsc_overlay_drif    = inputs$overlay,
    rsc_overlay_fac_max = inputs$overlay
  )

  expect_true("n_obs" %in% names(result))
  expect_false(any(is.na(result$n_obs)))

  full_row <- result[result$strategy == "SPY_overlay" & result$period == "Full Period", ]
  expect_equal(nrow(full_row), 1L)
  # Full Period spans the whole 500-day toy series -- no NAs injected by
  # .toy_rsc_inputs(), so n_obs must equal n_days exactly.
  expect_equal(full_row$n_obs, 500L)

  training_row <- result[result$strategy == "SPY_overlay" & result$period == "Training", ]
  expect_equal(nrow(training_row), 1L)
  expect_true(training_row$n_obs < full_row$n_obs)
})

test_that("rsc_metrics: DRIF_raw/FacMAX_raw rows have a real sharpe now rf_ret is wired (#677 slice 2)", {
  cmd <- .target_command(plan_risk_state(), "rsc_metrics")
  inputs <- .toy_rsc_inputs(n_days = 500L)

  result <- .eval_command(
    cmd,
    hd_hac_sharpe       = .mock_hac_sharpe,
    sharpe_ratio_rf     = sharpe_ratio_rf,
    rsc_params          = list(oos_start = as.Date("2019-01-01"), test_end = as.Date("2019-06-30")),
    rsc_portfolio       = inputs$port,
    rsc_overlay_drif    = inputs$overlay,
    rsc_overlay_fac_max = inputs$overlay
  )

  rf_rows <- result[result$strategy %in% c("DRIF_raw", "DRIF_overlay", "FacMAX_raw", "FacMAX_overlay"), ]
  expect_gt(nrow(rf_rows), 0L)
  # #677 slice 2: rsc_overlay_drif/rsc_overlay_fac_max now carry rf_ret
  # through from drif_portfolio/fm_portfolio, so sharpe is no longer NA.
  expect_true(all(is.finite(rf_rows$sharpe)))
  # hac_sharpe remains populated too (separate, non-rf-adjusted statistic).
  expect_false(any(is.na(rf_rows$hac_sharpe)))
  # The two Sharpe families use different bases (rf-adjusted geometric vs
  # naive arithmetic) so they must not be identical even at a shared
  # periods_per_year -- guards against calc_metrics() collapsing the two
  # statistics into the same computation by accident.
  expect_false(isTRUE(all.equal(rf_rows$sharpe, rf_rows$hac_sharpe)))
})
