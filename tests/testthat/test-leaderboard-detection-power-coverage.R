testthat::local_edition(3)
# Tests for check_leaderboard_detection_power_coverage() — QA gate S19 (#711 Gap 1)
#
# The function is defined in R/plan_qa_gates.R and depends on
# STRATEGY_OBS_ANN_FACTOR, defined in R/plan_leaderboard.R (single source of
# truth for each strategy's true observation periodicity, needed by
# historicaldata::hd_detection_power()). Tests exercise the gate directly
# without running tar_make().
#
# Background (#711): STRATEGY_OBS_ANN_FACTOR must declare EVERY leaderboard
# strategy, or the detection-power diagnostic join in the `leaderboard`
# target silently produces NA for a new strategy forever. This gate catches
# that gap at pipeline time instead.

# plan_strategy_names.R must be sourced first -- STRATEGY_OBS_ANN_FACTOR is
# now DERIVED from its hd_strategy_names_tbl() constructor (#629), not a
# second hand-maintained copy.
source(here::here("R/plan_strategy_names.R"))
source(here::here("R/plan_leaderboard.R"))
source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ──────────────────────────────────────────────────────────────

good_leaderboard <- tibble::tibble(
  strategy = c("Factor MAX", "Factor MAX", "OLMAR-1", "OLMAR-1"),
  period   = c("Training", "Full Period", "Training", "Full Period")
)

# "New Strategy" has no row in STRATEGY_OBS_ANN_FACTOR -- the #711 regression
# this gate exists to catch: a strategy wired into the leaderboard without a
# matching periodicity declaration.
missing_strategy_leaderboard <- tibble::tibble(
  strategy = c("Factor MAX", "Factor MAX", "New Strategy"),
  period   = c("Training", "Full Period", "Full Period")
)

# ── Tests ───────────────────────────────────────────────────────────────────

test_that("check_leaderboard_detection_power_coverage passes when every strategy is declared", {
  expect_true(
    check_leaderboard_detection_power_coverage(good_leaderboard, STRATEGY_OBS_ANN_FACTOR)
  )
})

test_that("check_leaderboard_detection_power_coverage throws when a strategy has no declared periodicity", {
  expect_error(
    check_leaderboard_detection_power_coverage(missing_strategy_leaderboard, STRATEGY_OBS_ANN_FACTOR),
    regexp = "New Strategy"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_detection_power_coverage(missing_strategy_leaderboard, STRATEGY_OBS_ANN_FACTOR)
  )
})

test_that("check_leaderboard_detection_power_coverage throws when leaderboard is missing strategy column", {
  bad <- dplyr::select(good_leaderboard, -strategy)
  expect_error(
    check_leaderboard_detection_power_coverage(bad, STRATEGY_OBS_ANN_FACTOR),
    regexp = "strategy"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_detection_power_coverage(bad, STRATEGY_OBS_ANN_FACTOR)
  )
})

test_that("check_leaderboard_detection_power_coverage throws when obs_ann_factor_tbl is missing strategy column", {
  bad_tbl <- dplyr::select(STRATEGY_OBS_ANN_FACTOR, -strategy)
  expect_error(
    check_leaderboard_detection_power_coverage(good_leaderboard, bad_tbl),
    regexp = "strategy"
  )
})

# ── STRATEGY_OBS_ANN_FACTOR itself ───────────────────────────────────────────

test_that("STRATEGY_OBS_ANN_FACTOR declares every strategy with a positive integer-ish ann_factor", {
  expect_true(all(STRATEGY_OBS_ANN_FACTOR$obs_ann_factor > 0))
  expect_true(all(STRATEGY_OBS_ANN_FACTOR$obs_ann_factor %in% c(12, 52, 252)))
})

test_that("STRATEGY_OBS_ANN_FACTOR flags the five known daily strategies as ann_factor = 252", {
  # CMR joined this list after #717/#720/#721 corrected its ann_factor from
  # the originally (wrongly) assumed monthly value.
  daily <- c("OLMAR-1", "TOM", "Risk State", "Avoid Worst", "CMR")
  daily_rows <- STRATEGY_OBS_ANN_FACTOR |>
    dplyr::filter(strategy %in% daily)
  expect_equal(nrow(daily_rows), length(daily))
  expect_true(all(daily_rows$obs_ann_factor == 252))
})

test_that("STRATEGY_OBS_ANN_FACTOR has no duplicate strategy rows", {
  expect_equal(
    nrow(STRATEGY_OBS_ANN_FACTOR),
    dplyr::n_distinct(STRATEGY_OBS_ANN_FACTOR$strategy)
  )
})
