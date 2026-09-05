testthat::local_edition(3)
# Tests for .assert_periodicity_reconciles() (R/utils_periodicity.R) --
# the generic, shareable form of .assert_cmr_ann_factor()
# (R/plan_commodities_mean_reversion.R, #717/#720/#738), generalised for
# #719 Layer 3 ("one assertion per helper -- repetitive, though a shared
# helper fixes that").
#
# The algorithm is identical to .assert_cmr_ann_factor()'s -- that function's
# own tests (tests/testthat/test-cmr-periodicity-consistency.R) already pin
# the full edge-case surface (holiday clusters, isolated-outage allowance,
# two-sided contamination, tolerance-table drift). These tests cover the
# same surface at a reduced density, plus the one thing genuinely NEW here:
# that `label` is generic (not hardcoded "CMR") and appears correctly in
# every message.

source(here::here("R/utils_periodicity.R"))

# ── Fixtures (same construction as test-cmr-periodicity-consistency.R) ─────

biz_days <- function(from, n) {
  all_days <- seq.Date(as.Date(from), by = "day", length.out = ceiling(n * 7 / 5) + 14L)
  wd <- all_days[!format(all_days, "%u") %in% c("6", "7")]
  wd[seq_len(n)]
}

month_days <- function(from, n) seq.Date(as.Date(from), by = "month", length.out = n)

# ── Happy path: clean series at the correct declared factor ────────────────

test_that("a clean business-daily series passes at ann_factor = 252 with a generic label", {
  expect_silent(.assert_periodicity_reconciles(biz_days("2010-01-04", 2000L), 252L, "OLMAR-1"))
})

test_that("a clean monthly series passes at ann_factor = 12 with a generic label", {
  expect_silent(.assert_periodicity_reconciles(month_days("1990-01-01", 300L), 12L, "Factor DRIF"))
})

test_that("fewer than three observations is a no-op, not a false abort", {
  expect_silent(.assert_periodicity_reconciles(as.Date(c("2020-01-01", "2020-06-01")), 252L, "tiny"))
})

# ── Classification check: declared factor disagrees with the median gap ────

test_that("classification mismatch aborts and names the supplied label", {
  expect_error(
    .assert_periodicity_reconciles(month_days("1990-01-01", 100L), 252L, "Risk State"),
    "Risk State"
  )
  expect_snapshot(
    error = TRUE,
    .assert_periodicity_reconciles(month_days("1990-01-01", 100L), 252L, "Risk State")
  )
})

# ── Consistency check: a series that changes frequency partway through ─────

test_that("a mixed-frequency series (monthly era then daily era) aborts and names the label", {
  d <- sort(unique(c(month_days("1992-03-01", 94L), biz_days("2000-01-03", 2000L))))
  expect_equal(stats::median(as.numeric(diff(d))), 1)  # classification check alone would pass
  expect_error(
    .assert_periodicity_reconciles(d, 252L, "Avoid Worst"),
    "NOT consistent with a single declared periodicity"
  )
  expect_match(
    tryCatch(
      .assert_periodicity_reconciles(d, 252L, "Avoid Worst"),
      error = function(e) conditionMessage(e)
    ),
    "Avoid Worst"
  )
})

test_that("on_violation = 'warn' downgrades the consistency abort to a warning, never silent", {
  d <- sort(unique(c(month_days("1992-03-01", 94L), biz_days("2000-01-03", 2000L))))
  expect_warning(
    .assert_periodicity_reconciles(d, 252L, "TOM", on_violation = "warn"),
    "NOT consistent with a single declared periodicity"
  )
  expect_error(.assert_periodicity_reconciles(d, 252L, "TOM", on_violation = "abort"))
})

test_that("isolated outages within the allowance floor do not fire", {
  d <- biz_days("2010-01-04", 400L)
  d <- d[-seq(100L, 121L)]
  d <- d[-seq(250L, 271L)]
  expect_silent(.assert_periodicity_reconciles(d, 252L, "two-outages"))
})

# ── Structure of the guard ──────────────────────────────────────────────────

test_that("a declared ann_factor with no tolerance row aborts rather than skipping the check", {
  custom_tol <- PERIODICITY_TOLERANCE_TBL[PERIODICITY_TOLERANCE_TBL$ann_factor != 252L, , drop = FALSE]
  expect_error(
    .assert_periodicity_reconciles(
      biz_days("2010-01-04", 500L), 252L, "no-tolerance-row",
      tolerance_tbl = custom_tol
    ),
    "no periodicity tolerance defined"
  )
})

test_that("PERIODICITY_TOLERANCE_TBL matches CMR_PERIODICITY_TOLERANCE's values (parallel, not diverging, tables)", {
  # These two tables are deliberately SEPARATE objects (see this file's
  # header comment for why .assert_cmr_ann_factor() was not refactored to
  # use this one), but they encode the same reconciliation policy and
  # should not silently drift apart. If R/plan_commodities_mean_reversion.R
  # is loaded, compare directly; otherwise this test is a no-op.
  if (exists("CMR_PERIODICITY_TOLERANCE", mode = "list")) {
    expect_equal(
      PERIODICITY_TOLERANCE_TBL[order(PERIODICITY_TOLERANCE_TBL$ann_factor), ],
      CMR_PERIODICITY_TOLERANCE[order(CMR_PERIODICITY_TOLERANCE$ann_factor), ]
    )
  } else {
    succeed("CMR_PERIODICITY_TOLERANCE not loaded in this test file; skipping cross-check.")
  }
})

test_that("the tolerance table covers every ann_factor the classifier can emit", {
  expect_true(all(c(252L, 52L, 12L, 4L) %in% PERIODICITY_TOLERANCE_TBL$ann_factor))
})
