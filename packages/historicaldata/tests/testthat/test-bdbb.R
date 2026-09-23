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

# --- Kyle's lambda regression fix (#624) ------------------------------------
#
# Prior to #624, kyle_lambda was `abs(log_ret) / pmax(volume, 1e-8)` — the
# exact same expression as amihud, so kyle_mean and amihud_mean were always
# numerically identical. Kyle's lambda is a price-impact *coefficient* (the
# regression slope of returns on signed order flow), not a per-bar ratio.
# These tests guard the fixed behaviour.

test_that("kyle_mean is no longer identical to amihud_mean when flow direction varies", {
  set.seed(624L)
  n <- 200L
  times <- seq(as.POSIXct("2023-01-01", tz = "UTC"), by = "hour", length.out = n)
  # Alternate signed flow direction and vary magnitude so amihud (a ratio of
  # |log_ret| to volume) and the Kyle regression slope diverge.
  sign_flow <- rep(c(1, -1), length.out = n)
  vol       <- abs(rnorm(n, mean = 1000, sd = 300)) + 50
  eps       <- rnorm(n, sd = 0.01)
  close     <- 100 * exp(cumsum(eps))
  open      <- close - sign_flow * 1e-3  # exact sign(close - open) == sign_flow
  df <- tibble::tibble(
    time = times, open = open, high = pmax(open, close) * 1.001,
    low  = pmin(open, close) * 0.999, close = close, volume = vol,
    trades = 50L
  )
  result <- bdbb_fit(df, window_days = 5L, min_frac = 0.5)
  computed <- dplyr::filter(result, !is.na(kyle_mean), !is.na(amihud_mean))
  expect_true(nrow(computed) > 0)
  # The two series must differ somewhere -- this is the regression guard for
  # the exact duplication bug fixed in #624.
  expect_false(isTRUE(all.equal(computed$kyle_mean, computed$amihud_mean)))
})

test_that("kyle_mean recovers a known regression slope on synthetic data", {
  set.seed(625L)
  n     <- 100L
  beta  <- 1.5e-6  # true price-impact coefficient
  times <- seq(as.POSIXct("2023-01-01", tz = "UTC"), by = "hour", length.out = n)

  # Freely choose desired signed_flow values, then back out volume/open/close
  # so the realised signed_flow and log_ret match the design exactly (up to
  # tiny numerical noise), letting us recover beta via OLS.
  desired_flow <- rnorm(n, mean = 0, sd = 800)
  sign_flow    <- sign(desired_flow)
  sign_flow[sign_flow == 0] <- 1
  vol          <- pmax(abs(desired_flow), 1)  # volume_t = |desired_flow_t|
  desired_flow <- sign_flow * vol             # exact signed_flow after rounding

  noise  <- rnorm(n, sd = 1e-8)  # negligible relative to beta * desired_flow
  logret <- beta * desired_flow + noise
  logret[1] <- 0  # first bar's log_ret is NA regardless (no lag); placeholder
  close  <- 100 * exp(cumsum(logret))
  open   <- close - sign_flow * 1e-6  # exact sign(close - open) == sign_flow

  df <- tibble::tibble(
    time = times, open = open, high = pmax(open, close) * 1.0001,
    low  = pmin(open, close) * 0.9999, close = close, volume = vol,
    trades = 50L
  )
  result <- bdbb_fit(df, window_days = 4L, min_frac = 0.9)
  kyle_vals <- result$kyle_mean[!is.na(result$kyle_mean)]
  expect_true(length(kyle_vals) > 0)
  # Recovered slope should be close to the true beta used to generate the data.
  expect_equal(kyle_vals, rep(beta, length(kyle_vals)), tolerance = 0.05)
})

test_that("kyle_mean is NA when window flow is zero-variance (flat)", {
  set.seed(626L)
  n <- 100L
  times <- seq(as.POSIXct("2023-01-01", tz = "UTC"), by = "hour", length.out = n)
  # Constant sign and constant volume -> signed_flow is identical every bar.
  close <- 100 * exp(cumsum(rnorm(n, sd = 0.01)))
  df <- tibble::tibble(
    time = times, open = close - 1e-3, high = close * 1.001,
    low  = close * 0.999, close = close, volume = 1000, trades = 50L
  )
  result <- bdbb_fit(df, window_days = 4L, min_frac = 0.9)
  expect_true(nrow(result) > 0)
  expect_true(all(is.na(result$kyle_mean)))
  # R and amihud are unaffected by flat flow (they don't divide by var(flow)).
  expect_true(any(!is.na(result$amihud_mean)))
})

