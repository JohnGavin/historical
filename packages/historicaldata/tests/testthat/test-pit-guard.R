
# Tests for point-in-time hard-error guard (issue #281, Step 2)
#
# RED phase: these tests will fail until the guard is added to the functions.

test_that("hd_ohlcv aborts when to > Sys.Date()", {
  future_date <- Sys.Date() + 30L
  expect_error(
    hd_ohlcv("AAPL", to = future_date),
    class = "hd_future_date"
  )
})

test_that("hd_ohlcv error message mentions the requested date", {
  future_date <- Sys.Date() + 30L
  expect_error(
    hd_ohlcv("AAPL", to = future_date),
    regexp = as.character(future_date)
  )
})

test_that("hd_ohlcv error mentions look-ahead", {
  future_date <- Sys.Date() + 30L
  expect_error(
    hd_ohlcv("AAPL", to = future_date),
    regexp = "look-ahead"
  )
})

test_that("hd_ohlcv accepts to = Sys.Date() without error", {
  # today is valid — should NOT trigger the guard
  # (network call: skip if offline; guard fires before any network I/O so no skip needed)
  today <- Sys.Date()
  expect_no_error(
    tryCatch(
      hd_ohlcv("AAPL", to = today),
      # Suppress network errors — we only care the guard doesn't fire
      error = function(e) {
        if (inherits(e, "hd_future_date")) stop(e)
        invisible(NULL)
      }
    )
  )
})

test_that("hd_ohlcv accepts to = Sys.Date() - 1 without error", {
  yesterday <- Sys.Date() - 1L
  expect_no_error(
    tryCatch(
      hd_ohlcv("AAPL", to = yesterday),
      error = function(e) {
        if (inherits(e, "hd_future_date")) stop(e)
        invisible(NULL)
      }
    )
  )
})

test_that("hd_ohlcv aborts on character future date string", {
  future_str <- as.character(Sys.Date() + 30L)
  expect_error(
    hd_ohlcv("AAPL", to = future_str),
    class = "hd_future_date"
  )
})

test_that("hd_macro aborts when to > Sys.Date()", {
  future_date <- Sys.Date() + 30L
  expect_error(
    hd_macro("SP500", to = future_date),
    class = "hd_future_date"
  )
})

test_that("hd_macro error message mentions the requested date", {
  future_date <- Sys.Date() + 30L
  expect_error(
    hd_macro("SP500", to = future_date),
    regexp = as.character(future_date)
  )
})

test_that("hd_macro error mentions look-ahead", {
  future_date <- Sys.Date() + 30L
  expect_error(
    hd_macro("SP500", to = future_date),
    regexp = "look-ahead"
  )
})

test_that("hd_macro accepts to = Sys.Date() without error", {
  today <- Sys.Date()
  expect_no_error(
    tryCatch(
      hd_macro("SP500", to = today),
      error = function(e) {
        if (inherits(e, "hd_future_date")) stop(e)
        invisible(NULL)
      }
    )
  )
})

test_that("hd_macro accepts to = NULL without error (no filter)", {
  # NULL to means no upper-date filter — guard must not fire
  expect_no_error(
    tryCatch(
      hd_macro("SP500", to = NULL),
      error = function(e) {
        if (inherits(e, "hd_future_date")) stop(e)
        invisible(NULL)
      }
    )
  )
})
