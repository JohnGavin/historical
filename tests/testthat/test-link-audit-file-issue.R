testthat::local_edition(3)

# Tests for scripts/link_audit_file_issue.sh using a stub `gh`.
# The stub logs every call to $STUB_LOG; `issue list` prints $STUB_LIST_OUT
# and exits $STUB_LIST_RC. No real GitHub call is made.

find_script <- function() {
  cands <- c(
    file.path("..", "..", "scripts", "link_audit_file_issue.sh"),
    file.path("scripts", "link_audit_file_issue.sh")
  )
  hit <- cands[file.exists(cands)]
  if (length(hit) == 0) testthat::skip("link_audit_file_issue.sh not found")
  normalizePath(hit[[1]])
}

run_case <- function(list_out = "", list_rc = 0, report = "report line\n",
                     make_report = TRUE) {
  script <- find_script()
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  log <- file.path(dir, "calls.log")
  stub <- file.path(dir, "gh")
  writeLines(c(
    "#!/usr/bin/env bash",
    "echo \"$*\" >> \"$STUB_LOG\"",
    "if [ \"$1 $2\" = \"issue list\" ]; then",
    "  [ -n \"$STUB_LIST_OUT\" ] && echo \"$STUB_LIST_OUT\"",
    "  exit \"$STUB_LIST_RC\"",
    "fi",
    "# capture body file content for comment/create",
    "prev=''; for a in \"$@\"; do",
    "  if [ \"$prev\" = '--body-file' ]; then cat \"$a\" > \"$STUB_LOG.body\"; fi",
    "  prev=\"$a\"; done",
    "exit 0"
  ), stub)
  Sys.chmod(stub, "0755")
  rpt <- file.path(dir, "lychee-out.md")
  if (make_report) {
    cat(report, file = rpt)
  }
  out <- suppressWarnings(system2(
    "bash", c(script, rpt),
    env = c(
      paste0("GH=", stub), paste0("STUB_LOG=", log),
      paste0("STUB_LIST_OUT=", list_out), paste0("STUB_LIST_RC=", list_rc)
    ),
    stdout = TRUE, stderr = TRUE
  ))
  status <- attr(out, "status")
  if (is.null(status)) status <- 0L
  calls <- if (file.exists(log)) readLines(log) else character()
  body <- if (file.exists(paste0(log, ".body"))) {
    paste(readLines(paste0(log, ".body"), warn = FALSE), collapse = "\n")
  } else {
    ""
  }
  list(status = status, calls = calls, out = out, body = body)
}

test_that("existing open issue -> comment, no create", {
  r <- run_case(list_out = "995")
  expect_equal(r$status, 0L)
  expect_true(any(grepl("^issue comment 995 ", r$calls)))
  expect_false(any(grepl("^issue create", r$calls)))
})

test_that("no open issue -> exactly one create with title and labels", {
  r <- run_case(list_out = "")
  expect_equal(r$status, 0L)
  creates <- grep("^issue create", r$calls, value = TRUE)
  expect_length(creates, 1)
  expect_match(creates, "link-audit: broken links detected on Pages site",
               fixed = TRUE)
  expect_match(creates, "--label bug,deploy,link-audit", fixed = TRUE)
  expect_false(any(grepl("^issue comment", r$calls)))
})

test_that("list failure -> non-zero, message, no create", {
  r <- run_case(list_rc = 1)
  expect_false(r$status == 0L)
  expect_true(any(grepl("could not tell whether", r$out)))
  expect_false(any(grepl("^issue create", r$calls)))
  expect_false(any(grepl("^issue comment", r$calls)))
})

test_that("missing report -> non-zero, gh never called", {
  r <- run_case(make_report = FALSE)
  expect_false(r$status == 0L)
  expect_length(r$calls, 0)
})

test_that("empty report -> non-zero", {
  r <- run_case(report = "")
  expect_false(r$status == 0L)
})

test_that("oversize report is truncated with an explicit note", {
  big <- paste0(strrep("x", 70000), "\n")
  r <- run_case(list_out = "995", report = big)
  expect_equal(r$status, 0L)
  expect_match(r$body, "[truncated]", fixed = TRUE)
  expect_lt(nchar(r$body), 61000)
})

test_that("small report is passed through without a truncation note", {
  r <- run_case(list_out = "995", report = "tiny\n")
  expect_false(grepl("[truncated]", r$body, fixed = TRUE))
  expect_match(r$body, "tiny", fixed = TRUE)
})
