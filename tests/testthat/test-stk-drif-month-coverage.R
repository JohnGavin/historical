testthat::local_edition(3)
# Tests for check_month_coverage() — QA gate S12 (#641)
#
# The function is defined in R/plan_qa_gates.R. Guards against the #641
# defect class: a lookback/rebalance window confined to a single calendar
# month can silently drop an entire calendar month (March, fed by a
# structurally-short February -- see stk_drif_month_features() in
# R/plan_stock_backtest.R) from EVERY year of a monthly strategy target,
# with no error and no warning anywhere else in the pipeline.

source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ──────────────────────────────────────────────────────────────────

make_full_coverage <- function() {
  yms <- format(seq.Date(as.Date("2010-01-01"), as.Date("2015-12-01"), by = "month"), "%Y-%m")
  tibble::tibble(ym = yms)
}

make_march_missing <- function() {
  full <- make_full_coverage()
  dplyr::filter(full, substr(ym, 6, 7) != "03")
}

make_sparse_but_all_months <- function() {
  # Every calendar month 1-12 appears at least once (one row per calendar
  # month, taken from 2010 only), but the [min, max] span implied by that
  # single year is 12 months while only 12 rows exist -- deliberately pair
  # this fixture with a year-spanning `full` set below so span coverage
  # comes out well under 100%.
  one_of_each_month <- make_full_coverage() |>
    dplyr::filter(substr(ym, 1, 4) == "2010")
  # Add a single row 4 years later so the [min, max] span is 5 years
  # (60 months) while only 12 rows are present: coverage = 12/60 = 20%.
  dplyr::bind_rows(one_of_each_month, tibble::tibble(ym = "2014-01"))
}

# ── Test: full coverage passes ───────────────────────────────────────────────

test_that("check_month_coverage passes when all 12 calendar months are present", {
  expect_true(check_month_coverage(make_full_coverage(), "test_portfolio"))
})

# ── Test: a wholly-missing calendar month aborts (the #641 regression) ──────

test_that("check_month_coverage throws when a calendar month is entirely absent (#641)", {
  expect_error(
    check_month_coverage(make_march_missing(), "stk_drif_portfolio"),
    regexp = "stk_drif_portfolio"
  )
  expect_error(
    check_month_coverage(make_march_missing(), "stk_drif_portfolio"),
    regexp = "3"
  )
  expect_snapshot(
    error = TRUE,
    check_month_coverage(make_march_missing(), "stk_drif_portfolio")
  )
})

# ── Test: broad span-coverage collapse aborts even with all 12 months present ──

test_that("check_month_coverage throws when span coverage is below the minimum", {
  sparse <- make_sparse_but_all_months()
  expect_setequal(sort(unique(as.integer(substr(sparse$ym, 6, 7)))), 1:12)
  expect_error(
    check_month_coverage(sparse, "test_portfolio", min_span_coverage = 0.9),
    regexp = "span"
  )
})

test_that("check_month_coverage passes the same sparse fixture at a lower min_span_coverage", {
  sparse <- make_sparse_but_all_months()
  expect_true(check_month_coverage(sparse, "test_portfolio", min_span_coverage = 0.2))
})

# ── Test: required column ────────────────────────────────────────────────────

test_that("check_month_coverage throws when the ym column is missing", {
  bad <- dplyr::select(make_full_coverage(), -ym)
  expect_error(
    check_month_coverage(bad, "test_portfolio"),
    regexp = "ym"
  )
  expect_snapshot(
    error = TRUE,
    check_month_coverage(bad, "test_portfolio")
  )
})

# ── Test: zero-row input ─────────────────────────────────────────────────────

test_that("check_month_coverage throws on zero-row input", {
  empty <- make_full_coverage()[0, , drop = FALSE]
  expect_error(
    check_month_coverage(empty, "test_portfolio"),
    regexp = "zero rows"
  )
})

# ── Test: function signature is stable (catches API drift) ──────────────────

test_that("check_month_coverage signature is stable (catches API drift)", {
  expect_snapshot(args(check_month_coverage))
})
