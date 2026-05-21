test_that("hd_av_registry returns expected structure", {
  reg <- hd_av_registry()
  expect_type(reg, "list")
  expect_true("alphavantage_daily" %in% names(reg))

  entry <- reg$alphavantage_daily
  expect_true(all(c("source", "schema", "frequency", "description",
                    "rate_limit", "key_env") %in% names(entry)))
  expect_equal(entry$frequency, "daily")
  expect_true(grepl("ALPHAVANTAGE_API_KEY", entry$key_env))
  expect_true(grepl("5", entry$rate_limit$calls_per_min))
})

test_that("hd_av_registry schema contains required columns", {
  reg <- hd_av_registry()
  expected_schema <- c("date", "open", "high", "low", "close",
                       "adjusted_close", "volume", "ticker")
  schema <- reg$alphavantage_daily$schema
  for (col in expected_schema) {
    expect_true(col %in% schema, info = paste("missing schema column:", col))
  }
})

test_that("hd_alphavantage aborts with informative message when key missing", {
  skip_if_not_installed("alphavantager")
  withr::with_envvar(c(ALPHAVANTAGE_API_KEY = ""), {
    expect_error(
      hd_alphavantage("AAPL", from = "2024-01-01"),
      regexp = "ALPHAVANTAGE_API_KEY"
    )
  })
})

test_that("hd_alphavantage returns tidy tibble on success path (mocked)", {
  skip_if_not_installed("alphavantager")
  # Mock av_get to avoid live API call
  mock_result <- tibble::tibble(
    timestamp            = as.Date(c("2024-01-02", "2024-01-03")),
    open                 = c(185.5, 186.0),
    high                 = c(187.1, 188.0),
    low                  = c(184.9, 185.5),
    close                = c(186.8, 187.5),
    adjusted_close       = c(186.0, 186.7),
    volume               = c(50000000L, 48000000L),
    dividend_amount      = c(0, 0),
    split_coefficient    = c(1, 1)
  )
  # Use local mock via testthat::local_mocked_bindings (testthat 3.1+)
  testthat::local_mocked_bindings(
    av_get = function(...) mock_result,
    .package = "alphavantager"
  )
  withr::with_envvar(c(ALPHAVANTAGE_API_KEY = "demo"), {
    result <- hd_alphavantage("AAPL", from = "2024-01-01")
  })
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 2L)
  expected_cols <- c("date", "open", "high", "low", "close",
                     "adjusted_close", "volume", "ticker")
  for (col in expected_cols) {
    expect_true(col %in% names(result), info = paste("missing output column:", col))
  }
  expect_equal(result$ticker, c("AAPL", "AAPL"))
  expect_equal(result$date, as.Date(c("2024-01-02", "2024-01-03")))
})

test_that("hd_alphavantage skips live API when key not set", {
  skip_if_not_installed("alphavantager")
  skip_if(nzchar(Sys.getenv("ALPHAVANTAGE_API_KEY")),
          "Skipping: ALPHAVANTAGE_API_KEY is set (would make live call)")
  expect_error(
    hd_alphavantage("IBM", from = "2024-01-01"),
    regexp = "ALPHAVANTAGE_API_KEY"
  )
})
