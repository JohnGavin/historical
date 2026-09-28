testthat::local_edition(3)
# Tests for check_leaderboard_prob_sharpe_positive() -- QA gate S40 (#851)
#
# The function is defined in R/plan_qa_gates.R alongside
# check_leaderboard_detection_power_values() (S20) and
# check_leaderboard_detection_power_correction() (S37), applied to the
# DIFFERENT statistic historicaldata::hd_prob_sharpe_positive() computes.
# S40 checks:
#
#   1. Coverage of prob_sharpe_positive (single-test) for every
#      positive-Sharpe row, with a documented-reason exemption escape hatch
#      (DEFLATED_SHARPE_EXEMPTIONS, the SAME table S21/S37 use) -- UNLIKE
#      S20, which hard-aborts on the single-test detection-power verdict
#      with no exemption, S40 grants the exemption at BOTH the single-test
#      and corrected level, per #851's own proposed-work wording.
#   2. The SAME coverage requirement for prob_sharpe_positive_mt, wherever
#      k_eff_leaderboard is usable.
#   3. Monotonicity: wherever both are non-NA, prob_sharpe_positive_mt must
#      be <= prob_sharpe_positive -- the OPPOSITE direction from S37's
#      detection_min_n_years_mt >= detection_min_n_years, because a
#      Bonferroni p-value correction DECREASES the reported probability
#      (S37's Bonferroni alpha-tightening INCREASES the required sample).

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
# figure sensibly <= the uncorrected one. "Value (HML)" has
# k_eff_leaderboard = NA, so its _mt column is legitimately NA -- must not
# trip either coverage check. "OLMAR-1"/Training has a negative sharpe with
# NA verdicts throughout -- proves both checks correctly ignore
# non-positive-Sharpe rows.
good_leaderboard <- tibble::tibble(
  strategy                = c("OLMAR-1", "OLMAR-1",  "Value (HML)"),
  period                  = c("Full Period", "Training", "Full Period"),
  sharpe                  = c(0.78, -0.20, 0.068),
  prob_sharpe_positive    = c(0.90, NA_real_, 0.55),
  prob_sharpe_positive_mt = c(0.85, NA_real_, NA_real_),
  k_eff_leaderboard       = c(4.847, 4.847, NA_real_)
)

# k_eff_leaderboard = 1 exactly (the falsification case): the corrected
# figure must equal the uncorrected one exactly, not merely be <=.
keff_one_leaderboard <- tibble::tibble(
  strategy                = "Single-Test Strategy",
  period                  = "Full Period",
  sharpe                  = 0.50,
  prob_sharpe_positive    = 0.70,
  prob_sharpe_positive_mt = 0.70,
  k_eff_leaderboard       = 1
)

# "New Strategy": k_eff_leaderboard usable, but no mt verdict AND no
# declared exemption -- the coverage gap check 2 exists to catch.
mt_coverage_offender_leaderboard <- tibble::tibble(
  strategy                = c("OLMAR-1", "New Strategy"),
  period                  = c("Full Period", "Full Period"),
  sharpe                  = c(0.78, 0.33),
  prob_sharpe_positive    = c(0.90, 0.62),
  prob_sharpe_positive_mt = c(0.85, NA_real_),
  k_eff_leaderboard       = c(4.847, 4.847)
)

# "Uncovered Strategy": no prob_sharpe_positive AND no declared exemption --
# the single-test coverage gap check 1 exists to catch.
single_coverage_offender_leaderboard <- tibble::tibble(
  strategy                = c("OLMAR-1", "Uncovered Strategy"),
  period                  = c("Full Period", "Full Period"),
  sharpe                  = c(0.78, 0.40),
  prob_sharpe_positive    = c(0.90, NA_real_),
  prob_sharpe_positive_mt = c(0.85, NA_real_),
  k_eff_leaderboard       = c(4.847, NA_real_)
)

# "PSO Optimal": k_eff_leaderboard usable... its real gap is
# k_eff_leaderboard = NA (excluded from STRAT_RETURNS_WIDE_CODES entirely)
# -- included anyway to prove exemption by name works even when
# k_eff_leaderboard IS (unrealistically) usable.
exempt_leaderboard <- tibble::tibble(
  strategy                = c("OLMAR-1", "PSO Optimal"),
  period                  = c("Full Period", "Full Period"),
  sharpe                  = c(0.78, 0.30),
  prob_sharpe_positive    = c(0.90, NA_real_),
  prob_sharpe_positive_mt = c(0.85, NA_real_),
  k_eff_leaderboard       = c(4.847, 4.847)
)

# The monotonicity offender: both non-NA, but corrected > uncorrected --
# backwards for a Bonferroni p-value correction (check 3's target defect).
monotonicity_offender_leaderboard <- tibble::tibble(
  strategy                = "Inverted Strategy",
  period                  = "Full Period",
  sharpe                  = 0.40,
  prob_sharpe_positive    = 0.60,
  prob_sharpe_positive_mt = 0.75,
  k_eff_leaderboard       = 5
)

# ── Tests: check 1 (single-test coverage-or-exemption) ──────────────────────

