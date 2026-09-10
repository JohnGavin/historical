testthat::local_edition(3)
# Tests for #778 -- extending cost-adjusted metrics (net_cagr/cvar_95/
# credible/ssr) beyond the 6 hardcoded strategies.
#
# The `leaderboard` target itself cannot be exercised without a real
# tar_make() store (out of scope for a worktree session -- see
# .claude/CLAUDE.md's "Verifying a change" table, `build.sh` main-checkout-
# only note). These tests instead cover the two module-level, standalone
# pieces #778 added to R/plan_leaderboard.R:
#
#   1. STRATEGY_COST_BASIS / .strategy_turnover_cost_basis() -- the
#      turnover-aware cost-basis table (#778 scope item 1: "a cost basis
#      per strategy family, turnover-aware, not a single blanket rate").
#   2. The joint-presence contract (S23, fail-loud-not-null.md) still holds
#      for a leaderboard shaped the way the #778 extension produces it --
#      exercised directly against check_leaderboard_cost_metrics_joint_
#      presence() (R/plan_qa_gates.R), the same pattern
#      test-leaderboard-cost-metrics-coverage.R already uses.

source(here::here("R/plan_strategy_names.R"))
source(here::here("R/plan_leaderboard.R"))
source(here::here("R/plan_qa_gates.R"))

# ── STRATEGY_COST_BASIS: coverage ───────────────────────────────────────────

test_that("STRATEGY_COST_BASIS covers every strategy in hd_strategy_names_tbl()", {
  expect_equal(nrow(STRATEGY_COST_BASIS), 17L)
  expect_setequal(STRATEGY_COST_BASIS$code_name, hd_strategy_names_tbl()$code_name)
  expect_true(all(!is.na(STRATEGY_COST_BASIS$monthly_cost)))
  expect_true(all(STRATEGY_COST_BASIS$monthly_cost > 0))
})

# The 11 strategy codes #778's cost_rows extension targets (R/plan_leaderboard.R
# `leaderboard` target, ".cost_ext_map" list) -- duplicated here deliberately
# (not extracted, since .cost_ext_map lives inside the tar_target command
# block, not at module level) so a future rename of one without the other
# fails a test instead of silently going stale.
COST_EXT_CODES_778 <- c(
  "ltr", "mom_prepeak", "mom_postpeak", "mom_combined", "ev_ebit",
  "mf_tsm", "cmr", "olmar", "tom", "rsc", "avoid_worst"
)

test_that("every #778 cost-extension strategy code has a STRATEGY_COST_BASIS row", {
  expect_length(COST_EXT_CODES_778, 11L)
  expect_true(all(COST_EXT_CODES_778 %in% STRATEGY_COST_BASIS$code_name))
})

# ── STRATEGY_COST_BASIS: formula (hand-derived, per strategy) ───────────────
# Formula (see STRATEGY_COST_BASIS's own comment, R/plan_leaderboard.R):
#   monthly_cost = (turnover_pct_per_period_avg / 100) * 0.005 * leg_multiplier
#                  + (borrow_rate_annual / 12 if directionality == "long_short" else 0)
#   leg_multiplier = 4 for long_short, 2 otherwise

test_that("monthly_cost matches the hand-derived turnover-aware formula for every strategy", {
  tbl <- hd_strategy_names_tbl()
  for (i in seq_len(nrow(tbl))) {
    code <- tbl$code_name[i]
    is_ls <- tbl$directionality[i] == "long_short"
    leg <- if (is_ls) 4 else 2
    expected <- (tbl$turnover_pct_per_period_avg[i] / 100) * 0.005 * leg +
      (if (is_ls) 0.03 / 12 else 0)
    actual <- STRATEGY_COST_BASIS$monthly_cost[STRATEGY_COST_BASIS$code_name == code]
    expect_equal(actual, expected, tolerance = 1e-12, label = paste0("monthly_cost[", code, "]"))
  }
})

test_that("long_short strategies get leg_multiplier 4 and long_only/overlay get 2", {
  tbl <- hd_strategy_names_tbl()
  ls_codes <- tbl$code_name[tbl$directionality == "long_short"]
  other_codes <- tbl$code_name[tbl$directionality != "long_short"]

  expect_true(all(
    STRATEGY_COST_BASIS$leg_multiplier[STRATEGY_COST_BASIS$code_name %in% ls_codes] == 4
  ))
  expect_true(all(
    STRATEGY_COST_BASIS$leg_multiplier[STRATEGY_COST_BASIS$code_name %in% other_codes] == 2
  ))
})

