# Opt-in live-endpoint coverage (issue #580 Phase 2).
#
# Phase 2 made the package suite hermetic: the tests that used to read the
# live hf:// parquet endpoint now run against bundled fixtures
# (inst/extdata/sample/*.parquet, see helper-sample.R and
# hd_dataset_source() in R/registry.R) instead of skipping or flaking on
# network conditions. That trades away one thing worth keeping: does the
# REAL remote schema/shape still match what the package expects?
#
# This file preserves the original live-endpoint assertions, verbatim
# (same date ranges, same tickers), for that purpose. It is double-gated:
#   1. skip_if_no_remote_data() -- the existing three cheap guards plus the
#      one-read probe (see helper-skip.R).
#   2. HD_TEST_LIVE must be set (non-empty) -- so this file never runs by
#      default in `devtools::test()` / CI / scripts/verify.sh, only when a
#      human or a scheduled job explicitly opts in.
#
# Run explicitly with:
#   HD_TEST_LIVE=1 Rscript -e 'testthat::test_file("tests/testthat/test-remote-live.R")'
# or, from the package root:
#   Sys.setenv(HD_TEST_LIVE = "1"); devtools::test()

skip_if_not_live <- function() {
  if (!nzchar(Sys.getenv("HD_TEST_LIVE"))) {
    testthat::skip("HD_TEST_LIVE not set -- live-endpoint tests are opt-in (#580 Phase 2)")
  }
}

test_that("hd_ohlcv returns tibble for AAPL (live)", {
  skip_if_not_live()
  skip_if_no_remote_data()

  result <- hd_ohlcv("AAPL", from = "2026-04-01", to = "2026-04-10")
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) > 0)
  expect_true(all(c("date", "close", "ticker") %in% names(result)))
  expect_true(all(result$ticker == "AAPL"))
})

test_that("hd_ohlcv auto-detects crypto dataset (live)", {
  skip_if_not_live()
  skip_if_no_remote_data()

  result <- hd_ohlcv("BTC", from = "2026-04-01", to = "2026-04-10")
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) > 0)
  expect_true(all(result$ticker == "BTC"))
})

test_that("hd_macro returns data for SP500 (live)", {
  skip_if_not_live()
  skip_if_no_remote_data()

  result <- hd_macro("SP500", from = "2026-04-01")
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) > 0)
  expect_true(all(result$series_id == "SP500"))
  expect_true(all(c("date", "value", "series_id") %in% names(result)))
})

test_that("hd_factors returns FF3 daily data (live)", {
  skip_if_not_live()
  skip_if_no_remote_data()

  result <- hd_factors("FF3", "daily", from = "2026-01-01")
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) > 0)
  expect_true(all(result$dataset == "FF3"))
  expect_true("Mkt-RF" %in% result$factor_name)
})

test_that("hd_tickers returns character vector (live)", {
  skip_if_not_live()
  skip_if_no_remote_data()

  tickers <- hd_tickers("equity_daily")
  expect_type(tickers, "character")
  expect_true(length(tickers) >= 50)
  expect_true("AAPL" %in% tickers)
})

test_that("hd_macro_series returns series IDs (live)", {
  skip_if_not_live()
  skip_if_no_remote_data()

  series <- hd_macro_series()
  expect_type(series, "character")
  expect_true(length(series) >= 15)
  expect_true("SP500" %in% series)
})

test_that("hd_ohlcv split-and-bind: mixed equity + crypto batch (live)", {
  skip_if_not_live()
  skip_if_no_remote_data()

  result <- hd_ohlcv(c("AAPL", "BTC"), from = "2026-04-01", to = "2026-04-10")
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) > 0L)
  expect_true("AAPL" %in% result$ticker)
  expect_true("BTC" %in% result$ticker)
  # Union of schemas: equity-only columns are NA for crypto rows
  expect_true("adjusted_close" %in% names(result))     # equity-only column (#397)
  aapl_rows <- result[result$ticker == "AAPL", ]
  btc_rows  <- result[result$ticker == "BTC",  ]
  expect_true(all(!is.na(aapl_rows$adjusted_close)))   # AAPL has adjusted prices
  expect_true(all(is.na(btc_rows$adjusted_close)))     # BTC rows get NA for equity-only col
})

test_that("hd_ohlcv split-and-bind: single-dataset batch keeps fast path (live)", {
  skip_if_not_live()
  skip_if_no_remote_data()

  # Two equity tickers — no inform message, no split, normal collect respected
  result <- hd_ohlcv(c("AAPL", "MSFT"), from = "2026-04-01", to = "2026-04-05")
  expect_s3_class(result, "tbl_df")
  expect_setequal(unique(result$ticker), c("AAPL", "MSFT"))
})

test_that("hd_top_by returns tibble from live metadata parquet", {
  skip_if_not_live()
  skip_if_no_remote_data()

  result <- hd_top_by("equity_daily", "market_cap", n = 5)

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 5L)
  expect_true("ticker" %in% names(result))
  expect_true("market_cap" %in% names(result))
  # Rows should be in descending market_cap order
  expect_true(all(diff(result$market_cap) <= 0))
})

test_that("hd_most_volatile returns tibble with expected schema (live)", {
  skip_if_not_live()
  skip_if_no_remote_data()

  result <- hd_most_volatile("equity_daily", n = 3)

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 3L)
  expect_true(all(c("ticker", "vol_21d", "as_of") %in% names(result)))
  # Rows are in descending volatility order
  expect_true(all(diff(result$vol_21d) <= 0))
})

test_that("registry schema matches actual parquet columns for all datasets (live)", {
  skip_if_not_live()
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
