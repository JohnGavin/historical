# Tests for .aw_sharpe_rf() in R/plan_avoid_worst.R (#677 slice 3)
#
# plan_avoid_worst.R's daily strategies (aw_metrics, aw_practical_sensitivity,
# aw_walkforward, aw_alpha_decay) previously used mean(r)/sd(r)*sqrt(252) --
# arithmetic-mean numerator AND no risk-free deduction at all.
# .aw_sharpe_rf() replaces this with the canonical rf-adjusted geometric
# sharpe_ratio_rf() (R/utils_metrics.R), joined against a real daily
# Fama-French rf series.
testthat::local_edition(3)

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_avoid_worst.R"))

make_dates <- function(n) seq.Date(as.Date("2020-01-02"), by = "day", length.out = n)

make_daily_rf <- function(n, rf_ret = 0.00006) {
  tibble::tibble(date = make_dates(n), rf_ret = rep(rf_ret, n))
}

test_that(".aw_sharpe_rf matches sharpe_ratio_rf() exactly", {
  set.seed(21)
  r   <- rnorm(300, mean = 0.0004, sd = 0.012)
  dts <- make_dates(300)
  rf  <- make_daily_rf(300)

  result   <- .aw_sharpe_rf(dts, r, rf, ann_factor = 252L)
  expected <- sharpe_ratio_rf(r, rf$rf_ret, periods_per_year = 252L)$sharpe

  expect_equal(result, expected)
})

test_that(".aw_sharpe_rf differs from the old arithmetic no-rf formula on a volatile fixture", {
  set.seed(22)
  r   <- rnorm(300, mean = 0.0006, sd = 0.02)  # deliberately volatile
  dts <- make_dates(300)
  rf  <- make_daily_rf(300)

  new_sharpe <- .aw_sharpe_rf(dts, r, rf, ann_factor = 252L)

  # Old (pre-#677) formula: arithmetic mean numerator, NO risk-free deduction.
  old_sharpe <- mean(r) / sd(r) * sqrt(252)

  # Direction is data-dependent (geometric vs arithmetic + rf-deduction can
  # net either way on a single random realisation) -- only assert the values
  # actually differ, matching the pattern in test-bt-sharpe-rf.R /
  # test-cmr-units.R / test-mom-prepeak-sharpe.R.
  expect_false(isTRUE(all.equal(new_sharpe, old_sharpe)))
})

test_that(".aw_sharpe_rf trims a trailing uncovered day and warns (Fama-French publication lag)", {
  r   <- rep(c(0.001, -0.0005), 50)  # varying returns -- a constant series has zero variance
  dts <- make_dates(100)
  rf  <- make_daily_rf(100)[1:90, ]  # rf ends 10 days before returns

  expect_warning(result <- .aw_sharpe_rf(dts, r, rf, ann_factor = 252L), regexp = "Dropped")
  expect_true(is.finite(result))
})

test_that(".aw_sharpe_rf aborts on an INTERIOR gap (not a publication lag)", {
  r   <- rep(0.001, 100)
  dts <- make_dates(100)
  rf  <- make_daily_rf(100)
  rf  <- rf[-50, ]  # remove a day from the middle of rf's own span

  expect_snapshot(error = TRUE, .aw_sharpe_rf(dts, r, rf, ann_factor = 252L))
})

test_that(".aw_sharpe_rf aborts when aw_daily_rf lacks required columns", {
  r      <- rep(0.001, 50)
  dts    <- make_dates(50)
  bad_rf <- tibble::tibble(date = make_dates(50))

  expect_snapshot(error = TRUE, .aw_sharpe_rf(dts, r, bad_rf, ann_factor = 252L))
})
