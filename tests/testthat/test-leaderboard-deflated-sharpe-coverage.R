testthat::local_edition(3)
# Tests for check_leaderboard_deflated_sharpe_coverage() — QA gate S21
# (#728 item 4)
#
# The function is defined in R/plan_qa_gates.R alongside
# DEFLATED_SHARPE_EXEMPTIONS. It follows the same "coverage or a documented
# exemption" shape as S19/S20 (see test-leaderboard-detection-power-*.R):
# a positive Full-Period Sharpe with no deflated_sharpe/dsr_pvalue/
# k_eff_leaderboard verdict either has a written reason in
# DEFLATED_SHARPE_EXEMPTIONS, or the gate aborts.
#
# Background (#728): deflated_sharpe covered only 4 of 17 leaderboard
# strategies before items 1+2 widened it to 11 (see
# R/plan_strategy_correlation.R's STRAT_RETURNS_WIDE_CODES). This gate is
# what keeps that count from silently regressing -- and, per
# fail-loud-not-null.md, ensures any remaining gap either has a written
# reason or fails the pipeline loudly.

source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ──────────────────────────────────────────────────────────────

# Small, self-contained exemption table (independent of the real
# DEFLATED_SHARPE_EXEMPTIONS so these tests do not silently start passing/
# failing if that table's strategy list changes).
test_exemptions <- tibble::tibble(
  strategy = "Avoid Worst",
  reason   = "daily-frequency series; test fixture"
)

# "Factor DRIF" and "Value (HML)" both have full deflated-Sharpe coverage.
# "Avoid Worst" has a positive sharpe and no verdict, but IS in
# test_exemptions -- must not trip the gate. A Training-period row with a
# positive sharpe and no verdict is included to prove the gate ignores
# non-Full-Period rows (deflated_sharpe is a full-sample statistic
# broadcast to every period row, so per-period gaps are not meaningful).
good_leaderboard <- tibble::tibble(
  strategy          = c("Factor DRIF", "Factor DRIF", "Value (HML)", "Avoid Worst", "Avoid Worst"),
  period            = c("Full Period", "Training",    "Full Period", "Full Period", "Training"),
  sharpe            = c(0.076,          0.10,           0.068,        0.620,         0.55),
  deflated_sharpe   = c(0.05,           NA_real_,       0.03,         NA_real_,      NA_real_),
  dsr_pvalue        = c(0.4,            NA_real_,       0.6,          NA_real_,      NA_real_),
  k_eff_leaderboard = c(9.2,            NA_real_,       9.2,          NA_real_,      NA_real_)
)

# "New Strategy" has a positive Full-Period sharpe, no deflated-Sharpe
# verdict, and NO declared exemption -- the #728 regression this gate
# exists to catch.
offender_leaderboard <- tibble::tibble(
  strategy          = c("Factor DRIF", "New Strategy"),
  period            = c("Full Period", "Full Period"),
  sharpe            = c(0.076,          0.330),
  deflated_sharpe   = c(0.05,           NA_real_),
  dsr_pvalue        = c(0.4,            NA_real_),
  k_eff_leaderboard = c(9.2,            NA_real_)
)

# ── Tests: coverage-or-exemption assertion ──────────────────────────────────

test_that("check_leaderboard_deflated_sharpe_coverage passes when every positive-Sharpe Full Period row has a verdict or exemption", {
  expect_true(
    check_leaderboard_deflated_sharpe_coverage(good_leaderboard, test_exemptions)
  )
})

test_that("check_leaderboard_deflated_sharpe_coverage ignores non-Full-Period rows entirely", {
  # Factor DRIF/Training has a positive sharpe and NA verdict in
  # good_leaderboard, with no matching exemption -- must not trip the gate
  # because deflated_sharpe is a full-sample statistic, not a per-period one.
  only_training <- good_leaderboard[good_leaderboard$period == "Training", ]
  expect_true(check_leaderboard_deflated_sharpe_coverage(only_training, test_exemptions))
})

test_that("check_leaderboard_deflated_sharpe_coverage throws and names the offending strategy when no exemption exists", {
  expect_error(
    check_leaderboard_deflated_sharpe_coverage(offender_leaderboard, test_exemptions),
    regexp = "New Strategy"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_deflated_sharpe_coverage(offender_leaderboard, test_exemptions)
  )
})

test_that("check_leaderboard_deflated_sharpe_coverage does not throw for an exempted strategy even with all three columns NA", {
  exempt_only <- good_leaderboard[good_leaderboard$strategy == "Avoid Worst" &
                                     good_leaderboard$period == "Full Period", ]
  expect_true(check_leaderboard_deflated_sharpe_coverage(exempt_only, test_exemptions))
})

# ── Tests: required columns ─────────────────────────────────────────────────

test_that("check_leaderboard_deflated_sharpe_coverage throws when leaderboard is missing required columns", {
  bad <- dplyr::select(good_leaderboard, -deflated_sharpe)
  expect_error(
    check_leaderboard_deflated_sharpe_coverage(bad, test_exemptions),
    regexp = "deflated_sharpe"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_deflated_sharpe_coverage(bad, test_exemptions)
  )
})

test_that("check_leaderboard_deflated_sharpe_coverage throws when exemptions table is missing required columns", {
  bad_exemptions <- dplyr::select(test_exemptions, -reason)
  expect_error(
    check_leaderboard_deflated_sharpe_coverage(good_leaderboard, bad_exemptions),
    regexp = "reason"
  )
})

# ── DEFLATED_SHARPE_EXEMPTIONS itself ────────────────────────────────────────

test_that("DEFLATED_SHARPE_EXEMPTIONS has strategy/reason columns with no blank reasons", {
  expect_true(all(c("strategy", "reason") %in% names(DEFLATED_SHARPE_EXEMPTIONS)))
  expect_true(all(nzchar(DEFLATED_SHARPE_EXEMPTIONS$reason)))
})

test_that("DEFLATED_SHARPE_EXEMPTIONS lists exactly the six documented STRAT_RETURNS_WIDE_CODES exclusions", {
  expect_setequal(
    DEFLATED_SHARPE_EXEMPTIONS$strategy,
    c("CMR", "OLMAR-1", "TOM", "Risk State", "Avoid Worst", "PSO Optimal")
  )
})

test_that("DEFLATED_SHARPE_EXEMPTIONS has no duplicate strategy rows", {
  expect_equal(
    nrow(DEFLATED_SHARPE_EXEMPTIONS),
    dplyr::n_distinct(DEFLATED_SHARPE_EXEMPTIONS$strategy)
  )
})
