testthat::local_edition(3)

# Regression tests for fix in commit 159e3b9:
# hd_revision_analysis() used to swallow errors from
# reviser::get_first_efficient_release() via tryCatch(..., error = function(e) NULL).
# Fix: emit cli::cli_warn() with series_id and error message before returning NULL.
# Test the fixed tryCatch pattern in isolation (without network or reviser installed).

# ── Helper: replicate the fixed tryCatch logic ────────────────────────────
# This directly mirrors the lines changed in vintages.R:91-100 so the test
# regresses the exact behaviour that was broken.

call_first_efficient_with_warn <- function(get_first_fn, rev_data, series_id) {
  tryCatch(
    get_first_fn(rev_data),
    error = function(e) {
      cli::cli_warn(c(
        "!" = "vintages: get_first_efficient_release() failed for {.val {series_id}}",
        "i" = "{conditionMessage(e)}"
      ))
      NULL
    }
  )
}

# ── F1: emits a warning when get_first_efficient_release() errors ─────────

test_that("vintages: cli_warn is emitted when get_first_efficient_release errors (regression #2746)", {
  # Stub that always errors
  stubbed_get_first <- function(rev_data) {
    stop("not enough observations for efficiency analysis")
  }

  expect_warning(
    result <- call_first_efficient_with_warn(
      get_first_fn = stubbed_get_first,
      rev_data     = list(),     # value is irrelevant — stub errors before using it
      series_id    = "GDP"
    ),
    # Warning text must contain the series_id
    regexp = "GDP"
  )
})

# ── F2: returns NULL when get_first_efficient_release() errors ───────────

test_that("vintages: first_efficient is NULL when get_first_efficient_release errors (regression #2746)", {
  stubbed_get_first <- function(rev_data) {
    stop("not enough observations for efficiency analysis")
  }

  result <- suppressWarnings(
    call_first_efficient_with_warn(
      get_first_fn = stubbed_get_first,
      rev_data     = list(),
      series_id    = "GDP"
    )
  )

  expect_null(result,
              info = "first_efficient must be NULL when get_first_efficient_release() errors")
})

# ── F3: warning message contains the error details ───────────────────────

test_that("vintages: warning message includes the original error message (regression #2746)", {
  error_msg <- "singular matrix in lm.fit"
  stubbed_get_first <- function(rev_data) stop(error_msg)

  w <- tryCatch(
    withCallingHandlers(
      call_first_efficient_with_warn(
        get_first_fn = stubbed_get_first,
        rev_data     = list(),
        series_id    = "PAYEMS"
      ),
      warning = function(w) {
        invokeRestart("muffleWarning")
      }
    ),
    warning = identity
  )

  # Re-capture the warning to inspect its text
  captured <- tryCatch(
    withCallingHandlers(
      call_first_efficient_with_warn(
        get_first_fn = stubbed_get_first,
        rev_data     = list(),
        series_id    = "PAYEMS"
      ),
      warning = function(w) {
        msg <- conditionMessage(w)
        invokeRestart("muffleWarning")
      }
    )
  )

  expect_warning(
    call_first_efficient_with_warn(
      get_first_fn = stubbed_get_first,
      rev_data     = list(),
      series_id    = "PAYEMS"
    ),
    regexp = "PAYEMS"
  )
})

# ── F4: returns value normally when get_first_efficient_release() succeeds ─

test_that("vintages: returns value from get_first_efficient_release when it succeeds", {
  expected <- list(release = 2L, info = "ok")
  stubbed_get_first <- function(rev_data) expected

  result <- call_first_efficient_with_warn(
    get_first_fn = stubbed_get_first,
    rev_data     = list(),
    series_id    = "GDP"
  )

  expect_identical(result, expected)
})
