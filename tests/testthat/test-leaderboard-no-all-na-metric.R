testthat::local_edition(3)
# Tests for the S24 all-NA gate (#668):
#   1. check_no_all_na_numeric_columns() — the general, property-based helper
#   2. check_leaderboard_no_all_na_metric() — its leaderboard-specific wrapper
#
# #668 escalated a defect class ("a guard's reach is drawn around the
# columns known to be broken at the time it was written, not the property it
# protects") after #677 defect B: `ltr_subperiod$sharpe` was `NA, NA, NA`
# since the target's inception, and every existing gate missed it because
# none of them named `ltr_subperiod`, or checked any column but `ssr` and
# `top5pct_share` by name.
#
# The two `all(is.na(leaderboard$ssr))` / `all(is.na(leaderboard$
# top5pct_share))` checks that used to live inside check_leaderboard_
# coverage() (S7, #400) were REMOVED as part of this change — see
# tests/testthat/test-leaderboard-coverage.R's note at the fixtures section.
# The first two test_that blocks below prove the new general gate still
# catches both of those original cases, behaviourally.

source(here::here("R/plan_qa_gates.R"))

# ── Regression coverage: the two cases the old hardcoded checks caught ──────

test_that("check_leaderboard_no_all_na_metric catches an all-NA ssr column (regression, #400/#668)", {
  bad <- tibble::tibble(
    strategy      = c("Factor MAX", "Factor DRIF"),
    period        = c("Full Period", "Full Period"),
    ssr           = c(NA_real_, NA_real_),
    top5pct_share = c(0.32, 0.28)
  )
  expect_error(
    check_leaderboard_no_all_na_metric(bad),
    regexp = "ssr"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_no_all_na_metric(bad)
  )
})

test_that("check_leaderboard_no_all_na_metric catches an all-NA top5pct_share column (regression, #400/#668)", {
  bad <- tibble::tibble(
    strategy      = c("Factor MAX", "Factor DRIF"),
    period        = c("Full Period", "Full Period"),
    ssr           = c(2.1, 1.8),
    top5pct_share = c(NA_real_, NA_real_)
  )
  expect_error(
    check_leaderboard_no_all_na_metric(bad),
    regexp = "top5pct_share"
  )
})

# ── The property this gate exists for: a column S9/S10/S23 never named ──────

test_that("check_leaderboard_no_all_na_metric catches an all-NA column with NO prior hardcoded check (the #668 point)", {
  # Mirrors the #677 defect B shape: a `sharpe` column that exists but is
  # entirely NA because its source computation silently failed (e.g.
  # referenced a missing `rf_ret` column, so mean(NULL, na.rm = TRUE) -> NA
  # for every row). No S7/S9/S10/S23 check ever named `sharpe` by number, so
  # only a property-based gate can catch this.
  bad <- tibble::tibble(
    strategy = c("LTR", "LTR", "LTR"),
    period   = c("Training", "Testing", "Full Period"),
    cagr     = c(0.02, 0.01, 0.03),
    sharpe   = c(NA_real_, NA_real_, NA_real_)
  )
  expect_error(
    check_leaderboard_no_all_na_metric(bad),
    regexp = "sharpe"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_no_all_na_metric(bad)
  )
})

# ── Passing cases ────────────────────────────────────────────────────────────

test_that("check_leaderboard_no_all_na_metric passes when every numeric column has at least one non-NA value", {
  good <- tibble::tibble(
    strategy      = c("Factor MAX", "Factor MAX", "Factor DRIF", "Factor DRIF"),
    period        = c("Training",   "Full Period", "Training",    "Full Period"),
    ssr           = c(NA_real_,     2.1,           NA_real_,      1.8),
    top5pct_share = c(NA_real_,     0.32,          NA_real_,      0.28)
  )
  expect_true(check_leaderboard_no_all_na_metric(good))
})

test_that("check_leaderboard_no_all_na_metric ignores non-numeric columns entirely", {
  # `wfc_verdict` (character) and `redundant` (logical) may legitimately be
  # entirely NA or entirely one value for every row -- neither carries a
  # "numeric metric never computed" signal the way an all-NA numeric column
  # does.
  ok <- tibble::tibble(
    strategy    = c("A", "B"),
    period      = c("Full Period", "Full Period"),
    cagr        = c(0.05, 0.03),
    wfc_verdict = c(NA_character_, NA_character_),
    redundant   = c(FALSE, FALSE)
  )
  expect_true(check_leaderboard_no_all_na_metric(ok))
})

test_that("check_no_all_na_numeric_columns is a no-op on NULL or empty input", {
  expect_true(check_no_all_na_numeric_columns(NULL, "leaderboard"))
  expect_true(check_no_all_na_numeric_columns(tibble::tibble(), "leaderboard"))
})

# ── Multiple offending columns named at once ────────────────────────────────

test_that("check_no_all_na_numeric_columns names every offending column, not just the first", {
  bad <- tibble::tibble(
    strategy = c("A", "B"),
    cagr     = c(NA_real_, NA_real_),
    vol      = c(NA_real_, NA_real_),
    max_dd   = c(-0.1, -0.2)
  )
  err <- tryCatch(
    check_no_all_na_numeric_columns(bad, "leaderboard"),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "cagr")
  expect_match(err, "vol")
})

# ── Exemption mechanism ──────────────────────────────────────────────────────

test_that("check_no_all_na_numeric_columns skips columns listed in exempt", {
  bad <- tibble::tibble(
    strategy = c("A", "B"),
    cagr     = c(0.05, 0.03),
    placeholder_metric = c(NA_real_, NA_real_)
  )
  expect_error(
    check_no_all_na_numeric_columns(bad, "leaderboard"),
    regexp = "placeholder_metric"
  )
  expect_true(
    check_no_all_na_numeric_columns(bad, "leaderboard", exempt = "placeholder_metric")
  )
})
