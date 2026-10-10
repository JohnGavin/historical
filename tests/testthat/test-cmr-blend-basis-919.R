# #919 follow-up: CMR Conditioned is a "blend" return basis -- an excess
# spread (CMR) blended with a cash leg that IS rf. rf must be deducted only
# on the cash leg's per-observation weight (cash_weight = 1 - exposure_mult),
# never on the whole series and never 0-filled where unknown.
testthat::local_edition(3)

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_commodities_mean_reversion.R"))

.dts <- seq.Date(as.Date("2020-01-01"), by = "month", length.out = 24L)

.overlay <- function(rf = 0.002, exposure = rep(c(1.0, 0.5, 0.1), length.out = 24L)) {
  portfolio_tbl <- tibble::tibble(
    date = .dts, net_ret = rep(c(0.01, -0.02, 0.015, 0.005), length.out = 24L)
  )
  cond_regime_tbl <- tibble::tibble(
    date = .dts, cond_signal = 0, regime = "benign", exposure_mult = exposure
  )
  daily_rf <- tibble::tibble(date = .dts, rf_ret = rf)
  .cmr_apply_conditioning_overlay(portfolio_tbl, cond_regime_tbl, daily_rf, lookback = "1m")
}

test_that("overlay derives cash_weight from exposure_mult and carries the cash-leg rf", {
  out <- .overlay()
  expect_equal(out$cash_weight, 1 - out$exposure_mult)
  expect_true(all(out$rf_ret == 0.002))
  # excess identity: net_ret_conditioned - cash_weight * rf == w * net_ret - cost
  expect_equal(
    out$net_ret_conditioned - out$cash_weight * out$rf_ret,
    out$exposure_mult * out$net_ret - out$switch_cost,
    tolerance = 1e-12
  )
})

test_that(".compute_cmr_metrics on the blend basis deducts rf only on the cash leg", {
  out <- .overlay(rf = 0.002)
  pt  <- out |> dplyr::select(date, net_ret = net_ret_conditioned, cash_weight)
  rf  <- tibble::tibble(date = .dts, rf_ret = 0.002)

  blend <- .compute_cmr_metrics(pt, lookback = "t", daily_rf = rf, ann_factor = 12L,
                                basis_strategy = "CMR Conditioned")
  expect_equal(blend$ann_rf, round(mean(out$cash_weight * 0.002) * 12, 4))

  # FALSIFICATION: the legacy whole-series rf deduction (a total-basis label
  # on the same input) gives a different, larger ann_rf and a lower Sharpe.
  total <- .compute_cmr_metrics(pt[c("date", "net_ret")], lookback = "t", daily_rf = rf,
                                ann_factor = 12L, basis_strategy = "Value (HML)")
  expect_equal(total$ann_rf, round(0.002 * 12, 4))
  expect_gt(total$ann_rf, blend$ann_rf)
  expect_lt(total$sharpe, blend$sharpe)
})

test_that("blend with zero cash weight deducts no rf (ann_rf == 0)", {
  out <- .overlay(exposure = rep(1.0, 24L))
  pt  <- out |> dplyr::select(date, net_ret = net_ret_conditioned, cash_weight)
  rf  <- tibble::tibble(date = .dts, rf_ret = 0.002)
  m <- .compute_cmr_metrics(pt, lookback = "t", daily_rf = rf, ann_factor = 12L,
                            basis_strategy = "CMR Conditioned")
  expect_equal(m$ann_rf, 0)
})

test_that("a blend strategy without a cash_weight column aborts (never silently rf-deducted)", {
  out <- .overlay()
  pt  <- out |> dplyr::select(date, net_ret = net_ret_conditioned)
  rf  <- tibble::tibble(date = .dts, rf_ret = 0.002)
  expect_snapshot(
    error = TRUE,
    .compute_cmr_metrics(pt, lookback = "t", daily_rf = rf, ann_factor = 12L,
                         basis_strategy = "CMR Conditioned")
  )
})
