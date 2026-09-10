testthat::local_edition(3)
# Tests for check_boot_monthly_returns_coverage() — QA gate S25 (#603/#656)
#
# The function is defined in R/plan_qa_gates.R and depends on nothing else
# in this repo, so it is exercised directly without running tar_make().
#
# Background (#603/#656): boot_monthly_returns used to chain four
# inner_join()s across its constituent strategies (stk_max, stk_drif,
# fac_max, fac_drif) — the SAME four constituents and the SAME hazard as the
# #641 port_returns defect (S13) and the #656 stk_all_comparison defect
# (S24) — so any month missing from ONE constituent silently deleted that
# month for ALL FOUR (historically ~128 of ~190 rows, #603). Worse: the
# block bootstrap in boot_draws (R/plan_bootstrap_ci.R) resamples
# CONTIGUOUS row-index blocks, so a non-contiguous join let a block splice
# non-adjacent calendar months together, defeating the point of block
# resampling. The join in R/plan_bootstrap_ci.R is now a calendar-complete
# spine with everything LEFT-joined onto it — a missing constituent
# surfaces as an explicit NA in that column, not a deleted row. This gate
# catches a recurrence of the deleted-row defect and flags (without
# aborting) genuinely thin-coverage months.

source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ──────────────────────────────────────────────────────────────────

# 12 calendar-complete months, all four constituents present every month.
good_boot_monthly_returns <- tibble::tibble(
  ym       = format(seq.Date(as.Date("2021-01-15"), as.Date("2021-12-15"), by = "month"), "%Y-%m"),
  stk_max  = seq(0.01, 0.12, length.out = 12L),
  stk_drif = seq(0.02, 0.13, length.out = 12L),
  fac_max  = seq(0.005, 0.06, length.out = 12L),
  fac_drif = seq(0.003, 0.05, length.out = 12L)
)

# March is entirely absent from the ym column -- the pre-#603 symptom (a row
# deleted outright), which should be structurally impossible after the
# spine fix and MUST abort if it recurs.
gapped_boot_monthly_returns <- good_boot_monthly_returns[good_boot_monthly_returns$ym != "2021-03", ]

# All 12 months present, but March has only 1 of 4 constituents (stk_max) --
# the expected, benign live-edge-lag shape after the #603/#656 fix. Must
# warn, not abort.
thin_march <- good_boot_monthly_returns
thin_march$stk_drif[thin_march$ym == "2021-03"] <- NA_real_
thin_march$fac_max[thin_march$ym == "2021-03"]  <- NA_real_
thin_march$fac_drif[thin_march$ym == "2021-03"] <- NA_real_

# ── Tests: assertion 1 (no calendar-month gap) ─────────────────────────────

test_that("check_boot_monthly_returns_coverage passes on a calendar-complete ym sequence", {
  expect_true(check_boot_monthly_returns_coverage(good_boot_monthly_returns))
})

test_that("check_boot_monthly_returns_coverage aborts when a calendar month is missing entirely (#603)", {
  expect_error(
    check_boot_monthly_returns_coverage(gapped_boot_monthly_returns),
    regexp = "2021-03"
  )
  expect_snapshot(
    error = TRUE,
    check_boot_monthly_returns_coverage(gapped_boot_monthly_returns)
  )
})

# ── Tests: assertion 2 (thin-coverage warning, not abort) ──────────────────

test_that("check_boot_monthly_returns_coverage warns (does not abort) on a thin-coverage month", {
  expect_warning(
    result <- check_boot_monthly_returns_coverage(thin_march),
    regexp = "2021-03"
  )
  expect_true(result)  # still returns TRUE -- a warning is not a failure
})

test_that("check_boot_monthly_returns_coverage names the missing constituents for a thin-coverage month", {
  expect_warning(
    check_boot_monthly_returns_coverage(thin_march),
    regexp = "stk_drif, fac_max, fac_drif"
  )
  expect_snapshot(
    check_boot_monthly_returns_coverage(thin_march)
  )
})

test_that("check_boot_monthly_returns_coverage does not warn when every month has all 4 constituents", {
  expect_no_warning(check_boot_monthly_returns_coverage(good_boot_monthly_returns))
})

# ── Tests: required columns ───────────────────────────────────────────────────

test_that("check_boot_monthly_returns_coverage throws when required columns are missing", {
  bad <- dplyr::select(good_boot_monthly_returns, -stk_drif)
  expect_error(
    check_boot_monthly_returns_coverage(bad),
    regexp = "stk_drif"
  )
  expect_snapshot(
    error = TRUE,
    check_boot_monthly_returns_coverage(bad)
  )
})
