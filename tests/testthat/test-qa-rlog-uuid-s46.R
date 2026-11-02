testthat::local_edition(3)
# Tests for S46 (a research-log hypotheses uuid must not repeat), Refs #968.
#
# Three outcomes, never collapsed: PASS / FAIL (qa_s46_fail) / INDETERMINATE
# (qa_s46_indeterminate). The tracked log holds ONE known historical repeat
# (uuid d2ccd873..., 7 rows, all written before commit a12524c); it is carried
# by an explicit, reasoned allow-list, not silently ignored.

pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
source(here::here("R/plan_qa_gates.R"))

none <- S46_RLOG_DUP_ALLOWLIST[0, ]
hyp <- function(u) tibble::tibble(uuid = u, timestamp = Sys.time())
run <- function(h, a = none) check_rlog_uuid_unique(build_rlog_uuid_table(h, a))

test_that("PASS when every uuid is unique", {
  out <- run(hyp(c("a", "b", "c")))
  s <- attr(out, "summary")
  expect_identical(s[["fail"]], 0L)
  expect_identical(s[["examined"]], 3L)
})

test_that("FAIL on a synthetic duplicate uuid (falsification)", {
  expect_error(run(hyp(c("a", "b", "a"))), class = "qa_s46_fail")
})

test_that("FAIL on a missing uuid", {
  expect_error(run(hyp(c("a", NA))), class = "qa_s46_fail")
})

test_that("INDETERMINATE (not PASS, not FAIL) on NULL, zero rows, or missing column", {
  expect_error(run(NULL), class = "qa_s46_indeterminate")
  expect_error(run(hyp(character(0))), class = "qa_s46_indeterminate")
  expect_error(run(tibble::tibble(x = 1)), class = "qa_s46_indeterminate")
})

test_that("an allow-listed repeat passes only up to its max_rows and states its reason", {
  al <- tibble::tibble(uuid = "a", max_rows = 2L, reason = "historical, test")
  out <- run(hyp(c("a", "a", "b")), al)
  expect_identical(attr(out, "summary")[["allowed"]], 1L)
  expect_match(out$detail[out$uuid == "a"], "historical, test", fixed = TRUE)
  expect_error(run(hyp(c("a", "a", "a")), al), class = "qa_s46_fail")
})

test_that("every allow-list entry carries a non-empty reason", {
  expect_true(all(nzchar(S46_RLOG_DUP_ALLOWLIST$reason)))
  expect_false(anyNA(S46_RLOG_DUP_ALLOWLIST$max_rows))
})

test_that("tracked log: PASS only through the reasoned allow-list", {
  h <- hd_rlog_query("hypotheses",
                                     base_dir = here::here("inst/extdata/research_log"))
  # without the allow-list the historical repeat is a FAIL (not hidden)
  expect_error(run(h), class = "qa_s46_fail")
  out <- run(h, S46_RLOG_DUP_ALLOWLIST)
  expect_gte(attr(out, "summary")[["allowed"]], 1L)
})
