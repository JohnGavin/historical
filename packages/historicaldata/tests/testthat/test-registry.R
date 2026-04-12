test_that("hd_datasets returns expected structure", {
  ds <- hd_datasets()
  expect_type(ds, "list")
  expect_true(length(ds) >= 2)
  expect_named(ds, c("equity_daily", "crypto_daily", "macro_daily", "factors", "metadata", "metadata_amendments"), ignore.order = TRUE)

  # Each dataset has required fields
  for (nm in names(ds)) {
    expect_true(all(c("url", "schema", "frequency", "description") %in% names(ds[[nm]])),
                info = paste("Missing fields in", nm))
    expect_type(ds[[nm]]$url, "character")
    expect_type(ds[[nm]]$schema, "character")
  }
})

test_that("detect_dataset classifies tickers correctly", {
  expect_equal(historicaldata:::detect_dataset("BTC"), "crypto_daily")
  expect_equal(historicaldata:::detect_dataset("ETH"), "crypto_daily")
  expect_equal(historicaldata:::detect_dataset("SOL"), "crypto_daily")
  expect_equal(historicaldata:::detect_dataset("AAPL"), "equity_daily")
  expect_equal(historicaldata:::detect_dataset("MSFT"), "equity_daily")
})

test_that("hd_cache_path returns a path", {
  path <- hd_cache_path()
  expect_type(path, "character")
  expect_true(nzchar(path))
})

test_that("hd_datasets snapshot", {
  expect_snapshot(str(hd_datasets()))
})
