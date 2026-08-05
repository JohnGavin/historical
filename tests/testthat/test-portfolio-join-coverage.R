testthat::local_edition(3)
# Tests for check_portfolio_join_coverage() — QA gate (#641)
#
# The function is defined in R/plan_qa_gates.R and depends on nothing else
# in this repo, so it is exercised directly without running tar_make().
#
# Background (#641): port_returns used to chain four inner_join()s across
# its constituent strategies (stk_max, stk_drif, fac_max, fac_drif), so any
# month missing from ONE constituent silently deleted that month for ALL
# FOUR — 128 of an expected ~190+ rows, including every March
# (stk_drif_portfolio had no March rows at all). The join in
# R/plan_portfolio_opt.R is now full_join(s1, s2) |> left_join(s3) |>
# left_join(s4) — a missing constituent surfaces as an explicit NA in that
# column, not a deleted row. This gate catches a recurrence of the deleted-
# row defect and flags (without aborting) genuinely thin-coverage months.

source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ──────────────────────────────────────────────────────────────────

# 12 calendar-complete months, all four constituents present every month.
good_port_returns <- tibble::tibble(
  date     = seq.Date(as.Date("2021-01-15"), as.Date("2021-12-15"), by = "month"),
  stk_max  = seq(0.01, 0.12, length.out = 12L),
  stk_drif = seq(0.02, 0.13, length.out = 12L),
  fac_max  = seq(0.005, 0.06, length.out = 12L),
  fac_drif = seq(0.003, 0.05, length.out = 12L)
)

# March is entirely absent from the date column -- the pre-#641 symptom
# (a row deleted outright), which should be structurally impossible after
# the full/left join fix and MUST abort if it recurs.
gapped_port_returns <- good_port_returns[format(good_port_returns$date, "%m") != "03", ]

# All 12 months present, but March has only 1 of 4 constituents (stk_max) --
# the expected, benign live-edge-lag shape after the #641 fix. Must warn,
# not abort.
thin_march <- good_port_returns
thin_march$stk_drif[thin_march$date == as.Date("2021-03-15")] <- NA_real_
thin_march$fac_max[thin_march$date == as.Date("2021-03-15")]  <- NA_real_
thin_march$fac_drif[thin_march$date == as.Date("2021-03-15")] <- NA_real_

# ── Tests: assertion 1 (no calendar-month gap) ─────────────────────────────

test_that("check_portfolio_join_coverage passes on a calendar-complete date sequence", {
  expect_true(check_portfolio_join_coverage(good_port_returns))
})

test_that("check_portfolio_join_coverage aborts when a calendar month is missing entirely (#641)", {
  expect_error(
    check_portfolio_join_coverage(gapped_port_returns),
    regexp = "2021-03"
  )
  expect_snapshot(
    error = TRUE,
    check_portfolio_join_coverage(gapped_port_returns)
  )
})

# ── Tests: assertion 2 (thin-coverage warning, not abort) ──────────────────

test_that("check_portfolio_join_coverage warns (does not abort) on a thin-coverage month", {
  expect_warning(
    result <- check_portfolio_join_coverage(thin_march),
    regexp = "2021-03"
  )
  expect_true(result)  # still returns TRUE -- a warning is not a failure
})

test_that("check_portfolio_join_coverage names the missing constituents for a thin-coverage month", {
  expect_warning(
    check_portfolio_join_coverage(thin_march),
    regexp = "stk_drif, fac_max, fac_drif"
  )
  expect_snapshot(
    check_portfolio_join_coverage(thin_march)
  )
})

test_that("check_portfolio_join_coverage does not warn when every month has >= 2 constituents", {
  expect_no_warning(check_portfolio_join_coverage(good_port_returns))
})

# ── Tests: required columns ───────────────────────────────────────────────────

test_that("check_portfolio_join_coverage throws when required columns are missing", {
  bad <- dplyr::select(good_port_returns, -stk_drif)
  expect_error(
    check_portfolio_join_coverage(bad),
    regexp = "stk_drif"
  )
  expect_snapshot(
    error = TRUE,
    check_portfolio_join_coverage(bad)
  )
})
