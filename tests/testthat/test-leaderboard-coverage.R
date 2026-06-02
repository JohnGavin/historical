# Tests for check_leaderboard_coverage() — QA gate S7 (#345, extended in #400)
#
# The function is defined in R/plan_qa_gates.R.  Tests exercise it directly
# without running tar_make().

# Load the function under test directly.
source(here::here("R/plan_qa_gates.R"))

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
})

# ── Tests: SSR column (#400) ─────────────────────────────────────────────────

test_that("check_leaderboard_coverage throws when ssr column absent", {
  expect_error(
    check_leaderboard_coverage(minimal_strategy_names, no_ssr_leaderboard),
    regexp = "ssr"
  )
})

test_that("check_leaderboard_coverage throws when ssr column is entirely NA", {
  expect_error(
    check_leaderboard_coverage(minimal_strategy_names, all_na_ssr_leaderboard),
    regexp = "entirely NA"
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
