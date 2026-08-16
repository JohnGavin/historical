testthat::local_edition(3)
# Tests for derive_borrow_status() (#664)
#
# The function and its supporting constants (BORROW_STATUS_ALLOWED,
# BORROW_STATUS_OVERRIDES) are defined in R/plan_cost_convention.R. Tests
# exercise the pure function directly without running tar_make().
#
# Background (#664): strategy_cost_convention's borrow_rate_annual column
# conflated "no short leg -- borrow correctly N/A" with "short leg exists,
# borrow genuinely unmodelled" as a single NA value, with the distinction
# recorded only as free prose in cost_source_ref that nothing could filter,
# sort, count, or gate on. borrow_status makes the distinction
# machine-readable; derive_borrow_status() is how each row's status is
# computed from strategy_names$directionality + borrow_rate_annual presence
# (plus a small, documented override table for rows directionality alone
# cannot distinguish).

source(here::here("R/plan_cost_convention.R"))

# ── Straightforward cases: directionality + rate presence is sufficient ────

test_that("long_short with a rate resolves to modelled", {
  expect_equal(
    derive_borrow_status("Stock MAX", "long_short", TRUE),
    "modelled"
  )
})

test_that("long_short with NO rate resolves to unmodelled", {
  expect_equal(
    derive_borrow_status("CMR", "long_short", FALSE),
    "unmodelled"
  )
})

test_that("long_only resolves to not_applicable regardless of rate presence", {
  expect_equal(derive_borrow_status("Factor MAX", "long_only", FALSE), "not_applicable")
  expect_equal(derive_borrow_status("Factor MAX", "long_only", TRUE),  "not_applicable")
})

test_that("overlay resolves to not_applicable", {
  expect_equal(derive_borrow_status("TOM", "overlay", FALSE), "not_applicable")
})

test_that("market_neutral behaves like long_short", {
  expect_equal(derive_borrow_status("Toy", "market_neutral", TRUE),  "modelled")
  expect_equal(derive_borrow_status("Toy", "market_neutral", FALSE), "unmodelled")
})

# ── Mechanism check: short leg + no rate resolves to unmodelled (#664) ─────
#
# This exercises derive_borrow_status() directly with synthetic
# has_borrow_rate = FALSE inputs -- it demonstrates the MECHANISM, not the
# current registry state. As of #665 none of these 4 strategy NAMES are
# actually "unmodelled" in strategy_cost_convention any more (Mom Pre-Peak/
# Post-Peak/12-2 now carry a real 0.005 borrow rate; CMR is overridden to
# not_applicable) -- see "all 17 strategies resolve..." below for the
# current, real registry expectation.

