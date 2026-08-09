testthat::local_edition(3)
# Tests for check_metric_window_bounds() — QA gate S11 (#645)
#
# The function is defined in R/plan_qa_gates.R. Tests exercise the gate
# directly without running tar_make().
#
# Background (#645): R/plan_managed_futures.R (mf_metrics) and
# R/plan_ev_ebit.R (ev_metrics) computed an "OOS" window bounded only below
# (dates >= oos_start, no upper bound). Because the canonical Validation
# partition (R/plan_partitions.R bt_partitions) is sealed at 2023-01-01, that
# unbounded OOS window silently swallowed the whole Validation partition on
# every tar_make() -- exactly the seal breach `backtest-partitions.md`
# prohibits. This gate catches a recurrence of that defect class: any
# non-Validation, non-Full(-Period) row whose window_end exceeds test_end.

source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ──────────────────────────────────────────────────────────────────

test_end <- as.Date("2022-12-31")

# A bounded OOS window -- the #645 fix. window_end sits inside the canonical
# Testing partition, well before the sealed Validation boundary.
bounded_metrics <- tibble::tibble(
  strategy     = c("TS-Mom L/S", "TS-Mom L/S"),
  period       = c("Training", "OOS"),
  window_start = as.Date(c("2005-01-01", "2010-01-01")),
  window_end   = as.Date(c("2009-12-31", "2022-06-30"))
)

# The #645 regression itself: an "OOS" row whose window_end reaches into the
# sealed Validation partition (2023+).
unbounded_oos_metrics <- tibble::tibble(
  strategy     = c("TS-Mom L/S", "TS-Mom L/S"),
  period       = c("Training", "OOS"),
  window_start = as.Date(c("2005-01-01", "2010-01-01")),
  window_end   = as.Date(c("2009-12-31", "2026-01-31"))
)

# The same wide window, but explicitly labelled "Validation" -- this is the
# sealed partition itself and MUST be exempt from the test_end bound.
validation_metrics <- tibble::tibble(
  strategy     = c("TS-Mom L/S", "TS-Mom L/S"),
  period       = c("OOS", "Validation"),
  window_start = as.Date(c("2010-01-01", "2023-01-01")),
  window_end   = as.Date(c("2022-06-30", "2026-01-31"))
)

# The whole-sample "Full Period" row is also expected to extend past
# test_end by definition (it spans the entire series, including Validation)
# -- backtest-partitions.md's own reference implementation lists
# calc_metrics(all_data, "Full Period") alongside Training/Testing/Validation.
full_period_metrics <- tibble::tibble(
  strategy     = c("TS-Mom L/S", "TS-Mom L/S"),
  period       = c("OOS", "Full Period"),
  window_start = as.Date(c("2010-01-01", "2005-01-01")),
  window_end   = as.Date(c("2022-06-30", "2026-01-31"))
)

# The "Holdout" tier (#660): observed but NOT sealed, computed automatically,
# and its whole purpose (like Validation and Full Period) is to extend past
# test_end -- it must be exempt from the bound the same way those two are.
holdout_metrics <- tibble::tibble(
  strategy     = c("TS-Mom L/S", "TS-Mom L/S"),
  period       = c("OOS", "Holdout"),
  window_start = as.Date(c("2010-01-01", "2024-01-01")),
  window_end   = as.Date(c("2022-06-30", "2026-04-30"))
)

# A genuine #645-style regression must still be caught even after the #660
# Holdout exemption is added -- an OOS window that extends past test_end and
# is NOT labelled Holdout or Validation must still abort.
unbounded_oos_with_holdout_metrics <- tibble::tibble(
  strategy     = c("TS-Mom L/S", "TS-Mom L/S", "TS-Mom L/S"),
  period       = c("OOS", "Holdout", "Full Period"),
  window_start = as.Date(c("2010-01-01", "2024-01-01", "2005-01-01")),
  window_end   = as.Date(c("2026-04-30", "2026-04-30", "2026-04-30"))
)

