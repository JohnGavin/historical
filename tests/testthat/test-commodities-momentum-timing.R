testthat::local_edition(3)
# #1048: backtest_commodity_momentum() must pair the signal measured at the
# end of month t with the return OVER month t+1 (one month ahead), not t+2.
#
# monthly_ret on the row dated t is the return over month t (value_t /
# value_{t-1} - 1, see calculate_commodity_returns()); build_commodity_signals()
# uses returns through t only. So the pairing is lead(monthly_ret) on the
# signal's own date.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
suppressMessages(library(dplyr))
source(here::here("R/commodities_momentum.R"))

# Toy: 6 series x 4 month-ends (CMR's minimum breadth at tercile frac, #1061).
# A,B always outrank C,D, which outrank E,F: n_leg = 2, long A,B, short E,F,
# each name weighted 1/2 (each leg sums to 1). Long names earn +r, short names
# -r, so the book earns 0.5*(2r) - 0.5*(-2r) = 2r.
.toy_dates <- as.Date(c("2020-01-31", "2020-02-29", "2020-03-31", "2020-04-30"))
.toy_ids <- c("A", "B", "C", "D", "E", "F")
.toy_sig <- c(0.6, 0.5, 0.1, -0.1, -0.5, -0.6)
.toy_r <- c(0.01, 0.02, 0.03, 0.04)

.toy_returns <- tibble::tibble(
  date = rep(.toy_dates, 6),
  series_id = rep(.toy_ids, each = 4),
  monthly_ret = c(rep(.toy_r, 2), rep(0, 8), rep(-.toy_r, 2))
)

.toy_signals <- tibble::tibble(
  date = rep(.toy_dates, 6),
  series_id = rep(.toy_ids, each = 4),
  mom_12d = rep(.toy_sig, each = 4),
  mom_3d = rep(.toy_sig, each = 4),
  mom_9d = rep(.toy_sig, each = 4),
  volatility_roll = 0.1,
  trend_strength = 0.5
)

test_that("signal at month t is paired with the month t+1 return (#1048)", {
  bt <- backtest_commodity_momentum(.toy_signals, .toy_returns, cost_bps = 0)
  base <- bt |> filter(strategy == "baseline") |> arrange(date)

  # Signals dated Jan, Feb, Mar get the Feb, Mar, Apr returns: 2r.
  expect_equal(base$date, .toy_dates[1:3])
  expect_equal(base$portfolio_ret, 2 * c(0.02, 0.03, 0.04))
  expect_equal(base$net_ret, 2 * c(0.02, 0.03, 0.04))
})

test_that("turnover cost applies to the first month only on constant positions (#1048)", {
  bt <- backtest_commodity_momentum(.toy_signals, .toy_returns, cost_bps = 20)
  base <- bt |> filter(strategy == "baseline") |> arrange(date)

  # First month builds 2 x 0.5 long + 2 x 0.5 short from flat: turnover 1; then 0.
  expect_equal(base$turnover, c(1, 0, 0))
  expect_equal(base$net_ret, c(0.04 - 1 * 0.002, 0.06, 0.08))
})
