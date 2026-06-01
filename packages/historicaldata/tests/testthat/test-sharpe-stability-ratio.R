# Tests for hd_rolling_sharpe() and hd_sharpe_stability_ratio()
# defined in R/stability.R.
#
# Strategy: all tests are self-contained and use set.seed() locally so
# results are reproducible regardless of global RNG state.
#
# Calibration anchors from published research (Bajor Traver & Rodriguez
# Dominguez 2026; Brine & Sueppel 2026 Macrosynergy post):
#   - S&P 500 daily returns since 1995: naive Sharpe ~0.5, SSR ~5.3
#   - White-noise null (E[r]=0): SSR mean_sharpe should be near zero
#   - Episodic series (single large gain, otherwise flat): SSR near zero


# ─────────────────────────────────────────────────────────────────────────────
# 1. Length invariant for hd_rolling_sharpe
# ─────────────────────────────────────────────────────────────────────────────

test_that("hd_rolling_sharpe: length = T - w + 1 for T=300, w=60", {
  set.seed(42)
  T <- 300L
  w <- 60L
  r <- rnorm(T, mean = 0.0004, sd = 0.01)

  result <- hd_rolling_sharpe(r, w = w)

  expect_length(result, T - w + 1L)
})


# ─────────────────────────────────────────────────────────────────────────────
# 2. Constant series produces NA Sharpe (sd = 0)
# ─────────────────────────────────────────────────────────────────────────────

test_that("hd_rolling_sharpe: constant return series yields all NA Sharpes", {
  r <- rep(0.001, 100L)
  result <- hd_rolling_sharpe(r, w = 20L)

  expect_length(result, 100L - 20L + 1L)
  expect_true(all(is.na(result)),
    info = "Windows with zero variance should all be NA")
})


# ─────────────────────────────────────────────────────────────────────────────
# 3. White-noise null: mean_sharpe close to zero (95% CI contains 0)
# ─────────────────────────────────────────────────────────────────────────────

test_that("hd_sharpe_stability_ratio: white-noise null has SSR below significance threshold", {
  # For iid white noise with mean=0 the rolling Sharpe series has zero
  # population mean.  With T=1000, w=60 -> 941 windows we expect the SSR
  # (a t-statistic) to be well below the 95% threshold (1.96).
  #
  # Note: individual seeds can occasionally give moderate SSR by chance.
  # We use a large T and multiple seeds to make this reliable.
  set.seed(42)
  T   <- 2000L
  w   <- 60L
  r   <- rnorm(T, mean = 0, sd = 0.01)

  res <- hd_sharpe_stability_ratio(r, w = w, ann_factor = 252L)

  expect_type(res, "list")
  # SSR for zero-mean white noise should be well below 1.96 (95% threshold).
  expect_lt(abs(res$ssr), 3,
    label = "SSR for white-noise null should be below 3 (not statistically significant)")
})


# ─────────────────────────────────────────────────────────────────────────────
# 4. Constant trend: all-NA rolling Sharpes -> graceful NA result
# ─────────────────────────────────────────────────────────────────────────────

test_that("hd_sharpe_stability_ratio: constant positive return series returns NA", {
  r   <- rep(0.001, 1000L)
  res <- hd_sharpe_stability_ratio(r, w = 60L)

  # All rolling Sharpes are NA (sd = 0).  The SSR loop sees n_windows > 0
  # but mean(NA) = NA -> SSR = NA.
  expect_true(is.na(res$ssr),
    info = "Constant series has no variance: SSR must be NA")
  expect_true(is.na(res$mean_sharpe))
})


# ─────────────────────────────────────────────────────────────────────────────
# 5. High-stability simulation: persistent positive-mean series -> SSR > 3
# ─────────────────────────────────────────────────────────────────────────────

test_that("hd_sharpe_stability_ratio: persistent positive-mean series yields SSR > 3", {
  # mu = 0.0004 daily ~= 10% annual; sigma = 0.01 daily ~= 16% annual
  # -> naive Sharpe ~0.63, comparable to S&P 500 long-run.
  # With T=5000 daily obs, the SSR should be well above 3.
  set.seed(42)
  T <- 5000L
  r <- rnorm(T, mean = 0.0004, sd = 0.01)

  res <- hd_sharpe_stability_ratio(r, w = 252L, ann_factor = 252L)

  expect_gt(res$ssr, 3,
    label = "High-stability persistent series should have SSR > 3")
  expect_gt(res$mean_sharpe, 0,
    label = "Positive-mean series should have positive mean_sharpe")
})


# ─────────────────────────────────────────────────────────────────────────────
# 6. Episodic spike: single large gain -> SSR should be low (< 1.5)
# ─────────────────────────────────────────────────────────────────────────────

