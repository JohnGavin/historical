# Top-level test runner for tests/testthat/
# These tests exercise repo-root R/ scripts that are NOT part of the
# packages/historicaldata package. They use source(here::here("R/..."))
# to load standalone utilities (utils_metrics.R, utils_align.R, etc.)
# directly - sourcing is intentional here because these functions live
# only at the repo root, outside any package namespace.
#
# CANONICAL entry point: scripts/verify.sh. Prefer it -- it also validates
# both _targets.R pipelines, checks dashboard freshness, compares failures
# against the known baseline (issue #569), and enforces the package-suite
# skip-count baseline (#654).
#
# This script is that entry point's underlying test runner, and is also a
# safe fallback if you need to run just the root suite directly:
#   nix develop --command Rscript tests/testthat.R
#
# It sets NOT_CRAN and TESTTHAT_EDITION itself so it is safe however invoked.
# Do NOT use a bare testthat::test_dir("tests/testthat") one-liner instead --
# that leaves NOT_CRAN unset, silently skipping every skip_on_cran()-gated
# test, and leaves TESTTHAT_EDITION unset, running edition 2 not 3 (#574).
Sys.setenv(NOT_CRAN = "true")
Sys.setenv(TESTTHAT_EDITION = "3")
library(testthat)
this_file <- tryCatch(
  normalizePath(sys.frame(1)$ofile),
  error = function(e) {
    arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
    if (length(arg) == 1L) normalizePath(sub("^--file=", "", arg))
    else stop("Cannot resolve script path")
  }
)
tests_dir <- file.path(dirname(this_file), "testthat")
stopifnot(identical(edition_get(), 3L))
testthat::test_dir(tests_dir)
