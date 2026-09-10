testthat::local_edition(3)
# Tests for hd_market_impact() and hd_capacity_curve() (#508, #794) --
# market-impact-based capacity estimation.
#
# hd_market_impact() implements the square-root law with an exact,
# hand-derivable closed form (impact_frac = eta * sigma * sqrt(Q/ADV)) --
# every numeric test below independently recomputes the expected value
# rather than re-deriving the same code path, same discipline as
# test-hd-detection-power.R.

# ── hd_market_impact(): hand-derived formula ────────────────────────────────

test_that("hd_market_impact matches the hand-derived square-root-law formula at known participation", {
  # $1M order against $100M ADV -> participation = 0.01 -> sqrt = 0.1
  # sigma = 0.02, eta = 1 -> impact = 1 * 0.02 * 0.1 = 0.002
  out <- hd_market_impact(order_usd = 1e6, adv_usd = 1e8, sigma = 0.02, eta = 1)
  expect_equal(out, 0.002, tolerance = 1e-12)
})

test_that("hd_market_impact scales with sqrt(participation), not linearly", {
  # Quadrupling the order size should exactly DOUBLE the impact cost
  # (sqrt(4x) = 2*sqrt(x)) -- the defining property of the square-root law
  # (#794: "grow faster than linearly").
  small <- hd_market_impact(order_usd = 1e6, adv_usd = 1e8, sigma = 0.02)
  large <- hd_market_impact(order_usd = 4e6, adv_usd = 1e8, sigma = 0.02)
  expect_equal(large, 2 * small, tolerance = 1e-9)
})

test_that("hd_market_impact scales linearly with sigma and eta", {
  base <- hd_market_impact(order_usd = 1e6, adv_usd = 1e8, sigma = 0.02, eta = 1)
  double_sigma <- hd_market_impact(order_usd = 1e6, adv_usd = 1e8, sigma = 0.04, eta = 1)
  double_eta <- hd_market_impact(order_usd = 1e6, adv_usd = 1e8, sigma = 0.02, eta = 2)
  expect_equal(double_sigma, 2 * base, tolerance = 1e-12)
  expect_equal(double_eta, 2 * base, tolerance = 1e-12)
})

test_that("hd_market_impact is vectorised over order_usd", {
  out <- hd_market_impact(order_usd = c(1e6, 4e6, 9e6), adv_usd = 1e8, sigma = 0.02)
  expect_length(out, 3L)
  expect_equal(out[2] / out[1], 2, tolerance = 1e-9)   # sqrt(4)
  expect_equal(out[3] / out[1], 3, tolerance = 1e-9)   # sqrt(9)
})

test_that("hd_market_impact is zero when order_usd is zero", {
  expect_equal(hd_market_impact(order_usd = 0, adv_usd = 1e8, sigma = 0.02), 0)
})

# ── hd_market_impact(): input validation ────────────────────────────────────

test_that("hd_market_impact rejects negative order_usd", {
  expect_snapshot(error = TRUE, hd_market_impact(order_usd = -1, adv_usd = 1e8, sigma = 0.02))
})

test_that("hd_market_impact rejects non-positive adv_usd", {
  expect_snapshot(error = TRUE, hd_market_impact(order_usd = 1e6, adv_usd = 0, sigma = 0.02))
})

test_that("hd_market_impact rejects negative sigma", {
  expect_snapshot(error = TRUE, hd_market_impact(order_usd = 1e6, adv_usd = 1e8, sigma = -0.01))
})

test_that("hd_market_impact rejects non-positive eta", {
  expect_snapshot(error = TRUE, hd_market_impact(order_usd = 1e6, adv_usd = 1e8, sigma = 0.02, eta = 0))
})

test_that("hd_market_impact method = 'istar' errors informatively and does not silently fall back", {
  expect_error(
    hd_market_impact(order_usd = 1e6, adv_usd = 1e8, sigma = 0.02, method = "istar"),
    regexp = "not implemented"
  )
  expect_snapshot(
    error = TRUE,
    hd_market_impact(order_usd = 1e6, adv_usd = 1e8, sigma = 0.02, method = "istar")
  )
})

test_that("hd_market_impact rejects an unrecognised method rather than silently defaulting", {
  # fail-loud-not-null.md: an unrecognised value must abort, not coerce.
  expect_snapshot(
    error = TRUE,
    hd_market_impact(order_usd = 1e6, adv_usd = 1e8, sigma = 0.02, method = "linear")
  )
})

# ── hd_capacity_curve(): schema and monotonicity ────────────────────────────

