# Test helpers separating CI-portable unit tests from network/integration tests.
#
# Issue #288: duckdb's `httpfs` extension cannot autoload on an offline CI
# runner, so integration tests that read remote `hf://` parquet (and other
# live-data tests) must be skipped on CI. These are integration tests, not
# offline-safe unit tests. testthat auto-loads `helper-*.R` before tests.

#' Skip a test that requires live remote data access.
#'
#' Skips on CRAN, on CI (where duckdb httpfs cannot autoload offline), and
#' when offline. Use in place of the `skip_on_cran(); skip_if_offline()` pair
#' for any test that hits the network (hf:// parquet, FRED, Ken French, etc.).
skip_if_no_remote_data <- function() {
  testthat::skip_on_cran()
  testthat::skip_on_ci()
  testthat::skip_if_offline()
}
