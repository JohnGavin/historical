# Tests for the #588 G2/G3 mechanical stop-rule engine.
#
# Synthetic fixtures only -- no live data, no targets store (this package's
# tests must be hermetic; see hermetic-test-fixtures memory). The
# whipsaw-destroys-expectancy fixture is a deliberately manufactured
# V-shaped drawdown-then-full-recovery series: it exists to demonstrate the
# mechanism Varma's article describes (a static stop locks out the rebound),
# not to claim anything about a real strategy -- that requires
# scripts/build.sh in the main checkout against real strategy return series.

# ── hd_drawdown() ────────────────────────────────────────────────────────

test_that("hd_drawdown computes equity/peak/dd correctly on a known series", {
  ret <- c(0.10, -0.20, 0.05, 0.30)
  out <- hd_drawdown(ret)
  equity_expected <- cumprod(1 + ret)
  expect_equal(out$equity, equity_expected)
  expect_equal(out$peak, cummax(equity_expected))
  expect_equal(out$dd, equity_expected / cummax(equity_expected) - 1)
  # First period never below its own peak
  expect_equal(out$dd[1], 0)
  # dd is always <= 0
  expect_true(all(out$dd <= 0))
})

test_that("hd_drawdown rejects non-numeric or NA input", {
  expect_snapshot(error = TRUE, hd_drawdown("not numeric"))
  expect_snapshot(error = TRUE, hd_drawdown(c(0.1, NA, 0.2)))
})


# ── hd_stop_rule_backtest() ─────────────────────────────────────────────

test_that("threshold = -Inf (no-stop arm) reproduces ret exactly", {
  set.seed(1)
  ret <- rnorm(24, mean = 0.01, sd = 0.05)
  out <- hd_stop_rule_backtest(ret, threshold = -Inf)
  expect_equal(out$ret_net, ret)
  expect_true(all(out$exposed))
  expect_equal(out$n_stops, 0L)
  expect_equal(out$turnover, 0L)
})

test_that("a breach at t exits at t+1, never t+0 (execution timing)", {
  # Big loss at t=2 breaches -10%; must still be exposed AT t=2 (dd
  # computed through end of period is what triggers the NEXT period's exit).
  ret <- c(0.02, -0.15, 0.01, 0.01, 0.01)
  out <- hd_stop_rule_backtest(ret, threshold = -0.10, reentry_periods = 1L)
  expect_true(out$exposed[2])   # still in when the breach happens
  expect_false(out$exposed[3])  # out the period AFTER the breach
})

test_that("reentry_periods controls how long the position stays out", {
  ret <- c(0.02, -0.15, 0.01, 0.01, 0.01, 0.01)
  out <- hd_stop_rule_backtest(ret, threshold = -0.10, reentry_periods = 2L)
  expect_true(out$exposed[2])
  expect_false(out$exposed[3])
  expect_false(out$exposed[4])
  expect_true(out$exposed[5])
})

test_that("turnover counts exposure flips; n_stops counts exits only", {
  # Crash then a strong rebound (new peak, dd resets to 0) -> exactly one
  # clean exit + one grace re-entry -> turnover 2, n_stops 1. (A series that
  # stays in drawdown past the grace re-entry can re-trigger repeatedly --
  # see "a fresh breach during a still-depressed drawdown can re-trigger
  # after the grace re-entry" below for that case.)
  ret <- c(0.02, -0.15, 0.20, 0.01, 0.01, 0.01)
  out <- hd_stop_rule_backtest(ret, threshold = -0.10, reentry_periods = 1L)
  expect_equal(out$exposed, c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE))
  expect_equal(out$n_stops, 1L)
  expect_equal(out$turnover, 2L)
})

test_that("a fresh breach during a still-depressed drawdown can re-trigger after the grace re-entry", {
  # Grace re-entry (Kaminski & Lo K-period rule) is UNCONDITIONAL -- it does
  # not wait for the underlying always-invested drawdown to itself recover
  # above threshold. If it hasn't recovered, the very next period can
  # re-trigger a fresh stop. This is intended behaviour, not a bug: it means
  # a slow, grinding drawdown accrues MORE switch cost than a sharp
  # V-shaped one, which is part of why static stops can destroy expectancy.
  ret <- c(0.02, -0.15, 0.01, 0.01, 0.01, 0.01)  # no rebound -- dd stays deep
  out <- hd_stop_rule_backtest(ret, threshold = -0.10, reentry_periods = 1L)
  expect_equal(out$exposed, c(TRUE, TRUE, FALSE, TRUE, FALSE, TRUE))
  expect_equal(out$n_stops, 2L)
  expect_equal(out$turnover, 4L)
})

