testthat::local_edition(3)
# Tests for check_leaderboard_coverage() — QA gate S7 (#345, extended in #400)
# Tests for .norm_mf / .norm_value normalizers — wiring fix for #489 Cluster C S7.
#
# The function is defined in R/plan_qa_gates.R.  Tests exercise it directly
# without running tar_make().

# Load the function under test directly.
source(here::here("R/plan_qa_gates.R"))

# ── Normalizer helpers (mirrors logic in plan_leaderboard.R for testability) ──
# These duplicate the private .norm_mf / .norm_value functions that live inside
# the leaderboard tar_target body.  Any schema change to those helpers MUST be
# reflected here and vice-versa.

.norm_mf_test <- function(m) {
  if (is.null(m) || nrow(m) == 0) return(NULL)
  m |>
    dplyr::filter(strategy == "Long-Short TS-Mom (MOP 2012, vol-targeted)") |>
    dplyr::select(-strategy, -calmar) |>
    dplyr::rename(months = n_months) |>
    dplyr::mutate(period = ifelse(period == "Full", "Full Period", period))
}

.norm_value_test <- function(m) {
  if (is.null(m) || nrow(m) == 0) return(NULL)
  m |>
    dplyr::filter(strategy == "Pure Value (100% HML, EV/EBIT proxy)") |>
    dplyr::select(-strategy, -calmar) |>
    dplyr::rename(months = n_months) |>
    dplyr::mutate(period = ifelse(period == "Full", "Full Period", period))
}

# ── Synthetic metrics fixtures (same schema as mf_metrics / ev_metrics) ──────

synthetic_mf_metrics <- tibble::tibble(
  strategy = rep(c(
    "Long-Short TS-Mom (MOP 2012, vol-targeted)",
    "Long-Only TS-Mom (12m signal, equal-weight)",
    "Equal-Weight Benchmark (SPY+TLT+GLD+DBC)"
  ), each = 3),
  period   = rep(c("Full", "Training", "OOS"), times = 3),
  n_months = 120L,
  cagr     = 5.0,
  vol      = 12.0,
  sharpe   = 0.42,
  max_dd   = -20.0,
  calmar   = 0.25
)

synthetic_ev_metrics <- tibble::tibble(
  strategy = rep(c(
    "Pure Value (100% HML, EV/EBIT proxy)",
    "Value+Quality (50% HML + 50% RMW, QVAL proxy)",
    "Benchmark (Cap-Weighted Market)"
  ), each = 3),
  period   = rep(c("Full", "Training", "OOS"), times = 3),
  n_months = 120L,
  cagr     = 3.0,
  vol      = 10.0,
  sharpe   = 0.30,
  max_dd   = -25.0,
  calmar   = 0.12
)

# ── Tests: .norm_mf ───────────────────────────────────────────────────────────

test_that(".norm_mf returns only canonical TS-Mom rows with base leaderboard columns", {
  res <- .norm_mf_test(synthetic_mf_metrics)
  expect_false(is.null(res))
  expect_true(nrow(res) == 3L)  # Full Period / Training / OOS
  expect_true(all(c("period", "months", "cagr", "vol", "sharpe", "max_dd") %in% names(res)))
  expect_false("strategy" %in% names(res))
  expect_false("calmar"   %in% names(res))
  expect_false("n_months" %in% names(res))
})

test_that(".norm_mf returns NULL on empty input", {
  expect_null(.norm_mf_test(tibble::tibble()))
  expect_null(.norm_mf_test(NULL))
})

test_that(".norm_mf renames 'Full' to the canonical 'Full Period' label (#643)", {
  res <- .norm_mf_test(synthetic_mf_metrics)
  expect_true("Full Period" %in% res$period)
  expect_false("Full" %in% res$period)
})

test_that(".norm_mf does NOT rename 'OOS' to 'Testing' (#643 -- different window)", {
  # mf_metrics' OOS window (dates >= oos_start, unbounded) is not the same
  # span as the canonical Testing partition (bounded, R/plan_partitions.R)
  # -- see the .norm_mf() comment in R/plan_leaderboard.R for the evidence.
  res <- .norm_mf_test(synthetic_mf_metrics)
  expect_true("OOS" %in% res$period)
  expect_false("Testing" %in% res$period)
})

# ── Tests: .norm_value ────────────────────────────────────────────────────────

test_that(".norm_value returns only Pure Value rows with base leaderboard columns", {
  res <- .norm_value_test(synthetic_ev_metrics)
  expect_false(is.null(res))
  expect_true(nrow(res) == 3L)  # Full Period / Training / OOS
  expect_true(all(c("period", "months", "cagr", "vol", "sharpe", "max_dd") %in% names(res)))
  expect_false("strategy" %in% names(res))
  expect_false("calmar"   %in% names(res))
  expect_false("n_months" %in% names(res))
})

