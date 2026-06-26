testthat::local_edition(3)
source(here::here("R/crypto_momentum.R"))

# ── Helpers ───────────────────────────────────────────────────────────────────

# Minimal daily crypto-style data spanning 2020-2022
make_crypto_returns <- function() {
  dates <- seq(as.Date("2020-01-01"), as.Date("2022-12-31"), by = "day")
  tickers <- c("BTC", "ETH", "XRP", "LTC", "ADA", "SOL")
  df <- tidyr::expand_grid(ticker = tickers, date = dates)
  set.seed(42L)
  df$ret <- stats::rnorm(nrow(df), 0, 0.03)
  df
}

# Minimal signals for backtest (one signal per ticker per month-end)
make_crypto_signals <- function(n_months = 6L) {
  tickers <- c("BTC", "ETH", "XRP", "LTC", "ADA", "SOL", "DOT", "LINK", "UNI", "AVAX")
  dates <- seq(as.Date("2020-01-31"), by = "month", length.out = n_months)
  df <- tidyr::expand_grid(date = dates, ticker = tickers)
  set.seed(7L)
  df$signal <- stats::rnorm(nrow(df))
  df
}

# ── Fix #489 Cluster B: POSIXct-vs-Date filter regression test ───────────────

test_that("C1: as.Date coercion makes POSIXct dates filterable against Date bounds", {
  # Reproduce the parquet scenario: date column arrives as POSIXct.
  # Without coercion, comparison against Date bounds returns 0 rows.
  # With coercion (the fix), it returns the expected subset.
  posixct_dates <- as.POSIXct(
    c("2020-06-01 00:00:00", "2020-07-15 00:00:00", "2021-03-10 00:00:00",
      "2014-12-31 00:00:00", "2027-01-05 00:00:00"),
    tz = "UTC"
  )
  df <- tibble::tibble(
    date   = posixct_dates,
    ticker = paste0("C", seq_along(posixct_dates)),
    close  = c(100, 200, 300, 50, 400)
  )

  sample_start <- as.Date("2017-01-01")  # Date object (as in crypto_mom_params)
  sample_end   <- as.Date("2026-12-31")

  # Without the fix: POSIXct vs Date comparison — expect 0 rows (demonstrates the bug)
  rows_without_fix <- df |>
    dplyr::filter(date >= sample_start, date <= sample_end) |>
    nrow()
  # This should be 0 — POSIXct vs Date silently produces no matches
  expect_equal(rows_without_fix, 0L,
    info = "POSIXct vs Date comparison must return 0 rows (pre-fix behaviour)")

  # With the fix: coerce to Date first — expect 3 rows (the 2020, 2020, 2021 entries)
  rows_with_fix <- df |>
    dplyr::mutate(date = as.Date(date)) |>
    dplyr::filter(date >= sample_start, date <= sample_end) |>
    nrow()
  expect_equal(rows_with_fix, 3L,
    info = "After as.Date() coercion, filter must keep the 3 in-range rows")
})

test_that("C1: as.Date coercion is a no-op when date is already Date", {
  # Confirm the fix is safe even when the parquet schema already returns Date
  date_col <- as.Date(c("2020-01-01", "2021-06-15", "2015-12-31"))
  df <- tibble::tibble(date = date_col, ticker = "BTC", close = 1)
  result <- df |> dplyr::mutate(date = as.Date(date))
  expect_s3_class(result$date, "Date")
  expect_equal(result$date, date_col)
})

# ── Defensive guard: empty signals / rebalance_dates ─────────────────────────

test_that("C2: backtest_crypto_momentum aborts informatively on empty signals", {
  empty_signals <- tibble::tibble(
    date   = as.Date(character(0)),
    ticker = character(0),
    signal = numeric(0)
  )
  empty_returns <- tibble::tibble(
    date   = as.Date(character(0)),
    ticker = character(0),
    ret    = numeric(0)
  )

  expect_snapshot(
    error = TRUE,
    backtest_crypto_momentum(empty_signals, empty_returns)
  )
})

test_that("C2: guard error message mentions empty universe as cause", {
  empty_signals <- tibble::tibble(
    date   = as.Date(character(0)),
    ticker = character(0),
    signal = numeric(0)
  )
  returns <- make_crypto_returns()

  err <- tryCatch(
    backtest_crypto_momentum(empty_signals, returns),
    error = function(e) e
  )
  expect_true(inherits(err, "error"))
  expect_true(
    grepl("empty universe", conditionMessage(err), fixed = FALSE),
    info = paste0("Error message should mention 'empty universe'. Got: ", conditionMessage(err))
  )
})

test_that("C2: backtest_crypto_momentum runs without error on well-formed inputs", {
  signals  <- make_crypto_signals(n_months = 6L)
  returns  <- make_crypto_returns()

  # Should not error; spot-check result structure
  result <- backtest_crypto_momentum(
    signals, returns,
    cost_bps = 30, n_long = 3L, n_short = 3L
  )
  expect_type(result, "list")
  expect_true("performance" %in% names(result))
  expect_true("summary" %in% names(result))
  expect_true(nrow(result$performance) > 0L)
})