test_that("short leg + no borrow rate resolves to unmodelled (mechanism, not current registry state)", {
  unmodelled_strategies <- c("Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "CMR")
  status <- derive_borrow_status(
    strategy        = unmodelled_strategies,
    directionality  = rep("long_short", 4L),
    has_borrow_rate = rep(FALSE, 4L)
  )
  expect_equal(status, rep("unmodelled", 4L))
})

# ── Overrides take priority over directionality-derived status ─────────────

test_that("a valid override wins over the directionality-based derivation", {
  expect_equal(
    derive_borrow_status("Value (HML)", "long_only", FALSE, override = "embedded_in_source"),
    "embedded_in_source"
  )
  # Even if directionality/rate would otherwise say something different.
  expect_equal(
    derive_borrow_status("Weird", "long_short", TRUE, override = "not_tradeable"),
    "not_tradeable"
  )
})

test_that("an override outside BORROW_STATUS_ALLOWED aborts", {
  expect_error(
    derive_borrow_status("Bogus", "long_only", FALSE, override = "not_a_real_status"),
    regexp = "Bogus"
  )
  expect_snapshot(
    error = TRUE,
    derive_borrow_status("Bogus", "long_only", FALSE, override = "not_a_real_status")
  )
})

# ── Fail-loud: NA directionality with no override aborts (never silently NA) ─

test_that("NA directionality with no override aborts, naming the strategy", {
  expect_error(
    derive_borrow_status("OLMAR-1", NA_character_, FALSE),
    regexp = "OLMAR-1"
  )
  expect_snapshot(
    error = TRUE,
    derive_borrow_status("OLMAR-1", NA_character_, FALSE)
  )
})

test_that("an unrecognised directionality value aborts, naming the allowed set", {
  expect_error(
    derive_borrow_status("Weird", "some_other_value", FALSE),
    regexp = "some_other_value"
  )
  expect_snapshot(
    error = TRUE,
    derive_borrow_status("Weird", "some_other_value", FALSE)
  )
})

test_that("mismatched vector lengths abort", {
  expect_error(
    derive_borrow_status(c("A", "B"), "long_only", c(TRUE, FALSE)),
    regexp = "same length"
  )
})

# ── Full 17-strategy registry resolves exactly as documented in #664/#665 ──
#
# directionality values below are taken directly from strategy_names
# (R/plan_strategy_names.R) as of this PR's authoring commit, with OLMAR-1
# filled per the documented #626/#629 join-gap workaround (matches the
# strategy_cost_convention target's own fill). BORROW_STATUS_OVERRIDES is
# read from the real source file, not re-typed, so a change to the override
# table is caught by this test. has_borrow_rate for Mom Pre-Peak/Post-Peak/
# Mom 12-2 is TRUE as of #665 (mom_prepeak_params$borrow_rate_annual =
# 0.005); CMR's has_borrow_rate stays FALSE (its borrow_rate_annual cell is
# still NA_real_) but is now overridden to not_applicable, not unmodelled.

test_that("all 17 strategies resolve to the expected borrow_status (#664/#665)", {
  strategy <- c(
    "Factor MAX", "Factor DRIF", "Stock MAX", "Stock DRIF", "XGB DRIF",
    "LTR", "OLMAR-1", "TOM", "CMR", "Risk State", "Avoid Worst",
    "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2",
    "Value (HML)", "Managed Futures", "PSO Optimal"
  )
  directionality <- c(
    "long_only", "long_only", "long_short", "long_short", "long_short",
    "long_short", "long_only", "overlay", "long_short", "overlay", "overlay",
    "long_short", "long_short", "long_short",
    "long_only", "long_short", "long_only"
  )
  has_borrow_rate <- c(
    FALSE, FALSE, TRUE, TRUE, TRUE,
    TRUE, FALSE, FALSE, FALSE, FALSE, FALSE,
    TRUE, TRUE, TRUE,
    FALSE, FALSE, FALSE
  )
  override <- BORROW_STATUS_OVERRIDES$borrow_status_override[
    match(strategy, BORROW_STATUS_OVERRIDES$strategy)
  ]

  status <- derive_borrow_status(strategy, directionality, has_borrow_rate, override)

  expected <- c(
    "not_applicable", "not_applicable",           # Factor MAX, Factor DRIF
    "modelled", "modelled", "modelled", "modelled", # Stock MAX/DRIF, XGB DRIF, LTR
    "not_applicable",                              # OLMAR-1
    "not_applicable",                              # TOM
    "not_applicable",                              # CMR (#665: overridden, was unmodelled)
    "not_applicable",                              # Risk State
    "not_tradeable",                               # Avoid Worst
    "modelled", "modelled", "modelled",            # Mom Pre-Peak/Post-Peak/12-2 (#665: 0.005 GC rate)
    "embedded_in_source",                          # Value (HML)
    "not_applicable",                              # Managed Futures (judgement call)
    "inherited"                                    # PSO Optimal
  )
  expect_equal(status, expected)

  # #665: no strategy is unmodelled any more -- the 4 named by #664 are now
  # either modelled (the 3 mom siblings) or overridden not_applicable (CMR).
  expect_equal(
    strategy[status == "unmodelled"],
    character(0)
  )
})

test_that("BORROW_STATUS_ALLOWED contains exactly the 6 documented statuses", {
  expect_setequal(
    BORROW_STATUS_ALLOWED,
    c("not_applicable", "modelled", "unmodelled",
      "embedded_in_source", "inherited", "not_tradeable")
  )
})
