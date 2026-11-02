# Tests for .bt_sharpe_rf() in R/plan_backtest.R (#677 slice 3)
#
# plan_backtest.R's targets (bt_metrics_is, bt_comparison,
# bt_replication_metrics, bt_oos_vs_is) previously used an arithmetic-mean
# numerator with a hardcoded 2%/yr rf_annual. .bt_sharpe_rf() replaces this
# with the canonical rf-adjusted geometric sharpe_ratio_rf() (R/utils_metrics.R),
# joined against the real Fama-French monthly rf (stk_rf target).
testthat::local_edition(3)

# hd_rf_for_basis() / hd_return_basis_of() come from the package (#937).
pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

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

  result   <- .bt_sharpe_rf(dts, r, rf, "Defense First", ann_factor = 12L)
  expected <- sharpe_ratio_rf(r, rf$rf_ret, periods_per_year = 12L)$sharpe

  expect_equal(result, expected)
})

test_that(".bt_sharpe_rf differs from the old arithmetic/hardcoded-rf formula on a volatile fixture", {
  set.seed(12)
  r   <- rnorm(36, mean = 0.01, sd = 0.09)  # deliberately volatile
  dts <- make_dates(36)
  rf  <- make_stk_rf(36)

  new_sharpe <- .bt_sharpe_rf(dts, r, rf, "Defense First", ann_factor = 12L)

  # Old (pre-#677) formula: arithmetic mean numerator, hardcoded 2%/yr rf_annual.
  old_sharpe <- (mean(r) * 12 - 0.02) / (sd(r) * sqrt(12))

  expect_false(isTRUE(all.equal(new_sharpe, old_sharpe)))
})

test_that(".bt_sharpe_rf trims a trailing uncovered month and warns (Fama-French publication lag)", {
  r   <- rep(c(0.01, -0.005), 12)  # varying returns -- a constant series has zero variance
  dts <- make_dates(24)
  rf  <- make_stk_rf(24)[1:20, ]  # rf ends 4 months before returns

  expect_warning(result <- .bt_sharpe_rf(dts, r, rf, "Defense First", ann_factor = 12L), regexp = "Dropped")
  expect_true(is.finite(result))
})

test_that(".bt_sharpe_rf aborts on an INTERIOR gap (not a publication lag)", {
  r   <- rep(0.01, 24)
  dts <- make_dates(24)
  rf  <- make_stk_rf(24)
  rf  <- rf[-10, ]

  expect_snapshot(error = TRUE, .bt_sharpe_rf(dts, r, rf, "Defense First", ann_factor = 12L))
})

test_that(".bt_sharpe_rf aborts when stk_rf lacks required columns", {
  r      <- rep(0.01, 12)
  dts    <- make_dates(12)
  bad_rf <- tibble::tibble(ym = format(make_dates(12), "%Y-%m"))

  expect_snapshot(error = TRUE, .bt_sharpe_rf(dts, r, bad_rf, "Defense First", ann_factor = 12L))
})

# ---- #937 item 4 row 1: rf routed through the return-basis registry --------
# Defense First (4 hedge ETFs at 40/30/20/10 weights, or 100% SPY on the
# fallback) and its SPY benchmark are fully invested, so both are TOTAL-basis
# series and the raw rf stays deducted. Registered, not assumed.
SPY_LABEL <- "Research: SPY buy and hold (Defense First benchmark)"

test_that("#937: Defense First and its SPY benchmark are registered TOTAL-basis rows", {
  expect_identical(hd_return_basis_of("Defense First"), "total")
  expect_identical(hd_return_basis_of(SPY_LABEL), "total")
  reg <- hd_return_basis()
  for (lab in c("Defense First", SPY_LABEL)) {
    expect_true(grepl("R/plan_backtest\\.R:[0-9]", reg$evidence[reg$strategy == lab]), info = lab)
  }
})

test_that("#937: .bt_sharpe_rf keeps rf for a total-basis label (value unchanged)", {
  set.seed(31)
  r   <- rnorm(36, mean = 0.008, sd = 0.05)
  dts <- make_dates(36)
  rf  <- make_stk_rf(36)
  expected <- sharpe_ratio_rf(r, rf$rf_ret, periods_per_year = 12L)$sharpe
  expect_equal(.bt_sharpe_rf(dts, r, rf, "Defense First", ann_factor = 12L), expected)
  expect_equal(.bt_sharpe_rf(dts, r, rf, SPY_LABEL, ann_factor = 12L), expected)
})

test_that("#937: .bt_sharpe_rf routes through the registry (an excess label deducts no rf)", {
  # Falsification: a label the registry classifies EXCESS must change the
  # result, proving the label drives the rf and is not ignored.
  set.seed(32)
  r   <- rnorm(36, mean = 0.008, sd = 0.05)
  dts <- make_dates(36)
  rf  <- make_stk_rf(36)
  total  <- .bt_sharpe_rf(dts, r, rf, "Defense First", ann_factor = 12L)
  excess <- .bt_sharpe_rf(dts, r, rf, "Mom 12-2", ann_factor = 12L)
  expect_equal(excess, sharpe_ratio_rf(r, rep(0, 36), periods_per_year = 12L)$sharpe)
  expect_false(isTRUE(all.equal(total, excess)))
})

test_that("#937: .bt_sharpe_rf aborts on an unregistered strategy label (never a silent default)", {
  r   <- rep(c(0.01, -0.005), 12)
  expect_error(
    .bt_sharpe_rf(make_dates(24), r, make_stk_rf(24), "Not A Strategy", ann_factor = 12L),
    "not registered"
  )
})
