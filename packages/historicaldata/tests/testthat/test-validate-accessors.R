# Accessor-layer date-type validation (#616).
#
# check_date_key_types() only covers registered pipeline targets (root
# R/utils_validation.R). These tests cover the gap: the exported accessors
# themselves, called directly, hermetically (HD_USE_SAMPLE_DATA=1) so they
# run in r-tests CI on every PR touching packages/historicaldata/**.

test_that("hd_check_accessor_date_types: default probe set is internally consistent (#615/#616)", {
  local_sample_data()

  result <- hd_check_accessor_date_types()

  expect_s3_class(result, "tbl_df")
  expect_true(all(c("accessor", "status", "date_class") %in% names(result)))
  expect_true(all(result$status == "ok"))

  # The point of #615: hd_ohlcv(), hd_macro(), hd_factors() must agree.
  expect_length(unique(result$date_class), 1L)
  expect_equal(unique(result$date_class), "Date")
})

test_that("hd_check_accessor_date_types: aborts on a genuine mismatch, naming accessor + class", {
  fake_accessors <- list(
    a = function() tibble::tibble(date = as.Date("2024-01-01"), x = 1),
    b = function() tibble::tibble(date = as.POSIXct("2024-01-01", tz = "UTC"), x = 1)
  )

  expect_snapshot(
    error = TRUE,
    hd_check_accessor_date_types(fake_accessors)
  )
})

test_that("hd_check_accessor_date_types: aborts when an accessor has no date column", {
  fake_accessors <- list(
    a = function() tibble::tibble(date = as.Date("2024-01-01"), x = 1),
    b = function() tibble::tibble(not_date = 1, x = 1)
  )

  expect_snapshot(
    error = TRUE,
    hd_check_accessor_date_types(fake_accessors)
  )
})

test_that("hd_check_accessor_date_types: an erroring accessor is skipped, not a failure", {
  fake_accessors <- list(
    a = function() tibble::tibble(date = as.Date("2024-01-01"), x = 1),
    b = function() stop("no network")
  )

  result <- suppressMessages(hd_check_accessor_date_types(fake_accessors))
  expect_equal(result$status, c("ok", "skipped"))
})

test_that("hd_check_accessor_date_types: empty accessor list returns empty tibble", {
  result <- hd_check_accessor_date_types(list())
  expect_equal(nrow(result), 0L)
  expect_true(all(c("accessor", "status", "date_class") %in% names(result)))
})

test_that("hd_check_accessor_date_types: rejects an unnamed accessor list", {
  expect_snapshot(error = TRUE, hd_check_accessor_date_types(list(function() NULL)))
})
