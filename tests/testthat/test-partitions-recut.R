testthat::local_edition(3)
# Tests for the #660 four-tier partition re-cut (Training / Testing /
# Holdout / Validation) in R/plan_partitions.R `bt_partitions`.
#
# Background (#660): the original Testing/Validation split (test_end =
# 2022-12-31, val_start = 2023-01-01) was burned -- docs/stock-backtest.qmd
# published Validation figures in prose and drew a strategy conclusion from
# them. Every month from 2024-01 to the data boundary (2026-04-15 equity,
# 2026-02-27 factor as of #660) had already been read, so the fix reclassifies
# that span as a new "Holdout" tier (observed, NOT sealed) and cuts a
# genuinely untouched "Validation" window starting 2026-05-01 -- the first
# month past the current data boundary.
#
# `bt_partitions` is a targets `command` expression, not a plain object, so
# these tests evaluate the target's own quoted expression directly rather
# than re-deriving the dates by hand -- a regression that changes the dates
# in R/plan_partitions.R without updating this test will be caught either
# way, but evaluating the real expression also catches a regression in the
# *shape* (e.g. a renamed field) that a hand-copied fixture would miss.

source(here::here("R/glossary.R"))  # #668: PERIOD_LABELS_ALLOWED derives from this
source(here::here("R/plan_partitions.R"))

.eval_bt_partitions <- function() {
  targets_list <- plan_partitions()
  tgt <- targets_list[[1]]
  eval(tgt$command$expr)
}

bt_partitions <- .eval_bt_partitions()

# ── Tests: shape ──────────────────────────────────────────────────────────────

test_that("bt_partitions has the three expected asset classes", {
  expect_setequal(names(bt_partitions), c("equity", "factor", "macro"))
})

test_that("every asset class has all 8 boundary fields", {
  expected_fields <- c(
    "train_start", "train_end", "test_start", "test_end",
    "holdout_start", "holdout_end", "val_start", "val_end"
  )
  for (cls in names(bt_partitions)) {
    expect_setequal(names(bt_partitions[[cls]]), expected_fields)
  }
})

# ── Tests: boundary values (#660) ──────────────────────────────────────────────

test_that("test_end moved to 2023-12-31 for every asset class (absorbs the burned 2023)", {
  for (cls in names(bt_partitions)) {
    expect_equal(bt_partitions[[cls]]$test_end, as.Date("2023-12-31"), info = cls)
  }
})

test_that("holdout_start/holdout_end are 2024-01-01/2026-04-30 for every asset class", {
  for (cls in names(bt_partitions)) {
    expect_equal(bt_partitions[[cls]]$holdout_start, as.Date("2024-01-01"), info = cls)
    expect_equal(bt_partitions[[cls]]$holdout_end,   as.Date("2026-04-30"), info = cls)
  }
})

test_that("val_start moved to 2026-05-01 (first month past the data boundary) for every asset class", {
  for (cls in names(bt_partitions)) {
    expect_equal(bt_partitions[[cls]]$val_start, as.Date("2026-05-01"), info = cls)
  }
})

test_that("val_end is unchanged at 2026-12-31 for every asset class", {
  for (cls in names(bt_partitions)) {
    expect_equal(bt_partitions[[cls]]$val_end, as.Date("2026-12-31"), info = cls)
  }
})

test_that("train_start/train_end are unchanged from before the re-cut", {
  expect_equal(bt_partitions$equity$train_start, as.Date("2005-01-01"))
  expect_equal(bt_partitions$factor$train_start, as.Date("1968-01-01"))
  expect_equal(bt_partitions$macro$train_start,  as.Date("2007-04-01"))
  for (cls in names(bt_partitions)) {
    expect_equal(bt_partitions[[cls]]$train_end, as.Date("2019-12-31"), info = cls)
  }
})

test_that("test_start is unchanged at 2020-01-01 for every asset class", {
  for (cls in names(bt_partitions)) {
    expect_equal(bt_partitions[[cls]]$test_start, as.Date("2020-01-01"), info = cls)
  }
})

# ── Tests: ordering invariants (no gaps, no overlaps) ─────────────────────────

test_that("the four tiers are contiguous with no gaps or overlaps, for every asset class", {
  for (cls in names(bt_partitions)) {
    p <- bt_partitions[[cls]]
    expect_true(p$train_start <= p$train_end, info = cls)
    expect_equal(p$test_start, p$train_end + 1, info = cls)
    expect_true(p$test_start <= p$test_end, info = cls)
    expect_equal(p$holdout_start, p$test_end + 1, info = cls)
    expect_true(p$holdout_start <= p$holdout_end, info = cls)
    expect_equal(p$val_start, p$holdout_end + 1, info = cls)
    expect_true(p$val_start <= p$val_end, info = cls)
  }
})

# ── Tests: Validation window is empty against the current data boundary ──────
# (#660: 2026-05-01 is the first month past the data boundary -- 2026-04-15
# equity / 2026-02-27 factor as of #660 -- so this is EXPECTED, not a defect.)

test_that("the Validation window starts after the documented current data boundary", {
  current_data_boundary_equity <- as.Date("2026-04-15")
  current_data_boundary_factor <- as.Date("2026-02-27")
  expect_true(bt_partitions$equity$val_start > current_data_boundary_equity)
  expect_true(bt_partitions$factor$val_start > current_data_boundary_factor)
})
