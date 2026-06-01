test_that("hd_datasets returns expected structure", {
  ds <- hd_datasets()
  expect_type(ds, "list")
  expect_true(length(ds) >= 2)
  expect_named(ds, c("equity_daily", "crypto_daily", "macro_daily", "factors", "macro_vintages", "metadata", "metadata_amendments", "jst_macrohistory", "alphavantage_daily"), ignore.order = TRUE)

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

test_that("registry schema matches actual parquet columns for all datasets", {
  skip_if_no_remote_data()

  ds_list <- hd_datasets()
  for (nm in names(ds_list)) {
    ds <- ds_list[[nm]]
    # Read one row to get column names without downloading full parquet
    actual_cols <- tryCatch(
      duckplyr::read_parquet_duckdb(ds$url) |>
        utils::head(1) |>
        dplyr::collect() |>
        names(),
      error = function(e) {
        testthat::skip(paste("Cannot reach", nm, "parquet:", conditionMessage(e)))
        character(0)
      }
    )
    if (!length(actual_cols)) next
    # Apply the same backward-compat alias that hd_lazy()/hd_ohlcv_single()
    # applies at read time (#325 / #397): parquets written before the rename
    # still contain 'adjusted'; the schema declares the post-alias canonical
    # name 'adjusted_close'.  Normalise before comparing so this test checks
    # the caller-visible schema, not the raw parquet column names.
    if ("adjusted" %in% actual_cols && !("adjusted_close" %in% actual_cols)) {
      actual_cols[actual_cols == "adjusted"] <- "adjusted_close"
    }
    missing_from_parquet <- setdiff(ds$schema, actual_cols)
    extra_in_parquet     <- setdiff(actual_cols, ds$schema)
    msg <- paste0(
      "dataset '", nm, "': ",
      if (length(missing_from_parquet)) paste("in schema not in parquet:", paste(missing_from_parquet, collapse=", ")),
      if (length(extra_in_parquet))     paste("in parquet not in schema:", paste(extra_in_parquet, collapse=", "))
    )
    expect_true(
      setequal(actual_cols, ds$schema),
      label = msg
    )
  }
})
