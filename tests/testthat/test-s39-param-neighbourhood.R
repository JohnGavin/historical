testthat::local_edition(3)
# Tests for compute_olmar_window_neighbourhood_sharpes() and
# check_param_neighbourhood() -- QA gate S39 (#849).
#
# hd_param_neighbourhood() itself (the plateau-vs-peak verdict logic) is
# unit-tested at the package level (packages/historicaldata/tests/testthat/
# test-hd_param_neighbourhood.R). These tests cover this repo's own
# abort/warn/inform consequence policy wrapped around it, and the
# OLMAR-1-specific sharpe computation, following the pattern in
# test-markov-diagonal-dominance.R.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_qa_gates.R"))

# ── compute_olmar_window_neighbourhood_sharpes() ───────────────────────────

# Synthetic mean-reverting price panel, mirroring packages/historicaldata/
# tests/testthat/test-olmar.R's make_mr_prices() helper, but with a `date`
# column so olmar_backtest()'s date-extraction path is exercised the same
# way the real olmar_prices target is (plan_olmar.R).
make_mr_prices_df <- function(n_days = 200L, n_assets = 4L, seed = 42L) {
  set.seed(seed)
  mat <- matrix(NA_real_, nrow = n_days, ncol = n_assets)
  for (j in seq_len(n_assets)) {
    p <- numeric(n_days)
    p[1L] <- 100
    for (i in 2:n_days) {
      p[i] <- p[i - 1] + (-0.5) * (p[i - 1] - 100) + rnorm(1, 0, 2)
    }
    mat[, j] <- pmax(p, 1)
  }
  dates <- seq(as.Date("2020-01-01"), by = "day", length.out = n_days)
  df <- as.data.frame(mat)
  names(df) <- paste0("T", seq_len(n_assets))
  cbind(date = dates, df)
}

make_daily_rf <- function(dates) {
  tibble::tibble(date = dates, rf_ret = 0.00005)
}

test_that("compute_olmar_window_neighbourhood_sharpes returns one Sharpe per window, named and ordered", {
  prices <- make_mr_prices_df(n_days = 150L)
  rf     <- make_daily_rf(prices$date)
  params <- list(window = 20L, epsilon = 5, leverage = 0.2, cost_bps = 5)

  out <- compute_olmar_window_neighbourhood_sharpes(prices, params, rf, half_width = 4L)

  expect_length(out, 9L)
  expect_equal(names(out), as.character(16:24))
  expect_true(all(is.finite(out) | is.na(out)))
})

test_that("compute_olmar_window_neighbourhood_sharpes respects half_width", {
  prices <- make_mr_prices_df(n_days = 150L)
  rf     <- make_daily_rf(prices$date)
  params <- list(window = 20L, epsilon = 5, leverage = 0.2, cost_bps = 5)

  out <- compute_olmar_window_neighbourhood_sharpes(prices, params, rf, half_width = 2L)

  expect_length(out, 5L)
  expect_equal(names(out), as.character(18:22))
})

# ── check_param_neighbourhood() ─────────────────────────────────────────────

test_that("check_param_neighbourhood is quiet and returns a plateau verdict for a broadly-similar neighbourhood", {
  windows <- 16:24
  sharpes <- c(0.97, 1.00, 0.98, 1.02, 1.00, 0.99, 1.01, 0.98, 1.00)

  out <- expect_no_message(
    check_param_neighbourhood(windows, sharpes, centre = 20, strategy_label = "TEST")
  )
  expect_equal(out$verdict, "plateau")
})

test_that("check_param_neighbourhood aborts on an un-acknowledged peak", {
  windows <- 16:24
  sharpes <- c(0.1, 0.1, 0.1, 0.1, 2.0, 0.1, 0.1, 0.1, 0.1)

  expect_error(
    check_param_neighbourhood(windows, sharpes, centre = 20, strategy_label = "TEST-PEAK"),
    regexp = "PEAK"
  )
  expect_snapshot(
    error = TRUE,
    check_param_neighbourhood(windows, sharpes, centre = 20, strategy_label = "TEST-PEAK")
  )
})

test_that("check_param_neighbourhood warns (does not abort) on an acknowledged peak", {
  windows <- 16:24
  sharpes <- c(0.1, 0.1, 0.1, 0.1, 2.0, 0.1, 0.1, 0.1, 0.1)

  expect_warning(
    out <- check_param_neighbourhood(
      windows, sharpes, centre = 20, strategy_label = "TEST-ACK",
      acknowledged = "TEST-ACK"
    ),
    regexp = "(?i)acknowledged"
  )
  expect_equal(out$verdict, "peak")
})

test_that("check_param_neighbourhood warns (does not abort) on an indeterminate verdict", {
  windows <- c(19, 20, 21)
  sharpes <- c(1.0, 1.0, 1.0)

  expect_warning(
    out <- check_param_neighbourhood(windows, sharpes, centre = 20, strategy_label = "TEST-INDET"),
    regexp = "INDETERMINATE"
  )
  expect_equal(out$verdict, "indeterminate")
})

test_that("an acknowledged peak never silently resembles a plateau", {
  windows <- 16:24
  sharpes <- c(0.1, 0.1, 0.1, 0.1, 2.0, 0.1, 0.1, 0.1, 0.1)

  out <- suppressWarnings(check_param_neighbourhood(
    windows, sharpes, centre = 20, strategy_label = "TEST-ACK2",
    acknowledged = "TEST-ACK2"
  ))
  expect_false(identical(out$verdict, "plateau"))
})
