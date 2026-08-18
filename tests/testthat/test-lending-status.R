testthat::local_edition(3)
# Tests for derive_lending_status() (#665 Part 1)
#
# The function and its supporting constants (LENDING_STATUS_ALLOWED,
# LENDING_STATUS_OVERRIDES) are defined in R/plan_cost_convention.R. Tests
# exercise the pure function directly without running tar_make().
#
# Background (#665): securities-lending income was previously modelled
# nowhere in this codebase, with no decision recorded either way --
# indistinguishable, per fail-loud-not-null.md, from a bug. lending_status
# makes the decision (deliberately zero, judged immaterial for this book's
# composition -- see R/plan_cost_convention.R for the full reasoning)
# machine-readable, mirroring how borrow_status (#664) made the borrow-side
# ambiguity machine-readable.

source(here::here("R/plan_cost_convention.R"))

# ── Default: every strategy resolves to zero_assumed_immaterial ────────────

test_that("a strategy with no override resolves to zero_assumed_immaterial", {
  expect_equal(
    derive_lending_status("Stock MAX"),
    "zero_assumed_immaterial"
  )
  expect_equal(
    derive_lending_status(c("Stock MAX", "CMR", "Mom Pre-Peak")),
    rep("zero_assumed_immaterial", 3L)
  )
})

# ── Overrides take priority over the default ────────────────────────────────

test_that("a valid override wins over the zero_assumed_immaterial default", {
  expect_equal(
    derive_lending_status("Value (HML)", override = "embedded_in_source"),
    "embedded_in_source"
  )
  expect_equal(
    derive_lending_status("PSO Optimal", override = "inherited"),
    "inherited"
  )
  expect_equal(
    derive_lending_status("Avoid Worst", override = "not_tradeable"),
    "not_tradeable"
  )
})

test_that("an override outside LENDING_STATUS_ALLOWED aborts", {
  expect_error(
    derive_lending_status("Bogus", override = "not_a_real_status"),
    regexp = "Bogus"
  )
  expect_snapshot(
    error = TRUE,
    derive_lending_status("Bogus", override = "not_a_real_status")
  )
})

test_that("mismatched override vector length aborts", {
  expect_error(
    derive_lending_status(c("A", "B"), override = c("embedded_in_source", "inherited", "not_tradeable")),
    regexp = "length"
  )
})

# ── Full 17-strategy registry resolves exactly as documented (#665) ────────
#
# override values below are read from LENDING_STATUS_OVERRIDES (the real
# source), not re-typed, so a change to the override table is caught by
# this test.

test_that("all 17 strategies resolve to the expected lending_status (#665)", {
  strategy <- c(
    "Factor MAX", "Factor DRIF", "Stock MAX", "Stock DRIF", "XGB DRIF",
    "LTR", "OLMAR-1", "TOM", "CMR", "Risk State", "Avoid Worst",
    "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2",
    "Value (HML)", "Managed Futures", "PSO Optimal"
  )
  override <- LENDING_STATUS_OVERRIDES$lending_status_override[
    match(strategy, LENDING_STATUS_OVERRIDES$strategy)
  ]

  status <- derive_lending_status(strategy, override)

  expected <- c(
    "zero_assumed_immaterial", "zero_assumed_immaterial",  # Factor MAX, Factor DRIF
    "zero_assumed_immaterial", "zero_assumed_immaterial",  # Stock MAX, Stock DRIF
    "zero_assumed_immaterial",                              # XGB DRIF
    "zero_assumed_immaterial",                              # LTR
    "zero_assumed_immaterial",                              # OLMAR-1
    "zero_assumed_immaterial",                              # TOM
    "zero_assumed_immaterial",                              # CMR (long ETF/futures leg is real)
    "zero_assumed_immaterial",                              # Risk State
    "not_tradeable",                                        # Avoid Worst
    "zero_assumed_immaterial", "zero_assumed_immaterial", "zero_assumed_immaterial", # Mom trio
    "embedded_in_source",                                   # Value (HML)
    "zero_assumed_immaterial",                              # Managed Futures (ETF-proxy long leg is real)
    "inherited"                                             # PSO Optimal
  )
  expect_equal(status, expected)

  # No strategy is left in a null-ish / undecided state -- every value is a
  # member of the documented vocabulary, never NA (fail-loud-not-null.md).
  expect_false(anyNA(status))
  expect_true(all(status %in% LENDING_STATUS_ALLOWED))
})

test_that("LENDING_STATUS_ALLOWED contains exactly the 4 documented statuses", {
  expect_setequal(
    LENDING_STATUS_ALLOWED,
    c("zero_assumed_immaterial", "embedded_in_source", "inherited", "not_tradeable")
  )
})

test_that("LENDING_STATUS_OVERRIDES covers exactly the 3 no-independent-position rows", {
  expect_setequal(
    LENDING_STATUS_OVERRIDES$strategy,
    c("Value (HML)", "PSO Optimal", "Avoid Worst")
  )
})
