# Tests for .bt_sharpe_rf() in R/plan_backtest.R (#677 slice 3)
#
# plan_backtest.R's targets (bt_metrics_is, bt_comparison,
# bt_replication_metrics, bt_oos_vs_is) previously used an arithmetic-mean
# numerator with a hardcoded 2%/yr rf_annual. .bt_sharpe_rf() replaces this
# with the canonical rf-adjusted geometric sharpe_ratio_rf() (R/utils_metrics.R),
# joined against the real Fama-French monthly rf (stk_rf target).
testthat::local_edition(3)

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_backtest.R"))

make_dates <- function(n) seq.Date(as.Date("2020-01-01"), by = "month", length.out = n)

make_stk_rf <- function(n, rf_ret = 0.0016) {
  tibble::tibble(ym = format(make_dates(n), "%Y-%m"), rf_ret = rep(rf_ret, n))
}

test_that(".bt_sharpe_rf matches sharpe_ratio_rf() exactly", {
  set.seed(11)
  r    <- rnorm(36, mean = 0.008, sd = 0.05)
  dts  <- make_dates(36)
  rf   <- make_stk_rf(36)

  result   <- .bt_sharpe_rf(dts, r, rf, ann_factor = 12L)
  expected <- sharpe_ratio_rf(r, rf$rf_ret, periods_per_year = 12L)$sharpe

  expect_equal(result, expected)
})

test_that(".bt_sharpe_rf differs from the old arithmetic/hardcoded-rf formula on a volatile fixture", {
  set.seed(12)
  r   <- rnorm(36, mean = 0.01, sd = 0.09)  # deliberately volatile
  dts <- make_dates(36)
  rf  <- make_stk_rf(36)

  new_sharpe <- .bt_sharpe_rf(dts, r, rf, ann_factor = 12L)

  # Old (pre-#677) formula: arithmetic mean numerator, hardcoded 2%/yr rf_annual.
  old_sharpe <- (mean(r) * 12 - 0.02) / (sd(r) * sqrt(12))

  expect_false(isTRUE(all.equal(new_sharpe, old_sharpe)))
})

test_that(".bt_sharpe_rf trims a trailing uncovered month and warns (Fama-French publication lag)", {
  r   <- rep(c(0.01, -0.005), 12)  # varying returns -- a constant series has zero variance
  dts <- make_dates(24)
  rf  <- make_stk_rf(24)[1:20, ]  # rf ends 4 months before returns

  expect_warning(result <- .bt_sharpe_rf(dts, r, rf, ann_factor = 12L), regexp = "Dropped")
  expect_true(is.finite(result))
})

test_that(".bt_sharpe_rf aborts on an INTERIOR gap (not a publication lag)", {
  r   <- rep(0.01, 24)
  dts <- make_dates(24)
  rf  <- make_stk_rf(24)
  rf  <- rf[-10, ]

  expect_snapshot(error = TRUE, .bt_sharpe_rf(dts, r, rf, ann_factor = 12L))
})

test_that(".bt_sharpe_rf aborts when stk_rf lacks required columns", {
  r      <- rep(0.01, 12)
  dts    <- make_dates(12)
  bad_rf <- tibble::tibble(ym = format(make_dates(12), "%Y-%m"))

  expect_snapshot(error = TRUE, .bt_sharpe_rf(dts, r, bad_rf, ann_factor = 12L))
})
