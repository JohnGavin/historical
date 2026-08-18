testthat::local_edition(3)
# Tests for check_leaderboard_sharpe_coherence() — QA gate S17 (#677)
#
# #677 found that leaderboard `sharpe` was computed by at least FOUR
# distinct mathematical bases across ~13 source metrics targets (geometric
# vs arithmetic numerator; risk-free deducted or not). Slices 1-3b migrated
# every leaderboard-feeding source metrics target onto the canonical
# sharpe_ratio_rf() (R/utils_metrics.R) and required each to publish the
# ann_rf it used. This gate is the belt-and-braces check that
# sharpe == (cagr - ann_rf) / vol holds EXACTLY (within a documented
# rounding tolerance) for every leaderboard row -- not a "plausible band"
# on the implied risk-free rate, which cannot distinguish a genuinely
# low-rf era from a formula that silently deducted no risk-free rate at
# all (fail-loud-not-null.md).
#
# The function is defined in R/plan_qa_gates.R. Tests exercise the gate
# directly without running tar_make().

source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ────────────────────────────────────────────────────────────────

good_leaderboard <- tibble::tibble(
  strategy = c("Factor MAX", "Factor MAX", "LTR"),
  period   = c("Training", "Full Period", "Full Period"),
  cagr     = c(0.02, 0.0349, 0.0770),
  vol      = c(0.09, 0.0892, 0.1720),
  ann_rf   = c(0.02, 0.0436, 0.0176),
  sharpe   = c((0.02 - 0.02) / 0.09, (0.0349 - 0.0436) / 0.0892, (0.0770 - 0.0176) / 0.1720)
)

# The full "current production leaderboard" (Full Period rows), reconstructed
# from the sanity-check table in issue #677's slice 4 task -- verified
# offline (max diff = 0.00124, comfortably under tol = 0.02) before writing
# these tests. Kept as a standing regression: if any of the ~13
# leaderboard-feeding source targets ever reverts to a different Sharpe
# basis, this fixture (not just the synthetic ones below) should catch it.
production_leaderboard <- tibble::tibble(
  strategy = c(
    "OLMAR-1", "Avoid Worst", "Managed Futures", "LTR", "Risk State",
    "Mom Pre-Peak", "Factor DRIF", "Value (HML)", "TOM", "PSO Optimal",
    "Factor MAX", "Mom 12-2", "CMR", "Mom Post-Peak", "Stock MAX",
    "XGB DRIF", "Stock DRIF"
  ),
  period = "Full Period",
  cagr   = c(15.96, 13.50, 4.37, 7.40, 6.15, 8.80, 5.15, 5.07, 2.13, 0.85,
             3.49, 0.90, -0.78, -10.90, -14.00, -20.10, -18.21) / 100,
  vol    = c(18.67, 18.00, 6.21, 17.10, 14.73, 19.80, 10.31, 10.39, 8.00, 6.57,
             8.92, 22.50, 4.99, 22.10, 17.51, 17.05, 14.73) / 100,
  sharpe = c(0.780, 0.620, 0.477, 0.330, 0.252, 0.226, 0.076, 0.068, -0.039,
             -0.084, -0.098, -0.151, -0.544, -0.685, -0.899, -1.261, -1.332),
  ann_rf = c(1.40, 2.34, 1.41, 1.76, 2.44, 4.33, 4.36, 4.36, 2.44, 1.41,
             4.36, 4.30, 1.93, 4.24, 1.74, 1.41, 1.41) / 100
)

# ── Assertion 3 (happy path): sharpe coherent with cagr/vol/ann_rf ──────────

test_that("check_leaderboard_sharpe_coherence passes when sharpe is exactly (cagr - ann_rf) / vol", {
  expect_true(check_leaderboard_sharpe_coherence(good_leaderboard))
})

test_that("check_leaderboard_sharpe_coherence passes on the real production leaderboard (#677 slice 4 sanity check)", {
  expect_true(check_leaderboard_sharpe_coherence(production_leaderboard))
})

# ── Required columns ─────────────────────────────────────────────────────────

test_that("check_leaderboard_sharpe_coherence throws when required columns are missing", {
  bad <- dplyr::select(good_leaderboard, -ann_rf)
  expect_error(
    check_leaderboard_sharpe_coherence(bad),
    regexp = "ann_rf"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_sharpe_coherence(bad)
  )
})

# ── Assertion 1: ann_rf must never be NA ────────────────────────────────────

test_that("check_leaderboard_sharpe_coherence throws when ann_rf is NA (#677 defect B, one level up)", {
  bad <- good_leaderboard
  bad$ann_rf[bad$strategy == "LTR"] <- NA_real_
  expect_error(
    check_leaderboard_sharpe_coherence(bad),
    regexp = "LTR"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_sharpe_coherence(bad)
  )
})

test_that("check_leaderboard_sharpe_coherence names every offending strategy/period when multiple rows have NA ann_rf", {
  bad <- good_leaderboard
  bad$ann_rf <- NA_real_
  expect_error(
    check_leaderboard_sharpe_coherence(bad),
    regexp = "3 row"
  )
})

# ── Assertion 2: vol must be positive and non-NA ────────────────────────────

test_that("check_leaderboard_sharpe_coherence throws when vol is zero", {
  bad <- good_leaderboard
  bad$vol[bad$strategy == "LTR"] <- 0
  expect_error(
    check_leaderboard_sharpe_coherence(bad),
    regexp = "LTR"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_sharpe_coherence(bad)
  )
})

