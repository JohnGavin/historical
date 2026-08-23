testthat::local_edition(3)
source(here::here("scripts", "check_pipeline_errors.R"))

# Regression tests for scripts/check_pipeline_errors.R (#680, #730).
#
# scripts/check_pipeline_errors.R defines its logic as `.cpe_*` functions and
# only RUNS the check (calling quit()) when it is the Rscript entry point
# (sys.nframe() == 0 at its own top level -- see that file's final block).
# source()'ing it here (sys.nframe() > 0) loads the functions without
# triggering a live run against the real repo's docs/_targets store, exactly
# the pattern test-dashboard-freshness.R uses for check_dashboard_freshness.R.
#
# These tests build REAL, throwaway targets stores under withr::local_tempdir()
# -- never the real docs/_targets store (see .claude/CLAUDE.md and the
# worktree-location rule: a worktree must not build or touch the main
# checkout's store).
#
# #730 regression -- the empirical finding that shaped .make_toy_store()'s
# default size: the real incident's meta file (~772 targets) triggered
# data.table::fread()'s "Stopped early" warning when two tar_make() runs
# interleaved a write to it. A SMALL corrupted store does NOT reliably
# reproduce that warning -- confirmed empirically while writing this test
# (8, 60, and 150-target stores all silently absorbed an identical
# double-the-line-onto-itself corruption with ZERO warning, via
# data.table::fread()'s `fill = TRUE` -- which targets::tar_meta() always
# passes -- padding/merging the ragged row instead of stopping). Only at
# ~300 targets does fread's warning reliably fire:
# "Stopped early on line 153. Expected 18 fields but found 35." -- the exact
# field counts (18 expected, 35 found) reported in #730 itself, which is
# strong independent confirmation this corruption method matches the real
# incident (two writers interleaving one target's record). Tests that need
# the warning to fire use n_targets = 300L for this reason; tests that don't
# (clean PASS / FAIL paths) use a small store to stay fast.

.make_toy_store <- function(dir, n_targets = 5L, with_error_target = TRUE) {
  script_path <- file.path(dir, "_targets.R")
  store_path <- file.path(dir, "_targets")
  defs <- sprintf("targets::tar_target(t%d, %d + 1)", seq_len(n_targets), seq_len(n_targets))
  if (with_error_target) {
    defs <- c(defs, 'targets::tar_target(bad, stop("deliberate test error"))')
  }
  writeLines(c(
    'targets::tar_option_set(error = "continue")', # matches docs/_targets.R's real setting
    "list(",
    paste0("  ", defs, collapse = ",\n"),
    ")"
  ), script_path)
  targets::tar_make(
    script = script_path, store = store_path,
    callr_function = NULL, reporter = "silent"
  )
  store_path
}

# Corrupts one line roughly in the MIDDLE of the meta file by duplicating it
# onto itself -- mimics two writers interleaving a record for the SAME
# target, exactly as #730 describes ("the leaderboard record written twice,
# concatenated"). A middle line matters: corrupting the LAST line does not
# reproduce the warning (confirmed empirically), only a line fread reaches
# mid-file, after it has already locked in an expected column count from
# earlier rows.
.corrupt_meta_middle_line <- function(store_path) {
  meta_path <- file.path(store_path, "meta", "meta")
  lines <- readLines(meta_path)
  mid_idx <- as.integer(floor(length(lines) / 2))
  stopifnot(mid_idx > 1L, mid_idx < length(lines))
  lines[mid_idx] <- paste0(lines[mid_idx], lines[mid_idx])
  writeLines(lines, meta_path)
  invisible(meta_path)
}

# ── .cpe_main() -- store-existence / clean / errored paths ─────────────────

