testthat::local_edition(3)
# S47 / #631: dashboard source links need a `#L<n>` anchor when the link text
# names a symbol, and every anchor must be within the target's line count.
# Render-independent: scans docs/*.qmd, so it runs in verify.sh with no store.

source(here::here("R/plan_qa_gates.R"))

root <- here::here()
gh <- "https://github.com/JohnGavin/historical/blob/main"

test_that("docs/*.qmd: no symbol link into project source lacks #L<n>, none is stale", {
  skip_if_not(dir.exists(here::here("docs")), "docs/ not present")
  hits <- check_no_bare_source_urls(here::here("docs"), root)
  expect_equal(
    nrow(hits), 0L,
    label = paste0("source-link violations (file:line kind url): ", paste(
      sprintf("%s:%d %s %s", basename(hits$file), hits$line, hits$kind, hits$url),
      collapse = "; "))
  )
})

test_that("falsification: an invented bare symbol link goes red (markdown + html)", {
  md <- sprintf("See [`hd_hac_sharpe()`](%s/packages/historicaldata/R/falsification.R).", gh)
  r <- scan_source_links_text(md, root)
  expect_equal(nrow(r), 1L)
  expect_identical(r$kind, "bare")

  ht <- sprintf("Source: <a href='%s/R/plan_ecb.R' target='_blank'>hd_ecb_registry()</a>.", gh)
  expect_equal(nrow(scan_source_links_text(ht, root)), 1L)

  # multi-line link text and a backslash-escaped href (as in R strings) still seen
  ml <- sprintf("[`some_\nfn()`](%s/R/plan_ecb.R)", gh)
  expect_equal(nrow(scan_source_links_text(ml, root)), 1L)
  esc <- sprintf("<a href=\\\"%s/R/plan_ecb.R\\\">`fn()`</a>", gh)
  expect_equal(nrow(scan_source_links_text(esc, root)), 1L)
})

test_that("an anchored symbol link and whole-file references are exempt", {
  ok_anchor <- sprintf("[`fn()`](%s/R/plan_qa_gates.R#L1)", gh)
  expect_equal(nrow(scan_source_links_text(ok_anchor, root)), 0L)
  expect_equal(nrow(scan_source_links_text(
    sprintf("[plan_drif.R](%s/R/plan_drif.R)", gh), root)), 0L)
  expect_equal(nrow(scan_source_links_text(
    sprintf("[`R/plan_drif.R`](%s/R/plan_drif.R)", gh), root)), 0L)
  expect_equal(nrow(scan_source_links_text(
    sprintf("[the DRIF plan](%s/R/plan_drif.R)", gh), root)), 0L)
  # an external (non-project) link is out of scope
  expect_equal(nrow(scan_source_links_text(
    "[`fn()`](https://github.com/other/repo/blob/main/R/x.R)", root)), 0L)
})

test_that("falsification: a stale / missing-file anchor goes red", {
  n <- length(readLines(here::here("R/plan_qa_gates.R"), warn = FALSE))
  stale <- sprintf("[plan_qa_gates.R](%s/R/plan_qa_gates.R#L%d)", gh, n + 1000L)
  r <- scan_source_links_text(stale, root)
  expect_identical(r$kind, "stale")
  expect_equal(r$max_line, n)
  at_end <- sprintf("[plan_qa_gates.R](%s/R/plan_qa_gates.R#L%d)", gh, n)
  expect_equal(nrow(scan_source_links_text(at_end, root)), 0L)
  gone <- sprintf("[x.R](%s/R/no_such_file_631.R#L3)", gh)
  r2 <- scan_source_links_text(gone, root)
  expect_true(is.na(r2$max_line))
  expect_identical(r2$kind, "stale")
})

test_that("reported line numbers point at the offending line", {
  txt <- paste0("a\nb\n", sprintf("[`fn()`](%s/R/plan_ecb.R)", gh), "\n")
  expect_identical(scan_source_links_text(txt, root)$line, 3L)
})

test_that("INDETERMINATE (not pass) when no .qmd is found", {
  d <- withr::local_tempdir()
  expect_error(check_no_bare_source_urls(d, root), class = "qa_s47_indeterminate")
})
