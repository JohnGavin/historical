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
.mock_hac_sharpe <- function(ret_vec) {
  list(hac_tstat = 0, naive_sharpe = mean(ret_vec) / stats::sd(ret_vec) * sqrt(252))
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
  overlay <- tibble::tibble(
    date        = dates,
    ret_raw     = stats::rnorm(n_days, 0.0003, 0.01),
    ret_overlay = stats::rnorm(n_days, 0.0003, 0.008)
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

test_that("rsc_metrics: DRIF_raw/FacMAX_raw rows have NA sharpe (no rf series wired -- documented, deliberate default)", {
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

  no_rf_rows <- result[result$strategy %in% c("DRIF_raw", "DRIF_overlay", "FacMAX_raw", "FacMAX_overlay"), ]
  expect_gt(nrow(no_rf_rows), 0L)
  expect_true(all(is.na(no_rf_rows$sharpe)))
  # hac_sharpe is unaffected -- still populated for these rows
  expect_false(any(is.na(no_rf_rows$hac_sharpe)))
})
