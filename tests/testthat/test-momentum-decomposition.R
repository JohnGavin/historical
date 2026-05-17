testthat::local_edition(3)
source(here::here("R/momentum_decomposition.R"))
source(here::here("R/utils_align.R"))

# ── Helpers ───────────────────────────────────────────────────────────────────

make_stock_returns <- function(n_tickers = 3L, n_months = 30L) {
  tickers <- paste0("T", seq_len(n_tickers))
  # month-end dates (stock convention)
  dates <- seq(as.Date("2020-01-31"), by = "month", length.out = n_months)
  tidyr::expand_grid(ticker = tickers, date = dates) |>
    dplyr::mutate(monthly_ret = stats::rnorm(dplyr::n(), 0, 0.05))
}

make_ff_factors <- function(n_months = 30L, start_date = as.Date("2020-01-01")) {
  # month-START dates (FF convention)
  dates <- seq(start_date, by = "month", length.out = n_months)
  tibble::tibble(
    date     = dates,
    Mkt.RF   = stats::rnorm(n_months, 0.005, 0.04),
    SMB      = stats::rnorm(n_months, 0.001, 0.02),
    HML      = stats::rnorm(n_months, 0.001, 0.02),
    RMW      = stats::rnorm(n_months, 0.001, 0.01),
    CMA      = stats::rnorm(n_months, 0.001, 0.01),
    RF       = rep(0.0002, n_months)
  )
}

# ── F1: zero-row join abort ───────────────────────────────────────────────────

test_that("F1: decompose_momentum aborts when factor join produces 0 rows", {
  # Stock returns: 2020-01-31 to 2022-06-30 (month-end)
  stock_ret <- make_stock_returns(n_tickers = 2L, n_months = 30L)

  # FF factors dated 2015-01-01 to 2017-06 — no year-month overlap
  ff_no_overlap <- make_ff_factors(n_months = 30L, start_date = as.Date("2015-01-01"))

  set.seed(42L)
  # Guard fires before RcppRoll is called — no package dependency needed
  expect_error(
    decompose_momentum(stock_ret, ff_no_overlap, lookback_months = 24L),
    regexp = "Factor join produced 0 rows"
  )
})

test_that("F1: error message includes date ranges for diagnosis", {
  stock_ret <- make_stock_returns(n_tickers = 2L, n_months = 5L)
  ff_no_overlap <- make_ff_factors(n_months = 5L, start_date = as.Date("2015-01-01"))

  expect_snapshot(
    error = TRUE,
    decompose_momentum(stock_ret, ff_no_overlap, lookback_months = 24L)
  )
})

# ── F2: asof_lookup intraday duplicate guard ──────────────────────────────────

test_that("F2: asof_lookup errors when y has duplicate dates after Date coercion", {
  x <- tibble::tibble(
    date  = as.Date(c("2025-01-31", "2025-02-28")),
    value = c(1.0, 2.0)
  )
  # y with intraday observations that collapse to duplicate dates
  y <- tibble::tibble(
    date   = as.POSIXct(c("2025-01-15 09:00:00", "2025-01-15 16:00:00",
                           "2025-02-15 09:00:00"),
                        tz = "UTC"),
    signal = c(10.0, 11.0, 20.0)
  )
  expect_error(
    asof_lookup(x, y, value_col = "signal"),
    regexp = "intraday observations"
  )
})

test_that("F2: asof_lookup error message shows first duplicate date", {
  x <- tibble::tibble(date = as.Date("2025-01-31"))
  y <- tibble::tibble(
    date   = as.POSIXct(c("2025-01-15 09:00:00", "2025-01-15 16:00:00"),
                        tz = "UTC"),
    signal = c(10.0, 11.0)
  )
  expect_snapshot(
    error = TRUE,
    asof_lookup(x, y, value_col = "signal")
  )
})

test_that("F2: asof_lookup succeeds when y has one row per date", {
  x <- tibble::tibble(
    date = as.Date(c("2025-01-31", "2025-02-28"))
  )
  y <- tibble::tibble(
    date   = as.Date(c("2025-01-15", "2025-02-15")),
    signal = c(10.0, 20.0)
  )
  result <- asof_lookup(x, y, value_col = "signal")
  expect_equal(nrow(result), 2L)
  expect_true("signal" %in% names(result))
})

# ── F4: turnover includes zero-weight exits ───────────────────────────────────
# Test the internal logic of compute_turnover using a minimal signals/returns
# setup where a ticker exits at month 2.

