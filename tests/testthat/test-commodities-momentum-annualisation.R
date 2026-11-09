testthat::local_edition(3)
# #1048 follow-up: the commodity momentum backtest runs on a DAILY date axis
# (median gap 1 day), so summarize_commodity_performance() must annualise with
# 252 bars/year, not 12. Before the fix it multiplied Sharpe by sqrt(12),
# converted rf with ^(1/12) and compounded annual_ret with ^12, understating
# the Sharpe by sqrt(252/12) = 4.58x and mis-stating annual_ret.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
suppressMessages(library(dplyr))
source(here::here("R/utils_metrics.R"))
if (!exists("summarize_commodity_performance", mode = "function")) {
  source(here::here("R/commodities_momentum.R"))
}

# Synthetic DAILY series with exactly known mean and sd: alternating
# mean +/- delta, so mean = 0.001 and sd = sd(c(0.011, -0.009)) repeated.
.daily_bt <- function(n = 500L) {
  ret <- rep(c(0.011, -0.009), length.out = n)
  tibble::tibble(
    date = seq(as.Date("2020-01-01"), by = "day", length.out = n),
    strategy = "baseline",
    portfolio_ret = ret, turnover = 0, cost = 0, net_ret = ret,
    n_positions = 20L
  )
}

test_that("annualised Sharpe on daily bars uses sqrt(252), not sqrt(12)", {
  bt  <- .daily_bt()
  r   <- bt$net_ret
  res <- summarize_commodity_performance(bt, annual_rf = 0.02,
                                         strategy = "Commodity Momentum L/S")
  # Excess-basis label: rf is not deducted, so Sharpe = mean/sd * sqrt(252).
  expect_equal(res$sharpe, mean(r) / stats::sd(r) * sqrt(252))
  expect_equal(res$gross_sharpe, mean(r) / stats::sd(r) * sqrt(252))
  # and it is NOT the old monthly annualisation
  expect_false(isTRUE(all.equal(res$sharpe, mean(r) / stats::sd(r) * sqrt(12))))
})

test_that("total-basis label converts annual rf to a DAILY rate", {
  bt  <- .daily_bt()
  r   <- bt$net_ret
  res <- summarize_commodity_performance(bt, annual_rf = 0.05, strategy = "Value (HML)")
  rf_daily <- (1 + 0.05)^(1 / 252) - 1
  expect_equal(res$sharpe, (mean(r) - rf_daily) / stats::sd(r) * sqrt(252))
})

test_that("annual_ret compounds the mean per-bar return over 252 bars", {
  bt  <- .daily_bt()
  res <- summarize_commodity_performance(bt, strategy = "Commodity Momentum L/S")
  expect_equal(res$annual_ret, (1 + mean(bt$net_ret))^252 - 1)
})

test_that("periods_per_year is overridable and validated", {
  bt <- .daily_bt()
  r  <- bt$net_ret
  m  <- summarize_commodity_performance(bt, strategy = "Commodity Momentum L/S",
                                        periods_per_year = 12L)
  expect_equal(m$sharpe, mean(r) / stats::sd(r) * sqrt(12))
  expect_error(
    summarize_commodity_performance(bt, strategy = "Commodity Momentum L/S",
                                    periods_per_year = 0),
    "periods_per_year"
  )
})
