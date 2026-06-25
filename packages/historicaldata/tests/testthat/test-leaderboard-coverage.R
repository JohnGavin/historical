# Tests for check_leaderboard_coverage() — leaderboard strategy coverage gate (S7)
# All tests are offline — no pipeline, no file I/O.
# testthat edition 3.

# check_leaderboard_coverage() lives in R/plan_qa_gates.R (plan-level, not
# exported from historicaldata).  When running devtools::test() from the package,
# source the plan file from the repo root so the helper is available.
# In CI the repo root is two levels up from packages/historicaldata/.
.repo_root <- function() {
  # Walk up until we find docs/_targets.R (reliable repo-root indicator).
  p <- normalizePath(".", mustWork = FALSE)
  for (i in seq_len(8L)) {
    if (file.exists(file.path(p, "docs", "_targets.R"))) return(p)
    p <- dirname(p)
  }
  stop("Cannot locate repo root from: ", normalizePath(".", mustWork = FALSE))
}

# Source plan_qa_gates.R only if the helper is not already in scope.
# This avoids double-sourcing when the plan is already loaded in the test
# runner's process.
if (!existsFunction("check_leaderboard_coverage")) {
  root <- .repo_root()
  source(file.path(root, "R", "plan_qa_gates.R"))
}


# ── Fixtures ─────────────────────────────────────────────────────────────────

.make_strategy_names <- function(short_names) {
  tibble::tibble(
    code_name  = tolower(gsub(" ", "_", short_names)),
    short_name = short_names
  )
}

.make_leaderboard <- function(strategies) {
  tibble::tibble(
    strategy      = strategies,
    period        = "Full Period",
    cagr          = 5.0,
    sharpe        = 0.5,
    ssr           = 0.8,
    top5pct_share = 0.05
  )
}


# ── Tests: missing strategies → error ────────────────────────────────────────

test_that("check_leaderboard_coverage: throws when a strategy is missing", {
  sn <- .make_strategy_names(c("Alpha", "Beta", "Gamma"))
  lb <- .make_leaderboard(c("Alpha", "Beta"))  # Gamma missing

  expect_error(
    check_leaderboard_coverage(sn, lb),
    regexp = "missing"
  )
})

test_that("check_leaderboard_coverage: error message names the missing strategy", {
  sn <- .make_strategy_names(c("Alpha", "Beta", "Gamma"))
  lb <- .make_leaderboard(c("Alpha", "Beta"))

  expect_error(
    check_leaderboard_coverage(sn, lb),
    regexp = "Gamma"
  )
})

test_that("check_leaderboard_coverage: error cites count correctly", {
  sn <- .make_strategy_names(c("Alpha", "Beta", "Gamma"))
  lb <- .make_leaderboard("Alpha")  # 2 of 3 missing

  expect_error(
    check_leaderboard_coverage(sn, lb),
    regexp = "2/3"
  )
})


# ── Tests: complete coverage → TRUE ──────────────────────────────────────────

test_that("check_leaderboard_coverage: returns TRUE when all strategies present", {
  sn <- .make_strategy_names(c("Alpha", "Beta", "Gamma"))
  lb <- .make_leaderboard(c("Alpha", "Beta", "Gamma"))

  result <- check_leaderboard_coverage(sn, lb)
  expect_true(result)
})

test_that("check_leaderboard_coverage: returns TRUE when leaderboard has extra strategies", {
  # Extra strategies (e.g. benchmarks) in leaderboard are fine
  sn <- .make_strategy_names(c("Alpha", "Beta"))
  lb <- .make_leaderboard(c("Alpha", "Beta", "Extra"))

  result <- check_leaderboard_coverage(sn, lb)
  expect_true(result)
})

test_that("check_leaderboard_coverage: handles duplicate strategy rows in leaderboard", {
  # Leaderboard has one row per period; strategy name repeats across periods
  sn <- .make_strategy_names(c("Alpha", "Beta"))
  lb <- tibble::tibble(
    strategy      = rep(c("Alpha", "Beta"), each = 4L),
    period        = rep(c("Training", "Testing", "Validation", "Full Period"), times = 2L),
    cagr          = 5.0,
    sharpe        = 0.5,
    ssr           = 0.8,
    top5pct_share = 0.05
  )

  result <- check_leaderboard_coverage(sn, lb)
  expect_true(result)
})

test_that("check_leaderboard_coverage: empty leaderboard with non-empty strategy_names throws", {
  sn <- .make_strategy_names(c("Alpha", "Beta"))
  lb <- .make_leaderboard(character(0))

  expect_error(
    check_leaderboard_coverage(sn, lb),
    regexp = "missing"
  )
})
