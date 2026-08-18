testthat::local_edition(3)
# Tests for check_lending_status_registry() — QA gate S18 (#665 Part 1)
#
# The function is defined in R/plan_qa_gates.R and depends on
# LENDING_STATUS_ALLOWED, defined in R/plan_cost_convention.R (single source
# of truth for the lending_status vocabulary). Tests exercise the gate
# directly without running tar_make(). Sibling to test-borrow-status-registry.R
# (S16) -- see check_lending_status_registry()'s roxygen for why this is a
# separate gate rather than an extension of S16.

source(here::here("R/plan_cost_convention.R"))
source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ─────────────────────────────────────────────────────────────

good <- tibble::tibble(
  strategy       = c("Stock MAX", "CMR", "Value (HML)"),
  lending_status = c("zero_assumed_immaterial", "zero_assumed_immaterial", "embedded_in_source")
)

# ── Pass case ────────────────────────────────────────────────────────────

test_that("check_lending_status_registry passes on a consistent registry", {
  expect_true(check_lending_status_registry(good))
})

# ── Assertion 1: no NA lending_status ────────────────────────────────────

test_that("check_lending_status_registry throws on NA lending_status", {
  bad <- good
  bad$lending_status[bad$strategy == "CMR"] <- NA_character_
  expect_error(check_lending_status_registry(bad), regexp = "CMR")
  expect_snapshot(error = TRUE, check_lending_status_registry(bad))
})

# ── Assertion 2: out-of-vocabulary status ───────────────────────────────

test_that("check_lending_status_registry throws on an out-of-vocabulary status", {
  bad <- good
  bad$lending_status[bad$strategy == "Stock MAX"] <- "bogus_status"
  expect_error(check_lending_status_registry(bad), regexp = "bogus_status")
  expect_snapshot(error = TRUE, check_lending_status_registry(bad))
})

# ── Required columns ─────────────────────────────────────────────────────

test_that("check_lending_status_registry throws when required columns are missing", {
  bad <- dplyr::select(good, -lending_status)
  expect_error(check_lending_status_registry(bad), regexp = "lending_status")
  expect_snapshot(error = TRUE, check_lending_status_registry(bad))
})
