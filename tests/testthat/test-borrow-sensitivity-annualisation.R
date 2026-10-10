testthat::local_edition(3)
# #936: compute_borrow_sensitivity() annualised EVERY series as monthly
# (`12 / n`, `sqrt(12)`, `rate / 12`), but CMR's series (cmr_port$net_ret) is
# DAILY. Hermetic synthetic data only.

source(here::here("R/plan_cost_convention.R"))

# 40 "years" x 12 months x 21 trading days = exactly 252 days per year, so a
# daily series and its monthly aggregate cover the same span and prod(1 + r)
# is identical for both.
make_daily_monthly <- function(years = 40L, seed = 936L) {
  set.seed(seed)
  n_days <- years * 252L
  daily <- stats::rnorm(n_days, mean = 0.0004, sd = 0.01)
  month_id <- rep(seq_len(years * 12L), each = 21L)
  monthly <- vapply(split(daily, month_id), function(x) prod(1 + x) - 1, numeric(1))
  list(daily = daily, monthly = unname(monthly))
}

test_that("RED #936: a daily series is annualised on 252, not 12", {
  d <- make_daily_monthly()$daily
  out <- compute_borrow_sensitivity(d)
  row0 <- out[out$borrow_rate_annual == 0, ]
  expect_equal(row0$vol, stats::sd(d) * sqrt(252), tolerance = 1e-12)
  expect_equal(row0$cagr, prod(1 + d)^(252 / length(d)) - 1, tolerance = 1e-12)
})

test_that("RED #936: daily and monthly views of the same returns agree", {
  s <- make_daily_monthly()
  out_d <- compute_borrow_sensitivity(s$daily)
  out_m <- compute_borrow_sensitivity(s$monthly)
  expect_equal(out_d$cagr[1], out_m$cagr[1], tolerance = 1e-9)
  # iid daily returns: monthly sd ~ sqrt(21) * daily sd; sampling error of a
  # 480-month sd is ~3%, so 15% is generous yet far inside the 12x error.
  expect_equal(out_d$vol[1], out_m$vol[1], tolerance = 0.15)
  expect_equal(out_d$sharpe[1], out_m$sharpe[1], tolerance = 0.15)
})

test_that("RED #936: the CMR-like falsification case is clearly wrong today", {
  d <- make_daily_monthly()$daily
  wrong_vol <- compute_borrow_sensitivity(d)$vol[1]
  true_vol  <- stats::sd(d) * sqrt(252)
  # monthly-only code understates a daily vol by sqrt(252 / 12) ~ 4.6x
  expect_lt(abs(wrong_vol / true_vol - 1), 0.01)
})
