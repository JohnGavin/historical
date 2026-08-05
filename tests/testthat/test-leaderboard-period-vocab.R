testthat::local_edition(3)
# Tests for check_leaderboard_period_vocab() — QA gate S10 (#643)
#
# The function is defined in R/plan_qa_gates.R and depends on
# PERIOD_LABELS_ALLOWED, defined in R/plan_partitions.R (single source of
# truth for the canonical `period` vocabulary). Tests exercise the gate
# directly without running tar_make().
#
# Background (#643): mf_metrics and ev_metrics used "Full" for their
# full-sample row where every other strategy in the leaderboard uses
# "Full Period" -- the headline ranking table filters on period ==
# "Full Period", so "Value (HML)" and "Managed Futures" were silently
# dropped. This gate catches a recurrence of that defect class.

source(here::here("R/plan_partitions.R"))
source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ──────────────────────────────────────────────────────────────────

good_leaderboard <- tibble::tibble(
  strategy = c(
    "Factor MAX", "Factor MAX", "Factor MAX",
    "Value (HML)", "Value (HML)", "Value (HML)"
  ),
  period = c(
    "Training", "Testing", "Full Period",
    "Training", "OOS",     "Full Period"
  )
)

# Value (HML) never got a "Full Period" row -- the #643 regression itself
# (its .norm_value() helper forgot to rename "Full" -> "Full Period").
missing_full_period_leaderboard <- tibble::tibble(
  strategy = c(
    "Factor MAX", "Factor MAX", "Factor MAX",
    "Value (HML)", "Value (HML)", "Value (HML)"
  ),
  period = c(
    "Training", "Testing", "Full Period",
    "Training", "OOS",     "Full"          # should be "Full Period"
  )
)

# A period value entirely outside the canonical vocabulary (typo / new
# strategy wired in without checking the allowed set). Every strategy still
# has a valid "Full Period" row so this fixture isolates assertion 2 (bad
# vocabulary) from assertion 1 (missing Full Period row).
bad_vocab_leaderboard <- tibble::tibble(
  strategy = c("Factor MAX", "Factor MAX", "Managed Futures", "Managed Futures"),
  period   = c("Training", "Full Period", "Full Period", "Full-Sample")  # typo
)

# ── Tests: assertion 1 (every strategy has a Full Period row) ────────────────

test_that("check_leaderboard_period_vocab passes when every strategy has a Full Period row", {
  expect_true(check_leaderboard_period_vocab(good_leaderboard))
})

test_that("check_leaderboard_period_vocab throws when a strategy is missing its Full Period row", {
  expect_error(
    check_leaderboard_period_vocab(missing_full_period_leaderboard),
    regexp = "Value \\(HML\\)"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_period_vocab(missing_full_period_leaderboard)
  )
})

# ── Tests: assertion 2 (no period value outside PERIOD_LABELS_ALLOWED) ───────

test_that("check_leaderboard_period_vocab passes with 'OOS' as a distinct, allowed label", {
  # OOS is deliberately its own label, not a synonym for Testing (#643) --
  # see R/plan_partitions.R PERIOD_LABELS_ALLOWED.
  expect_true("OOS" %in% PERIOD_LABELS_ALLOWED)
  expect_false("Testing" == "OOS")
  expect_true(check_leaderboard_period_vocab(good_leaderboard))
})

test_that("check_leaderboard_period_vocab throws when a period value is outside the canonical vocabulary", {
  expect_error(
    check_leaderboard_period_vocab(bad_vocab_leaderboard),
    regexp = "Full-Sample"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_period_vocab(bad_vocab_leaderboard)
  )
})

test_that("check_leaderboard_period_vocab names the offending strategy for a bad vocabulary value", {
  expect_error(
    check_leaderboard_period_vocab(bad_vocab_leaderboard),
    regexp = "Managed Futures"
  )
})

# ── Tests: required columns ───────────────────────────────────────────────────

test_that("check_leaderboard_period_vocab throws when required columns are missing", {
  bad <- dplyr::select(good_leaderboard, -period)
  expect_error(
    check_leaderboard_period_vocab(bad),
    regexp = "period"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_period_vocab(bad)
  )
})

# ── PERIOD_LABELS_ALLOWED itself ─────────────────────────────────────────────

test_that("PERIOD_LABELS_ALLOWED contains the 5 expected canonical labels", {
  expect_setequal(
    PERIOD_LABELS_ALLOWED,
    c("Training", "Testing", "Validation", "Full Period", "OOS")
  )
})