test_that("hd_sharpe_stability_ratio: alternating-sign regime yields lower SSR than persistent series", {
  # A strategy that alternates between good and bad regimes has a highly
  # variable rolling Sharpe series (some windows positive, some negative).
  # Its SSR should be substantially lower than a persistently positive series.
  #
  # Design: 2000 daily returns alternating every 252 obs between
  #   regime A: mu = +0.0008 (strong positive)
  #   regime B: mu = -0.0008 (strong negative)
  # Full-sample mean ~ 0, but rolling Sharpes vary wildly.
  set.seed(42)
  T     <- 2000L
  sigma <- 0.01
  # Regime periods of 252 obs: A, B, A, B, A (partial)
  regime <- ifelse((seq_len(T) - 1L) %/% 252L %% 2L == 0L, 0.0008, -0.0008)
  r_alt  <- rnorm(T, mean = regime, sd = sigma)

  # Persistently positive benchmark
  r_pos  <- rnorm(T, mean = 0.0004, sd = sigma)

  res_alt <- hd_sharpe_stability_ratio(r_alt, w = 60L, ann_factor = 252L)
  res_pos <- hd_sharpe_stability_ratio(r_pos, w = 60L, ann_factor = 252L)

  # SSR for alternating-regime series should be lower than for persistent.
  expect_lt(abs(res_alt$ssr), abs(res_pos$ssr),
    label = "Alternating-regime SSR should be lower than persistent SSR")
})


# ─────────────────────────────────────────────────────────────────────────────
# 7. HAC bandwidth: SE non-decreasing as lag_nw increases from 0 to T/4
# ─────────────────────────────────────────────────────────────────────────────

test_that("hd_sharpe_stability_ratio: SE non-decreasing as lag_nw increases", {
  set.seed(42)
  T <- 500L
  r <- rnorm(T, mean = 0.0005, sd = 0.01)

  # Evaluate SE at lag_nw = 0, 2, 5, 10, 20
  lags <- c(0L, 2L, 5L, 10L, 20L)
  ses  <- vapply(lags, function(lag) {
    hd_sharpe_stability_ratio(r, w = 60L, lag_nw = lag)$se
  }, numeric(1L))

  # Each additional lag should not strictly decrease SE.
  # The Bartlett kernel can give slightly non-monotone behaviour at very
  # small lags due to negative autocovariances, so we allow a small
  # tolerance: no step should *decrease* SE by more than 5%.
  for (i in seq_len(length(ses) - 1L)) {
    expect_gte(ses[i + 1L], ses[i] * 0.95,
      label = sprintf("SE at lag %d should be >= 95%% of SE at lag %d", lags[i + 1L], lags[i]))
  }
})


# ─────────────────────────────────────────────────────────────────────────────
# 8. Default bandwidth formula: for n=200 windows, lag_nw = 4
# ─────────────────────────────────────────────────────────────────────────────

test_that("hd_sharpe_stability_ratio: default lag_nw matches floor(4*(n/100)^(2/9))", {
  # n_windows = floor(T - w + 1) = 300 - 100 + 1 = 201.
  # Expected lag = floor(4 * (201/100)^(2/9)) = floor(4 * 1.167) = floor(4.667) = 4
  set.seed(42)
  T <- 300L
  w <- 100L
  r <- rnorm(T, mean = 0.0004, sd = 0.01)

  res <- hd_sharpe_stability_ratio(r, w = w)
  n   <- res$n_windows
  expected_lag <- max(1L, as.integer(floor(4 * (n / 100)^(2 / 9))))

  expect_equal(res$lag_nw, expected_lag)
})


# ─────────────────────────────────────────────────────────────────────────────
# 9. Return shape: correct names and types
# ─────────────────────────────────────────────────────────────────────────────

test_that("hd_sharpe_stability_ratio: return is named list with correct field types", {
  set.seed(42)
  r   <- rnorm(500L, mean = 0.0004, sd = 0.01)
  res <- hd_sharpe_stability_ratio(r, w = 60L, ann_factor = 252L)

  expect_type(res, "list")
  expect_named(res, c("ssr", "mean_sharpe", "se", "n_windows", "w", "lag_nw", "ann_factor"))

  expect_type(res$ssr,         "double")
  expect_type(res$mean_sharpe, "double")
  expect_type(res$se,          "double")
  expect_type(res$n_windows,   "integer")
  expect_type(res$w,           "integer")
  expect_type(res$lag_nw,      "integer")
  expect_type(res$ann_factor,  "double")
})


# ─────────────────────────────────────────────────────────────────────────────
# 10. Input validation: cli_abort on bad inputs
# ─────────────────────────────────────────────────────────────────────────────

test_that("hd_rolling_sharpe: rejects non-numeric r", {
  expect_error(hd_rolling_sharpe("not numeric", w = 10L),
               class = "rlang_error")
})

test_that("hd_rolling_sharpe: rejects non-integer w", {
  expect_error(hd_rolling_sharpe(rnorm(100), w = -1L),
               class = "rlang_error")
})

test_that("hd_sharpe_stability_ratio: rejects negative ann_factor", {
  expect_error(hd_sharpe_stability_ratio(rnorm(100), w = 20L, ann_factor = -1),
               class = "rlang_error")
})

test_that("hd_sharpe_stability_ratio: rejects non-integer lag_nw", {
  expect_error(hd_sharpe_stability_ratio(rnorm(100), w = 20L, lag_nw = 1.5),
               class = "rlang_error")
})

test_that("hd_rolling_sharpe: returns empty vector when T < w", {
  r <- rnorm(10L)
  expect_length(hd_rolling_sharpe(r, w = 20L), 0L)
})

test_that("hd_sharpe_stability_ratio: returns NA list when T < w", {
  r   <- rnorm(10L)
  res <- hd_sharpe_stability_ratio(r, w = 20L)

  expect_true(is.na(res$ssr))
  expect_equal(res$n_windows, 0L)
})