test_that("check_leaderboard_prob_sharpe_positive passes when every positive-Sharpe row has a verdict", {
  expect_true(check_leaderboard_prob_sharpe_positive(good_leaderboard, test_exemptions))
})

test_that("check_leaderboard_prob_sharpe_positive ignores non-positive-Sharpe rows entirely", {
  only_negative <- good_leaderboard[good_leaderboard$strategy == "OLMAR-1" &
                                       good_leaderboard$period == "Training", ]
  expect_true(check_leaderboard_prob_sharpe_positive(only_negative, test_exemptions))
})

test_that("check_leaderboard_prob_sharpe_positive throws and names the offending strategy when single-test coverage is missing and no exemption exists", {
  expect_error(
    check_leaderboard_prob_sharpe_positive(single_coverage_offender_leaderboard, test_exemptions),
    regexp = "Uncovered Strategy"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_prob_sharpe_positive(single_coverage_offender_leaderboard, test_exemptions)
  )
})

# ── Tests: check 2 (mt coverage-or-exemption) ───────────────────────────────

test_that("check_leaderboard_prob_sharpe_positive does not require the mt column when k_eff_leaderboard is NA", {
  na_keff_only <- good_leaderboard[good_leaderboard$strategy == "Value (HML)", ]
  expect_true(check_leaderboard_prob_sharpe_positive(na_keff_only, test_exemptions))
})

test_that("check_leaderboard_prob_sharpe_positive throws and names the offending strategy when mt coverage is missing and no exemption exists", {
  expect_error(
    check_leaderboard_prob_sharpe_positive(mt_coverage_offender_leaderboard, test_exemptions),
    regexp = "New Strategy"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_prob_sharpe_positive(mt_coverage_offender_leaderboard, test_exemptions)
  )
})

test_that("check_leaderboard_prob_sharpe_positive does not throw for an exempted strategy even with a usable k_eff_leaderboard", {
  expect_true(check_leaderboard_prob_sharpe_positive(exempt_leaderboard, test_exemptions))
})

# ── Tests: check 3 (monotonicity) ───────────────────────────────────────────

test_that("check_leaderboard_prob_sharpe_positive passes when corrected <= uncorrected for every row", {
  expect_true(check_leaderboard_prob_sharpe_positive(good_leaderboard, test_exemptions))
})

test_that("check_leaderboard_prob_sharpe_positive passes when corrected == uncorrected exactly (falsification: n_tests/k_eff = 1)", {
  expect_true(check_leaderboard_prob_sharpe_positive(keff_one_leaderboard, test_exemptions))
})

test_that("check_leaderboard_prob_sharpe_positive throws and names the offending strategy when corrected > uncorrected", {
  expect_error(
    check_leaderboard_prob_sharpe_positive(monotonicity_offender_leaderboard, test_exemptions),
    regexp = "Inverted Strategy"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_prob_sharpe_positive(monotonicity_offender_leaderboard, test_exemptions)
  )
})

test_that("check_leaderboard_prob_sharpe_positive ignores monotonicity where either figure is NA", {
  # Value (HML) has prob_sharpe_positive_mt = NA -- the "both_present" guard
  # must skip it rather than comparing NA against 0.55.
  na_mt_only <- good_leaderboard[good_leaderboard$strategy == "Value (HML)", ]
  expect_true(check_leaderboard_prob_sharpe_positive(na_mt_only, test_exemptions))
})

# ── Tests: required columns ─────────────────────────────────────────────────

test_that("check_leaderboard_prob_sharpe_positive throws when leaderboard is missing required columns", {
  bad <- dplyr::select(good_leaderboard, -prob_sharpe_positive_mt)
  expect_error(
    check_leaderboard_prob_sharpe_positive(bad, test_exemptions),
    regexp = "prob_sharpe_positive_mt"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_prob_sharpe_positive(bad, test_exemptions)
  )
})

test_that("check_leaderboard_prob_sharpe_positive throws when exemptions table is missing required columns", {
  bad_exemptions <- dplyr::select(test_exemptions, -reason)
  expect_error(
    check_leaderboard_prob_sharpe_positive(good_leaderboard, bad_exemptions),
    regexp = "reason"
  )
})

# ── Regression: literal curly braces in a strategy label must not break cli
# formatting (same defect class as S41's #910/#917 CMR fix -- cli treats
# every bullet element as a glue format string and re-parses literal `{}`
# as R code). None of the fixtures above ever contained a brace. ──

test_that("check_leaderboard_prob_sharpe_positive: a strategy label containing literal curly braces does not break the single-test coverage abort", {
  brace_offender <- tibble::tibble(
    strategy                = c("OLMAR-1", "Factor {x,y}"),
    period                  = c("Full Period", "Full Period"),
    sharpe                  = c(0.78, 0.40),
    prob_sharpe_positive    = c(0.90, NA_real_),
    prob_sharpe_positive_mt = c(0.85, NA_real_),
    k_eff_leaderboard       = c(4.847, NA_real_)
  )
  err <- testthat::capture_error(
    check_leaderboard_prob_sharpe_positive(brace_offender, test_exemptions)
  )
  expect_match(conditionMessage(err), "Factor {x,y}", fixed = TRUE)
})