test_that("check_leaderboard_sharpe_coherence throws when vol is NA", {
  bad <- good_leaderboard
  bad$vol[bad$strategy == "LTR"] <- NA_real_
  expect_error(
    check_leaderboard_sharpe_coherence(bad),
    regexp = "LTR"
  )
})

# ── Assertion 3: incoherent sharpe (generic) ────────────────────────────────

test_that("check_leaderboard_sharpe_coherence throws when sharpe does not match (cagr - ann_rf) / vol", {
  bad <- good_leaderboard
  bad$sharpe[bad$strategy == "LTR"] <- 1.5  # arbitrary, unrelated to cagr/vol/ann_rf
  expect_error(
    check_leaderboard_sharpe_coherence(bad),
    regexp = "LTR"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_sharpe_coherence(bad)
  )
})

test_that("check_leaderboard_sharpe_coherence treats NA sharpe (with checkable cagr/vol/ann_rf) as incoherent, not skipped", {
  bad <- good_leaderboard
  bad$sharpe[bad$strategy == "LTR"] <- NA_real_
  expect_error(
    check_leaderboard_sharpe_coherence(bad),
    regexp = "LTR"
  )
})

test_that("check_leaderboard_sharpe_coherence passes when the discrepancy is within the rounding tolerance", {
  ok <- good_leaderboard
  # LTR's stored sharpe nudged by less than tol (0.02) -- still coherent.
  ok$sharpe[ok$strategy == "LTR"] <- ok$sharpe[ok$strategy == "LTR"] + 0.01
  expect_true(check_leaderboard_sharpe_coherence(ok))
})

test_that("check_leaderboard_sharpe_coherence fails just outside the rounding tolerance", {
  bad <- good_leaderboard
  bad$sharpe[bad$strategy == "LTR"] <- bad$sharpe[bad$strategy == "LTR"] + 0.03
  expect_error(check_leaderboard_sharpe_coherence(bad), regexp = "LTR")
})

# ── Historical-defect reconstructions (#677) ────────────────────────────────
#
# These pin the exact two failure modes issue #677 was opened to fix. A gate
# that passes today but would not have caught the bug it was built for is
# worth very little -- these tests are the point.

test_that("check_leaderboard_sharpe_coherence catches LTR's pre-fix state (a naive HAC Sharpe renamed into sharpe)", {
  # Pre-#677, R/plan_leaderboard.R's .norm_ltr() did `rename(sharpe = hac_sharpe)`.
  # LTR's real cagr/vol (7.70%/17.20%) implied a risk-free rate of -32.89% --
  # not a rate, a different statistic (cagr/vol for LTR was 0.448; the
  # published figure was 2.360, a 5.3x gap). ann_rf here is LTR's real,
  # correctly-computed annualised risk-free rate (1.76%, from the production
  # fixture above) -- exactly what #677 slice 1 wired in. sharpe = 2.360 is
  # the pre-fix hac_sharpe value that should never have been called sharpe.
  ltr_prefix <- tibble::tibble(
    strategy = "LTR",
    period   = "Full Period",
    cagr     = 0.0770,
    vol      = 0.1720,
    ann_rf   = 0.0176,
    sharpe   = 2.360
  )
  expect_error(
    check_leaderboard_sharpe_coherence(ltr_prefix),
    regexp = "LTR"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_sharpe_coherence(ltr_prefix)
  )
})

test_that("check_leaderboard_sharpe_coherence catches the no-rf family's signature (sharpe == cagr / vol exactly, despite a non-zero ann_rf)", {
  # Pre-#677, TOM / Value (HML) / Managed Futures computed sharpe = cagr/vol
  # with NO risk-free deduction at all -- an implied rf of exactly 0.00%, a
  # formula signature, not a coincidence (#677). Value (HML)'s real ann_rf
  # (4.36%, from the production fixture above) makes that omission visible:
  # sharpe stored as the un-adjusted cagr/vol ratio is incoherent with a
  # published, non-zero ann_rf sitting right next to it.
  cagr   <- 0.0507
  vol    <- 0.1039
  ann_rf <- 0.0436
  value_no_rf <- tibble::tibble(
    strategy = "Value (HML)",
    period   = "Full Period",
    cagr     = cagr,
    vol      = vol,
    ann_rf   = ann_rf,
    sharpe   = cagr / vol  # the pre-#677 no-rf formula
  )
  expect_error(
    check_leaderboard_sharpe_coherence(value_no_rf),
    regexp = "Value \\(HML\\)"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_sharpe_coherence(value_no_rf)
  )
})

test_that("check_leaderboard_sharpe_coherence catches a missing/NA ann_rf row reconstructed as #677 defect B", {
  # Pre-fix ltr_subperiod$sharpe was silently NA for every subperiod because
  # compute_sp_metrics() read a non-existent rf_ret column
  # (mean(NULL, na.rm = TRUE) == NA, no error -- fail-loud-not-null.md).
  # Reconstructed here one level up: a row that reached the leaderboard
  # without ever publishing the ann_rf its sharpe depended on.
  defect_b <- tibble::tibble(
    strategy = "LTR",
    period   = "Q1 2020",
    cagr     = 0.05,
    vol      = 0.12,
    ann_rf   = NA_real_,
    sharpe   = NA_real_
  )
  expect_error(
    check_leaderboard_sharpe_coherence(defect_b),
    regexp = "ann_rf"
  )
})
