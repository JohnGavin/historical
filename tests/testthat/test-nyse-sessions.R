testthat::local_edition(3)
source(here::here("R/utils_nyse_sessions.R"))

# R/utils_nyse_sessions.R (#1080). Times are given in UTC; the comment shows the
# New York wall clock. New York is UTC-5 in winter (EST) and UTC-4 in summer (EDT).

.u <- function(x) as.POSIXct(x, tz = "UTC")
.s <- function(x) as.character(nyse_session(.u(x)))

test_that("a normal Tuesday changes session at every boundary (EST)", {
  # 2026-11-24 is a Tuesday, EST (UTC-5)
  expect_equal(.s("2026-11-24 14:29:59"), "extended")   # 09:29:59
  expect_equal(.s("2026-11-24 14:30:00"), "regular")    # 09:30:00
  expect_equal(.s("2026-11-24 20:59:59"), "regular")    # 15:59:59
  expect_equal(.s("2026-11-24 21:00:00"), "extended")   # 16:00:00
  expect_equal(.s("2026-11-25 00:59:59"), "extended")   # 19:59:59
  expect_equal(.s("2026-11-25 01:00:00"), "overnight")  # 20:00:00
  expect_equal(.s("2026-11-24 08:59:59"), "overnight")  # 03:59:59
  expect_equal(.s("2026-11-24 09:00:00"), "extended")   # 04:00:00
})

test_that("session boundaries follow daylight saving (2026-03-08 and 2026-11-01)", {
  # Spring forward is Sun 2026-03-08: Friday is EST, Monday is EDT.
  expect_equal(.s("2026-03-06 14:30:00"), "regular")    # Fri 09:30 EST
  expect_equal(.s("2026-03-06 14:29:59"), "extended")
  expect_equal(.s("2026-03-09 13:30:00"), "regular")    # Mon 09:30 EDT
  expect_equal(.s("2026-03-09 13:29:59"), "extended")
  # Fall back is Sun 2026-11-01: Friday is EDT, Monday is EST.
  expect_equal(.s("2026-10-30 13:30:00"), "regular")    # Fri 09:30 EDT
  expect_equal(.s("2026-10-30 13:29:59"), "extended")
  expect_equal(.s("2026-11-02 14:30:00"), "regular")    # Mon 09:30 EST
  expect_equal(.s("2026-11-02 14:29:59"), "extended")
  # The transition days themselves are Sundays: closed all day.
  expect_equal(.s(c("2026-03-08 06:00:00", "2026-03-08 18:00:00",
                    "2026-11-01 06:00:00", "2026-11-01 18:00:00")), rep("closed", 4))
})

test_that("weekends are closed all day; a trading day's late and early hours are overnight", {
  expect_equal(.s("2026-11-21 15:00:00"), "closed")     # Sat 10:00
  expect_equal(.s("2026-11-22 15:00:00"), "closed")     # Sun 10:00
  expect_equal(.s("2026-11-21 06:00:00"), "closed")     # Sat 01:00 (the calendar day decides)
  expect_equal(.s("2026-11-20 02:00:00"), "overnight")  # Thu 21:00
  expect_equal(.s("2026-11-23 06:00:00"), "overnight")  # Mon 01:00 (Monday is a trading day)
})

test_that("NYSE holidays are closed all day (Thanksgiving, Christmas)", {
  expect_equal(.s("2026-11-26 15:00:00"), "closed")     # Thanksgiving 10:00
  expect_equal(.s("2026-11-26 03:00:00"), "overnight")  # Wed 22:00 (Wednesday trades)
  expect_equal(.s("2026-11-26 06:00:00"), "closed")     # Thu 01:00 (the holiday starts at midnight)
  expect_equal(.s("2026-12-25 15:00:00"), "closed")     # Christmas 10:00
  # Red/green: the day after Thanksgiving is an ordinary trading day in this model
  expect_equal(.s("2026-11-27 15:00:00"), "regular")    # Fri 10:00
})

test_that("input is validated and NA passes through", {
  expect_error(nyse_session("2026-11-24 14:30:00"), "POSIXct")
  expect_error(nyse_session(as.Date("2026-11-24")), "POSIXct")
  x <- nyse_session(c(.u("2026-11-24 14:30:00"), NA))
  expect_equal(as.character(x), c("regular", NA))
  expect_s3_class(x, "factor")
  expect_equal(levels(x), c("regular", "extended", "overnight", "closed"))
  expect_length(nyse_session(.u(character())), 0L)
})

test_that("the instant counts, not the tz attribute", {
  a <- as.POSIXct("2026-11-24 14:30:00", tz = "UTC")
  b <- as.POSIXct("2026-11-24 09:30:00", tz = "America/New_York")
  expect_equal(as.character(nyse_session(a)), as.character(nyse_session(b)))
})

test_that("an hourly bar straddles the open only for the hour that holds 09:30", {
  # Winter: 09:30 NY = 14:30 UTC, so the 14:00 UTC hour straddles it
  expect_true(nyse_straddles_open(.u("2026-11-24 14:00:00"), 60))
  expect_false(nyse_straddles_open(.u("2026-11-24 13:00:00"), 60))
  expect_false(nyse_straddles_open(.u("2026-11-24 15:00:00"), 60))
  # Summer: 09:30 NY = 13:30 UTC, so the 13:00 UTC hour straddles it
  expect_true(nyse_straddles_open(.u("2026-07-14 13:00:00"), 60))
  expect_false(nyse_straddles_open(.u("2026-07-14 14:00:00"), 60))
  # The hour moved across the clock change (the reason this is not hard-coded)
  expect_false(nyse_straddles_open(.u("2026-11-02 13:00:00"), 60))  # was TRUE in summer
})

test_that("a 15m bar straddles the open only if it starts inside the open minute window", {
  # Aligned 15m bars never straddle 09:30: one ends there, the next starts there
  expect_false(nyse_straddles_open(.u("2026-11-24 14:15:00"), 15))  # 09:15-09:30
  expect_false(nyse_straddles_open(.u("2026-11-24 14:30:00"), 15))  # 09:30-09:45
  # A misaligned bar does
  expect_true(nyse_straddles_open(.u("2026-11-24 14:20:00"), 15))   # 09:20-09:35
  # Bar starting exactly at the open, hourly: starts there, does not straddle
  expect_false(nyse_straddles_open(.u("2026-11-24 14:30:00"), 60))
})

test_that("straddle is vectorised, NA-safe, and validates its inputs", {
  r <- nyse_straddles_open(c(.u("2026-11-24 14:00:00"), NA, .u("2026-11-24 13:00:00")), 60)
  expect_equal(r, c(TRUE, NA, FALSE))
  expect_error(nyse_straddles_open("2026-11-24 14:00:00", 60), "POSIXct")
  expect_error(nyse_straddles_open(.u("2026-11-24 14:00:00"), 0), "bar_len_minutes")
  expect_error(nyse_straddles_open(.u("2026-11-24 14:00:00"), NA_real_), "bar_len_minutes")
})