test_that(".cpe_main returns 2 and reports when no store directory exists", {
  dir <- withr::local_tempdir()
  missing_store <- file.path(dir, "does_not_exist")
  status <- NA_integer_
  msgs <- character(0)
  withCallingHandlers(
    status <- .cpe_main(store_path = missing_store),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_equal(status, 2L)
  expect_true(any(grepl("No targets store found", msgs)))
  expect_true(any(grepl("VERIFICATION DID NOT RUN", msgs)))
})

test_that(".cpe_main returns 0 and reports PASS on a clean store with no errored targets", {
  dir <- withr::local_tempdir()
  store <- .make_toy_store(dir, n_targets = 5L, with_error_target = FALSE)
  status <- NA_integer_
  out <- utils::capture.output(status <- .cpe_main(store_path = store))
  expect_equal(status, 0L)
  txt <- paste(out, collapse = "\n")
  expect_match(txt, "Targets inspected: 5")
  expect_match(txt, "Targets errored:   0")
  expect_match(txt, "PASS: no errored targets")
})

test_that(".cpe_main returns 1 and reports the errored target's name and message", {
  dir <- withr::local_tempdir()
  store <- .make_toy_store(dir, n_targets = 5L, with_error_target = TRUE)
  status <- NA_integer_
  out <- utils::capture.output(status <- .cpe_main(store_path = store))
  expect_equal(status, 1L)
  txt <- paste(out, collapse = "\n")
  expect_match(txt, "Targets inspected: 6")
  expect_match(txt, "FAIL: 1 errored target")
  expect_match(txt, "\\[ERROR\\] bad -- deliberate test error")
})

# ── #730: the corrupted-meta-file regression this issue is actually about ──

test_that(".cpe_read_meta() does NOT misfire on a large but uncorrupted store", {
  dir <- withr::local_tempdir()
  store <- .make_toy_store(dir, n_targets = 300L, with_error_target = FALSE)
  meta <- expect_no_warning(.cpe_read_meta(store))
  expect_equal(nrow(meta), 300L)
})

test_that(".cpe_read_meta() promotes a data.table::fread truncation warning to a fatal error naming #730 (#730)", {
  dir <- withr::local_tempdir()
  store <- .make_toy_store(dir, n_targets = 300L, with_error_target = FALSE)
  .corrupt_meta_middle_line(store)
  # A single call captured once, not re-invoked per assertion: calling
  # .cpe_read_meta()/tar_meta() twice in a row against the same store inside
  # one test hit an unrelated data.table::fread() internal-session error
  # ("Couldn't open file ... No such file or directory", confirmed empirically
  # while writing this test) -- an artefact of repeated fread() calls, not a
  # #730 concern. One call + one captured condition avoids it.
  cond <- tryCatch(.cpe_read_meta(store), error = function(e) e)
  expect_s3_class(cond, "error")
  msg <- conditionMessage(cond)
  expect_match(msg, "truncation warning")
  expect_match(msg, "#730")
  expect_match(msg, "INCOMPLETE view")
})

test_that("BEFORE this fix's mechanism, a corrupted meta file silently returns a truncated frame with no signal at all (documents the exact bug #730 reports)", {
  # This test calls targets::tar_meta() directly -- NOT .cpe_read_meta() --
  # to document the underlying fail-open behaviour #730 is about: fread()'s
  # warning is silently discardable, and the truncated row count alone
  # cannot be told apart from "the pipeline genuinely has fewer targets"
  # (.claude/rules/fail-loud-not-null.md). This is why #730 proposal 1
  # cannot be "check the row count" -- it must intercept the WARNING itself.
  dir <- withr::local_tempdir()
  store <- .make_toy_store(dir, n_targets = 300L, with_error_target = FALSE)
  .corrupt_meta_middle_line(store)
  raw <- suppressWarnings(
    targets::tar_meta(store = store, fields = error, targets_only = TRUE)
  )
  expect_lt(nrow(raw), 300L) # truncated -- the read silently lost rows
  expect_true(all(is.na(raw$error))) # and reports zero errors among what it DID read
})

test_that(".cpe_main() returns 2 -- NOT a false PASS -- when the meta file is corrupted by two interleaved writers (#730)", {
  # The end-to-end regression: BEFORE this fix, this exact scenario made the
  # top-level script print \"PASS: no errored targets\" on a truncated read
  # (see #730's incident table). AFTER, .cpe_main() must return 2
  # (\"could not run the check at all\") and say why -- never 0.
  dir <- withr::local_tempdir()
  store <- .make_toy_store(dir, n_targets = 300L, with_error_target = FALSE)
  .corrupt_meta_middle_line(store)
  status <- NA_integer_
  msgs <- character(0)
  withCallingHandlers(
    utils::capture.output(status <- .cpe_main(store_path = store)),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_equal(status, 2L)
  expect_false(identical(status, 0L)) # the exact false-PASS #730 reports must not recur
  all_msgs <- paste(msgs, collapse = "\n")
  expect_match(all_msgs, "tar_meta\\(\\) failed")
  expect_match(all_msgs, "#730")
  expect_match(all_msgs, "VERIFICATION DID NOT RUN")
})

# ── Function signature stability (catches API drift, snapshot-test-policy.md) ──

test_that("key .cpe_* function signatures are stable", {
  expect_snapshot(args(.cpe_read_meta))
  expect_snapshot(args(.cpe_main))
})
