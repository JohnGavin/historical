# Tests for .hd_params_diff_bullets(): the fetch-cache params-mismatch message.
testthat::local_edition(3)

test_that("normal case: shows only the differing pieces each way", {
  b <- historicaldata:::.hd_params_diff_bullets("x.parquet", "a=1;b=2;c=3", "a=1;b=9;c=3")
  expect_named(b, c("x", "i", "i", "i"))
  expect_match(b[[2L]], "b=2", fixed = TRUE)
  expect_match(b[[3L]], "b=9", fixed = TRUE)
  expect_no_match(b[[2L]], "a=1", fixed = TRUE)
})

test_that("reorder-only and trailing-semicolon cases never give empty bullets", {
  for (pair in list(c("a=1;b=2", "b=2;a=1"), c("a=1;b=2", "a=1;b=2;"),
                    c("a=1;b=2", "a=1;a=1;b=2"))) {
    b <- historicaldata:::.hd_params_diff_bullets("x.parquet", pair[[1L]], pair[[2L]])
    expect_true(all(nzchar(trimws(b))))
    expect_match(paste(b, collapse = "\n"), pair[[1L]], fixed = TRUE)
    expect_match(paste(b, collapse = "\n"), pair[[2L]], fixed = TRUE)
    expect_match(b[[2L]], "same key=value pieces", fixed = TRUE)
  }
})

test_that("the bullets render in cli_abort for the normal and fallback cases", {
  expect_snapshot(error = TRUE, cli::cli_abort(
    historicaldata:::.hd_params_diff_bullets("x.parquet", "a=1;b=2", "a=1;b=3")))
  expect_snapshot(error = TRUE, cli::cli_abort(
    historicaldata:::.hd_params_diff_bullets("x.parquet", "a=1;b=2", "b=2;a=1;")))
})

test_that("braces in a value do not get re-interpreted by cli", {
  b <- historicaldata:::.hd_params_diff_bullets("x.parquet", "a={x}", "a={y}")
  expect_error(cli::cli_abort(b), "{x}", fixed = TRUE)
})