test_that(".norm_value returns NULL on empty input", {
  expect_null(.norm_value_test(tibble::tibble()))
  expect_null(.norm_value_test(NULL))
})

test_that(".norm_value renames 'Full' to the canonical 'Full Period' label (#643)", {
  res <- .norm_value_test(synthetic_ev_metrics)
  expect_true("Full Period" %in% res$period)
  expect_false("Full" %in% res$period)
})

test_that(".norm_value does NOT rename 'OOS' to 'Testing' (#643 -- different window)", {
  # ev_metrics' OOS window (dates >= oos_start, unbounded) is not the same
  # span as the canonical Testing partition (bounded, R/plan_partitions.R)
  # -- see the .norm_value() comment in R/plan_leaderboard.R for the evidence.
  res <- .norm_value_test(synthetic_ev_metrics)
  expect_true("OOS" %in% res$period)
  expect_false("Testing" %in% res$period)
})

# ── Fixtures ──────────────────────────────────────────────────────────────────

# Minimal strategy_names tibble (only columns the function reads)
minimal_strategy_names <- tibble::tibble(
  short_name = c("Factor MAX", "Factor DRIF"),
  code_name  = c("fac_max",   "fac_drif")
)

# Leaderboard WITH both strategies and both stability columns
good_leaderboard <- tibble::tibble(
  strategy      = c("Factor MAX", "Factor MAX", "Factor DRIF", "Factor DRIF"),
  period        = c("Training",   "Full Period", "Training",    "Full Period"),
  ssr           = c(NA_real_,     2.1,           NA_real_,      1.8),
  top5pct_share = c(NA_real_,     0.32,          NA_real_,      0.28)
)

# Leaderboard missing one strategy
missing_strategy_leaderboard <- tibble::tibble(
  strategy      = c("Factor MAX", "Factor MAX"),
  period        = c("Training",   "Full Period"),
  ssr           = c(NA_real_,     2.1),
  top5pct_share = c(NA_real_,     0.32)
)

# Leaderboard missing the ssr column entirely
no_ssr_leaderboard <- tibble::tibble(
  strategy      = c("Factor MAX", "Factor DRIF"),
  period        = c("Full Period", "Full Period"),
  top5pct_share = c(0.32, 0.28)
)

# Leaderboard with ssr column present but entirely NA
all_na_ssr_leaderboard <- tibble::tibble(
  strategy      = c("Factor MAX", "Factor DRIF"),
  period        = c("Full Period", "Full Period"),
  ssr           = c(NA_real_, NA_real_),
  top5pct_share = c(0.32, 0.28)
)

# Leaderboard missing top5pct_share column
no_top5_leaderboard <- tibble::tibble(
  strategy = c("Factor MAX", "Factor DRIF"),
  period   = c("Full Period", "Full Period"),
  ssr      = c(2.1, 1.8)
)

# Leaderboard with top5pct_share entirely NA
all_na_top5_leaderboard <- tibble::tibble(
  strategy      = c("Factor MAX", "Factor DRIF"),
  period        = c("Full Period", "Full Period"),
  ssr           = c(2.1, 1.8),
  top5pct_share = c(NA_real_, NA_real_)
)

# ── Tests: strategy coverage ─────────────────────────────────────────────────

test_that("check_leaderboard_coverage passes when all strategies present with SSR columns", {
  expect_true(check_leaderboard_coverage(minimal_strategy_names, good_leaderboard))
})

test_that("check_leaderboard_coverage throws when a strategy is missing", {
  expect_error(
    check_leaderboard_coverage(minimal_strategy_names, missing_strategy_leaderboard),
    regexp = "Factor DRIF"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_coverage(minimal_strategy_names, missing_strategy_leaderboard)
  )
})

# ── Tests: SSR column (#400) ─────────────────────────────────────────────────

test_that("check_leaderboard_coverage throws when ssr column absent", {
  expect_error(
    check_leaderboard_coverage(minimal_strategy_names, no_ssr_leaderboard),
    regexp = "ssr"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_coverage(minimal_strategy_names, no_ssr_leaderboard)
  )
})

test_that("check_leaderboard_coverage throws when ssr column is entirely NA", {
  expect_error(
    check_leaderboard_coverage(minimal_strategy_names, all_na_ssr_leaderboard),
    regexp = "entirely NA"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_coverage(minimal_strategy_names, all_na_ssr_leaderboard)
  )
})

# ── Tests: top5pct_share column (#400) ───────────────────────────────────────

test_that("check_leaderboard_coverage throws when top5pct_share column absent", {
  expect_error(
    check_leaderboard_coverage(minimal_strategy_names, no_top5_leaderboard),
    regexp = "top5pct_share"
  )
})

test_that("check_leaderboard_coverage throws when top5pct_share is entirely NA", {
  expect_error(
    check_leaderboard_coverage(minimal_strategy_names, all_na_top5_leaderboard),
    regexp = "entirely NA"
  )
})
