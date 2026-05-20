# Top-level test runner for tests/testthat/
#
# These tests exercise repo-root R/ scripts that are NOT part of the
# packages/historicaldata package. They use source(here::here("R/..."))
# to load standalone utilities (utils_metrics.R, utils_align.R, etc.)
# directly — sourcing is intentional here because these functions live
# only at the repo root, outside any package namespace.
#
# Run via:
#   nix develop --command Rscript -e 'testthat::test_dir("tests/testthat")'
# or:
#   nix develop --command Rscript tests/testthat.R
library(testthat)
# Resolve tests/testthat relative to THIS script's own path, not the working
# directory. here::here() anchors on DESCRIPTION from the cwd — when Rscript
# is invoked from /tmp or another repo root it picks the wrong project root.
# sys.frame(1)$ofile is set when the script is sourced; commandArgs("--file=")
# is set when Rscript runs it directly. Both are normalised to absolute paths.
this_file <- tryCatch(
  normalizePath(sys.frame(1)$ofile),
  error = function(e) {
    arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
    if (length(arg) == 1L) normalizePath(sub("^--file=", "", arg))
    else stop("Cannot resolve script path")
  }
)
tests_dir <- file.path(dirname(this_file), "testthat")
testthat::test_dir(tests_dir)
