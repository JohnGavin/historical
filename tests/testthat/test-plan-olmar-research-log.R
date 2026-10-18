testthat::local_edition(3)
# Tests for .olmar_research_log_write() (R/plan_olmar.R, #968): the OLMAR-1
# research-log writer is idempotent, never writes the deprecated "tested"
# status, and never overrides a newer real status. Every run uses a temp log
# directory; the tracked log is never touched.

testthat::skip_if_not_installed("pkgload")
pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
source(here::here("R/plan_olmar.R"))

.mk_metrics <- function(sharpe = 0.78) {
  tibble::tibble(
    period = c("Training", "Testing", "Full Period"),
    days = c(3000L, 1063L, 4063L),
    cagr = c(10, 8, 9), vol = c(11, 12, 11.5),
    sharpe = c(0.9, 0.5, sharpe),
    ann_rf = c(1, 1, 1), max_dd = c(-20, -15, -25),
    avg_turnover_daily = c(0.1, 0.1, 0.1)
  )
}
.mk_params <- function() {
  list(window = 25L, epsilon = 10, leverage = 0.2, cost_bps = 10,
       start_date = as.Date("2010-01-01"))
}
.mk_prices <- function() {
  tibble::tibble(date = as.Date("2010-01-04") + 0:2, SPY = 1:3, QQQ = 1:3)
}
.mk_port <- function() {
  tibble::tibble(date = as.Date("2010-01-04") + 0:2, turnover = c(0.1, 0.2, 0.3))
}
.run <- function(base_dir, sharpe = 0.78) {
  suppressMessages(.olmar_research_log_write(
    .mk_metrics(sharpe), .mk_params(), .mk_prices(), .mk_port(),
    base_dir = base_dir
  ))
}
.n_files <- function(base_dir) {
  length(list.files(base_dir, pattern = "\\.parquet$", recursive = TRUE))
}
.n_rows <- function(base_dir, table) {
  nrow(hd_rlog_query(table, base_dir = base_dir))
}

test_that("first run on an empty log writes the expected rows, never 'tested'", {
  d <- withr::local_tempdir()
  out <- .run(d)
  expect_equal(
    vapply(hd_rlog_tables(), .n_rows, integer(1), base_dir = d),
    c(hypotheses = 1L, implementations = 1L, results = 1L,
      critiques = 2L, robustness = 2L)
  )
  hyp <- hd_rlog_query("hypotheses", base_dir = d)
  expect_equal(hyp$status, "testing")
  expect_false("tested" %in% hyp$status)
  expect_true(is.na(hyp$commit_hash))  # deliberately unsealed
  expect_match(hyp$extra_json, "\"preregistered\":false", fixed = TRUE)
  expect_match(hyp$extra_json, "seal_omitted_reason", fixed = TRUE)
  expect_equal(out$hyp_id, hyp$uuid)
})

test_that("an identical second run writes zero files", {
  d <- withr::local_tempdir()
  first <- .run(d)
  before <- .n_files(d)
  second <- .run(d)
  expect_equal(.n_files(d), before)
  expect_equal(second, first)
})

test_that("changed metrics append exactly one results row, no new hypothesis", {
  d <- withr::local_tempdir()
  first <- .run(d)
  second <- .run(d, sharpe = 0.5)
  expect_equal(
    vapply(hd_rlog_tables(), .n_rows, integer(1), base_dir = d),
    c(hypotheses = 1L, implementations = 1L, results = 2L,
      critiques = 4L, robustness = 4L)
  )
  expect_equal(second$hyp_id, first$hyp_id)
  expect_equal(second$impl_id, first$impl_id)
  expect_false(identical(second$res_id, first$res_id))
  crit <- hd_rlog_query("critiques", base_dir = d)
  expect_equal(sum(crit$parent_uuid == second$res_id), 2L)
})

test_that("a newer real status stays the ledger's latest after a re-run", {
  d <- withr::local_tempdir()
  first <- .run(d)
  hyp <- hd_rlog_query("hypotheses", base_dir = d)
  suppressMessages(hd_rlog_append("hypotheses", tibble::tibble(
    uuid = hd_rlog_uuid(), parent_uuid = first$hyp_id,
    economic_claim = hyp$economic_claim, predictor = hyp$predictor,
    status = "inconclusive-unmeasurable", extra_json = NA_character_
  ), base_dir = d))
  # Later builds run AFTER the real status was recorded, so any row they
  # append is newer than it (the ledger takes the newest row per claim).
  Sys.sleep(0.05)
  .run(d)
  .run(d, sharpe = 0.5)
  led <- hd_strategy_ledger(base_dir = d)
  expect_equal(nrow(led), 1L)
  expect_equal(led$latest_status, "inconclusive-unmeasurable")
  expect_equal(.n_rows(d, "hypotheses"), 2L)
})

test_that("a missing Full Period row aborts", {
  d <- withr::local_tempdir()
  bad <- .mk_metrics()[1:2, ]
  expect_snapshot(
    error = TRUE,
    .olmar_research_log_write(bad, .mk_params(), .mk_prices(), .mk_port(),
                              base_dir = d)
  )
  expect_equal(.n_files(d), 0L)
})

test_that("an unreadable log aborts instead of looking empty", {
  d <- withr::local_tempdir()
  dir.create(file.path(d, "hypotheses"))
  writeLines("not parquet", file.path(d, "hypotheses", "broken.parquet"))
  expect_snapshot(
    error = TRUE,
    .olmar_research_log_write(.mk_metrics(), .mk_params(), .mk_prices(),
                              .mk_port(), base_dir = d),
    transform = function(lines) {
      sub("Underlying error:.*", "Underlying error: <arrow message>", lines)
    }
  )
})
