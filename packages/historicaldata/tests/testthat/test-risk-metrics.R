test_that("hd_dd_duration: known synthetic drawdown", {
  # Construct a series with a clear drawdown:
  # obs 1-5: steady rise, obs 6-10: steady fall, obs 11-15: recovery above prior peak
  set.seed(123)
  returns <- c(rep(0.01, 5), rep(-0.025, 5), rep(0.03, 5))

  res <- hd_dd_duration(returns)

  expect_type(res, "list")
  expect_named(res, c("avg_dd_duration", "max_dd_duration", "n_drawdowns"))
  expect_gte(res$n_drawdowns, 1L)
  expect_true(!is.na(res$max_dd_duration))
  expect_true(!is.na(res$avg_dd_duration))
  # The drawdown runs for several observations
  expect_gte(res$max_dd_duration, 3)
})

test_that("hd_dd_duration: no drawdown returns n_drawdowns=0", {
  # Monotonically increasing series has no drawdown
  returns <- rep(0.01, 50)
  res <- hd_dd_duration(returns)
  expect_equal(res$n_drawdowns, 0L)
  expect_true(is.na(res$avg_dd_duration))
  expect_true(is.na(res$max_dd_duration))
})

test_that("hd_dd_duration: NA inputs removed without error", {
  returns <- c(0.01, NA, -0.05, -0.04, 0.03, 0.02, 0.02)
  expect_no_error(hd_dd_duration(returns))
})

test_that("hd_dd_duration: with dates returns calendar days", {
  returns <- c(rep(0.01, 5), rep(-0.03, 10), rep(0.02, 10))
  dates   <- seq.Date(as.Date("2020-01-01"), by = "month", length.out = 25)
  res_obs   <- hd_dd_duration(returns)
  res_dates <- hd_dd_duration(returns, dates = dates)

  # With monthly dates, duration should be in calendar days (larger than obs count)
  expect_gte(res_dates$max_dd_duration, res_obs$max_dd_duration)
})

test_that("hd_dd_duration: too-short series returns NA gracefully", {
  res <- hd_dd_duration(0.01)
  expect_true(is.na(res$avg_dd_duration))
  expect_true(is.na(res$max_dd_duration))
  expect_equal(res$n_drawdowns, 0L)
})

# ── hd_loss_clustering ────────────────────────────────────────────────────────

test_that("hd_loss_clustering: iid noise -> clustered = FALSE", {
  set.seed(42)
  r <- rnorm(200)
  res <- hd_loss_clustering(r)

  expect_type(res, "list")
  expect_named(res, c("runs_test_p", "acf_lag1", "clustered"))
  expect_false(isTRUE(res$clustered))
  # p-value should be > 0.05 most of the time for iid noise
  # (not guaranteed but highly likely with n=200 and set.seed(42))
  expect_true(is.na(res$clustered) || !isTRUE(res$clustered))
})

test_that("hd_loss_clustering: autocorrelated mixed-sign series -> clustered = TRUE", {
  # Create a strongly autocorrelated series with both positive and negative values:
  # AR(1) with phi=0.85 and noise centred near zero so we get mixed signs.
  # The high autocorrelation ensures runs_test_p < 0.05 and acf_lag1 > 0.2.
  set.seed(99)
  n    <- 300L
  r    <- numeric(n)
  r[1] <- 0.02
  for (i in seq(2L, n)) r[i] <- 0.85 * r[i - 1L] + rnorm(1, 0, 0.01)
  res <- hd_loss_clustering(r)

  expect_true(isTRUE(res$clustered))
  expect_lt(res$runs_test_p, 0.05)
  expect_gt(res$acf_lag1, 0.2)
})

test_that("hd_loss_clustering: too few observations returns NA", {
  res <- hd_loss_clustering(c(-0.01, 0.02, NA))
  expect_true(is.na(res$runs_test_p))
})

test_that("hd_loss_clustering: all NAs returns NA list", {
  res <- hd_loss_clustering(c(NA_real_, NA_real_))
  expect_true(is.na(res$runs_test_p))
  expect_true(is.na(res$acf_lag1))
  expect_true(is.na(res$clustered))
})

test_that("hd_loss_clustering: all same sign returns p=0 (degenerate single run)", {
  # All positive: only 1 run -> strongly significant clustering by convention
  set.seed(1)
  r <- abs(rnorm(50)) + 0.01
  res <- hd_loss_clustering(r)
  # Should not error; p = 0 for the degenerate all-same-sign case
  expect_false(is.na(res$runs_test_p))
  expect_equal(res$runs_test_p, 0)
})
