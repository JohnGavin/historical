testthat::local_edition(3)
# Tests for check_leaderboard_no_validation_rows() — QA gate S14 (#648)
#
# The function is defined in R/plan_qa_gates.R. Tests exercise the gate
# directly without running tar_make().
#
# Background (#648): `slice_portfolio()` in R/plan_leaderboard.R computed an
# explicit "Validation" cost-metric slice on every tar_make() for six
# strategies, and several source metrics targets (fm_metrics, drif_metrics,
# stk_max_metrics, stk_drif_metrics, xgb_drif_metrics, ltr_metrics,
# port_metrics) independently fed a "Validation" row into the leaderboard's
# `all_metrics`, unfiltered -- an automatic-computation violation of
# `.claude/rules/backtest-partitions.md` ("Validation metrics are NOT
# computed automatically by tar_make()"). This gate catches a recurrence of
# either source: any "Validation" row reaching the assembled `leaderboard`
# target's own output.

source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ──────────────────────────────────────────────────────────────────

good_leaderboard <- tibble::tibble(
  strategy = c(
    "Factor MAX", "Factor MAX", "Factor MAX",
    "Stock DRIF", "Stock DRIF", "Stock DRIF"
  ),
  period = c(
    "Training", "Testing", "Full Period",
    "Training", "Testing", "Full Period"
  )
)

# One strategy has a Validation row -- the #648 regression itself: a source
# metrics target (or slice_portfolio()) fed a Validation row through
# unfiltered.
one_validation_row_leaderboard <- tibble::tibble(
  strategy = c(
    "Factor MAX", "Factor MAX", "Factor MAX",
    "Stock DRIF", "Stock DRIF", "Stock DRIF", "Stock DRIF"
  ),
  period = c(
    "Training", "Testing", "Full Period",
    "Training", "Testing", "Full Period", "Validation"
  )
)

# Multiple strategies leaking Validation rows -- the actual #648 evidence
# shape (7 strategies with a Validation row in the built store).
multi_validation_leaderboard <- tibble::tibble(
  strategy = c(
    "Factor MAX", "Factor MAX", "Stock DRIF", "Stock DRIF", "XGB DRIF"
  ),
  period = c(
    "Full Period", "Validation", "Full Period", "Validation", "Validation"
  )
)

# A leaderboard with "Holdout" rows (#660) but no "Validation" row -- the
# tier this gate must NOT reject, since Holdout is observed-but-unsealed and
# allowed on the automatic path by design (backtest-partitions.md).
holdout_leaderboard <- tibble::tibble(
  strategy = c(
    "Factor MAX", "Factor MAX", "Factor MAX", "Factor MAX",
    "Stock DRIF", "Stock DRIF", "Stock DRIF", "Stock DRIF"
  ),
  period = c(
    "Training", "Testing", "Holdout", "Full Period",
    "Training", "Testing", "Holdout", "Full Period"
  )
)

# ── Tests: passes when no Validation row is present ──────────────────────────

test_that("check_leaderboard_no_validation_rows passes when no strategy has a Validation row", {
  expect_true(check_leaderboard_no_validation_rows(good_leaderboard))
})

test_that("check_leaderboard_no_validation_rows permits Holdout rows (#660) -- not the same tier as Validation", {
  expect_true(check_leaderboard_no_validation_rows(holdout_leaderboard))
})

# ── Tests: throws when a Validation row leaks through ────────────────────────

test_that("check_leaderboard_no_validation_rows throws when one strategy has a Validation row", {
  expect_error(
    check_leaderboard_no_validation_rows(one_validation_row_leaderboard),
    regexp = "Stock DRIF"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_no_validation_rows(one_validation_row_leaderboard)
  )
})

test_that("check_leaderboard_no_validation_rows names every offending strategy", {
  expect_error(
    check_leaderboard_no_validation_rows(multi_validation_leaderboard),
    regexp = "Factor MAX"
  )
  expect_error(
    check_leaderboard_no_validation_rows(multi_validation_leaderboard),
    regexp = "XGB DRIF"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_no_validation_rows(multi_validation_leaderboard)
  )
})

# ── Tests: required columns ───────────────────────────────────────────────────

test_that("check_leaderboard_no_validation_rows throws when required columns are missing", {
  bad <- dplyr::select(good_leaderboard, -period)
  expect_error(
    check_leaderboard_no_validation_rows(bad),
    regexp = "period"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_no_validation_rows(bad)
  )
})
