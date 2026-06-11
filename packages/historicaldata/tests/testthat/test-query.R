test_that("hd_ohlcv returns tibble for AAPL", {
  skip_if_no_remote_data()

  result <- hd_ohlcv("AAPL", from = "2026-04-01", to = "2026-04-10")
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) > 0)
  expect_true(all(c("date", "close", "ticker") %in% names(result)))
  expect_true(all(result$ticker == "AAPL"))
})

test_that("hd_ohlcv auto-detects crypto dataset", {
  expect_equal(historicaldata:::detect_dataset("BONK"), "crypto_daily")

  skip_if_no_remote_data()

  result <- hd_ohlcv("BTC", from = "2026-04-01", to = "2026-04-10")
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) > 0)
  expect_true(all(result$ticker == "BTC"))
})

test_that("hd_macro returns data for SP500", {
  skip_if_no_remote_data()

  result <- hd_macro("SP500", from = "2026-04-01")
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) > 0)
  expect_true(all(result$series_id == "SP500"))
  expect_true(all(c("date", "value", "series_id") %in% names(result)))
})

test_that("hd_factors returns FF3 daily data", {
  skip_if_no_remote_data()

  result <- hd_factors("FF3", "daily", from = "2026-01-01")
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) > 0)
  expect_true(all(result$dataset == "FF3"))
  expect_true("Mkt-RF" %in% result$factor_name)
})

test_that("hd_tickers returns character vector", {
  skip_if_no_remote_data()

  tickers <- hd_tickers("equity_daily")
  expect_type(tickers, "character")
  expect_true(length(tickers) >= 50)
  expect_true("AAPL" %in% tickers)
})

test_that("hd_macro_series returns series IDs", {
  skip_if_no_remote_data()

  series <- hd_macro_series()
  expect_type(series, "character")
  expect_true(length(series) >= 15)
  expect_true("SP500" %in% series)
})

