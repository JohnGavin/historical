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

# ── hd_trade_metrics: max_consecutive_losses is populated (#331) ─────────────

test_that("hd_trade_metrics: max_consecutive_losses is non-NA for any strategy with trades", {
  # Build a minimal monthly-strategy data frame with mixed wins and losses
  set.seed(77)
  n_months <- 24L
  monthly_ret <- tibble::tibble(
    date         = seq.Date(as.Date("2020-01-01"), by = "month", length.out = n_months),
    strategy_ret = c(rep(0.02, 6), rep(-0.01, 3), rep(0.015, 5),
                     rep(-0.008, 4), rep(0.01, 6))
  )
  trades  <- hd_monthly_trades(monthly_ret)
  metrics <- hd_trade_metrics(trades, ann_factor = 12L, n_years = n_months / 12)

  # Core contract: max_consecutive_losses must be a non-NA integer
  expect_false(is.na(metrics$max_consecutive_losses),
    info = "max_consecutive_losses should be populated for any strategy with trade data")
  expect_type(metrics$max_consecutive_losses, "integer")
  # With 3 and 4 consecutive loss runs, max must be >= 3
  expect_gte(metrics$max_consecutive_losses, 3L)
})

# ── hd_cdap: Coherent Drawdown-Adjusted Performance (#588) ──────────────────

test_that("hd_cdap: positive return matches conventional Calmar exactly", {
  expect_equal(hd_cdap(0.10, -0.05), 0.10 / 0.05)
  expect_equal(hd_cdap(0.30, -0.10), 0.30 / 0.10)
})

test_that("hd_cdap: negative return -- LARGER drawdown ranks WORSE (the #588 fix)", {
  # The defect: conventional cagr/abs(max_dd) would give -0.50 and -0.25
  # respectively, ranking the DEEPER drawdown "better". CDAP inverts this.
  shallow <- hd_cdap(-0.10, -0.20)
  deep    <- hd_cdap(-0.10, -0.40)

  expect_equal(shallow, -0.02)
  expect_equal(deep, -0.04)
  # The coherent ordering: identical return, deeper drawdown ranks worse
  # (more negative), never better.
  expect_lt(deep, shallow)
})

test_that("hd_cdap: zero drawdown returns NA (matches prior Calmar convention)", {
  expect_true(is.na(hd_cdap(0.10, 0)))
  expect_true(is.na(hd_cdap(-0.10, 0)))
})

test_that("hd_cdap: NA propagates", {
  expect_true(is.na(hd_cdap(NA_real_, -0.10)))
  expect_true(is.na(hd_cdap(0.10, NA_real_)))
})

test_that("hd_cdap: r == 0 returns 0, not NaN", {
  expect_equal(hd_cdap(0, -0.10), 0)
})

test_that("hd_cdap: vectorised over paired r/d, and d may be signed or magnitude", {
  r <- c(0.10, -0.10, -0.10, 0)
  d <- c(-0.05, -0.20, -0.40, -0.10)
  out <- hd_cdap(r, d)
  expect_equal(out, c(2, -0.02, -0.04, 0))
  # Passing the magnitude directly (unsigned d) gives the same result.
  expect_equal(hd_cdap(r, abs(d)), out)
})

test_that("hd_cdap: non-numeric inputs abort with an informative message", {
  expect_snapshot(error = TRUE, hd_cdap("not_numeric", -0.10))
  expect_snapshot(error = TRUE, hd_cdap(0.10, "not_numeric"))
})

test_that("hd_cdap: mismatched vector lengths abort", {
  expect_snapshot(error = TRUE, hd_cdap(c(0.1, 0.2, 0.3), c(-0.1, -0.2)))
})

test_that("hd_cdap: sign-behaviour snapshot pins the coherent ordering (#588)", {
  # A small grid spanning both signs and a range of drawdown depths --
  # this is the artefact a future change to the formula must explicitly
  # re-approve, per .claude/rules/snapshot-test-policy.md.
  grid <- expand.grid(
    r = c(-0.20, -0.10, 0, 0.10, 0.20),
    d = c(-0.05, -0.10, -0.20, -0.40)
  )
  out <- round(hd_cdap(grid$r, grid$d), 4)
  expect_snapshot(cat(paste(sprintf("r=%.2f d=%.2f -> cdap=%s", grid$r, grid$d, out), collapse = "\n")))
})
