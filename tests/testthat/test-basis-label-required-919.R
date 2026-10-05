# #919 follow-up: the return-basis label is REQUIRED. A NULL/missing label
# used to silently keep the legacy rf-deducted Sharpe, which is wrong for an
# excess-basis (dollar-neutral) series (fail-loud-not-null.md).
testthat::local_edition(3)

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

# .compute_cmr_metrics() calls library(dplyr); attach it up front so the
# "Attaching package" message cannot leak into a snapshot.
suppressMessages(library(dplyr))

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_stock_backtest.R"))
source(here::here("R/plan_commodities_mean_reversion.R"))

.bt_df <- dplyr::tibble(
  date = seq(as.Date("2020-01-15"), by = "month", length.out = 24),
  port_ret = rep(c(0.02, -0.01), 12), rf_ret = rep(0.003, 24),
  n_long = rep(10L, 24), n_short = rep(10L, 24)
)

test_that("calc_backtest_metrics aborts on a NULL / omitted label", {
  expect_snapshot(error = TRUE, calc_backtest_metrics(.bt_df, "Full"))
  expect_snapshot(error = TRUE, calc_backtest_metrics(.bt_df, "Full", strategy = NULL))
})

test_that("calc_backtest_metrics aborts on an unregistered / non-string label", {
  expect_snapshot(error = TRUE, calc_backtest_metrics(.bt_df, "Full", strategy = "Not A Strategy"))
  expect_snapshot(error = TRUE, calc_backtest_metrics(.bt_df, "Full", strategy = 1))
})

test_that("calc_backtest_metrics validates the label even when the window is too short to compute", {
  # Guard placement (fail-loud-not-null Pattern 5): the check runs where the
  # value ENTERS, not only on the path that consumes it.
  short <- .bt_df[1:5, ]
  expect_error(calc_backtest_metrics(short, "Validation"), "strategy")
})

test_that("calc_backtest_metrics: an excess label deducts no rf, a total label deducts it", {
  ex  <- calc_backtest_metrics(.bt_df, "Full", strategy = "Stock MAX")
  tot <- calc_backtest_metrics(.bt_df, "Full", strategy = "Value (HML)")
  expect_equal(ex$ann_rf, 0)
  expect_equal(tot$ann_rf, 0.003 * 12)
  expect_gt(ex$sharpe, tot$sharpe)
})

.cmr_pt <- tibble::tibble(
  date = seq.Date(as.Date("2020-01-01"), by = "month", length.out = 24L),
  net_ret = rep(c(0.02, -0.01), 12)
)
.cmr_rf <- tibble::tibble(date = .cmr_pt$date, rf_ret = 0.002)

test_that(".compute_cmr_metrics aborts on a NULL / omitted label", {
  expect_snapshot(error = TRUE, .compute_cmr_metrics(.cmr_pt, "1m", .cmr_rf, ann_factor = 12L))
  expect_snapshot(error = TRUE, .compute_cmr_metrics(.cmr_pt, "1m", .cmr_rf, ann_factor = 12L,
                                                      basis_strategy = NULL))
})

test_that(".compute_cmr_metrics aborts on an unregistered label", {
  expect_snapshot(error = TRUE, .compute_cmr_metrics(.cmr_pt, "1m", .cmr_rf, ann_factor = 12L,
                                                      basis_strategy = "Not A Strategy"))
})

test_that(".compute_cmr_metrics validates the label even on the n < 12 early-return path", {
  expect_error(.compute_cmr_metrics(.cmr_pt[1:5, ], "1m", .cmr_rf, ann_factor = 12L),
               "basis_strategy")
})
