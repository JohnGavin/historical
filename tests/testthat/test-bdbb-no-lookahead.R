# Tests for check_bdbb_no_lookahead() -- QA gate S34 (#868)
#
# Mirrors the S33 pattern (check_registry_leg_count_calibration): a pure
# function over a tibble, testable without a live pipeline run.
# bdbb_tail_predict() (packages/historicaldata/R/bdbb.R) attaches the
# "bdbb_scored_windows" tibble this gate inspects; its own tests live in
# packages/historicaldata/tests/testthat/test-bdbb.R.

testthat::local_edition(3)
source(here::here("R/plan_qa_gates.R"))

test_that("check_bdbb_no_lookahead passes when every scoreable row is strictly after window_end", {
  scored <- tibble::tibble(
    window_end = as.POSIXct(c("2023-01-01", "2023-01-02"), tz = "UTC"),
    next_time  = as.POSIXct(c("2023-01-01 01:00", "2023-01-02 01:00"), tz = "UTC")
  )
  expect_true(check_bdbb_no_lookahead(scored))
})

test_that("check_bdbb_no_lookahead passes when scoreable rows have no non-NA next_time", {
  scored <- tibble::tibble(
    window_end = as.POSIXct("2023-01-01", tz = "UTC"),
    next_time  = as.POSIXct(NA_character_, tz = "UTC")
  )
  expect_true(check_bdbb_no_lookahead(scored))
})

test_that("check_bdbb_no_lookahead aborts naming a row that scores a return at window_end (contemporaneous)", {
  scored <- tibble::tibble(
    window_end = as.POSIXct("2023-01-01 05:00:00", tz = "UTC"),
    next_time  = as.POSIXct("2023-01-01 05:00:00", tz = "UTC")
  )
  expect_snapshot(error = TRUE, check_bdbb_no_lookahead(scored))
})

test_that("check_bdbb_no_lookahead aborts naming a row that scores a return BEFORE window_end", {
  scored <- tibble::tibble(
    window_end = as.POSIXct("2023-01-01 05:00:00", tz = "UTC"),
    next_time  = as.POSIXct("2023-01-01 04:00:00", tz = "UTC")
  )
  expect_error(check_bdbb_no_lookahead(scored), regexp = "look-ahead bias")
})

test_that("check_bdbb_no_lookahead reports the total offending row count and the first offender", {
  we <- as.POSIXct(c("2023-01-01", "2023-01-02", "2023-01-03"), tz = "UTC")
  scored <- tibble::tibble(
    window_end = we, next_time = c(we[1], we[2] + 3600, we[3])
  )
  err <- tryCatch(check_bdbb_no_lookahead(scored), error = function(e) e)
  expect_s3_class(err, "error")
  expect_match(conditionMessage(err), "2 rows")
})

test_that("check_bdbb_no_lookahead aborts on a scored tibble missing required columns", {
  expect_snapshot(
    error = TRUE,
    check_bdbb_no_lookahead(tibble::tibble(window_end = Sys.time()))
  )
})

test_that("check_bdbb_no_lookahead signature is stable (catches API drift)", {
  expect_snapshot(args(check_bdbb_no_lookahead))
})
