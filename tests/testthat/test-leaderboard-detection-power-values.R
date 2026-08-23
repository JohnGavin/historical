testthat::local_edition(3)
# Tests for check_leaderboard_detection_power_values() — QA gate S20 (#726 items 3+4)
#
# The function is defined in R/plan_qa_gates.R. It closes the NA hole #726
# found in R/plan_leaderboard.R's .detection_diag_row(): S19
# (check_leaderboard_detection_power_coverage(), see the sibling test file
# test-leaderboard-detection-power-coverage.R) only guards the diagnostic's
# INPUT (a declared row in STRATEGY_OBS_ANN_FACTOR); it does not check that
# the diagnostic actually produced a value. S20 asserts the property #726
# wants: every row with sharpe > 0 has a non-NA detection_min_n_years /
# detection_underpowered, and (where k_eff_strat is itself usable) a non-NA
# detection_min_n_years_mt / detection_underpowered_mt.
#
# Background (#726): Risk State passed S19 (it IS in STRATEGY_OBS_ANN_FACTOR,
# declared 252) while its months column was always NA -- rsc_metrics never
# carried an observation-count column until #726 item 3's calc_metrics()
# fix (R/plan_risk_state.R). S20 is the gate that would have caught that gap
# at pipeline time instead of it surviving silently.

source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ──────────────────────────────────────────────────────────────

# All positive-Sharpe rows have a verdict. "OLMAR-1" / Training has a
# negative sharpe with an NA verdict -- deliberately included to prove the
# gate correctly ignores non-positive-Sharpe rows (path a, #726's own text:
# "underpowered is not a meaningful question for a strategy that isn't even
# claiming a positive edge"). "Value (HML)" has k_eff_strat = NA, so its mt
# columns are legitimately NA too (#726 item 4's documented guard) and must
# NOT trip the mt assertion.
good_leaderboard <- tibble::tibble(
  strategy                   = c("OLMAR-1", "OLMAR-1",     "Value (HML)"),
  period                     = c("Full Period", "Training", "Full Period"),
  sharpe                     = c(0.78, -0.20, 0.068),
  months                     = c(4000, 2000, 750),
  detection_min_n_years      = c(10, NA_real_, 1337),
  detection_underpowered     = c(FALSE, NA, TRUE),
  detection_min_n_years_mt   = c(12, NA_real_, NA_real_),
  detection_underpowered_mt  = c(FALSE, NA, NA),
  k_eff_strat                = c(4.847, 4.847, NA_real_)
)

# Path (b): Risk State's actual #726 shape -- sharpe > 0, months NA.
months_na_leaderboard <- tibble::tibble(
  strategy                   = "Risk State",
  period                     = "Full Period",
  sharpe                     = 0.252,
  months                     = NA_real_,
  detection_min_n_years      = NA_real_,
  detection_underpowered     = NA,
  detection_min_n_years_mt   = NA_real_,
  detection_underpowered_mt  = NA,
  k_eff_strat                = NA_real_
)

# Path (c): months is usable (present, >= 2) but hd_detection_power() still
# produced no value -- e.g. the tryCatch in .detection_diag_row() caught an
# error.
power_fail_leaderboard <- tibble::tibble(
  strategy                   = "LTR",
  period                     = "Full Period",
  sharpe                     = 0.330,
  months                     = 254,
  detection_min_n_years      = NA_real_,
  detection_underpowered     = NA,
  detection_min_n_years_mt   = NA_real_,
  detection_underpowered_mt  = NA,
  k_eff_strat                = NA_real_
)

# #726 item 4: single-test verdict is fine, but k_eff_strat IS usable
# (>= 1, non-NA) and the mt columns are still NA -- must trip the mt
# assertion even though the single-test assertion passes.
mt_missing_leaderboard <- tibble::tibble(
  strategy                   = "Factor DRIF",
  period                     = "Full Period",
  sharpe                     = 0.076,
  months                     = 691,
  detection_min_n_years      = 1067,
  detection_underpowered     = TRUE,
  detection_min_n_years_mt   = NA_real_,
  detection_underpowered_mt  = NA,
  k_eff_strat                = 4.847
)

# ── Tests: single-test assertion ────────────────────────────────────────────

test_that("check_leaderboard_detection_power_values passes when every positive-Sharpe row has a verdict", {
  expect_true(check_leaderboard_detection_power_values(good_leaderboard))
})

test_that("check_leaderboard_detection_power_values ignores non-positive-Sharpe rows entirely", {
  # The NA verdict on the negative-sharpe "OLMAR-1 / Training" row in
  # good_leaderboard must not trip the gate -- confirmed by the pass above,
  # this test isolates that one row to make the intent explicit.
  only_negative <- good_leaderboard[good_leaderboard$strategy == "OLMAR-1" &
                                       good_leaderboard$period == "Training", ]
  expect_true(check_leaderboard_detection_power_values(only_negative))
})

test_that("check_leaderboard_detection_power_values throws and names path (b) when months is NA/<2", {
  expect_error(
    check_leaderboard_detection_power_values(months_na_leaderboard),
    regexp = "Risk State"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_detection_power_values(months_na_leaderboard)
  )
})

test_that("check_leaderboard_detection_power_values throws and names path (c) when months is usable but the verdict is still NA", {
  expect_error(
    check_leaderboard_detection_power_values(power_fail_leaderboard),
    regexp = "LTR"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_detection_power_values(power_fail_leaderboard)
  )
})

# ── Tests: multiple-testing-corrected assertion (#726 item 4) ──────────────

test_that("check_leaderboard_detection_power_values throws when k_eff_strat is usable but the mt verdict is NA", {
  expect_error(
    check_leaderboard_detection_power_values(mt_missing_leaderboard),
    regexp = "Factor DRIF"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_detection_power_values(mt_missing_leaderboard)
  )
})

test_that("check_leaderboard_detection_power_values does not require mt columns when k_eff_strat is NA", {
  # power_fail_leaderboard has k_eff_strat = NA and NA mt columns -- would
  # wrongly trip the mt assertion if it didn't guard on k_eff_strat's own
  # usability. Isolate that shape with a passing single-test verdict so only
  # the mt guard is under test.
  fixture <- power_fail_leaderboard
  fixture$detection_min_n_years  <- 57
  fixture$detection_underpowered <- TRUE
  expect_true(check_leaderboard_detection_power_values(fixture))
})

# ── Tests: required columns ─────────────────────────────────────────────────

test_that("check_leaderboard_detection_power_values throws when leaderboard is missing required columns", {
  bad <- dplyr::select(good_leaderboard, -months)
  expect_error(
    check_leaderboard_detection_power_values(bad),
    regexp = "months"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_detection_power_values(bad)
  )
})
