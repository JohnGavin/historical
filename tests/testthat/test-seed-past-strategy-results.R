# Tests for scripts/seed_past_strategy_results.R (Refs #962): the backfill of
# past strategy results into the research-log ledger must be idempotent,
# unsealed, honest about its status, and must never touch the tracked log
# (every run here uses a temp base_dir).

testthat::local_edition(3)

.seed_script <- function() here::here("scripts", "seed_past_strategy_results.R")

.run_seed <- function(base_dir) {
  rscript <- file.path(R.home("bin"), "Rscript")
  out <- suppressWarnings(system2(
    rscript, c(shQuote(.seed_script()), shQuote(base_dir)),
    stdout = TRUE, stderr = TRUE
  ))
  out[grepl("^seed_past_strategy_results:|^  (written|skipped)", out)]
}

.skip_unless_seed_runnable <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_not(file.exists(.seed_script()), "seed script not found")
  testthat::skip_if_not_installed("pkgload")
}

test_that("seed script is idempotent: second run writes nothing", {
  .skip_unless_seed_runnable()
  d <- tempfile("seed-past-")
  dir.create(d)
  first <- .run_seed(d)
  second <- .run_seed(d)
  expect_snapshot(cat(sub("written: .*|skipped \\(already in ledger\\): .*", "<names>",
                          c(first, "--- second run ---", second)), sep = "\n"))
  n_files <- length(list.files(file.path(d, "hypotheses"), pattern = "\\.parquet$"))
  expect_equal(n_files, 11L)
})

test_that("seeded rows are unsealed, finished, honest, and quote < 15 words", {
  .skip_unless_seed_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- tempfile("seed-past-")
  dir.create(d)
  invisible(.run_seed(d))

  rows <- suppressWarnings(hd_rlog_query("hypotheses", base_dir = d))
  expect_equal(nrow(rows), 11L)
  expect_false(any(rows$status %in% c("tested", "proposed")))
  expect_true(all(rows$status %in% hd_rlog_statuses()$status))
  expect_true(all(is.na(rows$commit_hash)))
  expect_true(all(is.na(rows$sealed_at)))
  expect_true(all(is.na(rows$seal_method)))

  ex <- lapply(rows$extra_json, jsonlite::fromJSON)
  expect_true(all(vapply(ex, function(e) isFALSE(e$preregistered), logical(1))))
  expect_true(all(vapply(ex, function(e) {
    identical(e$seal_omitted_reason,
              "backfilled after the outcome was known; sealing post-hoc commits to nothing")
  }, logical(1))))
  expect_true(all(vapply(ex, function(e) is.null(e$priority), logical(1))))
  for (f in c("outcome_source", "outcome_quote", "status_basis", "caveats")) {
    expect_true(all(vapply(ex, function(e) length(e[[f]]) > 0L &&
                             all(nzchar(e[[f]])), logical(1))),
                info = f)
  }
  n_words <- vapply(ex, function(e) lengths(strsplit(trimws(e$outcome_quote), "\\s+")),
                    integer(1))
  expect_true(all(n_words < 15L))

  led <- hd_strategy_ledger(base_dir = d)
  expect_equal(nrow(led), 11L)
  expect_true(all(is.na(led$priority)))
  expect_equal(hd_strategy_trial_count(base_dir = d), 11L)
})
