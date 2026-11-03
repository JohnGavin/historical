testthat::local_edition(3)
source(here::here("R/utils_align.R"))

# Refs #657 (inner_join audit, row A9). `correlation_benchmark` used an exact-date
# inner_join of a strategy return series with DAILY SPY returns. For a MONTHLY
# strategy that pairs one month's return with a single day of SPY. The helper
# `align_to_benchmark()` compounds the benchmark to the strategy's return
# frequency before joining. Three outcomes: PASS (list returned), FAIL class
# (low coverage), INDETERMINATE class (cannot decide).
# Date-vs-POSIXct: data-validation-timeseries section 9.

make_spy_daily <- function(n_months = 120L, seed = 11L) {
  set.seed(seed)
  d <- seq(as.Date("2010-01-01"), by = "day", length.out = n_months * 31L)
  d <- d[as.integer(format(d, "%u")) <= 5L]
  tibble::tibble(date = d, spy_ret = stats::rnorm(length(d), 0.0004, 0.01))
}

spy_to_month <- function(spy) {
  ym <- format(spy$date, "%Y-%m")
  tapply(spy$spy_ret, ym, function(r) prod(1 + r) - 1)
}

make_monthly_strategy <- function(spy, beta = 0.5, noise = 0.004, seed = 12L) {
  mret <- spy_to_month(spy)
  # drop the last (possibly partial) month
  mret <- mret[-length(mret)]
  set.seed(seed)
  yms <- names(mret)
  month_end <- as.Date(vapply(yms, function(ym) {
    first <- as.Date(paste0(ym, "-01"))
    format(seq(first, by = "month", length.out = 2L)[2L] - 1L)
  }, character(1L)))
  tibble::tibble(
    date = month_end,
    strategy_ret = beta * as.numeric(mret) + stats::rnorm(length(mret), 0, noise)
  )
}

old_exact_date_cor <- function(strat, spy) {
  aligned <- dplyr::inner_join(strat, spy, by = "date")
  aligned <- dplyr::filter(aligned, !is.na(strategy_ret), !is.na(spy_ret))
  stats::cor(aligned$strategy_ret, aligned$spy_ret, use = "complete.obs")
}

# ── Characterisation: daily strategies must equal today's exact-date join ──────

test_that("daily strategy gives results identical to the old exact-date join", {
  spy <- make_spy_daily()
  set.seed(13L)
  strat <- tibble::tibble(
    date = spy$date,
    strategy_ret = 0.3 * spy$spy_ret + stats::rnorm(nrow(spy), 0, 0.01)
  )
  strat$strategy_ret[c(5L, 50L)] <- NA_real_

  res <- align_to_benchmark(strat, spy)

  expect_equal(res$frequency, "daily")
  expect_equal(
    stats::cor(res$aligned$strategy_ret, res$aligned$spy_ret),
    old_exact_date_cor(strat, spy)
  )
  expect_equal(res$n_matched, nrow(spy) - 2L)
  expect_equal(res$n_unmatched, 0L)
})

# ── PASS: monthly strategy recovers the known monthly correlation ──────────────

test_that("monthly strategy vs daily SPY recovers the true monthly correlation", {
  spy <- make_spy_daily()
  strat <- make_monthly_strategy(spy)

  res <- align_to_benchmark(strat, spy)

  mret <- spy_to_month(spy)
  expected <- stats::cor(strat$strategy_ret, as.numeric(mret[-length(mret)]))
  got <- stats::cor(res$aligned$strategy_ret, res$aligned$spy_ret)

  expect_equal(res$frequency, "monthly")
  expect_equal(got, expected)
  expect_gt(got, 0.9)
  expect_equal(res$n_matched, nrow(strat))
  expect_equal(res$n_strategy_periods, nrow(strat))
  expect_equal(res$n_unmatched, 0L)
})

test_that("the old exact-date join gives a near-zero value on the same monthly data", {
  spy <- make_spy_daily()
  strat <- make_monthly_strategy(spy)
  expect_lt(abs(old_exact_date_cor(strat, spy)), 0.45)
})

# ── FAIL: low coverage ─────────────────────────────────────────────────────────

test_that("low benchmark coverage raises the FAIL class", {
  spy <- make_spy_daily()
  strat <- make_monthly_strategy(spy)
  short_spy <- dplyr::filter(spy, date < as.Date("2013-01-01"))

  expect_error(
    align_to_benchmark(strat, short_spy),
    class = "hd_align_fail"
  )
  expect_snapshot(error = TRUE, align_to_benchmark(strat, short_spy))
})

# ── INDETERMINATE ──────────────────────────────────────────────────────────────

test_that("unknown frequency raises the INDETERMINATE class", {
  spy <- make_spy_daily()
  strat <- tibble::tibble(
    date = seq(as.Date("2010-01-31"), by = "100 days", length.out = 20L),
    strategy_ret = seq(-0.02, 0.02, length.out = 20L)
  )
  expect_error(align_to_benchmark(strat, spy), class = "hd_align_indeterminate")
  expect_snapshot(error = TRUE, align_to_benchmark(strat, spy))
})

test_that("POSIXct key on either side raises INDETERMINATE (Date vs POSIXct)", {
  spy <- make_spy_daily()
  strat <- make_monthly_strategy(spy)
  strat_ct <- dplyr::mutate(
    strat, date = as.POSIXct(paste(date, "23:59:59"), tz = "UTC")
  )
  spy_ct <- dplyr::mutate(spy, date = as.POSIXct(date, tz = "UTC"))

  expect_error(align_to_benchmark(strat_ct, spy), class = "hd_align_indeterminate")
  expect_error(align_to_benchmark(strat, spy_ct), class = "hd_align_indeterminate")
  expect_snapshot(error = TRUE, align_to_benchmark(strat_ct, spy))
})

test_that("an empty side raises INDETERMINATE", {
  spy <- make_spy_daily()
  strat <- make_monthly_strategy(spy)
  expect_error(
    align_to_benchmark(strat, spy[0L, ]),
    class = "hd_align_indeterminate"
  )
  expect_error(
    align_to_benchmark(strat[0L, ], spy),
    class = "hd_align_indeterminate"
  )
  expect_snapshot(error = TRUE, align_to_benchmark(strat[0L, ], spy))
})

test_that("duplicate strategy periods raise INDETERMINATE", {
  spy <- make_spy_daily()
  strat <- make_monthly_strategy(spy)
  strat <- dplyr::bind_rows(strat, strat[10L, ])
  expect_error(align_to_benchmark(strat, spy), class = "hd_align_indeterminate")
})
