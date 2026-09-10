test_that("hd_datasets returns expected structure", {
  ds <- hd_datasets()
  expect_type(ds, "list")
  expect_true(length(ds) >= 2)
  expect_named(ds, c("equity_daily", "crypto_daily", "macro_daily", "factors", "macro_vintages", "metadata", "metadata_amendments", "fundamentals", "jst_macrohistory", "alphavantage_daily", "kraken_ohlcvt"), ignore.order = TRUE)

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

test_that("registry schema matches actual parquet columns for sample-backed datasets", {
  # Hermetic version (#580 Phase 2): checks only the registry entries that
  # have a bundled sample fixture (see hd_sample_path()). The full-coverage
  # version against every registry entry (including non-parquet datasets
  # like jst_macrohistory and alphavantage_daily) is preserved, unchanged,
  # in test-remote-live.R (opt-in via HD_TEST_LIVE=1).
  local_sample_data()

  ds_list <- hd_datasets()
  sample_backed <- c("equity_daily", "crypto_daily", "macro_daily", "factors", "metadata")
  for (nm in intersect(names(ds_list), sample_backed)) {
    ds <- ds_list[[nm]]
    actual_cols <- duckplyr::read_parquet_duckdb(historicaldata:::hd_dataset_source(nm)) |>
      utils::head(1) |>
      dplyr::collect() |>
      names()
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
