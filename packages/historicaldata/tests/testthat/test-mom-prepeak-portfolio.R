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


# ---- Setup: convenience extractor for compute_returns ----------------------

compute_returns <- function(...) {
  skip_no_plan()
  plan_env$.mom_prepeak_compute_returns(...)
}


# ---- Helper: build a minimal universe_tbl for compute_returns tests --------

# .mom_prepeak_compute_returns computes fwd_ret = lead(adjusted)/adjusted - 1
# for each ticker row-by-row.  The portfolio's as_of_date signals at month-end
# t; the exec_date is the NEXT month-end t+1 (where we enter), and the return
# is the move from t+1 to t+2 (exit).  Therefore we need THREE month-ends:
#   month1 = as_of_date (signal formation)
#   month2 = exec_date  (entry; fwd_ret at this row = month3/month2 - 1)
#   month3 = exit       (exit prices; fwd_ret here is NA — last row)
# month1_prices, month2_prices, month3_prices: named numeric vectors (ticker->price).
make_universe_tbl <- function(tickers,
                               month1_date   = as.Date("2026-01-31"),
                               month2_date   = as.Date("2026-02-28"),
                               month3_date   = as.Date("2026-03-31"),
                               month1_prices,
                               month2_prices,
                               month3_prices) {
  tibble::tibble(
    ticker   = rep(tickers, 3L),
    date     = c(rep(month1_date, length(tickers)),
                 rep(month2_date, length(tickers)),
                 rep(month3_date, length(tickers))),
    adjusted = c(month1_prices[tickers],
                 month2_prices[tickers],
                 month3_prices[tickers])
  )
}

# Returns a minimal portfolio_tbl (one as_of_date, explicit weights).
make_portfolio_tbl <- function(tickers, weights,
                                as_of_date = as.Date("2026-01-31")) {
  tibble::tibble(
    as_of_date   = as_of_date,
    ticker       = tickers,
    signal_value = seq_along(tickers) / length(tickers),
    decile       = ifelse(weights > 0, 10L, 1L),
    weight       = weights
  )
}


# ---- 6. Short-leg return cap: squeezed short contributes at most 100% ------

test_that(".mom_prepeak_compute_returns caps short returns at +100%", {
  skip_no_plan()

  # Universe needs 3 month-ends: as_of_date (Jan), exec_date (Feb), exit (Mar).
  # The exec_date fwd_ret = exit_price / exec_price - 1.
  # Long:  T_LONG,  exec_price=100, exit_price=110  => fwd_ret = +10%
  # Short: T_SHORT, exec_price=100, exit_price=300  => fwd_ret = +200%
  #   Uncapped: ret_short = 1 * 2.0 = 2.0  =>  ret_ls = 0.10 - 2.0 = -1.90
  #   Capped:   ret_short = 1 * 1.0 = 1.0  =>  ret_ls = 0.10 - 1.0 = -0.90
  tickers <- c("T_LONG", "T_SHORT")
  month1  <- c(T_LONG = 100, T_SHORT = 100)  # as_of_date prices (any value)
  month2  <- c(T_LONG = 100, T_SHORT = 100)  # exec_date entry prices
  month3  <- c(T_LONG = 110, T_SHORT = 300)  # exit prices

  port <- make_portfolio_tbl(
    tickers = tickers,
    weights = c(1, -1)  # equal-weight: 1 long, 1 short
  )
  univ <- make_universe_tbl(
    tickers       = tickers,
    month1_prices = month1,
    month2_prices = month2,
    month3_prices = month3
  )

  result <- compute_returns(
    portfolio_tbl  = port,
    universe_tbl   = univ,
    cost_per_trade = 0
  )

  expect_equal(nrow(result), 1L, info = "Should have exactly 1 monthly row")
  expect_equal(result$ret_short, 1.0, tolerance = 1e-10,
    info = "Short-leg contribution capped at 1.0 (100% loss of notional)")
  expect_gt(result$ret_ls, -1,
    info = "ret_ls must be > -1 even with a +200% squeeze on the short leg")
  expect_equal(result$ret_ls, 0.10 - 1.0, tolerance = 1e-10,
    info = "ret_ls = ret_long (0.10) - ret_short_capped (1.0)")
})


# ---- 7. Cap is identity on normal months (no fwd_ret > 1 for shorts) -------

