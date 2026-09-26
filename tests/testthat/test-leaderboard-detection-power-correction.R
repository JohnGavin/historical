testthat::local_edition(3)
# Tests for check_leaderboard_detection_power_correction() — QA gate S37
# (#903, detection-power-required.md requirement 5)
#
# The function is defined in R/plan_qa_gates.R alongside
# check_leaderboard_detection_power_values() (S20). S20 already asserts
# detection_min_n_years_mt/detection_underpowered_mt are non-NA wherever
# k_eff_leaderboard is usable. S37 checks two DIFFERENT things:
#
#   1. The SAME coverage property as S20, restated with a documented-reason
#      escape hatch (the DEFLATED_SHARPE_EXEMPTIONS table S21 already uses),
#      as a standalone gate rather than assuming S20 always runs first.
#   2. Monotonicity: wherever both detection_min_n_years and
#      detection_min_n_years_mt are non-NA, the corrected figure must be
#      >= the uncorrected one -- a Bonferroni correction tightens alpha and
#      can only weakly increase the sample required. Neither S20 nor S21
#      checks this relationship.
#
# Background (#903): before this issue, hd_detection_power()'s multiple-
# testing correction was applied ad hoc at the R/plan_leaderboard.R call
# site (`alpha = 0.05 / keff`), with no gate ever comparing the corrected
# and uncorrected figures against each other.

source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ──────────────────────────────────────────────────────────────

# Small, self-contained exemption table (independent of the real
# DEFLATED_SHARPE_EXEMPTIONS so these tests do not silently start passing/
# failing if that table's strategy list changes).
test_exemptions <- tibble::tibble(
  strategy = "PSO Optimal",
  reason   = "linear combination of already-included series; test fixture"
)

# "OLMAR-1" has full single-test + corrected coverage, with the corrected
# figure sensibly >= the uncorrected one. "Value (HML)" has k_eff_leaderboard
# = NA, so its mt columns are legitimately NA -- must not trip either check.
# "OLMAR-1"/Training has a negative sharpe with NA verdicts throughout --
# proves both checks correctly ignore non-positive-Sharpe rows.
good_leaderboard <- tibble::tibble(
  strategy                  = c("OLMAR-1", "OLMAR-1",  "Value (HML)"),
  period                    = c("Full Period", "Training", "Full Period"),
  sharpe                    = c(0.78, -0.20, 0.068),
  detection_min_n_years     = c(10, NA_real_, 1337),
  detection_underpowered    = c(FALSE, NA, TRUE),
  detection_min_n_years_mt  = c(12, NA_real_, NA_real_),
  detection_underpowered_mt = c(FALSE, NA, NA),
  k_eff_leaderboard         = c(4.847, 4.847, NA_real_)
)

# k_eff_leaderboard = 1 exactly (the falsification case): the corrected
# figure must equal the uncorrected one exactly, not merely be >=.
keff_one_leaderboard <- tibble::tibble(
  strategy                  = "Single-Test Strategy",
  period                    = "Full Period",
  sharpe                    = 0.50,
  detection_min_n_years     = 42,
  detection_underpowered    = TRUE,
  detection_min_n_years_mt  = 42,
  detection_underpowered_mt = TRUE,
  k_eff_leaderboard         = 1
)

# "New Strategy": k_eff_leaderboard usable, but no mt verdict AND no
# declared exemption -- the coverage gap S37's check 1 exists to catch.
coverage_offender_leaderboard <- tibble::tibble(
  strategy                  = c("OLMAR-1", "New Strategy"),
  period                    = c("Full Period", "Full Period"),
  sharpe                    = c(0.78, 0.330),
  detection_min_n_years     = c(10, 57),
  detection_underpowered    = c(FALSE, TRUE),
  detection_min_n_years_mt  = c(12, NA_real_),
  detection_underpowered_mt = c(FALSE, NA),
  k_eff_leaderboard         = c(4.847, 4.847)
)

# "PSO Optimal": k_eff_leaderboard usable... no wait, PSO Optimal's real
# gap is k_eff_leaderboard = NA (excluded from STRAT_RETURNS_WIDE_CODES
# entirely) -- so its mt columns are legitimately NA via the k_eff guard,
# not via this gate's exemption path. Included anyway to prove exemption
# by name works even when k_eff_leaderboard IS (unrealistically) usable.
exempt_leaderboard <- tibble::tibble(
  strategy                  = c("OLMAR-1", "PSO Optimal"),
  period                    = c("Full Period", "Full Period"),
  sharpe                    = c(0.78, 0.30),
  detection_min_n_years     = c(10, 90),
  detection_underpowered    = c(FALSE, TRUE),
  detection_min_n_years_mt  = c(12, NA_real_),
  detection_underpowered_mt = c(FALSE, NA),
  k_eff_leaderboard         = c(4.847, 4.847)
)

