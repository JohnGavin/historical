# Test helper for hermetic fixture tests (issue #580 Phase 2).
#
# Sets HD_USE_SAMPLE_DATA=1 for the duration of the calling test (or other
# scope), which routes every dataset accessor through hd_dataset_source()
# to the bundled inst/extdata/sample/*.parquet fixtures instead of the live
# hf:// endpoint. See R/registry.R::hd_dataset_source() and
# R/sample_data.R::hd_sample_path(). testthat auto-loads `helper-*.R` before
# tests, same mechanism as helper-skip.R.

#' Route dataset accessors to the bundled sample-data fixtures for this scope.
#'
#' @param env Environment the override is scoped to (defaults to the
#'   calling test's frame, so it is unset automatically at test end).
#' @return Invisible; called for its side effect via [withr::local_envvar()].
#' @noRd
local_sample_data <- function(env = parent.frame()) {
  withr::local_envvar(c(HD_USE_SAMPLE_DATA = "1"), .local_envir = env)
}
