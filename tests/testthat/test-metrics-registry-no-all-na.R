testthat::local_edition(3)
# Tests for the S36 metrics-registry + subperiod all-NA gate
# (#668 deferred item 1):
#   1. discover_subperiod_targets() — source-level scan for `*_subperiod`
#      targets across R/plan_*.R
#   2. check_metrics_registry_no_all_na() — applies the S26 property
#      (no numeric column entirely NA) to every target named in
#      S11_METRICS_REGISTRY plus every discovered subperiod target
#
# #668's comment thread (2026-08-18) named `ltr_subperiod$sharpe` sitting
# `NA, NA, NA` since inception (#677 defect B) as the motivating case: it is
# neither a leaderboard input (S26's scope) nor a registry-writer target
# (S11's scope), so it sat outside every existing gate. This closes that gap
# for the whole category (S11_METRICS_REGISTRY targets + every
# `*_subperiod` target), not just for `ltr_subperiod` alone.

source(here::here("R/utils_validation.R"))
source(here::here("R/plan_qa_gates.R"))

# ── Helpers ──────────────────────────────────────────────────────────────────

# Fake read_fn keyed by name -- avoids touching the real targets store.
make_reader <- function(...) {
  store <- list(...)
  function(nm) {
    if (!nm %in% names(store)) stop(paste0("target not found: ", nm))
    store[[nm]]
  }
}

# ── discover_subperiod_targets(): the derived-set-is-non-empty property ─────

test_that("discover_subperiod_targets() finds the known #668 subperiod targets in the real repo", {
  found <- discover_subperiod_targets()
  expect_gt(length(found), 0L)
  expect_true(all(c("aw_subperiod", "ltr_subperiod", "rsc_subperiod") %in% found))
})

test_that("discover_subperiod_targets() returns a sorted, deduplicated character vector", {
  found <- discover_subperiod_targets()
  expect_type(found, "character")
  expect_identical(found, sort(unique(found)))
})

test_that("the S36 registry_names union (S11_METRICS_REGISTRY + discovered subperiod targets) is non-empty", {
  registry_names <- sort(unique(c(
    names(S11_METRICS_REGISTRY),
    discover_subperiod_targets()
  )))
  expect_gt(length(registry_names), 0L)
  # Union must be at least as large as either half alone.
  expect_gte(length(registry_names), length(S11_METRICS_REGISTRY))
})

# ── discover_subperiod_targets(): fail-loud-not-null Pattern 5 (RED→GREEN) ──

test_that("discover_subperiod_targets() aborts loud when plan_dir has no plan_*.R files", {
  empty_dir <- withr::local_tempdir()
  expect_error(
    discover_subperiod_targets(plan_dir = empty_dir),
    regexp = "zero plan_\\*\\.R files"
  )
})

test_that("discover_subperiod_targets() aborts loud when no *_subperiod target is found (RED case)", {
  no_match_dir <- withr::local_tempdir()
  writeLines(
    "targets::tar_target(some_other_target, 1)",
    file.path(no_match_dir, "plan_foo.R")
  )
  expect_error(
    discover_subperiod_targets(plan_dir = no_match_dir),
    regexp = "zero `\\*_subperiod` targets"
  )
  expect_snapshot(
    error = TRUE,
    discover_subperiod_targets(plan_dir = no_match_dir)
  )
})

test_that("discover_subperiod_targets() passes (GREEN) once a matching target is added", {
  match_dir <- withr::local_tempdir()
  writeLines(
    "targets::tar_target(zzz_subperiod, { 1 })",
    file.path(match_dir, "plan_foo.R")
  )
  expect_identical(discover_subperiod_targets(plan_dir = match_dir), "zzz_subperiod")
})

test_that("discover_subperiod_targets() finds multiple targets across multiple files", {
  multi_dir <- withr::local_tempdir()
  writeLines(
    "targets::tar_target(aaa_subperiod, { 1 })",
    file.path(multi_dir, "plan_a.R")
  )
  writeLines(
    "targets::tar_target(bbb_subperiod, { 2 })",
    file.path(multi_dir, "plan_b.R")
  )
  expect_identical(
    discover_subperiod_targets(plan_dir = multi_dir),
    c("aaa_subperiod", "bbb_subperiod")
  )
})