# ── Tests: bounded window passes ──────────────────────────────────────────────

test_that("check_metric_window_bounds passes when all non-Validation windows are bounded at test_end", {
  expect_true(check_metric_window_bounds(bounded_metrics, test_end, "mf_metrics"))
})

# ── Tests: unbounded OOS window aborts (#645 regression) ─────────────────────

test_that("check_metric_window_bounds throws when an OOS window extends past test_end", {
  expect_error(
    check_metric_window_bounds(unbounded_oos_metrics, test_end, "mf_metrics"),
    regexp = "OOS"
  )
  expect_snapshot(
    error = TRUE,
    check_metric_window_bounds(unbounded_oos_metrics, test_end, "mf_metrics")
  )
})

test_that("check_metric_window_bounds names the source label and test_end in the error", {
  expect_error(
    check_metric_window_bounds(unbounded_oos_metrics, test_end, "mf_metrics"),
    regexp = "mf_metrics"
  )
})

# ── Tests: exempt period labels pass even when window_end > test_end ─────────

test_that("check_metric_window_bounds exempts period == 'Validation'", {
  expect_true(check_metric_window_bounds(validation_metrics, test_end, "mf_metrics"))
})

test_that("check_metric_window_bounds exempts period == 'Full Period'", {
  expect_true(check_metric_window_bounds(full_period_metrics, test_end, "mf_metrics"))
})

# ── Tests: 'Holdout' exemption (#660) ─────────────────────────────────────────

test_that("check_metric_window_bounds exempts period == 'Holdout'", {
  expect_true(check_metric_window_bounds(holdout_metrics, test_end, "mf_metrics"))
})

test_that("check_metric_window_bounds still catches a genuine #645 regression when a Holdout row is also present", {
  expect_error(
    check_metric_window_bounds(unbounded_oos_with_holdout_metrics, test_end, "mf_metrics"),
    regexp = "OOS"
  )
  # Holdout and Full Period rows in the same fixture must NOT be flagged --
  # only the offending OOS row should appear in the error.
  expect_error(
    check_metric_window_bounds(unbounded_oos_with_holdout_metrics, test_end, "mf_metrics"),
    regexp = "1 row"
  )
})

# ── Tests: required columns ───────────────────────────────────────────────────

test_that("check_metric_window_bounds throws when required columns are missing", {
  bad <- dplyr::select(bounded_metrics, -window_end)
  expect_error(
    check_metric_window_bounds(bad, test_end, "mf_metrics"),
    regexp = "window_end"
  )
  expect_snapshot(
    error = TRUE,
    check_metric_window_bounds(bad, test_end, "mf_metrics")
  )
})

# ── Tests: check_s11_registry_consistency (#667) ──────────────────────────────
#
# Guards the `qa_metric_window_bounds` target's own S11_METRICS_REGISTRY
# against silently drifting out of sync with the `metrics_by_name` list
# literal it fetches from -- an omission there would mean a registered
# target is never actually checked by S11, the exact "scope drawn around
# known instances" failure #667 widened S11 to fix in the first place.

test_that("check_s11_registry_consistency passes when every registry name is fetched", {
  expect_true(check_s11_registry_consistency(
    registry_names       = c("mf_metrics", "ev_metrics", "rsc_metrics"),
    metrics_by_name_names = c("mf_metrics", "ev_metrics", "rsc_metrics", "extra_ok")
  ))
})

test_that("check_s11_registry_consistency throws when a registry name is never fetched", {
  expect_error(
    check_s11_registry_consistency(
      registry_names       = c("mf_metrics", "ev_metrics", "rsc_metrics"),
      metrics_by_name_names = c("mf_metrics", "ev_metrics")
    ),
    regexp = "rsc_metrics"
  )
  expect_snapshot(
    error = TRUE,
    check_s11_registry_consistency(
      registry_names       = c("mf_metrics", "ev_metrics", "rsc_metrics"),
      metrics_by_name_names = c("mf_metrics", "ev_metrics")
    )
  )
})
