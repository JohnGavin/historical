testthat::local_edition(3)
# Tests for check_markov_diagonal_dominance() — QA gate S32 (#838)
#
# The function is defined in R/plan_qa_gates.R and calls
# historicaldata::hd_markov_transition() at runtime, so the package must be
# loaded before sourcing the plan file. Mirrors the pattern used in
# test-cmr-units.R.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

source(here::here("R/plan_qa_gates.R"))

# ── Tests ───────────────────────────────────────────────────────────────────

test_that("check_markov_diagonal_dominance passes for a sticky 3-state series", {
  # Strongly persistent: each state repeats many times in a row before
  # switching, so every state's diagonal easily clears 1/3.
  sticky <- factor(
    rep(c("benign", "cautious", "hostile", "benign"), times = c(20, 15, 10, 20)),
    levels = c("benign", "cautious", "hostile")
  )
  expect_true(check_markov_diagonal_dominance(sticky))
})

test_that("check_markov_diagonal_dominance throws when a state persists no better than chance", {
  # Alternating series: every state's diagonal persistence is exactly 0,
  # far below the 1/3 baseline for a 3-state vocabulary.
  noisy <- factor(
    rep(c("benign", "cautious", "hostile"), times = 10),
    levels = c("benign", "cautious", "hostile")
  )
  expect_error(check_markov_diagonal_dominance(noisy), regexp = "random baseline")
  expect_snapshot(error = TRUE, check_markov_diagonal_dominance(noisy))
})

test_that("check_markov_diagonal_dominance excludes a never-observed-as-origin state from the check", {
  # "hostile" appears only as the very last element -- never as an origin,
  # so it must be excluded (NA persistence), not treated as an offender.
  s <- factor(
    c(rep("benign", 10), rep("cautious", 10), "hostile"),
    levels = c("benign", "cautious", "hostile")
  )
  expect_true(check_markov_diagonal_dominance(s))
})

test_that("check_markov_diagonal_dominance reports a custom label in the abort message", {
  noisy <- factor(rep(c("low", "high"), times = 10), levels = c("low", "high"))
  expect_error(
    check_markov_diagonal_dominance(noisy, label = "my_custom_series"),
    regexp = "my_custom_series"
  )
})