# The monotonicity offender: both non-NA, but corrected < uncorrected --
# backwards for a Bonferroni correction (check 2's target defect).
monotonicity_offender_leaderboard <- tibble::tibble(
  strategy                  = "Inverted Strategy",
  period                    = "Full Period",
  sharpe                    = 0.40,
  detection_min_n_years     = 100,
  detection_underpowered    = TRUE,
  detection_min_n_years_mt  = 80,
  detection_underpowered_mt = TRUE,
  k_eff_leaderboard         = 5
)

# ── Tests: check 1 (coverage-or-exemption) ──────────────────────────────────

test_that("check_leaderboard_detection_power_correction passes when every positive-Sharpe row has a verdict", {
  expect_true(check_leaderboard_detection_power_correction(good_leaderboard, test_exemptions))
})

test_that("check_leaderboard_detection_power_correction ignores non-positive-Sharpe rows entirely", {
  only_negative <- good_leaderboard[good_leaderboard$strategy == "OLMAR-1" &
                                       good_leaderboard$period == "Training", ]
  expect_true(check_leaderboard_detection_power_correction(only_negative, test_exemptions))
})

test_that("check_leaderboard_detection_power_correction does not require mt columns when k_eff_leaderboard is NA", {
  na_keff_only <- good_leaderboard[good_leaderboard$strategy == "Value (HML)", ]
  expect_true(check_leaderboard_detection_power_correction(na_keff_only, test_exemptions))
})

test_that("check_leaderboard_detection_power_correction throws and names the offending strategy when no exemption exists", {
  expect_error(
    check_leaderboard_detection_power_correction(coverage_offender_leaderboard, test_exemptions),
    regexp = "New Strategy"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_detection_power_correction(coverage_offender_leaderboard, test_exemptions)
  )
})

test_that("check_leaderboard_detection_power_correction does not throw for an exempted strategy even with a usable k_eff_leaderboard", {
  expect_true(check_leaderboard_detection_power_correction(exempt_leaderboard, test_exemptions))
})

# ── Tests: check 2 (monotonicity) ───────────────────────────────────────────

test_that("check_leaderboard_detection_power_correction passes when corrected >= uncorrected for every row", {
  expect_true(check_leaderboard_detection_power_correction(good_leaderboard, test_exemptions))
})

test_that("check_leaderboard_detection_power_correction passes when corrected == uncorrected exactly (falsification: k_eff = 1)", {
  expect_true(check_leaderboard_detection_power_correction(keff_one_leaderboard, test_exemptions))
})

test_that("check_leaderboard_detection_power_correction throws and names the offending strategy when corrected < uncorrected", {
  expect_error(
    check_leaderboard_detection_power_correction(monotonicity_offender_leaderboard, test_exemptions),
    regexp = "Inverted Strategy"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_detection_power_correction(monotonicity_offender_leaderboard, test_exemptions)
  )
})

test_that("check_leaderboard_detection_power_correction ignores monotonicity where either figure is NA", {
  # Value (HML) has detection_min_n_years_mt = NA -- the "both_present" guard
  # must skip it rather than comparing NA < 1337.
  na_mt_only <- good_leaderboard[good_leaderboard$strategy == "Value (HML)", ]
  expect_true(check_leaderboard_detection_power_correction(na_mt_only, test_exemptions))
})

# ── Tests: required columns ─────────────────────────────────────────────────

test_that("check_leaderboard_detection_power_correction throws when leaderboard is missing required columns", {
  bad <- dplyr::select(good_leaderboard, -detection_min_n_years_mt)
  expect_error(
    check_leaderboard_detection_power_correction(bad, test_exemptions),
    regexp = "detection_min_n_years_mt"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_detection_power_correction(bad, test_exemptions)
  )
})

test_that("check_leaderboard_detection_power_correction throws when exemptions table is missing required columns", {
  bad_exemptions <- dplyr::select(test_exemptions, -reason)
  expect_error(
    check_leaderboard_detection_power_correction(good_leaderboard, bad_exemptions),
    regexp = "reason"
  )
})