test_that("kyle_mean is NA when too few paired observations, even though R/amihud compute", {
  set.seed(627L)
  n <- 200L
  times <- seq(as.POSIXct("2023-01-01", tz = "UTC"), by = "hour", length.out = n)
  eps   <- rnorm(n, sd = 0.01)
  close <- 100 * exp(cumsum(eps))
  vol   <- abs(rnorm(n, mean = 1000, sd = 200)) + 50
  # NA out 25% of volume (scattered) -- log_ret coverage is unaffected (only
  # the first bar is NA by construction), but paired (log_ret, signed_flow)
  # coverage drops below the stricter 0.9 kyle gate while staying above the
  # 0.5 min_frac gate used for the row as a whole.
  na_idx      <- sample(seq_len(n), size = floor(0.25 * n))
  vol[na_idx] <- NA_real_
  df <- tibble::tibble(
    time = times, open = close - 1e-3, high = close * 1.001,
    low  = close * 0.999, close = close, volume = vol, trades = 50L
  )
  result <- bdbb_fit(df, window_days = 4L, min_frac = 0.5)
  expect_true(nrow(result) > 0)
  expect_true(all(is.na(result$kyle_mean)))
  expect_true(any(!is.na(result$R)))
  expect_true(any(!is.na(result$amihud_mean)))
})

# --- bdbb_tail_predict look-ahead fix (#868) -------------------------------
#
# Defect 1 (contemporaneous join) and Defect 2 (full-sample threshold) are
# both covered by .bdbb_score_next_return() -- the internal helper
# bdbb_tail_predict() now builds its extreme-move flags from. These tests
# exercise that helper directly plus the attribute bdbb_tail_predict()
# attaches to its return value.

test_that(".bdbb_score_next_return scores the NEXT bar, never the bar at window_end", {
  times <- seq(as.POSIXct("2023-01-01", tz = "UTC"), by = "hour", length.out = 10L)
  log_ret <- c(NA_real_, seq(0.001, 0.009, by = 0.001))
  returns_df <- tibble::tibble(time = times, log_ret = log_ret)
  scored <- .bdbb_score_next_return(returns_df)
  row5 <- dplyr::filter(scored, window_end == times[5])

  expect_equal(row5$next_time, times[6])
  expect_equal(row5$next_log_ret, log_ret[6])
  expect_false(isTRUE(row5$next_log_ret == log_ret[5]))
})

test_that(".bdbb_score_next_return next_log_ret is invariant to perturbing the window_end bar itself (regression, #868)", {
  times <- seq(as.POSIXct("2023-01-01", tz = "UTC"), by = "hour", length.out = 10L)
  log_ret <- c(NA_real_, rep(0.001, 9L))
  returns_df <- tibble::tibble(time = times, log_ret = log_ret)

  window_end_idx <- 5L
  scored_before <- .bdbb_score_next_return(returns_df)
  before_row <- dplyr::filter(scored_before, window_end == times[window_end_idx])

  # Perturb ONLY the bar AT window_end -- exactly the perturbation #868
  # empirically verified moves R for the pre-fix contemporaneous join.
  returns_df_perturbed <- returns_df
  returns_df_perturbed$log_ret[window_end_idx] <- log_ret[window_end_idx] + 10
  scored_after <- .bdbb_score_next_return(returns_df_perturbed)
  after_row <- dplyr::filter(scored_after, window_end == times[window_end_idx])

  # The value being scored is the NEXT bar return -- perturbing the bar AT
  # window_end must not change it. This is exactly what the pre-#868 join
  # got wrong (see the origin/main falsification test below).
  expect_equal(before_row$next_log_ret, after_row$next_log_ret)
  expect_true(before_row$next_time > times[window_end_idx])
})

test_that("the pre-#868 join on origin/main was contemporaneous (falsification)", {
  skip_on_cran()
  old_src <- tryCatch(
    system2("git", c("show", "origin/main:packages/historicaldata/R/bdbb.R"),
            stdout = TRUE, stderr = TRUE),
    error = function(e) character(0)
  )
  skip_if(
    length(old_src) == 0L || any(grepl("^fatal:", old_src)),
    "origin/main not reachable in this checkout (offline/shallow clone)"
  )
  # Confirm this test targets the SAME join #868 diagnosed, not a hand-typed
  # stand-in: if this literal string is absent, either the fix already
  # landed on origin/main, or the join was refactored under a different
  # name -- either way a hand-written reproduction would misrepresent
  # origin/main and must not be trusted.
  join_line <- grep(
    "join_by(window_end == time)", old_src, fixed = TRUE, value = TRUE
  )
  skip_if(
    length(join_line) == 0L,
    "origin/main bdbb_tail_predict() no longer contains the pre-#868 join -- already fixed"
  )

  # Reproduce EXACTLY that join (verified present in old_src above) against
  # returns data where the bar AT window_end and the bar AFTER window_end
  # carry deliberately different log_ret values.
  window_end <- as.POSIXct("2023-01-01 05:00:00", tz = "UTC")
  returns_df <- tibble::tibble(
    time    = window_end + c(0, 3600),
    log_ret = c(0.001, 0.999)  # [bar AT window_end, bar AFTER window_end]
  )
  diag_df <- tibble::tibble(window_end = window_end)

  joined_old <- dplyr::left_join(
    diag_df, returns_df, by = dplyr::join_by(window_end == time)
  )
  # The pre-#868 join resolves to the SAME-CLOCK bar (0.001), not the next
  # one (0.999) -- contemporaneous, exactly as #868 reports.
  expect_equal(joined_old$log_ret, 0.001)

  # Perturbing ONLY the bar at window_end changes what the old join scores
  # -- the exact defect #868 fixes.
  returns_df_perturbed <- returns_df
  returns_df_perturbed$log_ret[1] <- 0.001 + 10
  joined_old_perturbed <- dplyr::left_join(
    diag_df, returns_df_perturbed, by = dplyr::join_by(window_end == time)
  )
  expect_false(isTRUE(all.equal(joined_old$log_ret, joined_old_perturbed$log_ret)))
})

