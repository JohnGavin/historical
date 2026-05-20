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
testthat::test_dir("tests/testthat")
