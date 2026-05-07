test_that("hd_ecb_registry has expected entries", {
  reg <- hd_ecb_registry()
  expect_type(reg, "list")
  for (nm in c("eurusd", "eurgbp", "euribor_3m", "ecb_refi_rate",
               "yield_curve_10y", "hicp_inflation", "ciss_composite")) {
    expect_true(nm %in% names(reg), info = paste("missing:", nm))
    expect_true(all(c("key", "description", "frequency", "unit") %in% names(reg[[nm]])),
                info = paste("incomplete fields in", nm))
  }
})

test_that("hd_ecb parses daily series success path", {
  skip_if_not_installed("httr2")
  csv_body <- "KEY,FREQ,TIME_PERIOD,OBS_VALUE\nEXR/D.USD.EUR.SP00.A,D,2024-01-02,1.0956\nEXR/D.USD.EUR.SP00.A,D,2024-01-03,1.0921\n"
  fake <- function(req) {
    httr2::response(
      status_code = 200,
      headers = list(`Content-Type` = "text/csv"),
      body = charToRaw(csv_body)
    )
  }
  result <- httr2::with_mocked_responses(fake, {
    hd_ecb("EXR/D.USD.EUR.SP00.A", start = "2024-01-01")
  })
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 2L)
  expect_equal(result$frequency, c("daily", "daily"))
  expect_equal(result$date, as.Date(c("2024-01-02", "2024-01-03")))
  expect_equal(result$value, c(1.0956, 1.0921))
})

test_that("hd_ecb parses monthly series (YYYY-MM) success path", {
  skip_if_not_installed("httr2")
  csv_body <- "KEY,FREQ,TIME_PERIOD,OBS_VALUE\nFM/M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA,M,2024-01,3.92\nFM/M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA,M,2024-02,3.93\n"
  fake <- function(req) {
    httr2::response(
      status_code = 200,
      headers = list(`Content-Type` = "text/csv"),
      body = charToRaw(csv_body)
    )
  }
  result <- httr2::with_mocked_responses(fake, {
    hd_ecb("FM/M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA")
  })
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 2L)
  expect_equal(result$frequency, c("monthly", "monthly"))
  expect_equal(result$date, as.Date(c("2024-01-01", "2024-02-01")))
  expect_equal(result$value, c(3.92, 3.93))
})

test_that("hd_ecb returns NULL on non-200 response with warning", {
  skip_if_not_installed("httr2")
  fake <- function(req) {
    httr2::response(
      status_code = 404,
      headers = list(`Content-Type` = "text/plain"),
      body = charToRaw("not found")
    )
  }
  result <- httr2::with_mocked_responses(fake, {
    expect_warning(hd_ecb("BAD/KEY"))
  })
  expect_null(suppressWarnings(httr2::with_mocked_responses(fake, hd_ecb("BAD/KEY"))))
})

test_that("hd_ecb returns NULL on malformed schema with warning", {
  skip_if_not_installed("httr2")
  csv_body <- "FOO,BAR\n1,2\n"
  fake <- function(req) {
    httr2::response(
      status_code = 200,
      headers = list(`Content-Type` = "text/csv"),
      body = charToRaw(csv_body)
    )
  }
  expect_warning(
    result <- httr2::with_mocked_responses(fake, hd_ecb("FOO/BAR"))
  )
  expect_null(suppressWarnings(httr2::with_mocked_responses(fake, hd_ecb("FOO/BAR"))))
})
