test_that("hd_ohlcv returns tibble for AAPL", {
  skip_on_cran()
  skip_if_offline()

  result <- hd_ohlcv("AAPL", from = "2026-04-01", to = "2026-04-10")
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) > 0)
  expect_true(all(c("date", "close", "ticker") %in% names(result)))
  expect_true(all(result$ticker == "AAPL"))
})

test_that("hd_ohlcv auto-detects crypto dataset", {
  expect_equal(historicaldata:::detect_dataset("BONK"), "crypto_daily")

  skip_on_cran()
  skip_if_offline()

  result <- hd_ohlcv("BTC", from = "2026-04-01", to = "2026-04-10")
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) > 0)
  expect_true(all(result$ticker == "BTC"))
})

test_that("hd_macro returns data for SP500", {
  skip_on_cran()
  skip_if_offline()

  result <- hd_macro("SP500", from = "2026-04-01")
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) > 0)
  expect_true(all(result$series_id == "SP500"))
  expect_true(all(c("date", "value", "series_id") %in% names(result)))
})

test_that("hd_factors returns FF3 daily data", {
  skip_on_cran()
  skip_if_offline()

  result <- hd_factors("FF3", "daily", from = "2026-01-01")
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) > 0)
  expect_true(all(result$dataset == "FF3"))
  expect_true("Mkt-RF" %in% result$factor_name)
})

test_that("hd_tickers returns character vector", {
  skip_on_cran()
  skip_if_offline()

  tickers <- hd_tickers("equity_daily")
  expect_type(tickers, "character")
  expect_true(length(tickers) >= 50)
  expect_true("AAPL" %in% tickers)
})

test_that("hd_macro_series returns series IDs", {
  skip_on_cran()
  skip_if_offline()

  series <- hd_macro_series()
  expect_type(series, "character")
  expect_true(length(series) >= 15)
  expect_true("SP500" %in% series)
})

test_that("hd_ohlcv snapshot of AAPL structure", {
  skip_on_cran()
  skip_if_offline()

  result <- hd_ohlcv("AAPL", from = "2026-04-07", to = "2026-04-10")
  expect_snapshot(str(result))
})

test_that("hd_datasets snapshot", {
  expect_snapshot(str(hd_datasets()))
})

test_that("hd_connect_local handles quoted parquet paths", {
  skip_if_not_installed("arrow")

  cache_dir <- tempfile("hd-cache-'")
  dir.create(cache_dir)
  arrow::write_parquet(tibble::tibble(x = 1), file.path(cache_dir, "sample.parquet"))

  con <- hd_connect_local(cache_dir)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  result <- DBI::dbGetQuery(con, "SELECT x FROM sample")
  expect_equal(result$x, 1)
})
