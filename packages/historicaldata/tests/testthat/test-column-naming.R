# Regression tests for #325: canonical adjusted_close column across datasets.

test_that("equity_daily schema uses adjusted_close, not adjusted", {
  ds <- hd_datasets()
  schema <- ds[["equity_daily"]][["schema"]]
  expect_true("adjusted_close" %in% schema,
              label = "equity_daily schema must contain 'adjusted_close'")
  expect_false("adjusted" %in% schema,
               label = "equity_daily schema must NOT contain bare 'adjusted'")
})

test_that("alphavantage_daily schema uses adjusted_close", {
  ds <- hd_datasets()
  schema <- ds[["alphavantage_daily"]][["schema"]]
  expect_true("adjusted_close" %in% schema,
              label = "alphavantage_daily schema must contain 'adjusted_close'")
  expect_false("adjusted" %in% schema,
               label = "alphavantage_daily schema must NOT contain bare 'adjusted'")
})

test_that("backward-compat alias: old 'adjusted' column is renamed to 'adjusted_close'", {
  # Simulate a parquet-like tibble with the OLD column name
  old_frame <- tibble::tibble(
    date          = as.Date(c("2024-01-02", "2024-01-03")),
    open          = c(185.5, 186.0),
    high          = c(187.1, 188.0),
    low           = c(184.9, 185.5),
    close         = c(186.8, 187.5),
    adjusted      = c(186.0, 186.7),   # OLD column name
    volume        = c(50000000L, 48000000L),
    ticker        = c("AAPL", "AAPL"),
    source        = c("yahoo", "yahoo"),
    asset_class   = c("equity", "equity")
  )

  # Apply the same alias logic used inside hd_lazy() / hd_ohlcv_single()
  col_names <- names(old_frame)
  if ("adjusted" %in% col_names && !("adjusted_close" %in% col_names)) {
    old_frame <- dplyr::rename(old_frame, adjusted_close = adjusted)
  }

  expect_true("adjusted_close" %in% names(old_frame),
              label = "alias must produce 'adjusted_close'")
  expect_false("adjusted" %in% names(old_frame),
               label = "old 'adjusted' column must be gone after alias")
})

test_that("backward-compat alias is a no-op when adjusted_close already present", {
  new_frame <- tibble::tibble(
    date           = as.Date("2024-01-02"),
    close          = 186.8,
    adjusted_close = 186.0,
    ticker         = "AAPL"
  )

  col_names <- names(new_frame)
  if ("adjusted" %in% col_names && !("adjusted_close" %in% col_names)) {
    new_frame <- dplyr::rename(new_frame, adjusted_close = adjusted)
  }

  expect_true("adjusted_close" %in% names(new_frame))
  expect_false("adjusted" %in% names(new_frame))
  expect_equal(nrow(new_frame), 1L)
})

test_that("hd_alphavantage output uses adjusted_close", {
  skip_if_not_installed("alphavantager")
  mock_result <- tibble::tibble(
    timestamp         = as.Date(c("2024-01-02", "2024-01-03")),
    open              = c(185.5, 186.0),
    high              = c(187.1, 188.0),
    low               = c(184.9, 185.5),
    close             = c(186.8, 187.5),
    adjusted_close    = c(186.0, 186.7),
    volume            = c(50000000L, 48000000L),
    dividend_amount   = c(0, 0),
    split_coefficient = c(1, 1)
  )
  testthat::local_mocked_bindings(
    av_get = function(...) mock_result,
    .package = "alphavantager"
  )
  withr::with_envvar(c(ALPHAVANTAGE_API_KEY = "demo"), {
    result <- hd_alphavantage("AAPL", from = "2024-01-01")
  })
  expect_true("adjusted_close" %in% names(result),
              label = "hd_alphavantage() must return 'adjusted_close'")
  expect_false("adjusted" %in% names(result),
               label = "hd_alphavantage() must NOT return bare 'adjusted'")
})
