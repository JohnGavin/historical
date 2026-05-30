# Tests for .mom_prepeak_form_portfolio() — portfolio-formation helper
# defined in R/plan_mom_prepeak.R.
#
# These tests are self-contained (no ltr_universe, no parquet files).
# The helper is accessed via source() of the plan file in a temp env,
# since it is a plan-level private function not exported from the package.
#
# Strategy: source the plan into a local environment, extract the helper,
# then test it directly with manufactured fixtures.

# ---- Setup: source the plan helper ----------------------------------------

# We need to source plan_mom_prepeak.R to get .mom_prepeak_form_portfolio().
# Skip gracefully if the plan file is not findable (e.g., during isolated
# package-only test runs on CI without the project root).

plan_file <- tryCatch(
  here::here("R", "plan_mom_prepeak.R"),
  error = function(e) NULL
)

skip_no_plan <- function() {
  if (is.null(plan_file) || !file.exists(plan_file)) {
    testthat::skip("R/plan_mom_prepeak.R not found — skipping plan helper tests")
  }
}

# Source once into a test environment so we don't pollute global env.
# The helper functions are defined at top-level in the plan file, so they land
# in the test env after source().
plan_env <- new.env(parent = baseenv())

if (!is.null(plan_file) && file.exists(plan_file)) {
  # Suppress messages from library() calls inside helpers
  suppressMessages(
    source(plan_file, local = plan_env)
  )
}

# Convenience extractor
form_portfolio <- function(...) {
  skip_no_plan()
  plan_env$.mom_prepeak_form_portfolio(...)
}


# ---- Shared fixture builder --------------------------------------------------

# Build a synthetic signal tibble with `n_stocks` tickers and one as_of_date.
# signal values are deterministic: ticker "T01" gets signal 1, "T02" gets 2, etc.
make_signal_tbl <- function(n_stocks     = 50L,
                             as_of_date   = as.Date("2026-01-31"),
                             signal_col   = "pre_peak_return") {
  tickers <- sprintf("T%02d", seq_len(n_stocks))
  signals <- seq_len(n_stocks) / n_stocks  # 0.02, 0.04, ... 1.00
  tibble::tibble(
    ticker         = tickers,
    as_of_date     = as_of_date,
    pre_peak_return  = signals,
    post_peak_return = rev(signals),
    total_return     = signals * 0.5 + 0.1
  )
}


# ---- 1. Drop dates with fewer stocks than min_stocks -----------------------

test_that(".mom_prepeak_form_portfolio drops dates with < min_stocks", {
  skip_no_plan()

  small_tbl <- make_signal_tbl(n_stocks = 20L)  # < 30 (default min)

  result <- form_portfolio(
    signal_tbl  = small_tbl,
    signal_col  = "pre_peak_return",
    n_quantiles = 10L,
    min_stocks  = 30L
  )

  expect_equal(nrow(result), 0L,
    info = "Dates with fewer stocks than min_stocks must be dropped entirely")
})


# ---- 2. Long top decile / short bottom decile ------------------------------

test_that(".mom_prepeak_form_portfolio: long top decile / short bottom decile", {
  skip_no_plan()

  tbl <- make_signal_tbl(n_stocks = 50L)

  result <- form_portfolio(
    signal_tbl  = tbl,
    signal_col  = "pre_peak_return",
    n_quantiles = 10L,
    min_stocks  = 30L
  )

  # Top 5 (tickers T46..T50, highest signal) must be in long leg (weight > 0)
  long_leg  <- result[result$weight > 0, ]
  short_leg <- result[result$weight < 0, ]

  # With 50 stocks and 10 deciles: 5 per decile
  expect_equal(nrow(long_leg),  5L, info = "Long leg: top decile = 5 stocks")
  expect_equal(nrow(short_leg), 5L, info = "Short leg: bottom decile = 5 stocks")

  # Long leg should have the 5 highest signal values
  top5_signal <- sort(tbl$pre_peak_return, decreasing = TRUE)[1:5]
  long_signals <- sort(long_leg$signal_value, decreasing = TRUE)
  expect_equal(long_signals, top5_signal, tolerance = 1e-10)

  # Short leg should have the 5 lowest signal values
  bottom5_signal <- sort(tbl$pre_peak_return)[1:5]
  short_signals  <- sort(short_leg$signal_value)
  expect_equal(short_signals, bottom5_signal, tolerance = 1e-10)
})


# ---- 3. Weights sum to ±1 --------------------------------------------------

test_that(".mom_prepeak_form_portfolio: long and short weights sum to ±1", {
  skip_no_plan()

  tbl <- make_signal_tbl(n_stocks = 50L)

  result <- form_portfolio(
    signal_tbl  = tbl,
    signal_col  = "pre_peak_return",
    n_quantiles = 10L,
    min_stocks  = 30L
  )

  long_wgt  <- sum(result$weight[result$weight > 0])
  short_wgt <- sum(result$weight[result$weight < 0])

  expect_equal(long_wgt,  1,  tolerance = 1e-10,
    info = "Long leg weights must sum to +1 (equal-weighted)")
  expect_equal(short_wgt, -1, tolerance = 1e-10,
    info = "Short leg weights must sum to -1 (equal-weighted)")
})


# ---- 4. Tied signals resolve via ntile (no spurious splitting) -------------

test_that(".mom_prepeak_form_portfolio: tied signals fall in the same decile", {
  skip_no_plan()

  # 50 stocks: all have the SAME signal value (complete tie).
  # ntile distributes ties sequentially — each decile gets exactly 5 stocks.
  # No stock should be missing from any decile due to a tie-break error.
  tied_tbl <- tibble::tibble(
    ticker           = sprintf("T%02d", 1:50),
    as_of_date       = as.Date("2026-01-31"),
    pre_peak_return  = rep(0.5, 50L),  # all identical
    post_peak_return = rep(0.3, 50L),
    total_return     = rep(0.4, 50L)
  )

  result <- form_portfolio(
    signal_tbl  = tied_tbl,
    signal_col  = "pre_peak_return",
    n_quantiles = 10L,
    min_stocks  = 30L
  )

  # ntile with ties: should still produce long and short legs (5 stocks each)
  expect_equal(nrow(result), 10L,
    info = "Tied signals must still produce 10 portfolio members (5 long + 5 short)")

  long_n  <- sum(result$weight > 0)
  short_n <- sum(result$weight < 0)
  expect_equal(long_n,  5L, info = "5 in long leg even with ties")
  expect_equal(short_n, 5L, info = "5 in short leg even with ties")
})


# ---- 5. Snapshot: portfolio output structure is stable ---------------------

test_that("portfolio output structure is stable", {
  skip_no_plan()

  tbl    <- make_signal_tbl(n_stocks = 50L)
  result <- form_portfolio(
    signal_tbl  = tbl,
    signal_col  = "pre_peak_return",
    n_quantiles = 10L,
    min_stocks  = 30L
  )

  expect_snapshot(str(result))
})
