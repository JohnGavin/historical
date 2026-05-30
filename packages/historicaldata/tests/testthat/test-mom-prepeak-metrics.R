# Tests for .mom_prepeak_compute_metrics() — bankruptcy-aware L/S metric helper.
#
# The helper lives in packages/historicaldata/R/utils_mom_prepeak_metrics.R
# and is a non-exported internal function.  Access via `:::`.
#
# Fixtures are fully self-contained: no parquet files, no ltr_universe, no
# database.  All return series are manufactured analytically.

# Helper: build a minimal returns_tbl from a numeric vector of ret_ls values.
make_returns_tbl <- function(r) {
  tibble::tibble(ret_ls = r)
}

# ---- 1. Normal case: no bankruptcy -----------------------------------------

test_that("normal case: no bankruptcy — cagr, max_dd computed normally", {
  # 24 months of constant 1% returns — monotone cumulative path, zero drawdown.
  r <- rep(0.01, 24)
  result <- historicaldata:::.mom_prepeak_compute_metrics(
    make_returns_tbl(r), strategy = "test_strategy"
  )

  expect_equal(result$blown_up, FALSE)
  expect_true(is.na(result$bankrupt_month))
  expect_true(result$cagr > 0)
  expect_equal(result$max_dd, 0)          # monotone series → no drawdown
  expect_equal(result$strategy, "test_strategy")
  expect_equal(result$n_months, 24L)
})

# ---- 2. Bankruptcy: ret_ls < -1 in single month ----------------------------

test_that("bankruptcy: ret_ls < -1 in single month — blown_up TRUE, max_dd == -100, cagr NA", {
  # 24 months; month 13 is an extreme short squeeze that wipes the portfolio.
  r <- rep(0.01, 24)
  r[13] <- -1.2   # single month return < -1 → cumprod goes negative

  result <- historicaldata:::.mom_prepeak_compute_metrics(
    make_returns_tbl(r), strategy = "test_blown_up"
  )

  expect_true(result$blown_up)
  expect_equal(result$bankrupt_month, 13L)
  expect_equal(result$max_dd, -100.0)
  expect_true(is.na(result$cagr))
})

# ---- 3. cumprod exactly zero -----------------------------------------------

test_that("cumprod exactly zero — blown_up TRUE", {
  # Month 13 = exactly -1.0 → cum[13] = 0 (bankruptcy floor).
  r <- rep(0.01, 24)
  r[13] <- -1.0

  result <- historicaldata:::.mom_prepeak_compute_metrics(
    make_returns_tbl(r), strategy = "test_exact_zero"
  )

  expect_true(result$blown_up)
  expect_equal(result$bankrupt_month, 13L)
  expect_equal(result$max_dd, -100.0)
  expect_true(is.na(result$cagr))
})

# ---- 4. Normal drawdown without bankruptcy ---------------------------------

test_that("normal drawdown without bankruptcy: max_dd between (-100, 0)", {
  # Returns that draw down to ~50% of starting equity but never cross zero.
  # Pattern: 6 months up, 6 months down (but not below starting equity cumulative),
  # then recover.  Use a simple sequence: 12 months of -0.05 (draw down to ~0.54
  # of starting equity) then 12 months of +0.10 (recover).
  r <- c(rep(-0.05, 12), rep(0.10, 12))
  cum_check <- cumprod(1 + r)
  # Verify fixture: no zero crossing
  expect_true(all(cum_check > 0))

  result <- historicaldata:::.mom_prepeak_compute_metrics(
    make_returns_tbl(r), strategy = "test_drawdown"
  )

  expect_false(result$blown_up)
  expect_true(is.na(result$bankrupt_month))
  expect_true(result$max_dd > -100)
  expect_true(result$max_dd < 0)         # there IS a drawdown
})

# ---- 5. Sharpe computable even when blown_up --------------------------------

test_that("sharpe still computable even when blown_up", {
  r <- rep(0.01, 24)
  r[13] <- -1.2   # same bankruptcy fixture as test 2

  result <- historicaldata:::.mom_prepeak_compute_metrics(
    make_returns_tbl(r), strategy = "test_sharpe_blown_up"
  )

  expect_true(result$blown_up)
  expect_false(is.na(result$sharpe))     # sharpe uses per-period r, unaffected
})

# ---- 6. Snapshot: output tibble structure includes new columns --------------

test_that("output tibble structure includes blown_up and bankrupt_month columns", {
  r <- rep(0.01, 24)
  r[13] <- -1.2   # bankruptcy fixture

  result <- historicaldata:::.mom_prepeak_compute_metrics(
    make_returns_tbl(r), strategy = "test_struct"
  )

  expect_snapshot(str(result))
})
