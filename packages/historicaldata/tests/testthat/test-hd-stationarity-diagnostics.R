# Tests for hd_stationarity_diagnostics() — ADF + ACF/Ljung-Box clustering
# diagnostics (#838)
#
# The ADF regression is implemented directly with stats::lm() (no tseries/
# urca package is available in this project's Nix environment -- see the
# roxygen "ADF implementation note"). Tests below verify: (1) the ADF
# statistic distinguishes a strongly mean-reverting series from a random
# walk (the property the test exists to detect, not merely "runs without
# error" -- see verification-before-completion.md's Type C trap), (2) the
# ACF/Ljung-Box output detects genuine autocorrelation, and (3) input
# validation aborts loudly per fail-loud-not-null.md.

test_that("a strongly mean-reverting AR(1) series is flagged stationary at 5%", {
  set.seed(42)
  x <- as.numeric(stats::arima.sim(list(ar = 0.3), n = 300))
  out <- hd_stationarity_diagnostics(x)
  expect_true(out$stationary_5pct)
  expect_lt(out$adf_statistic, out$adf_critical_values["5%"])
})

test_that("a random walk is NOT flagged stationary at 5%", {
  set.seed(42)
  x <- cumsum(stats::rnorm(300))
  out <- hd_stationarity_diagnostics(x)
  expect_false(out$stationary_5pct)
  expect_gt(out$adf_statistic, out$adf_critical_values["5%"])
})

test_that("adf_lag_order defaults to trunc((n-1)^(1/3)) when not supplied", {
  x <- as.numeric(stats::arima.sim(list(ar = 0.3), n = 100))
  out <- hd_stationarity_diagnostics(x)
  expect_equal(out$adf_lag_order, trunc((100 - 1)^(1 / 3)))
})

test_that("adf_lag_order can be overridden explicitly", {
  x <- as.numeric(stats::arima.sim(list(ar = 0.3), n = 100))
  out <- hd_stationarity_diagnostics(x, adf_lag_order = 2L)
  expect_equal(out$adf_lag_order, 2L)
})

test_that("acf_values has length acf_lags and matches stats::acf directly", {
  set.seed(7)
  x <- as.numeric(stats::arima.sim(list(ar = 0.5), n = 200))
  out <- hd_stationarity_diagnostics(x, acf_lags = 5L)
  expect_length(out$acf_values, 5L)
  expected <- as.numeric(stats::acf(x, lag.max = 5L, plot = FALSE)$acf[-1])
  expect_equal(out$acf_values, expected, tolerance = 1e-9)
})

test_that("a strongly autocorrelated series has a small Ljung-Box p-value", {
  set.seed(7)
  x <- as.numeric(stats::arima.sim(list(ar = 0.8), n = 300))
  out <- hd_stationarity_diagnostics(x)
  expect_lt(out$ljung_box_p_value, 0.01)
})

test_that("ljung_box_stat/p_value match stats::Box.test directly", {
  set.seed(7)
  x <- as.numeric(stats::arima.sim(list(ar = 0.5), n = 200))
  out <- hd_stationarity_diagnostics(x, acf_lags = 8L)
  expected <- stats::Box.test(x, lag = 8L, type = "Ljung-Box")
  expect_equal(out$ljung_box_stat, unname(expected$statistic), tolerance = 1e-9)
  expect_equal(out$ljung_box_p_value, unname(expected$p.value), tolerance = 1e-9)
})

test_that("non-finite values are dropped, counted, and warned about", {
  set.seed(1)
  x <- as.numeric(stats::arima.sim(list(ar = 0.3), n = 100))
  x[c(5, 50)] <- NA
  x[10] <- Inf
  expect_warning(
    out <- hd_stationarity_diagnostics(x),
    regexp = "Dropped 3 non-finite value"
  )
  expect_equal(out$n_dropped, 3L)
  expect_equal(out$n_obs, 97L)
})

# ── Input validation (fail-loud-not-null.md) ─────────────────────────────

test_that("non-numeric x aborts", {
  expect_snapshot(error = TRUE, hd_stationarity_diagnostics(c("a", "b", "c")))
})

test_that("a series with fewer than 20 finite observations aborts", {
  expect_snapshot(error = TRUE, hd_stationarity_diagnostics(stats::rnorm(10)))
})

test_that("acf_lags >= n_obs aborts", {
  expect_snapshot(error = TRUE, hd_stationarity_diagnostics(stats::rnorm(20), acf_lags = 20L))
})

test_that("a non-positive acf_lags aborts", {
  expect_snapshot(error = TRUE, hd_stationarity_diagnostics(stats::rnorm(30), acf_lags = 0L))
})

test_that("a negative adf_lag_order aborts", {
  expect_snapshot(error = TRUE, hd_stationarity_diagnostics(stats::rnorm(30), adf_lag_order = -1L))
})

test_that("an adf_lag_order too large for the sample aborts", {
  expect_snapshot(
    error = TRUE,
    hd_stationarity_diagnostics(stats::rnorm(20), adf_lag_order = 15L)
  )
})

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_stationarity_diagnostics))
})
