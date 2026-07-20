testthat::local_edition(3)
# Tests for plan_stock_backtest.R helpers
# Sourced directly since these are non-exported helper functions

# Load the helper functions by sourcing the file into a local environment.
# Parent = globalenv() so base packages (stats, etc.) are accessible.
local_env <- new.env(parent = globalenv())
suppressWarnings(
  sys.source(
    here::here("R/plan_stock_backtest.R"),
    envir = local_env,
    keep.source = FALSE
  )
)
apply_adv_cap <- local_env$apply_adv_cap

# ── F3: apply_adv_cap iterative convergence ────────────────────────────────

test_that("apply_adv_cap: result sums to 1", {
  w <- c(a = 0.05, b = 0.05, c = 0.10, d = 0.20, e = 0.60)
  # Use simple named adv so ADV cap = adv_pct_cap * adv_share * n
  adv <- c(a = 1, b = 1, c = 1, d = 1, e = 1)  # equal ADV => adv_share = 0.2 each
  result <- apply_adv_cap(w, adv, adv_pct_cap = 0.30)
  expect_equal(sum(result$capped_w), 1, tolerance = 1e-9)
})

test_that("apply_adv_cap converges below cap after redistribution", {
  # Construct a case where a single large weight would cause redistribution
  # to push another weight over the cap.
  # Equal ADV => adv_share = 0.2, n = 5 => w_max = 0.30 * 0.2 * 5 = 0.30 for each.
  # e = 0.60 gets clipped to 0.30, residual = 0.30 redistributed to a,b,c,d.
  # Each of a,b,c,d gets +0.30/4 = 0.075 added.
  # d was 0.20 → 0.20 + 0.075 = 0.275 (still under 0.30: no overshoot here).
  # Use unequal weights so redistribution definitely pushes one over:
  w <- setNames(c(0.01, 0.01, 0.01, 0.01, 0.96), letters[1:5])
  adv <- setNames(rep(1, 5), letters[1:5])
  # adv_share = 0.2, n = 5, cap = adv_pct_cap * 0.2 * 5 = adv_pct_cap
  # With adv_pct_cap = 0.30: cap = 0.30 for all. e=0.96 clipped to 0.30.
  # Residual = 0.66 → shared among a,b,c,d (0.01 each → 0.01 + 0.165 = 0.175).
  # 0.175 < 0.30, so one round suffices.
  result <- apply_adv_cap(w, adv, adv_pct_cap = 0.30)
  expect_true(max(result$capped_w) <= 0.30 + 1e-9)
  expect_equal(sum(result$capped_w), 1, tolerance = 1e-9)
})

test_that("apply_adv_cap: all-capped names leave residual as cash, not over-cap renorm (#r2122)", {
  # 3 names with equal ADV; cap = adv_pct_cap * (1/3) * 3 = adv_pct_cap = 0.30.
  # w = c(0.01, 0.01, 0.98). After clip: (0.01, 0.01, 0.30), residual = 0.68.
  # Distribute among a,b: each gets 0.34 → BOTH exceed 0.30.
  # Second iteration clips a and b to 0.30; residual = 0.08 but NO uncapped left.
  # Feasible total = 3 × 0.30 = 0.90 < 1. The 0.10 gap is uninvested cash.
  # Dividing by 0.90 would give 1/3 > 0.30 — a cap violation. Correct: leave as-is.
  w <- c(a = 0.01, b = 0.01, c = 0.98)
  adv <- c(a = 1, b = 1, c = 1)
  # 10% residual cash → warns (10% > 5% threshold)
  # NOTE: the assignment MUST happen inside the expect_warning() expression.
  # Under testthat edition 3, expect_warning() invisibly returns the warning
  # CONDITION object, not the wrapped expression's value (edition 2 returned
  # the expression's value) -- `result <- expect_warning(apply_adv_cap(...))`
  # silently captured the condition instead of the function's return list,
  # making result$capped_w NULL. Found while adding local_edition(3) for the
  # Tier A snapshot work in this file (#578).
  expect_warning(
    result <- apply_adv_cap(w, adv, adv_pct_cap = 0.30),
    regexp = "uninvested cash",
    label = "warns when residual cash exceeds 5%"
  )
  # Each weight must be ≤ cap (not 1/3 ≈ 0.333 > 0.30).
  expect_lte(max(result$capped_w), 0.30 + 1e-9,
    label = "No weight exceeds cap even when all names are cap-constrained")
  # Total may be < 1 (uninvested cash) but must not exceed 1.
  expect_lte(sum(result$capped_w), 1 + 1e-9,
    label = "Total weight does not exceed 1")
  expect_true(all(result$hit_cap),
    label = "All positions flagged as capped when all exceed limit")
  # When there is headroom (4 names, only 1 large), redistribution MUST stay under cap:
  # This is the actual regression test for the overshoot bug.
  w2 <- c(a = 0.01, b = 0.01, c = 0.01, d = 0.97)
  adv2 <- c(a = 1, b = 1, c = 1, d = 1)
  # cap = 0.30 * 0.25 * 4 = 0.30 for each; d clipped, residual to a,b,c.
  # a,b,c each get 0.01 + (0.97-0.30)/3 = 0.01 + 0.2233 = 0.2333 < 0.30. No overshoot.
  result2 <- apply_adv_cap(w2, adv2, adv_pct_cap = 0.30)
  expect_lte(max(result2$capped_w), 0.30 + 1e-9,
    label = "No position exceeds cap when there is sufficient headroom in other names")
  expect_equal(sum(result2$capped_w), 1, tolerance = 1e-9)
})

