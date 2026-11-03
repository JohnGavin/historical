testthat::local_edition(3)
# Tests for S47 (build code must not call a research-log writer), Refs #968
# option (c). Three outcomes, never collapsed: PASS / FAIL (qa_s47_fail) /
# INDETERMINATE (qa_s47_indeterminate).

source(here::here("R/plan_qa_gates.R"))

.write_r <- function(dir, name, lines) {
  f <- file.path(dir, name)
  writeLines(lines, f)
  f
}
run <- function(files) check_rlog_build_readonly(build_rlog_writer_table(files))

test_that("PASS on code that only reads the log", {
  d <- withr::local_tempdir()
  f <- .write_r(d, "ok.R", c(
    "plan_x <- function() list(targets::tar_target(a, hd_rlog_query('results')))",
    ".helper <- function() hd_rlog_query('hypotheses')"
  ))
  out <- run(f)
  expect_identical(attr(out, "summary")[["fail"]], 0L)
  expect_identical(attr(out, "summary")[["examined"]], 1L)
})

test_that("FAIL when a target function plants a writer call (falsification)", {
  d <- withr::local_tempdir()
  f <- .write_r(d, "planted.R", c(
    "plan_x <- function() {",
    "  list(targets::tar_target(a, { hd_rlog_append('results', tibble::tibble()) }))",
    "}"
  ))
  expect_error(run(f), class = "qa_s47_fail")
  tbl <- build_rlog_writer_table(f)
  expect_identical(tbl$fn, "plan_x")
})

test_that("FAIL on writers reached by string, and on indirect writers", {
  d <- withr::local_tempdir()
  expect_error(run(.write_r(d, "s.R", "f <- function() do.call('hd_rlog_append', list())")),
               class = "qa_s47_fail")
  expect_error(run(.write_r(d, "i.R", "g <- function() arrow::write_parquet(x, 'p')")),
               class = "qa_s47_fail")
  expect_error(run(.write_r(d, "t.R", "h <- function() hd_strategy_idea_append(name = 'x')")),
               class = "qa_s47_fail")
})

test_that("the allow-listed commit function may write, but no one else may name it", {
  d <- withr::local_tempdir()
  ok <- .write_r(d, "commit.R", c(
    ".olmar_research_log_commit <- function(plan) hd_rlog_append('results', plan)"
  ))
  expect_identical(attr(run(ok), "summary")[["fail"]], 0L)
  caller <- .write_r(d, "caller.R", c(
    "plan_y <- function() list(targets::tar_target(b, .olmar_research_log_commit(p)))"
  ))
  expect_error(run(caller), class = "qa_s47_fail")
})

test_that("INDETERMINATE (not PASS) on no files, a missing file, or a parse error", {
  d <- withr::local_tempdir()
  expect_error(run(character(0)), class = "qa_s47_indeterminate")
  expect_error(run(file.path(d, "nope.R")), class = "qa_s47_indeterminate")
  expect_error(run(.write_r(d, "bad.R", "f <- function( {")),
               class = "qa_s47_indeterminate")
})

test_that("the real build code is clean, and a planted write in it would be seen", {
  files <- c(list.files(here::here("R"), pattern = "\\.R$", full.names = TRUE),
             here::here("docs", "_targets.R"))
  out <- run(files)
  expect_identical(attr(out, "summary")[["fail"]], 0L)
  expect_gt(attr(out, "summary")[["examined"]], 10L)
  # Falsification: the same scan over a copy of plan_olmar.R with the old
  # build-time write reinstated must FAIL.
  d <- withr::local_tempdir()
  src <- readLines(here::here("R", "plan_olmar.R"))
  planted <- .write_r(d, "plan_olmar.R", c(
    src, "", ".planted <- function() hd_rlog_append('results', tibble::tibble())"
  ))
  expect_error(run(planted), class = "qa_s47_fail")
})