test_that(".mom_prepeak_compute_returns: cap does not alter normal-month returns", {
  skip_no_plan()

  # Universe needs 3 month-ends: as_of_date (Jan), exec_date (Feb), exit (Mar).
  # All fwd_ret (Mar/Feb - 1) are in [-1, 1] — the cap should be a no-op.
  # Long:  T_LONG1 +10%, T_LONG2 +5%
  # Short: T_SH1   +20% (loss on short; < 100% so no cap), T_SH2 -10% (profit)
  tickers  <- c("T_LONG1", "T_LONG2", "T_SH1", "T_SH2")
  weights  <- c(0.5, 0.5, -0.5, -0.5)  # equal-weight within each leg

  # month2 = exec_date entry prices (all 100)
  month1   <- c(T_LONG1 = 100, T_LONG2 = 100, T_SH1 = 100, T_SH2 = 100)
  month2   <- c(T_LONG1 = 100, T_LONG2 = 100, T_SH1 = 100, T_SH2 = 100)
  # month3 = exit prices
  month3   <- c(T_LONG1 = 110, T_LONG2 = 105, T_SH1 = 120, T_SH2 = 90)

  port <- make_portfolio_tbl(tickers = tickers, weights = weights)
  univ <- make_universe_tbl(
    tickers       = tickers,
    month1_prices = month1,
    month2_prices = month2,
    month3_prices = month3
  )

  result <- compute_returns(
    portfolio_tbl  = port,
    universe_tbl   = univ,
    cost_per_trade = 0
  )

  # Manual calculation (no cap triggered):
  # ret_long  = 0.5 * 0.10 + 0.5 * 0.05 = 0.075
  # ret_short = 0.5 * 0.20 + 0.5 * (-0.10) = 0.05   (all within [-1, 1])
  # ret_ls    = 0.075 - 0.05 = 0.025
  expect_equal(nrow(result), 1L)
  expect_equal(result$ret_long,  0.075, tolerance = 1e-10,
    info = "ret_long unaffected by cap (long leg)")
  expect_equal(result$ret_short, 0.05, tolerance = 1e-10,
    info = "ret_short unaffected by cap — all fwd_ret <= 1 for shorts")
  expect_equal(result$ret_ls,    0.025, tolerance = 1e-10,
    info = "ret_ls matches manual calculation; cap is a no-op in normal months")
})


# ---- 8. borrow_rate_annual (#665): charged monthly on the short leg -------

test_that(".mom_prepeak_compute_returns: borrow_rate_annual reduces ret_ls by exactly rate/12, default 0 leaves existing callers unchanged", {
  skip_no_plan()

  # Same fixture as test 7 (no cap triggered) — isolates the borrow term.
  tickers  <- c("T_LONG1", "T_LONG2", "T_SH1", "T_SH2")
  weights  <- c(0.5, 0.5, -0.5, -0.5)
  month1   <- c(T_LONG1 = 100, T_LONG2 = 100, T_SH1 = 100, T_SH2 = 100)
  month2   <- c(T_LONG1 = 100, T_LONG2 = 100, T_SH1 = 100, T_SH2 = 100)
  month3   <- c(T_LONG1 = 110, T_LONG2 = 105, T_SH1 = 120, T_SH2 = 90)

  port <- make_portfolio_tbl(tickers = tickers, weights = weights)
  univ <- make_universe_tbl(
    tickers       = tickers,
    month1_prices = month1,
    month2_prices = month2,
    month3_prices = month3
  )

  # Default (no borrow_rate_annual argument) must match an explicit 0 --
  # every caller except the 3 published mom_prepeak targets relies on this
  # (FIP screen, walk-forward gauntlet, random-peak falsification).
  result_no_arg  <- compute_returns(portfolio_tbl = port, universe_tbl = univ, cost_per_trade = 0)
  result_zero    <- compute_returns(portfolio_tbl = port, universe_tbl = univ, cost_per_trade = 0,
                                     borrow_rate_annual = 0)
  expect_equal(result_no_arg$ret_ls, result_zero$ret_ls, tolerance = 1e-10,
    info = "omitting borrow_rate_annual must be identical to passing 0 (unchanged behaviour for existing callers)")

  # Non-zero rate: ret_ls must fall by exactly rate/12 (monthly charge on
  # 100% short notional -- see roxygen on .mom_prepeak_compute_returns()).
  rate <- 0.12
  result_borrow <- compute_returns(portfolio_tbl = port, universe_tbl = univ, cost_per_trade = 0,
                                    borrow_rate_annual = rate)
  expect_equal(result_zero$ret_ls - result_borrow$ret_ls, rate / 12, tolerance = 1e-10,
    info = "borrow charge must equal borrow_rate_annual / 12 exactly")
  expect_equal(result_borrow$ret_long,  result_zero$ret_long,  tolerance = 1e-10,
    info = "borrow charge must not alter ret_long")
  expect_equal(result_borrow$ret_short, result_zero$ret_short, tolerance = 1e-10,
    info = "borrow charge must not alter ret_short (it's a separate deduction on ret_ls)")
})
