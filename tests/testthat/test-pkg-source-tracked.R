testthat::local_edition(3)
# Tests for check_pkg_source_tracked() -- QA gate S22 (#753)
#
# The function is defined in R/plan_qa_gates.R. It guards the #753
# package-source digest MECHANISM itself (pkg_source_files/pkg_source_digest
# in docs/_targets.R), NOT cross-run staleness of other targets -- see the
# function's own roxygen for why the deeper staleness check cannot live in
# this pipeline at all and instead lives in scripts/check_pkg_staleness.R
# (tested separately in tests/testthat/test-check-pkg-staleness.R).

source(here::here("R/plan_qa_gates.R"))

test_that("check_pkg_source_tracked passes with a plausible file list and digest", {
  expect_true(
    check_pkg_source_tracked(
      pkg_source_files = paste0("file", 1:20, ".R"),
      pkg_source_digest = "abc123"
    )
  )
})

test_that("check_pkg_source_tracked throws when too few files are tracked", {
  expect_error(
    check_pkg_source_tracked(
      pkg_source_files = character(0),
      pkg_source_digest = "abc123"
    ),
    regexp = "0 file"
  )
  expect_snapshot(
    error = TRUE,
    check_pkg_source_tracked(
      pkg_source_files = character(0),
      pkg_source_digest = "abc123"
    )
  )
})

test_that("check_pkg_source_tracked throws when file count is below min_files but nonzero", {
  expect_error(
    check_pkg_source_tracked(
      pkg_source_files = c("a.R", "b.R"),
      pkg_source_digest = "abc123",
      min_files = 10L
    ),
    regexp = "2 file"
  )
})

test_that("check_pkg_source_tracked throws when digest is empty, NA, or not length-1", {
  files <- paste0("file", 1:20, ".R")
  expect_error(check_pkg_source_tracked(files, ""), regexp = "digest")
  expect_error(check_pkg_source_tracked(files, NA_character_), regexp = "digest")
  expect_error(check_pkg_source_tracked(files, c("a", "b")), regexp = "digest")
  expect_snapshot(
    error = TRUE,
    check_pkg_source_tracked(files, "")
  )
})

test_that("key check_pkg_source_tracked() signature is stable", {
  expect_snapshot(args(check_pkg_source_tracked))
})