test_that("switch cost is deducted only on the flip periods", {
  ret <- c(0.02, -0.15, 0.20, 0.01, 0.01, 0.01)
  out_costed <- hd_stop_rule_backtest(ret, threshold = -0.10, cost_bps = 100,
                                       reentry_periods = 1L)
  out_free   <- hd_stop_rule_backtest(ret, threshold = -0.10, cost_bps = 0,
                                       reentry_periods = 1L)
  diff <- out_free$ret_net - out_costed$ret_net
  n_switch_periods <- sum(diff > 0)
  expect_equal(n_switch_periods, out_costed$turnover)
  expect_equal(diff[diff > 0], rep(100 / 1e4, out_costed$turnover))
})

test_that("a rf series is used while stopped out, not cash, when supplied", {
  ret <- c(0.02, -0.15, 0.01, 0.01, 0.01)
  rf  <- c(0.001, 0.001, 0.001, 0.001, 0.001)
  out <- hd_stop_rule_backtest(ret, threshold = -0.10, rf = rf, cost_bps = 0,
                                reentry_periods = 1L)
  expect_equal(out$ret_net[3], rf[3])  # stopped out at t=3, earns rf not ret
})

test_that("static stop locks out a fast rebound -- destructive-stop mechanism (Varma)", {
  # Manufactured whipsaw: -18% crash breaches -10%, immediately followed by
  # a +25% rebound that a stopped-out position misses entirely.
  ret <- c(0.01, -0.18, 0.25, 0.01, 0.01, 0.01)
  no_stop  <- hd_stop_rule_backtest(ret, threshold = -Inf)
  stopped  <- hd_stop_rule_backtest(ret, threshold = -0.10, reentry_periods = 1L)
  term_no_stop <- prod(1 + no_stop$ret_net)
  term_stopped <- prod(1 + stopped$ret_net)
  expect_true(term_stopped < term_no_stop)
  expect_false(stopped$exposed[3])  # missed the rebound period
})

test_that("hd_stop_rule_backtest validates inputs and reports them via cli_abort", {
  expect_snapshot(error = TRUE, hd_stop_rule_backtest("x", threshold = -0.1))
  expect_snapshot(error = TRUE, hd_stop_rule_backtest(c(0.1, NA), threshold = -0.1))
  expect_snapshot(error = TRUE, hd_stop_rule_backtest(c(0.1), threshold = -0.1))
  expect_snapshot(error = TRUE, hd_stop_rule_backtest(rnorm(10), threshold = "x"))
  expect_snapshot(error = TRUE, hd_stop_rule_backtest(rnorm(10), threshold = c(-0.1, -0.2)))
  expect_snapshot(error = TRUE, hd_stop_rule_backtest(rnorm(10), threshold = 0))
  expect_snapshot(error = TRUE, hd_stop_rule_backtest(rnorm(10), threshold = -1.5))
  expect_snapshot(error = TRUE, hd_stop_rule_backtest(rnorm(10), threshold = -0.1, rf = rnorm(5)))
  expect_snapshot(error = TRUE, hd_stop_rule_backtest(rnorm(10), threshold = -0.1, cost_bps = -1))
  expect_snapshot(error = TRUE, hd_stop_rule_backtest(rnorm(10), threshold = -0.1, reentry_periods = 0))
})


# ── hd_regime_stop_thresholds() ─────────────────────────────────────────

test_that("regime thresholds match manual per-regime quantiles", {
  set.seed(2)
  ret <- rnorm(60, mean = 0.005, sd = 0.04)
  regime <- rep(c("low", "high"), each = 30)
  out <- hd_regime_stop_thresholds(ret, regime, percentile = 0.10, min_train_obs = 5L)

  dd <- hd_drawdown(ret)$dd
  expected_low  <- stats::quantile(dd[regime == "low"],  probs = 0.10, names = FALSE)
  expected_high <- stats::quantile(dd[regime == "high"], probs = 0.10, names = FALSE)

  expect_equal(out$regime_levels[["low"]],  expected_low)
  expect_equal(out$regime_levels[["high"]], expected_high)
  expect_equal(out$threshold[regime == "low"],  rep(expected_low, 30))
  expect_equal(out$threshold[regime == "high"], rep(expected_high, 30))
  expect_equal(out$n_fallback, 0L)
})

test_that("NA regime and under-observed regimes fall back to the pooled threshold", {
  set.seed(3)
  ret <- rnorm(40, mean = 0.005, sd = 0.03)
  # "rare" regime has only 3 obs -- below min_train_obs -- and 5 NAs.
  regime <- c(rep("common", 32), rep("rare", 3), rep(NA_character_, 5))
  out <- hd_regime_stop_thresholds(ret, regime, percentile = 0.10, min_train_obs = 10L)

  dd <- hd_drawdown(ret)$dd
  pooled <- stats::quantile(dd, probs = 0.10, names = FALSE)

  expect_null(out$regime_levels[["rare"]])
  # NB: a raw `regime == "rare"` logical index carries NA at every NA-regime
  # position (R's rule for NA in a logical index), which would pull those
  # positions into the subset too -- exclude them explicitly.
  expect_equal(out$threshold[!is.na(regime) & regime == "rare"], rep(pooled, 3))
  expect_equal(out$threshold[is.na(regime)], rep(pooled, 5))
  expect_equal(out$n_fallback, 8L)
})

