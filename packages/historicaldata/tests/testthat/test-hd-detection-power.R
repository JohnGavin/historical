# Tests for hd_detection_power() — prospective detection power (#711 Gap 1)
#
# The function has an exact closed form (see its roxygen derivation), so
# every numeric test below independently recomputes the expected value from
# stats::qnorm()/stats::pnorm() rather than re-deriving the same code path —
# a mismatch here would mean the implementation drifted from the documented
# formula, not that the formula is wrong.
#
# The target_power = 0.5 special case is used heavily below because the
# closed form collapses to T_min = (qnorm(1 - alpha) / sr_period)^2 exactly
# (z_beta = 0 zeroes out the c1 term) — see the roxygen "Derivation" section.

test_that("min_n_periods at target_power = 0.5 matches the parameter-free closed form exactly", {
  for (sharpe_annual in c(0.3, 0.5, 1.0, 1.5)) {
    for (ann_factor in c(12, 252)) {
      alpha <- 0.05
      sr_period <- sharpe_annual / sqrt(ann_factor)
      expected_min_n <- (stats::qnorm(1 - alpha) / sr_period)^2

      out <- hd_detection_power(
        sharpe_annual = sharpe_annual, ann_factor = ann_factor,
        alpha = alpha, target_power = 0.5
      )
      expect_equal(out$min_n_periods, expected_min_n, tolerance = 1e-9)
    }
  }
})

test_that("min_n_years at target_power = 0.5 is exactly invariant to ann_factor", {
  sharpe_annual <- 0.6
  alpha <- 0.05
  years_12  <- hd_detection_power(sharpe_annual, ann_factor = 12,  alpha = alpha, target_power = 0.5)$min_n_years
  years_252 <- hd_detection_power(sharpe_annual, ann_factor = 252, alpha = alpha, target_power = 0.5)$min_n_years
  years_52  <- hd_detection_power(sharpe_annual, ann_factor = 52,  alpha = alpha, target_power = 0.5)$min_n_years

  expected <- (stats::qnorm(1 - alpha) / sharpe_annual)^2
  expect_equal(years_12,  expected, tolerance = 1e-9)
  expect_equal(years_252, expected, tolerance = 1e-9)
  expect_equal(years_52,  expected, tolerance = 1e-9)
})

test_that("min_n_years at target_power = 0.8 is approximately invariant to ann_factor", {
  # Not exact (c1 depends on sr_period, which differs by ann_factor), but the
  # c1 correction is small for realistic Sharpe ratios -- loose tolerance.
  sharpe_annual <- 0.6
  years_12  <- hd_detection_power(sharpe_annual, ann_factor = 12,  target_power = 0.8)$min_n_years
  years_252 <- hd_detection_power(sharpe_annual, ann_factor = 252, target_power = 0.8)$min_n_years
  expect_equal(years_12, years_252, tolerance = 0.02)
})

test_that("power formula matches an independently recomputed value", {
  sharpe_annual <- 0.5
  ann_factor <- 12
  n_obs <- 60
  alpha <- 0.05

  sr_period <- sharpe_annual / sqrt(ann_factor)
  z_alpha <- stats::qnorm(1 - alpha)
  c1 <- sqrt(1 + 0.5 * sr_period^2)
  se_h0 <- 1 / sqrt(n_obs)
  se_h1 <- c1 / sqrt(n_obs)
  expected_power <- stats::pnorm((sr_period - z_alpha * se_h0) / se_h1)

  out <- hd_detection_power(sharpe_annual, n_obs = n_obs, ann_factor = ann_factor, alpha = alpha)
  expect_equal(out$power, expected_power, tolerance = 1e-9)
})

test_that("power at n_obs == min_n_periods round-trips to approximately target_power", {
  out1 <- hd_detection_power(sharpe_annual = 0.7, ann_factor = 12, target_power = 0.80)
  out2 <- hd_detection_power(
    sharpe_annual = 0.7, n_obs = out1$min_n_periods, ann_factor = 12, target_power = 0.80
  )
  expect_equal(out2$power, 0.80, tolerance = 1e-6)
})

test_that("a short sample is correctly flagged as underpowered", {
  # Small annualised Sharpe (0.3) with only 12 months of monthly data --
  # this is exactly the cmr_summary / Testing-partition scenario #711
  # describes (3-year window, monthly commodity data).
  out <- hd_detection_power(sharpe_annual = 0.3, n_obs = 12, ann_factor = 12)
  expect_true(out$underpowered)
  expect_lt(out$power, 0.80)
  expect_lt(out$n_obs, out$min_n_periods)
})

test_that("a long sample is correctly flagged as adequately powered", {
  out <- hd_detection_power(sharpe_annual = 1.0, n_obs = 240, ann_factor = 12)
  expect_false(out$underpowered)
  expect_gte(out$power, 0.80)
})

test_that("n_obs = NULL returns NA power/underpowered but valid min_n fields", {
  out <- hd_detection_power(sharpe_annual = 0.5, ann_factor = 12)
  expect_true(is.na(out$power))
  expect_true(is.na(out$underpowered))
  expect_true(is.na(out$n_obs))
  expect_true(is.finite(out$min_n_periods))
  expect_true(is.finite(out$min_n_years))
})

test_that("larger claimed effect size requires fewer observations (monotonicity)", {
  n_small_effect <- hd_detection_power(sharpe_annual = 0.2, ann_factor = 12)$min_n_periods
  n_large_effect <- hd_detection_power(sharpe_annual = 1.0, ann_factor = 12)$min_n_periods
  expect_lt(n_large_effect, n_small_effect)
})

test_that("min_n_periods == min_n_years * ann_factor exactly (unit consistency)", {
  out <- hd_detection_power(sharpe_annual = 0.4, ann_factor = 252, target_power = 0.9, alpha = 0.01)
  expect_equal(out$min_n_periods, out$min_n_years * out$ann_factor, tolerance = 1e-9)
})

test_that("sharpe_period conversion matches sharpe_annual / sqrt(ann_factor)", {
  out <- hd_detection_power(sharpe_annual = 0.8, ann_factor = 252)
  expect_equal(out$sharpe_period, 0.8 / sqrt(252), tolerance = 1e-12)
})

# ── Input validation (fail-loud-not-null.md) ─────────────────────────────

test_that("non-positive sharpe_annual aborts with informative message", {
  expect_snapshot(error = TRUE, hd_detection_power(sharpe_annual = 0))
  expect_snapshot(error = TRUE, hd_detection_power(sharpe_annual = -0.5))
})

test_that("NA sharpe_annual aborts", {
  expect_snapshot(error = TRUE, hd_detection_power(sharpe_annual = NA_real_))
})

test_that("non-positive ann_factor aborts", {
  expect_snapshot(error = TRUE, hd_detection_power(sharpe_annual = 0.5, ann_factor = 0))
})

test_that("alpha outside (0, 1) aborts", {
  expect_snapshot(error = TRUE, hd_detection_power(sharpe_annual = 0.5, alpha = 0))
  expect_snapshot(error = TRUE, hd_detection_power(sharpe_annual = 0.5, alpha = 1))
})

test_that("target_power outside (0, 1) aborts", {
  expect_snapshot(error = TRUE, hd_detection_power(sharpe_annual = 0.5, target_power = 1))
})

test_that("n_obs < 2 aborts", {
  expect_snapshot(error = TRUE, hd_detection_power(sharpe_annual = 0.5, n_obs = 1))
})

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_detection_power))
})
