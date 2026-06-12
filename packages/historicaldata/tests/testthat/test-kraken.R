# Tests for hd_kraken_ohlcvt() (#436 Phase B)
#
# Strategy: write a small fixture parquet whose 'time' column is a proper
# TIMESTAMP (POSIXct via arrow), redirect the local cache there via
# HD_CACHE_DIR, and exercise the local = TRUE path. The remote (hf://)
# path shares all logic except source_path resolution.

.make_kraken_fixture <- function(dir) {
  hours <- as.POSIXct("2024-01-01 00:00:00", tz = "UTC") + 3600 * 0:99
  fixture <- rbind(
    tibble::tibble(
      ticker = "SOL", pair = "SOLUSD", interval_min = 60L, time = hours,
      open = 100 + 0:99, high = 101 + 0:99, low = 99 + 0:99,
      close = 100.5 + 0:99, volume = 1000, trades = 10L
    ),
    tibble::tibble(
      ticker = "EURUSD", pair = "EURUSD", interval_min = 60L, time = hours,
      open = 1.10, high = 1.11, low = 1.09, close = 1.105,
      volume = 500, trades = 5L
    ),
    tibble::tibble(
      ticker = "SOL", pair = "SOLUSD", interval_min = 1440L,
      time = as.POSIXct("2024-01-01", tz = "UTC") + 86400 * 0:9,
      open = 100, high = 110, low = 95, close = 105,
      volume = 24000, trades = 240L
    )
  )
  arrow::write_parquet(fixture, file.path(dir, "kraken_ohlcvt.parquet"))
  fixture
}

test_that("hd_kraken_ohlcvt filters ticker, interval, and typed time bounds", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckplyr")

  tmp <- withr::local_tempdir()
  .make_kraken_fixture(tmp)
  withr::local_envvar(HD_CACHE_DIR = tmp)

  # Hourly SOL, bounded window (string bounds must coerce to TIMESTAMP, #453)
  x <- hd_kraken_ohlcvt("SOL", interval_min = 60L,
                        from = "2024-01-02 00:00:00", to = "2024-01-03 00:00:00",
                        local = TRUE)
  expect_s3_class(x$time, "POSIXct")
  expect_true(all(x$ticker == "SOL"))
  expect_true(all(x$interval_min == 60L))
  expect_equal(nrow(x), 25L)  # inclusive hourly bounds: 24 + 1
  expect_true(min(x$time) >= as.POSIXct("2024-01-02 00:00:00", tz = "UTC"))
  expect_true(max(x$time) <= as.POSIXct("2024-01-03 00:00:00", tz = "UTC"))
})

test_that("hd_kraken_ohlcvt default returns all pairs at the chosen interval", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckplyr")

  tmp <- withr::local_tempdir()
  .make_kraken_fixture(tmp)
  withr::local_envvar(HD_CACHE_DIR = tmp)

  x <- hd_kraken_ohlcvt(interval_min = 60L, local = TRUE)
  expect_setequal(unique(x$ticker), c("SOL", "EURUSD"))
  expect_equal(nrow(x), 200L)

  d <- hd_kraken_ohlcvt(interval_min = 1440L, local = TRUE)
  expect_equal(unique(d$ticker), "SOL")
  expect_equal(nrow(d), 10L)
})

test_that("hd_kraken_ohlcvt rejects unsupported intervals and future dates", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckplyr")

  tmp <- withr::local_tempdir()
  .make_kraken_fixture(tmp)
  withr::local_envvar(HD_CACHE_DIR = tmp)

  expect_snapshot(error = TRUE, hd_kraken_ohlcvt("SOL", interval_min = 5L, local = TRUE))
  expect_error(
    hd_kraken_ohlcvt("SOL", to = Sys.Date() + 30, local = TRUE),
    class = "hd_future_date"
  )
})

test_that("hd_kraken_ohlcvt errors helpfully when local cache is absent", {
  skip_if_not_installed("duckplyr")

  tmp <- withr::local_tempdir()  # empty — no fixture
  withr::local_envvar(HD_CACHE_DIR = tmp)

  expect_snapshot(error = TRUE, hd_kraken_ohlcvt("SOL", local = TRUE))
})

test_that("hd_kraken_ohlcvt API signature is stable", {
  expect_snapshot(args(hd_kraken_ohlcvt))
})

test_that("kraken_ohlcvt registry entry has the canonical schema", {
  ds <- hd_datasets()[["kraken_ohlcvt"]]
  expect_false(is.null(ds))
  expect_snapshot({
    cat("schema:", paste(ds$schema, collapse = ", "), "\n")
    cat("frequency:", ds$frequency, "\n")
  })
})