test_that("apply_adv_cap: 4 names × 0.20 cap leaves 20% as uninvested cash (#r2122)", {
  # 4 names, equal ADV, all capped at 0.20.
  # cap = 0.20 * (1/4) * 4 = 0.20 for each.
  # Initial w heavily concentrated: w = c(0.01, 0.01, 0.01, 0.97).
  # After convergence all 4 hit cap at 0.20; feasible total = 0.80.
  # Correct: weights stay at 0.20 each; 0.20 residual is uninvested cash.
  w <- c(a = 0.01, b = 0.01, c = 0.01, d = 0.97)
  adv <- c(a = 1, b = 1, c = 1, d = 1)
  # 20% residual cash → warns (20% > 5% threshold)
  # See NOTE above: assignment must be inside expect_warning() under edition 3.
  expect_warning(
    result <- apply_adv_cap(w, adv, adv_pct_cap = 0.20),
    regexp = "uninvested cash",
    label = "warns when 20% residual cash"
  )
  # Each weight ≤ 0.20
  expect_lte(max(result$capped_w), 0.20 + 1e-9,
    label = "No weight exceeds 0.20 cap")
  # Total = 0.80 (4 × 0.20), not 1.0
  expect_equal(sum(result$capped_w), 0.80, tolerance = 1e-9,
    label = "Total is 0.80, with 0.20 as uninvested cash")
  # All positions flagged as capped
  expect_true(all(result$hit_cap),
    label = "All positions flagged as capped")
})

test_that("apply_adv_cap: empty input returns empty output", {
  result <- apply_adv_cap(numeric(0), numeric(0))
  expect_equal(length(result$capped_w), 0L)
  expect_equal(length(result$hit_cap), 0L)
})

test_that("apply_adv_cap: function signature is stable (catches API drift)", {
  expect_snapshot(args(apply_adv_cap))
})

test_that("apply_adv_cap: uninvested-cash cli_warn wording is stable (#r2122)", {
  # 3 names, all cap-constrained -> 10% residual cash -> warns. Assigning the
  # result (rather than letting it auto-print) keeps this Tier A: only the
  # cli_warn text is captured, not the numeric capped_w/hit_cap payload.
  w <- c(a = 0.01, b = 0.01, c = 0.98)
  adv <- c(a = 1, b = 1, c = 1)
  expect_snapshot(result <- apply_adv_cap(w, adv, adv_pct_cap = 0.30))
})

test_that("apply_adv_cap: no cap binds when weights are small", {
  # All weights well below cap; nothing should be clipped.
  # Input must sum to 1 (contract: w is a portfolio weight vector).
  w <- setNames(rep(0.2, 5), letters[1:5])  # 0.20 each, sums to 1
  adv <- setNames(rep(1, 5), letters[1:5])
  # cap = 0.50 * 0.2 * 5 = 0.50 — well above 0.20
  result <- apply_adv_cap(w, adv, adv_pct_cap = 0.50)
  expect_false(any(result$hit_cap))
  expect_equal(sum(result$capped_w), 1, tolerance = 1e-9)
})

# ── F4: stk_universe date coercion — no Ops.POSIXt/Ops.Date warning (#203) ───

test_that("date >= Date threshold emits no Ops.POSIXt/Ops.Date warning", {
  # Reproduce the stk_universe filter pattern: DuckDB returns POSIXct;
  # stk_params$start_date is Date (from as.Date() in plan_partitions.R).
  # Before fix, this produced:
  #   Warning: Incompatible methods ("Ops.POSIXt", "Ops.Date") for ">="
  library(dplyr)

  posixct_dates <- as.POSIXct(c("2005-01-03", "2006-06-15", "2020-01-02"), tz = "UTC")
  df <- tibble::tibble(
    date   = posixct_dates,
    ticker = c("AAPL", "MSFT", "GOOG"),
    close  = c(1.0, 2.0, 3.0)
  )
  start_date <- as.Date("2006-01-01")   # Date, as set by bt_partitions$equity$train_start

  # After fix: coerce POSIXct -> Date before comparison
  df_coerced <- df |> mutate(date = as.Date(date, tz = "UTC"))

  expect_no_warning(
    df_coerced |> filter(date >= start_date),
    message = "Incompatible methods"
  )

  # Confirm the filter actually works correctly: only 2006-06-15 and 2020-01-02 survive
  result <- df_coerced |> filter(date >= start_date)
  expect_equal(nrow(result), 2L)
  expect_equal(class(result$date), "Date")
})

test_that("raw POSIXct vs Date comparison emits Ops.POSIXt warning (baseline)", {
  # Confirm the original bug is detectable — raw POSIXct warns.
  library(dplyr)

  posixct_dates <- as.POSIXct(c("2005-01-03", "2020-01-02"), tz = "UTC")
  df <- tibble::tibble(date = posixct_dates, value = 1:2)
  start_date <- as.Date("2006-01-01")

  expect_warning(
    df |> filter(date >= start_date),
    regexp = "Incompatible methods"
  )
})