# ── check_metrics_registry_no_all_na(): synthetic RED→GREEN ─────────────────

test_that("check_metrics_registry_no_all_na() catches an all-NA numeric column on a NON-leaderboard target (the #668/#691 shape)", {
  clean <- tibble::tibble(strategy = "X", period = "Full Period", cagr = 0.05)
  bad_subperiod <- tibble::tibble(
    subperiod = c("Subperiod 1", "Subperiod 2", "Subperiod 3"),
    sharpe    = c(NA_real_, NA_real_, NA_real_)
  )
  reader <- make_reader(mf_metrics = clean, ltr_subperiod = bad_subperiod)

  expect_error(
    check_metrics_registry_no_all_na(
      c("mf_metrics", "ltr_subperiod"),
      read_fn = reader
    ),
    regexp = "ltr_subperiod"
  )
  expect_snapshot(
    error = TRUE,
    check_metrics_registry_no_all_na(
      c("mf_metrics", "ltr_subperiod"),
      read_fn = reader
    )
  )
})

test_that("check_metrics_registry_no_all_na() passes (GREEN) when every numeric column has a non-NA value", {
  clean_a <- tibble::tibble(strategy = "X", period = "Full Period", cagr = 0.05)
  clean_b <- tibble::tibble(subperiod = "Subperiod 1", sharpe = 1.2)
  reader <- make_reader(mf_metrics = clean_a, ltr_subperiod = clean_b)

  expect_true(
    check_metrics_registry_no_all_na(c("mf_metrics", "ltr_subperiod"), read_fn = reader)
  )
})

test_that("check_metrics_registry_no_all_na() skips a target absent from the store (not yet built)", {
  clean <- tibble::tibble(strategy = "X", period = "Full Period", cagr = 0.05)
  reader <- make_reader(mf_metrics = clean)

  expect_true(
    check_metrics_registry_no_all_na(c("mf_metrics", "not_yet_built"), read_fn = reader)
  )
})

test_that("check_metrics_registry_no_all_na() respects per-target exemptions from METRICS_REGISTRY_ALL_NA_EXEMPT", {
  bad <- tibble::tibble(strategy = "X", period = "Full Period", placeholder = NA_real_)
  reader <- make_reader(mf_metrics = bad)

  old <- METRICS_REGISTRY_ALL_NA_EXEMPT
  on.exit(METRICS_REGISTRY_ALL_NA_EXEMPT <<- old, add = TRUE)
  METRICS_REGISTRY_ALL_NA_EXEMPT <<- list(mf_metrics = "placeholder")

  expect_true(
    check_metrics_registry_no_all_na(c("mf_metrics"), read_fn = reader)
  )
})

# ── check_metrics_registry_no_all_na(): fail-loud on empty input (defence) ──

test_that("check_metrics_registry_no_all_na() aborts loud when registry_names is empty", {
  expect_error(
    check_metrics_registry_no_all_na(character(0)),
    regexp = "zero registry_names"
  )
  expect_snapshot(
    error = TRUE,
    check_metrics_registry_no_all_na(character(0))
  )
})

# ── Live-store spot check (#668 item 4): every currently-registered target
# passes today (documented here so a future regression has a named baseline
# to diff against, not just "the gate is green"). This mirrors
# check_date_key_types()'s own "reads directly from store" contract but
# skips entirely when no store exists yet (fresh checkout / no prior
# tar_make()) -- matching S33's `.run_qa_registry_leg_count_calibration()`
# treatment of a not-yet-applicable state as informational, not a failure.
test_that("check_metrics_registry_no_all_na() passes against the real store when one exists", {
  store <- here::here("docs", "_targets")
  skip_if_not(dir.exists(store), "no docs/_targets store in this checkout")

  registry_names <- sort(unique(c(
    names(S11_METRICS_REGISTRY),
    discover_subperiod_targets()
  )))
  expect_true(check_metrics_registry_no_all_na(registry_names, store = store))
})
