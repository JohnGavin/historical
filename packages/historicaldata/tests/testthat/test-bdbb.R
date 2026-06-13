# Tests for BDBB M/G/∞ queueing diagnostics (#443 Phase 1)
#
# TDD: these tests are written before the implementation in R/bdbb.R.
# See also: half-life-decay rule — bdbb_half_life MUST use log(2)/theta.

# --- bdbb_half_life --------------------------------------------------------

test_that("bdbb_half_life gives exactly 0.5 weight at half-life", {
  theta <- log(2) / 10  # theta such that half-life = 10 hours
  expect_equal(bdbb_half_life(theta) * theta, log(2), tolerance = 1e-10)
  expect_equal(bdbb_half_life(theta), 10, tolerance = 1e-10)
})

test_that("bdbb_half_life uses log(2)/theta not 1/theta", {
  theta <- 0.5
  result <- bdbb_half_life(theta)
  expect_false(abs(result - 1 / theta) < 0.01)  # NOT the time constant
  expect_equal(result, log(2) / theta, tolerance = 1e-10)
})

# --- bdbb_fit schema -------------------------------------------------------

test_that("bdbb_fit returns expected schema on synthetic data", {
  set.seed(42)
  n <- 800L  # > 30 days * 24 hours = 720 bars
  times <- seq(as.POSIXct("2023-01-01", tz = "UTC"),
               by = "hour", length.out = n)
  # AR(1) with rho = 0.3 (mild mean reversion)
  eps <- rnorm(n, sd = 0.02)
  r <- stats::filter(eps, filter = 0.3, method = "recursive", sides = 1)
  prices <- exp(cumsum(as.numeric(r)))
  df <- tibble::tibble(
    time   = times,
    open   = prices,
    high   = prices * 1.001,
    low    = prices * 0.999,
    close  = prices * (1 + rnorm(n, sd = 0.001)),
    volume = abs(rnorm(n, mean = 1000, sd = 200)),
    trades = as.integer(abs(rnorm(n, mean = 50, sd = 10)))
  )
  result <- bdbb_fit(df)
  expect_s3_class(result, "tbl_df")
  expected_cols <- c(
    "window_end", "R", "theta", "half_life_hours",
    "signed_flow_mean", "amihud_mean", "kyle_mean",
    "n_obs", "regime"
  )
  expect_true(all(expected_cols %in% names(result)))
  expect_true(nrow(result) > 0)
  expect_true(all(result$n_obs > 0, na.rm = TRUE))
})

# --- Regime detection ------------------------------------------------------

test_that("bdbb_fit detects mean_reversion in AR(1) data", {
  set.seed(123)
  n <- 1200L
  times <- seq(as.POSIXct("2023-01-01", tz = "UTC"),
               by = "hour", length.out = n)
  # Strong AR(1) rho = 0.6
  eps <- rnorm(n, sd = 0.01)
  r <- stats::filter(eps, filter = 0.6, method = "recursive", sides = 1)
  prices <- exp(cumsum(as.numeric(r)))
  df <- tibble::tibble(
    time   = times, open = prices, high = prices * 1.001, low = prices * 0.999,
    close  = prices, volume = rep(1000, n), trades = rep(50L, n)
  )
  result <- bdbb_fit(df, window_days = 30L)
  mr_pct <- mean(result$regime == "mean_reversion", na.rm = TRUE)
  # With strong AR(1), at least 20% of windows should show mean reversion
  expect_gte(mr_pct, 0.2)
})

# --- Insufficient data -----------------------------------------------------

test_that("bdbb_fit handles insufficient observations gracefully", {
  df <- tibble::tibble(
    time   = seq(as.POSIXct("2023-01-01", tz = "UTC"),
                 by = "hour", length.out = 100),
    open   = 1, high = 1, low = 1, close = 1, volume = 1, trades = 1L
  )
  # window_days = 30 → needs 720 bars; only 100 → all rows should be NA
  result <- bdbb_fit(df, window_days = 30L)
  expect_equal(nrow(result), 0L)  # .complete = TRUE drops incomplete windows
})

# --- Snapshot: error on missing column -------------------------------------

test_that("bdbb_fit aborts informatively on missing column", {
  df <- tibble::tibble(time = Sys.time(), close = 1, volume = 1)
  expect_snapshot(error = TRUE, bdbb_fit(df))
})

# --- Snapshot: function signature stability --------------------------------

test_that("bdbb_fit signature is stable", {
  expect_snapshot(args(bdbb_fit))
})

# --- bdbb_tail_predict schema ----------------------------------------------

test_that("bdbb_tail_predict returns expected columns", {
  set.seed(99)
  n <- 200L
  diag_df <- tibble::tibble(
    window_end  = seq(as.POSIXct("2023-02-01", tz = "UTC"),
                      by = "hour", length.out = n),
    R           = abs(rnorm(n, 0.001, 0.0005)),
    amihud_mean = abs(rnorm(n, 0.0005, 0.0002)),
    kyle_mean   = abs(rnorm(n, 0.0003, 0.0001))
  )
  ret_df <- tibble::tibble(
    time    = diag_df$window_end + 3600,  # 1 hour later
    log_ret = rnorm(n, 0, 0.02)
  )
  result <- bdbb_tail_predict(diag_df, ret_df)
  expect_s3_class(result, "tbl_df")
  expect_true(all(c(
    "predictor", "p_extreme_high_tercile", "p_extreme_low_tercile", "spread_pp"
  ) %in% names(result)))
  expect_equal(nrow(result), 3L)  # R, amihud_mean, kyle_mean
})

test_that("bdbb_fit output column schema is stable", {
  set.seed(1L)
  n   <- 800L
  eps <- rnorm(n, sd = 0.01)
  ar1 <- as.numeric(stats::filter(eps, filter = 0.3, method = "recursive", sides = 1))
  df  <- tibble::tibble(
    time   = seq(as.POSIXct("2022-01-01", tz = "UTC"),
                 by = "1 hour", length.out = n),
    open   = 100 + cumsum(ar1),
    high   = open + abs(rnorm(n, sd = 0.5)),
    low    = open - abs(rnorm(n, sd = 0.5)),
    close  = open + ar1,
    volume = abs(rnorm(n, mean = 1000, sd = 200)),
    trades = as.integer(abs(rnorm(n, mean = 100, sd = 20)))
  )
  result <- bdbb_fit(df, window_days = 10L, min_frac = 0.5)
  expect_snapshot(names(result))
})

test_that("bdbb_half_life and bdbb_tail_predict signatures are stable", {
  expect_snapshot(args(bdbb_half_life))
  expect_snapshot(args(bdbb_tail_predict))
})
