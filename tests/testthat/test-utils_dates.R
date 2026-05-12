testthat::local_edition(3)
source(here::here("R/utils_dates.R"))

# ── to_month_end_bizday ───────────────────────────────────────────────────────

test_that("mid-month input returns last business day of same month", {
  # Feb 28 2026 is a Saturday -> snap back to Friday Feb 27
  result <- to_month_end_bizday(as.Date("2026-02-15"))
  expect_equal(result, as.Date("2026-02-27"))
})

test_that("month-end input is idempotent when month-end is weekday", {
  # Mar 31 2026 is a Tuesday -> no snap needed
  result <- to_month_end_bizday(as.Date("2026-03-31"))
  expect_equal(result, as.Date("2026-03-31"))
})

test_that("Saturday month-end snaps to Friday", {
  # Jan 31 2026 is a Saturday -> snap to Jan 30 (Friday)
  result <- to_month_end_bizday(as.Date("2026-01-15"))
  expect_equal(result, as.Date("2026-01-30"))
})

test_that("Sunday month-end snaps to Friday two days back", {
  # Aug 31 2025 is a Sunday -> snap to Aug 29 (Friday)
  result <- to_month_end_bizday(as.Date("2025-08-15"))
  expect_equal(result, as.Date("2025-08-29"))
})

test_that("calendar month-end already a weekday is returned unchanged", {
  # Mar 31 2026 is Tuesday
  result <- to_month_end_bizday(as.Date("2026-03-15"))
  expect_equal(result, as.Date("2026-03-31"))
})

test_that("POSIXct input is coerced to Date and returns correct result", {
  posix_input <- as.POSIXct("2026-02-15 23:59:59", tz = "UTC")
  date_input  <- as.Date("2026-02-15")
  expect_equal(
    to_month_end_bizday(posix_input),
    to_month_end_bizday(date_input)
  )
})

test_that("vectorised input of length 12 returns output of length 12", {
  dates <- seq(as.Date("2026-01-15"), by = "month", length.out = 12L)
  result <- to_month_end_bizday(dates)
  expect_length(result, 12L)
  expect_s3_class(result, "Date")
})

test_that("NA input propagates to NA output without error", {
  result <- to_month_end_bizday(as.Date(NA))
  expect_true(is.na(result))
  expect_length(result, 1L)
})

test_that("character input aborts with informative cli error", {
  expect_snapshot(
    error = TRUE,
    to_month_end_bizday("2026-02-15")
  )
})

test_that("numeric input aborts with informative cli error", {
  expect_snapshot(
    error = TRUE,
    to_month_end_bizday(20250215)
  )
})

# ── to_next_month_end_bizday ──────────────────────────────────────────────────

test_that("next-month helper returns last bizday of following month", {
  # Feb 15 2026 + 32 days = Mar 19 2026 -> last bizday of March = Mar 31 (Tuesday)
  result <- to_next_month_end_bizday(as.Date("2026-02-15"))
  expect_equal(result, as.Date("2026-03-31"))
})

test_that("next-month helper at month-end boundary advances to FOLLOWING month", {
  # Jan 31 2026 + 32 days = Mar 4 2026 -> last bizday of March = Mar 31 (Tuesday)
  # (NOT Feb 27 — the +32 pushes past February entirely)
  result <- to_next_month_end_bizday(as.Date("2026-01-31"))
  expect_equal(result, as.Date("2026-03-31"))
})