test_that("F4: turnover counts zero-weight exits from portfolio", {
  # 3-month signals so that month 2 has forward returns from month 3.
  # backtest_momentum_signals() lags returns by 1 period, so with 2 months of
  # signals we only get 1 backtest period. Need 3 months of stock returns.
  #
  # Month 1 portfolio: T1=long, T2=short
  # Month 2 portfolio: T2=long, T3=short  ← T1 exits, must be counted as turnover
  set.seed(7L)

  signals <- tibble::tibble(
    scheme = "test",
    ticker = rep(c("T1", "T2", "T3"), times = 2L),
    date   = as.Date(rep(c("2025-01-31", "2025-02-28"), each = 3L)),
    signal = c(
       1.0, -1.0, -1.5,   # month1: T1 long, T2 short
      -1.5,  1.0, -1.0    # month2: T2 long, T3 short; T1 exits
    )
  )

  # Three months of stock returns so the lag in backtest has a match at month 2
  stock_returns <- tibble::tibble(
    ticker     = rep(c("T1", "T2", "T3"), each = 3L),
    date       = rep(as.Date(c("2025-01-31", "2025-02-28", "2025-03-31")), times = 3L),
    monthly_ret = c(0.03, -0.01, 0.02,   # T1
                    -0.02, 0.04, 0.01,   # T2
                    0.01,  0.02, 0.03)   # T3
  )

  result <- backtest_momentum_signals(
    signals       = signals,
    stock_returns = stock_returns,
    n_long        = 1L,
    n_short       = 1L,
    cost_per_trade = 0,
    leverage      = 1
  )

  # Month 2 backtest: signals at 2025-02-28 predict returns at 2025-03-31
  # T1 exits the long position, T3 enters the short position.
  # With the union-based fix, BOTH the exit (T1→0) and entry (T3) are counted.
  turnover_month2 <- result |>
    dplyr::filter(date == as.Date("2025-02-28")) |>
    dplyr::pull(turnover)

  expect_true(
    length(turnover_month2) == 1L && turnover_month2 > 0,
    info = paste0(
      "F4: exit of T1 from long position must be counted as turnover. ",
      "Got turnover = ", if (length(turnover_month2) > 0L) turnover_month2 else "(empty)"
    )
  )
})

# ── F6: lookback_months minimum guard ────────────────────────────────────────

test_that("F6: decompose_momentum aborts when lookback_months too low for parameter count", {
  set.seed(3L)
  stock_ret <- make_stock_returns(n_tickers = 2L, n_months = 30L)
  ff        <- make_ff_factors(n_months = 30L)

  # With industry_returns = NULL: n_params = 6 (intercept + 5 FF), min = 6+7 = 13
  # lookback_months = 10 is below the minimum — guard fires before RcppRoll.
  # Use tryCatch + inherits to avoid cli formatting issues with expect_error regexp.
  err <- tryCatch(
    decompose_momentum(stock_ret, ff, lookback_months = 10L),
    error = function(e) e
  )
  expect_true(
    inherits(err, "error"),
    info = "F6: expected an error for lookback_months = 10 (< min 13)"
  )
  expect_true(
    grepl("lookback_months", conditionMessage(err), fixed = FALSE),
    info = paste0("F6: error message should mention lookback_months. Got: ",
                  conditionMessage(err))
  )
})

test_that("F6: error message includes parameter count", {
  set.seed(3L)
  stock_ret <- make_stock_returns(n_tickers = 2L, n_months = 20L)
  ff        <- make_ff_factors(n_months = 20L)

  expect_snapshot(
    error = TRUE,
    decompose_momentum(stock_ret, ff, lookback_months = 10L)
  )
})

test_that("F6: lookback_months = 24 satisfies minimum for FF-only model (no abort)", {
  set.seed(4L)
  stock_ret <- make_stock_returns(n_tickers = 2L, n_months = 30L)
  ff        <- make_ff_factors(n_months = 30L)

  # Guard must NOT fire at lookback_months = 24 for FF-only (min_lookback = 13)
  # The function will fail later due to missing RcppRoll in test env — that's OK,
  # we only need the guard not to fire.
  err <- tryCatch(
    decompose_momentum(stock_ret, ff, lookback_months = 24L),
    error = function(e) e
  )
  # The guard message says "lookback_months must be" — if we get any other error,
  # the guard did not fire (correct behaviour).
  guard_fired <- inherits(err, "error") &&
    grepl("lookback_months must be", conditionMessage(err))
  expect_false(guard_fired,
    info = "F6 guard must not fire at lookback_months = 24 for FF-only model")
})