test_that("LTR's monthly_cost is the documented 0.65%/month (20% turnover, long_short)", {
  # Hand-worked example from the STRATEGY_COST_BASIS comment / PR report:
  # 0.20 * 0.005 * 4 = 0.004 (0.40% txn) + 0.03/12 = 0.0025 (borrow) = 0.0065
  ltr_cost <- STRATEGY_COST_BASIS$monthly_cost[STRATEGY_COST_BASIS$code_name == "ltr"]
  expect_equal(ltr_cost, 0.0065, tolerance = 1e-12)
})

test_that("Value (HML)'s monthly_cost has no borrow component (long_only)", {
  # 0.20 * 0.005 * 2 = 0.002 (0.20% txn), no borrow cost (long_only)
  ev_cost <- STRATEGY_COST_BASIS$monthly_cost[STRATEGY_COST_BASIS$code_name == "ev_ebit"]
  expect_equal(ev_cost, 0.002, tolerance = 1e-12)
})

test_that("original 6 cost_rows strategies remain at their historical COST_PER_MONTH, unaffected by STRATEGY_COST_BASIS", {
  # #778 explicitly leaves the original 6 (Factor MAX/DRIF, Stock MAX/DRIF,
  # XGB DRIF, PSO Optimal) at the flat 0.20%/month COST_PER_MONTH constant --
  # STRATEGY_COST_BASIS is consulted ONLY for the 11 newly-added strategies.
  #
  # COST_PER_MONTH itself is defined INSIDE the `leaderboard` tar_target's
  # command block (R/plan_leaderboard.R), not at module level, so it cannot
  # be evaluated by source()-ing the file (the surrounding target needs its
  # full set of upstream pipeline targets to run, out of scope for a
  # worktree session -- see this file's header comment). Assert on the
  # SOURCE TEXT instead: a regression here would silently alter six
  # strategies' already-published net_cagr.
  leaderboard_src <- readLines(here::here("R/plan_leaderboard.R"))
  expect_true(any(grepl("^\\s*COST_PER_MONTH <- 0\\.002\\s*$", leaderboard_src)))
})

test_that("STRATEGY_COST_BASIS output is stable (snapshot)", {
  expect_snapshot(
    STRATEGY_COST_BASIS |>
      dplyr::arrange(code_name) |>
      as.data.frame()
  )
})

test_that(".strategy_turnover_cost_basis() function signature is stable (catches API drift)", {
  expect_snapshot(args(.strategy_turnover_cost_basis))
})

# ── S23 joint-presence gate still holds for #778-shaped rows ────────────────
# calc_cost_metrics() (R/plan_leaderboard.R) always returns net_cagr, cum_pnl,
# cvar_95, credible TOGETHER from a single call -- the #778 extension calls
# the SAME function (with a turnover-aware cost_per_month instead of the flat
# default), so the joint-presence contract S23 guards is structurally
# preserved. This test proves it against a synthetic leaderboard shaped like
# the post-#778 leaderboard: the original 6 strategies have Training/Testing/
# Holdout/Full Period cost rows; the 11 #778-extended strategies have ONLY a
# Full Period cost row (by design -- see the "#778: extend cost_rows"
# comment in R/plan_leaderboard.R for why sub-period cells are intentionally
# left NA, not computed).

test_that("S23 passes on a leaderboard shaped like the post-#778 extension (6 full-coverage + 11 Full-Period-only)", {
  original_six <- tibble::tibble(
    strategy = rep(c("Factor MAX", "PSO Optimal"), each = 4),
    period   = rep(c("Training", "Testing", "Holdout", "Full Period"), times = 2),
    net_cagr = c(0.02, 0.03, 0.01, 0.025, 0.04, 0.02, 0.015, 0.03),
    cvar_95  = c(-0.03, -0.04, -0.02, -0.035, -0.05, -0.03, -0.02, -0.04),
    credible = TRUE
  )
  extended_eleven <- tibble::tibble(
    strategy = c("LTR", "CMR", "Value (HML)"),
    period   = "Full Period",
    net_cagr = c(0.018, 0.022, 0.011),
    cvar_95  = c(-0.028, -0.031, -0.019),
    credible = TRUE
  )
  # An extended strategy's OTHER period rows (Training/Testing/Holdout, which
  # come from all_metrics' base rows, NOT from cost_rows) correctly carry all
  # three cost columns as NA together -- the "not computed for sub-periods"
  # case, not a defect.
  extended_eleven_subperiods <- tibble::tibble(
    strategy = c("LTR", "LTR"),
    period   = c("Training", "Testing"),
    net_cagr = NA_real_,
    cvar_95  = NA_real_,
    credible = NA
  )
  synthetic_leaderboard <- dplyr::bind_rows(
    original_six, extended_eleven, extended_eleven_subperiods
  )

  expect_true(check_leaderboard_cost_metrics_joint_presence(synthetic_leaderboard))
})