test_that(".bdbb_score_next_return threshold_90_asof is NA below the minimum-observations floor", {
  n <- 150L
  times <- seq(as.POSIXct("2023-01-01", tz = "UTC"), by = "hour", length.out = n)
  set.seed(868L)
  log_ret <- c(NA_real_, stats::rnorm(n - 1L, sd = 0.01))
  returns_df <- tibble::tibble(time = times, log_ret = log_ret)
  scored <- .bdbb_score_next_return(returns_df)

  below_floor <- dplyr::filter(scored, n_obs_asof < 100L)
  at_or_above_floor <- dplyr::filter(scored, n_obs_asof >= 100L)

  expect_true(all(is.na(below_floor$threshold_90_asof)))
  expect_true(any(!is.na(at_or_above_floor$threshold_90_asof)))
})

test_that(".bdbb_score_next_return threshold_90_asof at an early row is unaffected by a later outlier (Defect 2 regression, #868)", {
  n <- 200L
  times <- seq(as.POSIXct("2023-01-01", tz = "UTC"), by = "hour", length.out = n)
  set.seed(869L)
  log_ret <- c(NA_real_, stats::rnorm(n - 1L, sd = 0.001))
  returns_df <- tibble::tibble(time = times, log_ret = log_ret)

  scored_before <- .bdbb_score_next_return(returns_df)
  row_120_before <- dplyr::filter(scored_before, window_end == times[120])

  # A huge outlier placed AFTER row 120 (row 150) must not move the
  # threshold computed as-of row 120 -- a full-sample quantile (the pre-
  # #868 behaviour) would move; a trailing/expanding one must not.
  returns_df_future_outlier <- returns_df
  returns_df_future_outlier$log_ret[150] <- 5
  scored_after <- .bdbb_score_next_return(returns_df_future_outlier)
  row_120_after <- dplyr::filter(scored_after, window_end == times[120])

  expect_equal(row_120_before$threshold_90_asof, row_120_after$threshold_90_asof)

  # But the threshold as-of row 160 (which now includes the outlier at row
  # 150) DOES change -- confirming the outlier is visible once it is
  # actually in the past, and the invariance above is not a no-op.
  row_160_before <- dplyr::filter(scored_before, window_end == times[160])
  row_160_after  <- dplyr::filter(scored_after,  window_end == times[160])
  expect_false(isTRUE(all.equal(row_160_before$threshold_90_asof, row_160_after$threshold_90_asof)))
})

test_that(".bdbb_score_next_return aborts informatively on a returns_df missing required columns", {
  expect_snapshot(error = TRUE, .bdbb_score_next_return(tibble::tibble(time = Sys.time())))
})

test_that(".bdbb_score_next_return signature is stable", {
  expect_snapshot(args(.bdbb_score_next_return))
})

test_that("bdbb_tail_predict attaches a bdbb_scored_windows attribute with the join it used", {
  set.seed(868L)
  n <- 200L
  times <- seq(as.POSIXct("2023-01-01", tz = "UTC"), by = "hour", length.out = n)
  diag_df <- tibble::tibble(
    window_end  = times,
    R           = abs(stats::rnorm(n, 0.001, 0.0005)),
    amihud_mean = abs(stats::rnorm(n, 0.0005, 0.0002)),
    kyle_mean   = abs(stats::rnorm(n, 0.0003, 0.0001))
  )
  log_ret <- c(NA_real_, stats::rnorm(n - 1L, sd = 0.01))
  ret_df <- tibble::tibble(time = times, log_ret = log_ret)

  result <- bdbb_tail_predict(diag_df, ret_df)
  scored <- attr(result, "bdbb_scored_windows")

  expect_true(is.data.frame(scored))
  expect_true(all(c(
    "window_end", "next_time", "next_log_ret", "threshold_90_asof",
    "n_obs_asof", "extreme"
  ) %in% names(scored)))
  scoreable <- dplyr::filter(scored, !is.na(next_time))
  expect_true(all(scoreable$next_time > scoreable$window_end))
})
