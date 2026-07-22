# Tests for R/ranked.R — hd_top_by() and hd_most_volatile()
#
# Unit tests (no network):
#   - .pick_price_col() column-priority logic (covers Fix 2 core regression)
#   - .rolling_vol_rank() rolling-vol logic with deterministic synthetic data
#   - hd_top_by() collect-before-slice with a local synthetic parquet (Fix 1)
#   - hd_top_by() invalid metric triggers informative cli_abort (snapshot)
#
# Integration tests (remote data, CI-skipped):
#   - hd_top_by() returns sorted tibble against live metadata parquet
#   - hd_most_volatile() returns tibble with expected schema

# ── .pick_price_col() — pure unit tests, no network ──────────────────────────

test_that(".pick_price_col picks adjusted_close when present", {
  expect_equal(
    historicaldata:::.pick_price_col(c("date", "adjusted_close", "adjusted", "close")),
    "adjusted_close"
  )
})

test_that(".pick_price_col falls back to adjusted when adjusted_close absent", {
  expect_equal(
    historicaldata:::.pick_price_col(c("date", "open", "high", "low", "close", "adjusted", "volume")),
    "adjusted"
  )
})

test_that(".pick_price_col falls back to close when only close present", {
  expect_equal(
    historicaldata:::.pick_price_col(c("date", "open", "high", "low", "close", "volume")),
    "close"
  )
})

test_that(".pick_price_col snapshot of priority table is stable", {
  cases <- list(
    all_three   = c("adjusted_close", "adjusted", "close"),
    adj_missing = c("adjusted", "close"),
    close_only  = c("close")
  )
  results <- vapply(cases, historicaldata:::.pick_price_col, character(1))
  expect_snapshot(results)
})

# ── .rolling_vol_rank() — pure unit tests, no network ────────────────────────
#
# The helper is the post-collect computation extracted from hd_most_volatile().
# Tests verify: column names, ordering, vol positivity, and that the higher-vol
# ticker always ranks first on a deterministic synthetic input.

test_that(".rolling_vol_rank returns higher-vol ticker first", {
  set.seed(42)
  n_rows <- 35L
  dates <- seq(as.Date("2024-01-01"), by = "day", length.out = n_rows)
  # HIGH has large daily moves (sd ~5%); LOW has tiny moves (sd ~0.1%)
  high_prices <- cumprod(c(100, 1 + rnorm(n_rows - 1L, 0, 0.05)))
  low_prices  <- cumprod(c(100, 1 + rnorm(n_rows - 1L, 0, 0.001)))

  raw <- tibble::tibble(
    ticker = rep(c("HIGH", "LOW"), each = n_rows),
    date   = rep(dates, times = 2L),
    close  = c(high_prices, low_prices)
  )

  result <- historicaldata:::.rolling_vol_rank(raw, "close", window_days = 21L, n = 2L)

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 2L)
  expect_equal(names(result), c("ticker", "vol_21d", "as_of"))
  # Higher-vol ticker must come first
  expect_equal(result$ticker[[1L]], "HIGH")
  # vol_21d is strictly descending
  expect_true(result$vol_21d[[1L]] > result$vol_21d[[2L]])
  # vol values are positive and finite
  expect_true(all(is.finite(result$vol_21d)))
  expect_true(all(result$vol_21d > 0))
})

test_that(".rolling_vol_rank returns non-NA vol_21d when window is met", {
  set.seed(7)
  n_rows <- 30L
  dates <- seq(as.Date("2024-01-01"), by = "day", length.out = n_rows)
  prices <- cumprod(c(50, 1 + rnorm(n_rows - 1L, 0, 0.02)))

  raw <- tibble::tibble(
    ticker = "ONLY",
    date   = dates,
    close  = prices
  )

  result <- historicaldata:::.rolling_vol_rank(raw, "close", window_days = 21L, n = 1L)

  expect_equal(nrow(result), 1L)
  expect_false(is.na(result$vol_21d))
  expect_true(result$vol_21d > 0)
  # as_of should be the last date in the raw data
  expect_equal(result$as_of, max(dates))
})

test_that(".rolling_vol_rank respects the price_col argument", {
  set.seed(99)
  n_rows <- 25L
  dates <- seq(as.Date("2024-01-01"), by = "day", length.out = n_rows)

  raw <- tibble::tibble(
    ticker        = "T",
    date          = dates,
    adjusted_close = cumprod(c(100, 1 + rnorm(n_rows - 1L, 0, 0.03))),
    close         = rep(100, n_rows)   # flat — would produce NA vol if used
  )

  # Using adjusted_close (has variance) should give non-NA vol
  result_ac <- historicaldata:::.rolling_vol_rank(raw, "adjusted_close", 21L, 1L)
  expect_equal(nrow(result_ac), 1L)
  expect_false(is.na(result_ac$vol_21d))
})