test_that("train_idx restricts quantile estimation to the training window", {
  ret <- c(rep(0.01, 20), rep(-0.30, 5), rep(0.01, 5))  # crash only in the "test" tail
  regime <- rep("only", 30)
  train_idx <- c(rep(TRUE, 20), rep(FALSE, 10))
  out <- hd_regime_stop_thresholds(ret, regime, percentile = 0.10, train_idx = train_idx,
                                    min_train_obs = 5L)
  dd_train <- hd_drawdown(ret)$dd[train_idx]
  expect_equal(out$regime_levels[["only"]],
               stats::quantile(dd_train, probs = 0.10, names = FALSE))
  # The crash period's own drawdown must NOT have leaked into the threshold.
  expect_true(out$regime_levels[["only"]] > -0.05)
})

test_that("hd_regime_stop_thresholds validates inputs", {
  expect_snapshot(error = TRUE, hd_regime_stop_thresholds("x", rep("a", 3)))
  expect_snapshot(error = TRUE, hd_regime_stop_thresholds(rnorm(10), rep("a", 5)))
  expect_snapshot(error = TRUE, hd_regime_stop_thresholds(rnorm(10), rep("a", 10), percentile = 1.5))
  expect_snapshot(error = TRUE, hd_regime_stop_thresholds(rnorm(10), rep("a", 10), train_idx = 1:3))
  expect_snapshot(error = TRUE, hd_regime_stop_thresholds(c(rnorm(9), NA), rep("a", 10)))
})


# ── hd_stop_rule_compare_arms() ─────────────────────────────────────────

test_that("auto sequencing skips Arm C when the best static stop destroys expectancy", {
  # Whipsaw series repeated so static stops reliably underperform no-stop.
  set.seed(4)
  base <- c(0.01, -0.18, 0.25, 0.01, 0.01, 0.01)
  ret <- rep(base, 6) + rnorm(36, sd = 0.001)
  regime <- rep(c("low", "high"), each = 18)

  out <- hd_stop_rule_compare_arms(
    ret, regime = regime,
    static_thresholds = c(-0.08, -0.10, -0.12),
    run_regime_arm = "auto"
  )

  expect_true(is.character(out$skipped_regime_arm))
  expect_false(is.na(out$regime_arm_note))
  expect_false("regime-stop" %in% out$results$arm)
  expect_true(all(c("no-stop", "static-stop") %in% out$results$arm))
})

test_that("run_regime_arm = 'always' forces Arm C even when it would be auto-skipped", {
  set.seed(4)
  base <- c(0.01, -0.18, 0.25, 0.01, 0.01, 0.01)
  ret <- rep(base, 6) + rnorm(36, sd = 0.001)
  regime <- rep(c("low", "high"), each = 18)

  out <- hd_stop_rule_compare_arms(
    ret, regime = regime,
    static_thresholds = c(-0.08, -0.10, -0.12),
    run_regime_arm = "always"
  )
  expect_true("regime-stop" %in% out$results$arm)
  expect_false(isTRUE(is.character(out$skipped_regime_arm)))
})

test_that("run_regime_arm = 'never' skips Arm C without requiring regime", {
  set.seed(5)
  ret <- rnorm(24, mean = 0.01, sd = 0.02)
  out <- hd_stop_rule_compare_arms(ret, regime = NULL, run_regime_arm = "never")
  expect_false("regime-stop" %in% out$results$arm)
  expect_equal(out$skipped_regime_arm, "run_regime_arm = \"never\"")
})

test_that("results tibble has one row per arm x threshold with expected columns", {
  set.seed(6)
  ret <- rnorm(48, mean = 0.008, sd = 0.03)
  regime <- rep(c("low", "high"), each = 24)
  out <- hd_stop_rule_compare_arms(
    ret, regime = regime,
    static_thresholds = c(-0.10, -0.15),
    run_regime_arm = "always"
  )
  expect_equal(nrow(out$results), 4L)  # 1 no-stop + 2 static + 1 regime
  expect_true(all(c("arm", "threshold", "sharpe", "cagr", "vol", "max_dd",
                     "turnover", "n_stops", "n") %in% names(out$results)))
})

test_that("hd_stop_rule_compare_arms requires regime unless run_regime_arm = 'never'", {
  ret <- rnorm(24, mean = 0.01, sd = 0.02)
  expect_snapshot(error = TRUE,
                   hd_stop_rule_compare_arms(ret, regime = NULL, run_regime_arm = "auto"))
})

test_that("hd_stop_rule_compare_arms validates its own inputs", {
  expect_snapshot(error = TRUE, hd_stop_rule_compare_arms("x"))
  expect_snapshot(error = TRUE,
                   hd_stop_rule_compare_arms(rnorm(10), static_thresholds = numeric(0)))
})

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_stop_rule_backtest))
  expect_snapshot(args(hd_regime_stop_thresholds))
  expect_snapshot(args(hd_stop_rule_compare_arms))
})
