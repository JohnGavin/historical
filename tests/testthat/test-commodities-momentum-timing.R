testthat::local_edition(3)
# #1048: backtest_commodity_momentum() must pair the signal measured at the
# end of month t with the return OVER month t+1 (one month ahead), not t+2.
#
# monthly_ret on the row dated t is the return over month t (value_t /
# value_{t-1} - 1, see calculate_commodity_returns()); build_commodity_signals()
# uses returns through t only. So the pairing is lead(monthly_ret) on the
# signal's own date.

suppressMessages(library(dplyr))
source(here::here("R/commodities_momentum.R"))

# Toy: 2 series x 4 month-ends. A always outranks B (long A, short B with
# n_long = n_short = 1, so weights +0.5 / -0.5).
.toy_dates <- as.Date(c("2020-01-31", "2020-02-29", "2020-03-31", "2020-04-30"))

.toy_returns <- tibble::tibble(
  date = rep(.toy_dates, 2),
  series_id = rep(c("A", "B"), each = 4),
  monthly_ret = c(0.01, 0.02, 0.03, 0.04,
                  -0.01, -0.02, -0.03, -0.04)
)

.toy_signals <- tibble::tibble(
  date = rep(.toy_dates, 2),
  series_id = rep(c("A", "B"), each = 4),
  mom_12d = rep(c(0.5, -0.5), each = 4),
  mom_3d = rep(c(0.5, -0.5), each = 4),
  mom_9d = rep(c(0.5, -0.5), each = 4),
  volatility_roll = 0.1,
  trend_strength = 0.5
)

test_that("signal at month t is paired with the month t+1 return (#1048)", {
  bt <- backtest_commodity_momentum(.toy_signals, .toy_returns,
                                    cost_bps = 0, n_long = 1, n_short = 1)
  base <- bt |> filter(strategy == "baseline") |> arrange(date)

  # Signals dated Jan, Feb, Mar get the Feb, Mar, Apr returns:
  # 0.5 * ret_A + 0.5 * -ret_B = 0.5*r + 0.5*r = r
  expect_equal(base$date, .toy_dates[1:3])
  expect_equal(base$portfolio_ret, c(0.02, 0.03, 0.04))
  expect_equal(base$net_ret, c(0.02, 0.03, 0.04))
})

test_that("turnover cost applies to the first month only on constant positions (#1048)", {
  bt <- backtest_commodity_momentum(.toy_signals, .toy_returns,
                                    cost_bps = 20, n_long = 1, n_short = 1)
  base <- bt |> filter(strategy == "baseline") |> arrange(date)

  # First month builds 0.5 long + 0.5 short from flat: turnover 0.5; then 0.
  expect_equal(base$turnover, c(0.5, 0, 0))
  expect_equal(base$net_ret, c(0.02 - 0.5 * 0.002, 0.03, 0.04))
})