# ── hd_top_by() invalid metric — cli_abort snapshot ──────────────────────────

test_that("hd_top_by rejects invalid metric with informative error", {
  expect_snapshot(
    error = TRUE,
    hd_top_by("equity_daily", "not_a_metric", 3)
  )
})

# ── hd_top_by() collect-before-slice — local synthetic parquet ───────────────

test_that("hd_top_by returns top-n rows in descending order from local parquet", {
  skip_if_not_installed("arrow")

  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)

  # Synthetic metadata: 5 tickers, market_cap values deliberately out of order
  arrow::write_parquet(
    tibble::tibble(
      ticker     = c("AAPL", "MSFT", "NVDA", "TSLA", "AMZN"),
      dataset    = "equity_daily",
      market_cap = c(3.0e12, 2.8e12, 3.2e12, 0.9e12, 1.9e12),
      volume_avg = c(6e7, 4e7, 5e7, 8e7, 3e7)
    ),
    sink = tmp
  )

  # Temporarily replace hd_datasets() so hd_top_by reads the local parquet
  testthat::local_mocked_bindings(
    hd_datasets = function() list(
      metadata = list(url = tmp, schema = c("ticker", "dataset", "market_cap", "volume_avg"))
    ),
    .package = "historicaldata"
  )

  result <- hd_top_by("equity_daily", "market_cap", n = 3)

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 3L)
  # Top 3 by market_cap descending: NVDA (3.2T), AAPL (3.0T), MSFT (2.8T)
  expect_equal(result$ticker, c("NVDA", "AAPL", "MSFT"))
  # Rows are strictly descending in market_cap
  expect_true(all(diff(result$market_cap) < 0))
})

test_that("hd_top_by .data[[metric]] path works via dynamic column name", {
  skip_if_not_installed("arrow")

  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)

  arrow::write_parquet(
    tibble::tibble(
      ticker     = c("A", "B", "C"),
      dataset    = "crypto_daily",
      volume_avg = c(1000, 5000, 2000)
    ),
    sink = tmp
  )

  testthat::local_mocked_bindings(
    hd_datasets = function() list(
      metadata = list(url = tmp, schema = c("ticker", "dataset", "volume_avg"))
    ),
    .package = "historicaldata"
  )

  # volume_avg is passed as a string → exercises .data[[metric]] branch
  result <- hd_top_by("crypto_daily", "volume_avg", n = 2)

  expect_equal(nrow(result), 2L)
  # Top 2 by volume descending: B (5000), C (2000)
  expect_equal(result$ticker, c("B", "C"))
})

test_that("hd_top_by respects desc=FALSE (ascending order)", {
  skip_if_not_installed("arrow")

  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)

  arrow::write_parquet(
    tibble::tibble(
      ticker     = c("X", "Y", "Z"),
      dataset    = "equity_daily",
      market_cap = c(100, 300, 200)
    ),
    sink = tmp
  )

  testthat::local_mocked_bindings(
    hd_datasets = function() list(
      metadata = list(url = tmp, schema = c("ticker", "dataset", "market_cap"))
    ),
    .package = "historicaldata"
  )

  result <- hd_top_by("equity_daily", "market_cap", n = 2, desc = FALSE)

  expect_equal(nrow(result), 2L)
  # Bottom 2 by market_cap ascending: X (100), Z (200)
  expect_equal(result$ticker, c("X", "Z"))
})

# ── hermetic tests against the bundled sample-data fixtures (#580 Phase 2) ────
#
# Run against inst/extdata/sample/metadata_sample.parquet /
# equity_sample.parquet via local_sample_data() (helper-sample.R). The
# fixture has 55 equity tickers with market_cap/volume_avg populated for all
# of them (data-raw/make_sample_data.R), so these assertions stay meaningful.
# The original live-endpoint versions are preserved, unchanged, in
# test-remote-live.R (opt-in via HD_TEST_LIVE=1).

test_that("hd_top_by returns tibble from sample metadata parquet", {
  local_sample_data()

  result <- hd_top_by("equity_daily", "market_cap", n = 5)

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 5L)
  expect_true("ticker" %in% names(result))
  expect_true("market_cap" %in% names(result))
  # Rows should be in descending market_cap order
  expect_true(all(diff(result$market_cap) <= 0))
})

test_that("hd_most_volatile returns tibble with expected schema", {
  local_sample_data()

  result <- hd_most_volatile("equity_daily", n = 3)

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 3L)
  expect_true(all(c("ticker", "vol_21d", "as_of") %in% names(result)))
  # Rows are in descending volatility order
  expect_true(all(diff(result$vol_21d) <= 0))
})
