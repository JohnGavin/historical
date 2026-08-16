testthat::local_edition(3)
# Tests for compute_borrow_sensitivity() / build_borrow_sensitivity_table() (#665)
#
# REPORTING-ONLY functions defined in R/plan_cost_convention.R -- nothing
# they compute feeds leaderboard/all_metrics/any published return. Tests
# verify the borrow-rate sweep arithmetic on toy fixtures and the required
# invariants: sharpe_delta == 0 at borrow_rate_annual == 0, sharpe strictly
# decreases as the borrow rate increases (subtracting a constant charge
# leaves volatility unchanged but lowers the mean), and NA / too-short /
# out-of-range inputs abort loudly rather than silently coercing.

source(here::here("R/plan_cost_convention.R"))

# 24 months of a toy strategy return series -- small positive drift + noise
# so cagr/vol/sharpe are all well-defined (vol > 0) and reproducible.
set.seed(42)
toy_ret <- rep(0.01, 24L) + stats::rnorm(24L, sd = 0.01)

# ── Input validation (fail-loud-not-null.md) ────────────────────────────

test_that("compute_borrow_sensitivity requires >= 12 months", {
  expect_error(compute_borrow_sensitivity(rep(0.01, 6L)), regexp = "12")
  expect_snapshot(error = TRUE, compute_borrow_sensitivity(rep(0.01, 6L)))
})

test_that("compute_borrow_sensitivity aborts on NA input rather than dropping it silently", {
  bad <- toy_ret
  bad[3] <- NA_real_
  expect_error(compute_borrow_sensitivity(bad), regexp = "NA")
  expect_snapshot(error = TRUE, compute_borrow_sensitivity(bad))
})

test_that("compute_borrow_sensitivity requires 0 in borrow_rates_annual (sharpe_delta baseline)", {
  expect_error(
    compute_borrow_sensitivity(toy_ret, borrow_rates_annual = c(0.03, 0.10)),
    regexp = "0"
  )
})

test_that("compute_borrow_sensitivity rejects an out-of-range short_notional_frac", {
  expect_error(
    compute_borrow_sensitivity(toy_ret, short_notional_frac = 1.5),
    regexp = "\\[0, 1\\]"
  )
  expect_error(
    compute_borrow_sensitivity(toy_ret, short_notional_frac = -0.1),
    regexp = "\\[0, 1\\]"
  )
})

# ── Core arithmetic ──────────────────────────────────────────────────────

test_that("sharpe_delta is exactly 0 at borrow_rate_annual == 0", {
  out <- compute_borrow_sensitivity(toy_ret)
  expect_equal(out$sharpe_delta[out$borrow_rate_annual == 0], 0)
})

test_that("sharpe strictly decreases as borrow rate increases", {
  # Subtracting a larger constant monthly charge lowers the mean but leaves
  # sd() unchanged, so sharpe = ann_ret / ann_vol must strictly decrease as
  # the swept rate increases -- true for ANY non-degenerate return series.
  out <- compute_borrow_sensitivity(toy_ret, borrow_rates_annual = c(0, 0.03, 0.10, 0.25))
  expect_true(all(diff(out$sharpe) < 0))
  expect_true(all(diff(out$sharpe_delta) < 0))
})

test_that("short_notional_frac = 0 makes the sweep a no-op (no short exposure to charge)", {
  out <- compute_borrow_sensitivity(toy_ret, short_notional_frac = 0)
  expect_true(all(out$sharpe_delta == 0))
  expect_true(all(out$cagr == out$cagr[1]))
})

test_that("compute_borrow_sensitivity's cagr/vol match an independent formula recomputation", {
  out <- compute_borrow_sensitivity(toy_ret, borrow_rates_annual = c(0, 0.03, 0.10, 0.25))
  for (rate in c(0, 0.03, 0.10, 0.25)) {
    r <- toy_ret - rate / 12
    row <- out[out$borrow_rate_annual == rate, ]
    expect_equal(row$cagr, prod(1 + r)^(12 / length(r)) - 1, tolerance = 1e-12)
    expect_equal(row$vol,  stats::sd(r) * sqrt(12),           tolerance = 1e-12)
  }

  # Snapshot: catches format/column drift.
  expect_snapshot(print(out, n = Inf))
})

# ── build_borrow_sensitivity_table: multi-strategy assembly ──────────────

test_that("build_borrow_sensitivity_table requires a non-empty named list", {
  expect_error(build_borrow_sensitivity_table(list()), regexp = "non-empty")
  expect_error(build_borrow_sensitivity_table(list(1:5)), regexp = "non-empty")
  expect_snapshot(error = TRUE, build_borrow_sensitivity_table(list()))
})

test_that("build_borrow_sensitivity_table combines multiple strategies and filters NA per-strategy", {
  strat_a <- toy_ret
  strat_b <- c(NA_real_, toy_ret)  # leading NA -- must be filtered, not propagated

  out <- build_borrow_sensitivity_table(list("Strategy A" = strat_a, "Strategy B" = strat_b))

  expect_setequal(out$strategy, c("Strategy A", "Strategy B"))
  expect_equal(nrow(out), 2L * length(c(0, 0.03, 0.10, 0.25)))
  expect_true(all(!is.na(out$sharpe)))

  # Both strategies swept over the identical rate grid.
  expect_equal(
    sort(unique(out$borrow_rate_annual[out$strategy == "Strategy A"])),
    sort(unique(out$borrow_rate_annual[out$strategy == "Strategy B"]))
  )
})
