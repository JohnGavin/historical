testthat::local_edition(3)
# Tests for check_leaderboard_years_available() — QA gate S43 (#726/#851/#927)
#
# The function is defined in R/plan_qa_gates.R. The #927 Phase-0 prototype
# for #851 (P(true Sharpe > 0) leaderboard column) found `leaderboard$years`
# NA for 15 of 18 Full-Period strategies, verified via a direct tar_read()
# query -- most .norm_*() helpers in R/plan_leaderboard.R never carried a
# `years` column through at all, and three (.norm_tom()/.norm_cmr()/
# .norm_mom_sibling()) use transmute(), which silently drops any `years`
# their source DID compute. `years` is now derived ONCE, centrally, in
# R/plan_leaderboard.R immediately after the STRATEGY_OBS_ANN_FACTOR join --
# years = round(months / obs_ann_factor, 1) -- the SAME sample length
# hd_detection_power() itself uses (n_obs / ann_factor). This gate asserts
# BOTH properties: (1) every positive-Sharpe row has a non-NA, strictly
# positive `years`, and (2) `years` agrees with months / obs_ann_factor --
# so a future regression that reintroduces a second, competing `years`
# source fails loudly instead of silently drifting from the Detection
# column's own sample-length figure.

source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ──────────────────────────────────────────────────────────────

obs_ann_factor_tbl <- tibble::tibble(
  strategy       = c("OLMAR-1", "Value (HML)", "Risk State", "LTR"),
  obs_ann_factor = c(252, 12, 252, 12)
)

# All positive-Sharpe rows have a usable, consistent `years`. "OLMAR-1" /
# Training has a negative sharpe with an NA years -- deliberately included
# to prove the gate correctly ignores non-positive-Sharpe rows for
# assertion 1 (mirrors S20's own "sr <= 0 is not a meaningful question"
# scope, detection-power-required.md).
good_leaderboard <- tibble::tibble(
  strategy = c("OLMAR-1", "OLMAR-1",  "Value (HML)"),
  period   = c("Full Period", "Training", "Full Period"),
  sharpe   = c(0.78, -0.20, 0.068),
  months   = c(4000, 2000, 750),
  years    = c(round(4000 / 252, 1), NA_real_, round(750 / 12, 1))
)

# Path found by #927: sharpe > 0 but `years` is NA -- the exact defect the
# central derivation closes (Risk State's real #726/#927 shape: months is
# populated, but no per-strategy .norm_*() helper ever carried `years`
# through, so it arrived NA before this fix).
years_na_leaderboard <- tibble::tibble(
  strategy = "Risk State",
  period   = "Full Period",
  sharpe   = 0.252,
  months   = 8365,  # 33.2 years x 252 (#726's own reported figure)
  years    = NA_real_
)

# `years` is non-NA but zero/negative -- a defect distinct from NA (a
# strategy cannot have zero or negative years of data backing a positive
# Sharpe).
years_zero_leaderboard <- tibble::tibble(
  strategy = "LTR",
  period   = "Full Period",
  sharpe   = 0.330,
  months   = 254,
  years    = 0
)

# `years` is non-NA and positive, but DISAGREES with months / obs_ann_factor
# -- the regression assertion 2 exists to catch (a second, independently
# computed `years` reintroduced by a .norm_*() helper, drifting from the
# Detection column's own sample-length figure).
years_drift_leaderboard <- tibble::tibble(
  strategy = "Value (HML)",
  period   = "Full Period",
  sharpe   = 0.068,
  months   = 750,
  years    = 99.9  # true value is 750 / 12 = 62.5
)

# ── Tests: assertion 1 (non-NA, strictly positive years) ───────────────────

test_that("check_leaderboard_years_available passes when every positive-Sharpe row has a usable, consistent years", {
  expect_true(check_leaderboard_years_available(good_leaderboard, obs_ann_factor_tbl))
})

test_that("check_leaderboard_years_available ignores non-positive-Sharpe rows entirely", {
  # The NA years on the negative-sharpe "OLMAR-1 / Training" row in
  # good_leaderboard must not trip the gate -- confirmed by the pass above,
  # this test isolates that one row to make the intent explicit.
  only_negative <- good_leaderboard[good_leaderboard$strategy == "OLMAR-1" &
                                       good_leaderboard$period == "Training", ]
  expect_true(check_leaderboard_years_available(only_negative, obs_ann_factor_tbl))
})

test_that("check_leaderboard_years_available throws and names the offender when years is NA (#726/#927)", {
  expect_error(
    check_leaderboard_years_available(years_na_leaderboard, obs_ann_factor_tbl),
    regexp = "Risk State"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_years_available(years_na_leaderboard, obs_ann_factor_tbl)
  )
})

test_that("check_leaderboard_years_available throws when years is non-NA but not strictly positive", {
  expect_error(
    check_leaderboard_years_available(years_zero_leaderboard, obs_ann_factor_tbl),
    regexp = "LTR"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_years_available(years_zero_leaderboard, obs_ann_factor_tbl)
  )
})

# ── Tests: assertion 2 (agreement with months / obs_ann_factor) ────────────

test_that("check_leaderboard_years_available throws when years drifts from months / obs_ann_factor", {
  expect_error(
    check_leaderboard_years_available(years_drift_leaderboard, obs_ann_factor_tbl),
    regexp = "Value \\(HML\\)"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_years_available(years_drift_leaderboard, obs_ann_factor_tbl)
  )
})

test_that("check_leaderboard_years_available tolerates rounding (agreement within 0.05 years)", {
  fixture <- tibble::tibble(
    strategy = "Value (HML)",
    period   = "Full Period",
    sharpe   = 0.068,
    months   = 750,
    years    = 62.53  # 750 / 12 = 62.5, within tolerance
  )
  expect_true(check_leaderboard_years_available(fixture, obs_ann_factor_tbl))
})

# ── Tests: required columns ─────────────────────────────────────────────────

test_that("check_leaderboard_years_available throws when leaderboard is missing required columns", {
  bad <- dplyr::select(good_leaderboard, -years)
  expect_error(
    check_leaderboard_years_available(bad, obs_ann_factor_tbl),
    regexp = "years"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_years_available(bad, obs_ann_factor_tbl)
  )
})

test_that("check_leaderboard_years_available throws when obs_ann_factor_tbl is missing required columns", {
  bad_tbl <- dplyr::select(obs_ann_factor_tbl, -obs_ann_factor)
  expect_error(
    check_leaderboard_years_available(good_leaderboard, bad_tbl),
    regexp = "obs_ann_factor"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_years_available(good_leaderboard, bad_tbl)
  )
})