test_that("hd_ohlcv snapshot of AAPL structure", {
  skip_if_no_remote_data()

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

test_that("hd_ohlcv split-and-bind: mixed equity + crypto batch", {
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

test_that("hd_ohlcv split-and-bind: collect=FALSE informs user", {
  skip_if_no_remote_data()

  expect_snapshot(
    result <- hd_ohlcv(c("AAPL", "BTC"), from = "2026-04-01",
                       to = "2026-04-05", collect = FALSE)
  )
  expect_s3_class(result, "tbl_df")  # materialised despite collect=FALSE
})

test_that("hd_ohlcv split-and-bind: single-dataset batch keeps fast path", {
  skip_if_no_remote_data()

  # Two equity tickers — no inform message, no split, normal collect respected
  result <- hd_ohlcv(c("AAPL", "MSFT"), from = "2026-04-01", to = "2026-04-05")
  expect_s3_class(result, "tbl_df")
  expect_setequal(unique(result$ticker), c("AAPL", "MSFT"))
})

test_that("hd_ohlcv: empty ticker vector errors", {
  expect_snapshot(error = TRUE, hd_ohlcv(character(0)))
})

# ── Regression tests for #453 ──────────────────────────────────────────────────
# Root cause: DuckDB throws an INTERNAL exception when comparing a TIMESTAMP_NS
# column (HF equity_daily parquet) against either a STRING_LITERAL or a DATE
# literal inside a stingy duckplyr frame.  The fix probes the 'date' column
# type via head(0)|>collect() and injects:
#   TIMESTAMP column → as.POSIXct(tz="UTC")  (TIMESTAMP candidate matches)
#   DATE column      → as.Date()              (DATE candidate matches)
# These tests use a local temp parquet so they run offline.

test_that("date filter works against TIMESTAMP-typed parquet column (#453)", {
  skip_if_not_installed("duckdb")

  # Write a tiny parquet whose 'date' column is TIMESTAMP (not DATE) —
  # replicating the HF equity_daily schema.
  tmp_parquet <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp_parquet), add = TRUE)

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, paste0(
    "COPY (SELECT ",
    "  CAST(d AS TIMESTAMP) AS date, ",
    "  'SPY' AS ticker, ",
    "  100.0 + ROW_NUMBER() OVER () AS close ",
    "FROM UNNEST(CAST(['1994-01-03','1994-02-01','1994-03-01','1994-04-01'] AS DATE[])) t(d)) ",
    "TO '", tmp_parquet, "' (FORMAT PARQUET)"
  ))

  # Probe the date column class — should be POSIXct for TIMESTAMP parquet
  schema0 <- duckplyr::read_parquet_duckdb(tmp_parquet) |> head(0) |> dplyr::collect()
  expect_true(inherits(schema0[["date"]], "POSIXct"))

  # Filter using as.POSIXct (the fixed pattern for TIMESTAMP columns)
  from_ts <- as.POSIXct("1994-01-01", tz = "UTC")
  to_ts   <- as.POSIXct("1994-03-01", tz = "UTC")

  result <- duckplyr::read_parquet_duckdb(tmp_parquet) |>
    dplyr::filter(date >= !!from_ts, date <= !!to_ts) |>
    dplyr::collect()

  # Should include 1994-01-03, 1994-02-01, 1994-03-01 (3 rows); not 1994-04-01
  expect_equal(nrow(result), 3L)
  expect_true(all(result$date <= as.POSIXct("1994-03-01", tz = "UTC")))
  expect_true(all(result$date >= as.POSIXct("1994-01-01", tz = "UTC")))

  # Snapshot: stable structure
  expect_snapshot(names(result))
})

test_that("date filter works with character from/to for TIMESTAMP column (#453)", {
  skip_if_not_installed("duckdb")

  tmp_parquet <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp_parquet), add = TRUE)

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, paste0(
    "COPY (SELECT ",
    "  CAST(d AS TIMESTAMP) AS date, ",
    "  'SPY' AS ticker, ",
    "  1.0 AS close ",
    "FROM UNNEST(CAST(['1994-01-03','1994-02-01','1994-03-15'] AS DATE[])) t(d)) ",
    "TO '", tmp_parquet, "' (FORMAT PARQUET)"
  ))

  # Mimic what hd_ohlcv_single() does: probe type, then inject as.POSIXct
  from <- "1994-02-01"
  to   <- "1994-03-15"
  schema0 <- duckplyr::read_parquet_duckdb(tmp_parquet) |> head(0) |> dplyr::collect()
  date_coerce <- if (inherits(schema0[["date"]], "POSIXct")) {
    function(x) as.POSIXct(x, tz = "UTC")
  } else {
    as.Date
  }

  result <- duckplyr::read_parquet_duckdb(tmp_parquet) |>
    dplyr::filter(date >= !!date_coerce(from), date <= !!date_coerce(to)) |>
    dplyr::collect()

  expect_equal(nrow(result), 2L)  # 1994-02-01 and 1994-03-15, not 1994-01-03
})

test_that("date filter works against DATE-typed parquet column (#453)", {
  skip_if_not_installed("duckdb")

  tmp_parquet <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp_parquet), add = TRUE)

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, paste0(
    "COPY (SELECT ",
    "  CAST(d AS DATE) AS date, ",
    "  'SP500' AS series_id, ",
    "  100.0 AS value ",
    "FROM UNNEST(CAST(['1994-01-03','1994-02-01','1994-04-01'] AS DATE[])) t(d)) ",
    "TO '", tmp_parquet, "' (FORMAT PARQUET)"
  ))

  # Probe: DATE parquet should give Date class, not POSIXct
  schema0 <- duckplyr::read_parquet_duckdb(tmp_parquet) |> head(0) |> dplyr::collect()
  expect_false(inherits(schema0[["date"]], "POSIXct"))
  expect_true(inherits(schema0[["date"]], "Date"))

  # Filter using as.Date (the fixed pattern for DATE columns)
  result <- duckplyr::read_parquet_duckdb(tmp_parquet) |>
    dplyr::filter(date >= !!as.Date("1994-01-01"), date <= !!as.Date("1994-03-01")) |>
    dplyr::collect()

  expect_equal(nrow(result), 2L)  # 1994-01-03 and 1994-02-01; not 1994-04-01
})

test_that("hd_ohlcv: API stability snapshot (#453)", {
  expect_snapshot(args(hd_ohlcv))
})
