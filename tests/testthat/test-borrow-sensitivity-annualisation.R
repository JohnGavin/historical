testthat::local_edition(3)
# #936: compute_borrow_sensitivity() annualised EVERY series as monthly
# (`12 / n`, `sqrt(12)`, `rate / 12`), but CMR's series (cmr_port$net_ret) is
# DAILY. The periodicity now travels with each series. Hermetic synthetic data.

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

test_that("a daily series is annualised on its own factor (252), not 12", {
  d <- make_daily_monthly()$daily
  out <- compute_borrow_sensitivity(d, ann_factor = 252)
  row0 <- out[out$borrow_rate_annual == 0, ]
  expect_equal(row0$vol, stats::sd(d) * sqrt(252), tolerance = 1e-12)
  expect_equal(row0$cagr, prod(1 + d)^(252 / length(d)) - 1, tolerance = 1e-12)
})

test_that("daily and monthly views of the same returns agree, each on its own factor", {
  s <- make_daily_monthly()
  out_d <- compute_borrow_sensitivity(s$daily, ann_factor = 252)
  out_m <- compute_borrow_sensitivity(s$monthly, ann_factor = 12)
  expect_equal(out_d$cagr[1], out_m$cagr[1], tolerance = 1e-9)
  # iid daily returns: monthly sd ~ sqrt(21) * daily sd; sampling error of a
  # 480-month sd is ~3%, so 15% is generous yet far inside the ~5x error.
  expect_equal(out_d$vol[1], out_m$vol[1], tolerance = 0.15)
  expect_equal(out_d$sharpe[1], out_m$sharpe[1], tolerance = 0.15)
  # The borrow charge is the same ANNUAL rate on both bases.
  expect_equal(out_d$cagr[out_d$borrow_rate_annual == 0.10],
               out_m$cagr[out_m$borrow_rate_annual == 0.10], tolerance = 0.01)
})

test_that("falsification: forcing the monthly factor on the daily series is clearly different", {
  # This is what the pre-#936 code did to CMR. The test must see it as wrong.
  d <- make_daily_monthly()$daily
  right <- compute_borrow_sensitivity(d, ann_factor = 252)
  wrong <- compute_borrow_sensitivity(d, ann_factor = 12)
  expect_gt(right$vol[1] / wrong$vol[1], 4)
  expect_gt(abs(right$cagr[1] - wrong$cagr[1]), 0.05)
})

test_that("ann_factor missing / invalid aborts naming the series", {
  r <- rep(c(0.01, -0.005), 12L)
  expect_error(compute_borrow_sensitivity(r), regexp = "ann_factor")
  for (bad in list(NA_real_, 0, -12, Inf, c(12, 252), "12")) {
    expect_error(compute_borrow_sensitivity(r, ann_factor = bad), regexp = "ann_factor")
  }
  expect_snapshot(error = TRUE, compute_borrow_sensitivity(r, series_label = "CMR"))
  expect_snapshot(error = TRUE, compute_borrow_sensitivity(r, ann_factor = 0, series_label = "CMR"))
})

test_that("build_borrow_sensitivity_table aborts naming a strategy with no ann_factor", {
  r <- rep(c(0.01, -0.005), 12L)
  expect_snapshot(
    error = TRUE,
    build_borrow_sensitivity_table(list("CMR" = r, "LTR" = r), c(LTR = 12))
  )
  expect_snapshot(error = TRUE, build_borrow_sensitivity_table(list("CMR" = r), 252))
})

test_that("mixed-periodicity table applies each strategy's own factor", {
  s <- make_daily_monthly()
  out <- build_borrow_sensitivity_table(
    list("CMR" = s$daily, "Mom" = s$monthly), c(CMR = 252, Mom = 12)
  )
  expect_equal(out$vol[out$strategy == "CMR" & out$borrow_rate_annual == 0],
               stats::sd(s$daily) * sqrt(252), tolerance = 1e-12)
  expect_equal(out$vol[out$strategy == "Mom" & out$borrow_rate_annual == 0],
               stats::sd(s$monthly) * sqrt(12), tolerance = 1e-12)
})

test_that("the sweep target's ann_factors come from strategy_names for all eight labels", {
  source(here::here("R/plan_strategy_names.R"))
  sn <- hd_strategy_names_tbl()
  labels <- c("Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "CMR",
              "Stock MAX", "Stock DRIF", "XGB DRIF", "LTR")
  af <- sn$ann_factor[match(labels, sn$short_name)]
  expect_false(anyNA(af))
  expect_equal(af, c(12L, 12L, 12L, 252L, 12L, 12L, 12L, 12L))
})
