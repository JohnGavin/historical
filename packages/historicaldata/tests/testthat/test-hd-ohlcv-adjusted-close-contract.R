# Regression tests for issue #669: hd_ohlcv()/hd_lazy() must always present
# the canonical adjusted_close column, even when the underlying parquet
# still uses the legacy adjusted name (as both the live equity_daily
# parquet and the bundled sample fixture currently do -- see
# test-sample-data.R "equity sample columns match the registry schema
# (legacy 'adjusted' name)". Consumers must select adjusted_close, never bare
# "adjusted" -- see R/plan_backtest.R and friends at the repo root, all fixed
# in #669 to reference the canonical name.

test_that("hd_ohlcv() presents adjusted_close, never bare 'adjusted' (#669)", {
  local_sample_data()

  result <- hd_ohlcv("AAPL", from = "2024-01-02", to = "2024-01-08")
  expect_true("adjusted_close" %in% names(result))
  expect_false("adjusted" %in% names(result))
})

test_that("a consumer selecting adjusted_close from hd_ohlcv() succeeds (#669)", {
  local_sample_data()

  # Mirrors R/plan_backtest.R's bt_prices target after the #669 fix: select
  # the canonical column and compute a lagged return.
  result <- hd_ohlcv("AAPL", from = "2024-01-02") |>
    dplyr::arrange(date) |>
    dplyr::mutate(ret = adjusted_close / dplyr::lag(adjusted_close) - 1) |>
    dplyr::filter(!is.na(ret))

  expect_true(nrow(result) > 0)
  expect_true(all(is.finite(result$ret)))
})

test_that("hd_lazy() presents adjusted_close after collect() (#669)", {
  local_sample_data()

  result <- hd_lazy("equity_daily") |>
    dplyr::filter(ticker == "AAPL") |>
    dplyr::collect()

  expect_true("adjusted_close" %in% names(result))
  expect_false("adjusted" %in% names(result))
})

test_that(".hd_assert_price_schema() fires when adjusted_close is missing for a dataset that promises it (#669)", {
  expect_snapshot(
    error = TRUE,
    historicaldata:::.hd_assert_price_schema(c("date", "open", "close", "volume"), "equity_daily")
  )
})

test_that(".hd_assert_price_schema() is silent when adjusted_close is present (#669)", {
  expect_no_error(
    historicaldata:::.hd_assert_price_schema(c("date", "adjusted_close"), "equity_daily")
  )
})

test_that(".hd_assert_price_schema() is silent for datasets that do not promise adjusted_close (#669)", {
  expect_no_error(
    historicaldata:::.hd_assert_price_schema(c("date", "open", "close", "volume"), "crypto_daily")
  )
})

test_that(".hd_assert_price_schema() is silent for an unknown dataset (defensive default) (#669)", {
  expect_no_error(
    historicaldata:::.hd_assert_price_schema(c("date"), "not_a_real_dataset")
  )
})
