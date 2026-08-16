testthat::local_edition(3)
# Tests for check_borrow_status_registry() — QA gate S16 (#664)
#
# The function is defined in R/plan_qa_gates.R and depends on
# BORROW_STATUS_ALLOWED, defined in R/plan_cost_convention.R (single source
# of truth for the borrow_status vocabulary). Tests exercise the gate
# directly without running tar_make().
#
# Background (#664): borrow_status is DERIVED (derive_borrow_status(),
# tested in test-borrow-status.R), but the registry itself could still drift
# out of sync -- a hand-edited borrow_rate_annual without a matching status
# update, or a future override that doesn't match BORROW_STATUS_ALLOWED.
# This gate is the belt-and-braces check on the assembled
# strategy_cost_convention target.

source(here::here("R/plan_cost_convention.R"))
source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ─────────────────────────────────────────────────────────────

good <- tibble::tibble(
  strategy            = c("Stock MAX", "CMR", "Factor MAX"),
  borrow_status       = c("modelled", "unmodelled", "not_applicable"),
  borrow_rate_annual  = c(0.03, NA_real_, NA_real_)
)

# ── Pass case ────────────────────────────────────────────────────────────

test_that("check_borrow_status_registry passes on a consistent registry", {
  expect_true(check_borrow_status_registry(good))
})

# ── Assertion 1: no NA borrow_status ────────────────────────────────────

test_that("check_borrow_status_registry throws on NA borrow_status", {
  bad <- good
  bad$borrow_status[bad$strategy == "CMR"] <- NA_character_
  expect_error(check_borrow_status_registry(bad), regexp = "CMR")
  expect_snapshot(error = TRUE, check_borrow_status_registry(bad))
})

# ── Assertion 2: out-of-vocabulary status ───────────────────────────────

test_that("check_borrow_status_registry throws on an out-of-vocabulary status", {
  bad <- good
  bad$borrow_status[bad$strategy == "Factor MAX"] <- "bogus_status"
  expect_error(check_borrow_status_registry(bad), regexp = "bogus_status")
  expect_snapshot(error = TRUE, check_borrow_status_registry(bad))
})

# ── Assertion 3: contradiction between status and rate presence ─────────
# This is the exact defect shape named in the task: a "modelled" row with no
# rate, or a non-"modelled" row WITH a rate, must abort.

test_that("check_borrow_status_registry throws when a modelled row has no rate", {
  bad <- good
  bad$borrow_rate_annual[bad$strategy == "Stock MAX"] <- NA_real_
  expect_error(check_borrow_status_registry(bad), regexp = "Stock MAX")
  expect_snapshot(error = TRUE, check_borrow_status_registry(bad))
})

test_that("check_borrow_status_registry throws when a non-modelled row HAS a rate", {
  bad <- good
  bad$borrow_rate_annual[bad$strategy == "CMR"] <- 0.05
  expect_error(check_borrow_status_registry(bad), regexp = "CMR")
  expect_snapshot(error = TRUE, check_borrow_status_registry(bad))
})

test_that("check_borrow_status_registry throws when a not_applicable row HAS a rate", {
  bad <- good
  bad$borrow_rate_annual[bad$strategy == "Factor MAX"] <- 0.02
  expect_error(check_borrow_status_registry(bad), regexp = "Factor MAX")
})

# ── Required columns ─────────────────────────────────────────────────────

test_that("check_borrow_status_registry throws when required columns are missing", {
  bad <- dplyr::select(good, -borrow_rate_annual)
  expect_error(check_borrow_status_registry(bad), regexp = "borrow_rate_annual")
  expect_snapshot(error = TRUE, check_borrow_status_registry(bad))
})
