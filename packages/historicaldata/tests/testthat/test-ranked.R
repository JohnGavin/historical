# Tests for R/ranked.R — hd_top_by() and hd_most_volatile()
#
# Unit tests (no network):
#   - .pick_price_col() column-priority logic (covers Fix 2 core regression)
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
      ticker    = c("AAPL", "MSFT", "NVDA", "TSLA", "AMZN"),
      dataset   = "equity_daily",
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

# ── integration tests (remote data, CI-skipped) ───────────────────────────────

test_that("hd_top_by returns tibble from live metadata parquet", {
  skip_if_no_remote_data()

  result <- hd_top_by("equity_daily", "market_cap", n = 5)

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 5L)
  expect_true("ticker" %in% names(result))
  expect_true("market_cap" %in% names(result))
  # Rows should be in descending market_cap order
  expect_true(all(diff(result$market_cap) <= 0))
})

test_that("hd_most_volatile returns tibble with expected schema", {
  skip_if_no_remote_data()

  result <- hd_most_volatile("equity_daily", n = 3)

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 3L)
  expect_true(all(c("ticker", "vol_21d") %in% names(result)))
  # Rows are in descending volatility order
  expect_true(all(diff(result$vol_21d) <= 0))
})