test_that("hd_capacity_curve returns one row per aum_grid element with the documented schema", {
  set.seed(1)
  rets <- stats::rnorm(60, mean = 0.01, sd = 0.04)
  out <- hd_capacity_curve(
    monthly_ret = rets, aum_grid = c(0, 1e6, 1e7, 1e8, 1e9),
    adv_usd = 5e7, turnover_frac = 1.0
  )
  expect_equal(nrow(out), 5L)
  expect_setequal(
    names(out),
    c("aum", "participation", "impact_cost_frac", "net_sharpe", "net_cagr", "gross_sharpe")
  )
  expect_true(all(diff(out$aum) > 0))
})

test_that("hd_capacity_curve's aum=0 row has zero impact cost and net_sharpe == gross_sharpe", {
  set.seed(2)
  rets <- stats::rnorm(48, mean = 0.008, sd = 0.03)
  out <- hd_capacity_curve(
    monthly_ret = rets, aum_grid = c(0, 1e9), adv_usd = 5e7, turnover_frac = 1.0
  )
  zero_row <- out[out$aum == 0, ]
  expect_equal(zero_row$impact_cost_frac, 0)
  expect_equal(zero_row$net_sharpe, zero_row$gross_sharpe, tolerance = 1e-9)
})

test_that("hd_capacity_curve's net_sharpe is non-increasing in aum (impact cost only grows)", {
  set.seed(3)
  rets <- stats::rnorm(60, mean = 0.012, sd = 0.035)
  out <- hd_capacity_curve(
    monthly_ret = rets,
    aum_grid = c(0, 1e6, 1e7, 5e7, 1e8, 5e8, 1e9),
    adv_usd = 5e7, turnover_frac = 1.0
  )
  expect_true(all(diff(out$net_sharpe) <= 1e-9))
})

test_that("hd_capacity_curve reports capacity_aum_ceiling as the first AUM where net_sharpe <= 0", {
  set.seed(4)
  # Modest positive drift + low vol -> impact cost overwhelms it at large AUM
  # against a small ADV, guaranteeing a ceiling exists inside this grid.
  rets <- stats::rnorm(60, mean = 0.006, sd = 0.02)
  out <- hd_capacity_curve(
    monthly_ret = rets,
    aum_grid = c(1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11),
    adv_usd = 1e6, turnover_frac = 1.0
  )
  ceiling <- attr(out, "capacity_aum_ceiling")
  expect_true(!is.na(ceiling))
  expect_true(ceiling %in% out$aum)
  below_ceiling <- out[out$aum < ceiling, ]
  expect_true(all(below_ceiling$net_sharpe > 0))
})

test_that("hd_capacity_curve reports capacity_aum_ceiling as NA when net_sharpe never crosses zero in the grid", {
  set.seed(5)
  rets <- stats::rnorm(60, mean = 0.02, sd = 0.03)
  out <- hd_capacity_curve(
    monthly_ret = rets, aum_grid = c(1e5, 1e6),  # tiny AUM range, no real impact
    adv_usd = 1e12, turnover_frac = 0.5           # enormous ADV -> negligible participation
  )
  expect_true(is.na(attr(out, "capacity_aum_ceiling")))
})

# ── hd_capacity_curve(): input validation ───────────────────────────────────

test_that("hd_capacity_curve rejects a non-increasing aum_grid", {
  expect_snapshot(
    error = TRUE,
    hd_capacity_curve(
      monthly_ret = stats::rnorm(24), aum_grid = c(1e6, 1e6, 1e7),
      adv_usd = 5e7, turnover_frac = 1.0
    )
  )
})

test_that("hd_capacity_curve rejects turnover_frac outside (0, 1]", {
  expect_snapshot(
    error = TRUE,
    hd_capacity_curve(
      monthly_ret = stats::rnorm(24), aum_grid = c(1e6, 1e7),
      adv_usd = 5e7, turnover_frac = 1.5
    )
  )
})

test_that("hd_capacity_curve rejects too-short monthly_ret", {
  expect_snapshot(
    error = TRUE,
    hd_capacity_curve(
      monthly_ret = 0.01, aum_grid = c(1e6, 1e7), adv_usd = 5e7, turnover_frac = 1.0
    )
  )
})

test_that("hd_capacity_curve rejects non-positive adv_usd", {
  expect_snapshot(
    error = TRUE,
    hd_capacity_curve(
      monthly_ret = stats::rnorm(24), aum_grid = c(1e6, 1e7),
      adv_usd = -1, turnover_frac = 1.0
    )
  )
})

# ── Function signature stability ─────────────────────────────────────────────

test_that("hd_market_impact() function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_market_impact))
})

test_that("hd_capacity_curve() function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_capacity_curve))
})
