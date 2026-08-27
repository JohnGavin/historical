testthat::local_edition(3)
# Tests for check_leaderboard_cost_metrics_joint_presence() — QA gate S23
# (fail-loud-not-null.md)
#
# net_cagr, cvar_95, and credible are all produced together, in a single
# pass, by calc_cost_metrics() (R/plan_leaderboard.R) from the SAME
# cost_rows join. docs/leaderboard.qmd's Rankings table renders all three
# NA-together as a single "not computed" verdict (Credible/Net CAGR/CVaR
# 95% columns) -- this gate is what keeps that assumption from silently
# going stale if a future change populates one of the three columns for a
# strategy/period without the other two.
#
# The function is defined in R/plan_qa_gates.R. Tests exercise the gate
# directly without running tar_make().

source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ──────────────────────────────────────────────────────────────

# "Factor MAX" has all three cost metrics computed (in cost_rows' 5-core-
# strategies-plus-PSO-Optimal scope). "LTR" has none of the three -- outside
# that scope, all jointly NA (the normal "not computed" case, not a defect).
good_leaderboard <- tibble::tibble(
  strategy = c("Factor MAX", "Factor MAX", "LTR",     "LTR"),
  period   = c("Full Period", "Training",  "Full Period", "Training"),
  net_cagr = c(0.035,          0.020,       NA_real_,      NA_real_),
  cvar_95  = c(-0.045,        -0.030,       NA_real_,      NA_real_),
  credible = c(TRUE,           TRUE,        NA,            NA)
)

# "New Strategy" has net_cagr computed but cvar_95/credible left NA -- the
# regression this gate exists to catch (a future cost_rows change wired up
# one column of the trio without the other two).
offender_leaderboard <- tibble::tibble(
  strategy = c("Factor MAX", "New Strategy"),
  period   = c("Full Period", "Full Period"),
  net_cagr = c(0.035,          0.120),
  cvar_95  = c(-0.045,         NA_real_),
  credible = c(TRUE,           NA)
)

# ── Tests: joint-presence assertion ─────────────────────────────────────────

test_that("check_leaderboard_cost_metrics_joint_presence passes when all three are jointly present or jointly NA", {
  expect_true(check_leaderboard_cost_metrics_joint_presence(good_leaderboard))
})

test_that("check_leaderboard_cost_metrics_joint_presence passes on an all-NA (never-computed) leaderboard", {
  all_na <- tibble::tibble(
    strategy = c("LTR", "CMR"),
    period   = c("Full Period", "Full Period"),
    net_cagr = NA_real_,
    cvar_95  = NA_real_,
    credible = NA
  )
  expect_true(check_leaderboard_cost_metrics_joint_presence(all_na))
})

test_that("check_leaderboard_cost_metrics_joint_presence checks every period row, not just Full Period", {
  # good_leaderboard already includes a Training row for both strategies --
  # confirm the gate does not silently ignore them (unlike S21, this gate
  # is deliberately NOT scoped to Full Period only -- cost_rows produces a
  # row per Training/Testing/Holdout/Full Period slice).
  bad <- good_leaderboard
  bad$cvar_95[bad$strategy == "Factor MAX" & bad$period == "Training"] <- NA_real_
  expect_error(
    check_leaderboard_cost_metrics_joint_presence(bad),
    regexp = "Training"
  )
})

test_that("check_leaderboard_cost_metrics_joint_presence throws and names the offending strategy when only one column is populated", {
  expect_error(
    check_leaderboard_cost_metrics_joint_presence(offender_leaderboard),
    regexp = "New Strategy"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_cost_metrics_joint_presence(offender_leaderboard)
  )
})

test_that("check_leaderboard_cost_metrics_joint_presence names every offending strategy/period when multiple rows disagree", {
  bad <- tibble::tibble(
    strategy = c("A", "B"),
    period   = c("Full Period", "Full Period"),
    net_cagr = c(0.05, NA_real_),
    cvar_95  = c(NA_real_, 0.02),
    credible = c(NA, NA)
  )
  expect_error(
    check_leaderboard_cost_metrics_joint_presence(bad),
    regexp = "2 row"
  )
})

# ── Required columns ─────────────────────────────────────────────────────────

test_that("check_leaderboard_cost_metrics_joint_presence throws when leaderboard is missing required columns", {
  bad <- dplyr::select(good_leaderboard, -cvar_95)
  expect_error(
    check_leaderboard_cost_metrics_joint_presence(bad),
    regexp = "cvar_95"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_cost_metrics_joint_presence(bad)
  )
})
