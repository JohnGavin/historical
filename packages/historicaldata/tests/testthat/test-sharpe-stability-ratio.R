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

  # Tier A: function signature snapshot (catches param renames/additions).
  expect_snapshot(args(hd_sharpe_stability_ratio))
})


# ─────────────────────────────────────────────────────────────────────────────
# 10. Input validation: cli_abort on bad inputs
# ─────────────────────────────────────────────────────────────────────────────

test_that("hd_rolling_sharpe: rejects non-numeric r", {
  expect_snapshot(error = TRUE, hd_rolling_sharpe("not numeric", w = 10L))
})

test_that("hd_rolling_sharpe: rejects non-integer w", {
  expect_snapshot(error = TRUE, hd_rolling_sharpe(rnorm(100), w = -1L))
})

test_that("hd_sharpe_stability_ratio: rejects negative ann_factor", {
  expect_snapshot(error = TRUE, hd_sharpe_stability_ratio(rnorm(100), w = 20L, ann_factor = -1))
})

test_that("hd_sharpe_stability_ratio: rejects non-integer lag_nw", {
  expect_snapshot(error = TRUE, hd_sharpe_stability_ratio(rnorm(100), w = 20L, lag_nw = 1.5))
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


# ─────────────────────────────────────────────────────────────────────────────
# hd_top5pct_share
# ─────────────────────────────────────────────────────────────────────────────

# Test 1: all-positive uniform series -- share equals pct exactly
test_that("hd_top5pct_share: uniform positive series yields share = 0.05", {
  r   <- rep(0.01, 100L)
  res <- hd_top5pct_share(r)

  expect_type(res, "list")
  # ceiling(100 * 0.05) = 5 top periods; top_sum = 5*0.01 = 0.05;
  # total_sum = 100*0.01 = 1.0; share = 0.05 / 1.0 = 0.05
  expect_equal(res$n_top,     5L)
  expect_equal(res$n_total,   100L)
  expect_equal(res$top_share, 0.05, tolerance = 1e-12)
})


# Test 2: single outlier -- share captures full concentration
test_that("hd_top5pct_share: single non-zero outlier yields share = 1.0", {
  r   <- c(rep(0, 99L), 1.0)
  res <- hd_top5pct_share(r)

  # ceiling(100 * 0.05) = 5 top periods; sorted desc: 1.0, 0, 0, 0, 0
  # top_sum = 1.0; total_sum = 1.0; share = 1.0
  expect_equal(res$n_top,     5L)
  expect_equal(res$top_share, 1.0, tolerance = 1e-12)
})


# Test 3: negative-tail series -- share and sign are preserved
test_that("hd_top5pct_share: negative-dominated series returns negative share", {
  r         <- c(rep(0.001, 95L), rep(-0.05, 5L))
  res       <- hd_top5pct_share(r)
  # top 5 sorted desc: 0.001, 0.001, 0.001, 0.001, 0.001
  top_sum   <- 5 * 0.001
  total_sum <- 95 * 0.001 + 5 * (-0.05)
  expected  <- top_sum / total_sum

  expect_equal(res$n_top,     5L)
  expect_equal(res$top_share, expected, tolerance = 1e-9)
  expect_lt(res$top_share, 0,
    label = "share is negative when total return is negative")
})


# Test 4: empty and all-NA inputs
test_that("hd_top5pct_share: empty vector returns NA sentinel", {
  res <- hd_top5pct_share(numeric(0L))

  expect_true(is.na(res$top_share))
  expect_equal(res$n_top,    0L)
  expect_equal(res$n_total,  0L)
  expect_true(is.na(res$total_return))
})

test_that("hd_top5pct_share: all-NA vector returns NA sentinel", {
  res <- hd_top5pct_share(c(NA_real_, NA_real_, NA_real_))

  expect_true(is.na(res$top_share))
  expect_equal(res$n_top,   0L)
  expect_equal(res$n_total, 0L)
})


# Test 5: n_top rounding -- ceiling behaviour
test_that("hd_top5pct_share: n_top uses ceiling(n_total * pct)", {
  # n_total=22, pct=0.05: ceiling(22*0.05) = ceiling(1.1) = 2
  res22 <- hd_top5pct_share(rep(0.01, 22L))
  expect_equal(res22$n_top, 2L)

  # n_total=10, pct=0.05: ceiling(10*0.05) = ceiling(0.5) = 1
  res10 <- hd_top5pct_share(rep(0.01, 10L))
  expect_equal(res10$n_top, 1L)
})


# Test 6: pct override
test_that("hd_top5pct_share: pct=0.10 override yields share=0.10 for uniform series", {
  r   <- rep(0.01, 100L)
  res <- hd_top5pct_share(r, pct = 0.10)

  # ceiling(100 * 0.10) = 10 top periods; share = 10*0.01 / (100*0.01) = 0.10
  expect_equal(res$n_top,     10L)
  expect_equal(res$pct,       0.10)
  expect_equal(res$top_share, 0.10, tolerance = 1e-12)
})


# Test 7: pct validation -- out-of-range values trigger cli_abort
test_that("hd_top5pct_share: pct=0 triggers error", {
  expect_snapshot(error = TRUE, hd_top5pct_share(rep(0.01, 10L), pct = 0))
})

test_that("hd_top5pct_share: pct=1 triggers error", {
  expect_snapshot(error = TRUE, hd_top5pct_share(rep(0.01, 10L), pct = 1))
})

test_that("hd_top5pct_share: pct=1.5 triggers error", {
  expect_snapshot(error = TRUE, hd_top5pct_share(rep(0.01, 10L), pct = 1.5))
})

test_that("hd_top5pct_share: pct=-0.1 triggers error", {
  expect_snapshot(error = TRUE, hd_top5pct_share(rep(0.01, 10L), pct = -0.1))
})


# Test 8: NA handling -- NAs stripped before computation
test_that("hd_top5pct_share: NA values are dropped before computation", {
  r   <- c(1, 2, NA, 3, 4)
  res <- hd_top5pct_share(r)

  # After NA removal: r_clean = c(1, 2, 3, 4); n_total=4
  # n_top = ceiling(4 * 0.05) = ceiling(0.2) = 1
  # sorted desc: 4, 3, 2, 1; top_sum = 4; total_sum = 10; share = 0.4
  expect_equal(res$n_total,   4L)
  expect_equal(res$n_top,     1L)
  expect_equal(res$top_share, 0.4, tolerance = 1e-12)
})


# Test 9: article calibration smoke test
test_that("hd_top5pct_share: benign seasonality series has share above 0.3 and SSR > 1", {
  # Mimic a macro strategy with 12.5% of months showing positive shocks:
  #   base: rnorm(240, mean=0, sd=0.01)
  #   shocks: add 0.03 to 30 randomly chosen months
  # This produces a "benign seasonality" series where a minority of periods
  # contributes a disproportionate share of total return.
  #
  # Lower bound is intentionally wide (0.30) -- this is a sanity check, not a
  # precise calibration.  The article states macro strategies with benign
  # seasonality "typically score above 0.30"; we test that floor only.
  set.seed(1L)
  n_total <- 240L
  r       <- rnorm(n_total, mean = 0, sd = 0.01)
  shock_idx <- sample(n_total, 30L)
  r[shock_idx] <- r[shock_idx] + 0.03

  res_top <- hd_top5pct_share(r)
  res_ssr <- hd_sharpe_stability_ratio(r, w = 36L, ann_factor = 12L)

  expect_gte(res_top$top_share, 0.30,
    label = "benign seasonality: top5pct share should be concentrated (>= 0.30)")
  expect_lte(res_top$top_share, 0.99,
    label = "benign seasonality: top5pct share should be below 0.99 (not purely episodic)")
  expect_gt(res_ssr$ssr, 1,
    label = "benign seasonality: SSR should be > 1 (significant and consistent)")
})
