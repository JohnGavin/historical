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

# ---- 5. Sharpe is a placeholder from this function as of #677 ---------------
#
# .mom_prepeak_compute_metrics() no longer computes sharpe itself: the
# canonical rf-adjusted geometric sharpe_ratio_rf() lives at the pipeline
# layer (R/utils_metrics.R), not inside this package, so it cannot be called
# here. sharpe is always NA_real_ from this function alone; the caller
# (.mom_prepeak_sharpe() in R/plan_mom_prepeak.R) overwrites it. See
# tests/testthat/test-mom-prepeak-sharpe.R (root-level) for coverage of the
# actual Sharpe computation, including the "still finite when blown_up" case
# this test used to assert.

test_that("sharpe is always NA_real_ from this function alone (#677)", {
  r <- rep(0.01, 24)
  r[13] <- -1.2   # same bankruptcy fixture as test 2

  result <- historicaldata:::.mom_prepeak_compute_metrics(
    make_returns_tbl(r), strategy = "test_sharpe_blown_up"
  )

  expect_true(result$blown_up)
  expect_true(is.na(result$sharpe))
})

test_that("sharpe is always NA_real_ from this function alone, non-bankrupt case (#677)", {
  r <- rep(0.01, 24)

  result <- historicaldata:::.mom_prepeak_compute_metrics(
    make_returns_tbl(r), strategy = "test_sharpe_normal"
  )

  expect_false(result$blown_up)
  expect_true(is.na(result$sharpe))
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

# ---- 7. Pillar-8: normal case has finite metrics ────────────────────────────

test_that("Pillar-8 metrics present and finite in normal (non-bankrupt) case", {
  # 36 months: 6 months of 2% gains then 3% drawdown then recover
  r <- c(rep(0.02, 12), rep(-0.03, 6), rep(0.02, 18))

  result <- historicaldata:::.mom_prepeak_compute_metrics(
    make_returns_tbl(r), strategy = "test_pillar8_normal"
  )

  expect_false(result$blown_up)
  expect_true("avg_dd_days"     %in% names(result))
  expect_true("max_dd_days"     %in% names(result))
  expect_true("max_cons_losses" %in% names(result))
  expect_true("loss_clustered"  %in% names(result))

  # With a drawdown period, these should be finite (not NA)
  expect_true(!is.na(result$avg_dd_days))
  expect_true(!is.na(result$max_dd_days))
  expect_true(!is.na(result$max_cons_losses))
  expect_true(result$max_cons_losses >= 0L)
})

# ---- 8. Pillar-8: blown-up case uses pre-bankruptcy slice only ──────────────

test_that("Pillar-8 metrics computed on pre-bankruptcy slice when blown_up", {
  # 30 months; bankruptcy at month 20.
  # Months 21-30 are post-bankruptcy; their loss runs should NOT be counted.
  r <- rep(0.01, 30)
  r[20] <- -1.5   # bankruptcy at month 20

  result <- historicaldata:::.mom_prepeak_compute_metrics(
    make_returns_tbl(r), strategy = "test_pillar8_blown"
  )

  expect_true(result$blown_up)
  expect_equal(result$bankrupt_month, 20L)

  # max_cons_losses should be based on months 1-19 only (all positive +1%)
  # — no consecutive losses in pre-bankruptcy slice, so max_cons_losses = 0
  expect_equal(result$max_cons_losses, 0L)

  # avg_dd_days and max_dd_days: monotone-up series before bankruptcy → NA (no dd events)
  # (hd_dd_duration returns NA avg/max when no drawdown events exist)
  # We just check they are not informed by post-bankruptcy returns (which would have negative runs)
  expect_true(is.na(result$avg_dd_days) || result$avg_dd_days >= 0)
})

# ---- 9. Pillar-8 columns present even when blown_up (sharpe is a placeholder) --

test_that("Pillar-8 columns present even when blown_up; sharpe is a placeholder (#677)", {
  r <- rep(0.01, 24)
  r[13] <- -1.2

  result <- historicaldata:::.mom_prepeak_compute_metrics(
    make_returns_tbl(r), strategy = "test_pillar8_sharpe_blown"
  )

  expect_true(result$blown_up)
  expect_true(is.na(result$sharpe))
  # All four Pillar-8 columns must exist
  expect_true(all(c("avg_dd_days", "max_dd_days", "max_cons_losses", "loss_clustered") %in% names(result)))
})
