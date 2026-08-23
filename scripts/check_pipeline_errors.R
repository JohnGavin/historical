#!/usr/bin/env Rscript
# scripts/check_pipeline_errors.R — post-build check for errored targets (#680).
#
# scripts/verify.sh validates the docs/_targets.R PIPELINE STRUCTURE
# (parses, tar_validate()) — it never runs a single target body, so it
# cannot catch a runtime failure inside one. PR #678 (a cli_abort() inside
# ltr_portfolio, rf coverage) and PR #683 (the same class, stk_rf scoped to
# one consumer's window) both passed every check in verify.sh and still
# errored at build. This script is the companion check that closes that
# gap — but it needs a REAL store to inspect, so it is deliberately NOT part
# of verify.sh and must be run separately, after a real tar_make(), in the
# main checkout. A worktree normally has no store, and must not build one
# that could race the main checkout's store (see .claude/CLAUDE.md).
#
# docs/_targets.R sets `error = "continue"` project-wide, so tar_make()
# itself exits 0 even when targets errored, and tar_read() then silently
# serves the LAST GOOD value for anything that errored. Neither the
# tar_make() exit code nor a routine tar_read() call will tell you a target
# broke — tar_meta(fields = error) is the only reliable signal, and that is
# what this script inspects.
#
# What this script does NOT cover: docs/*.qmd chunks that call tar_read()
# for a target name that no longer exists fail only at RENDER time, not
# here — tar_meta() has no opinion about a chunk that references a target
# that was simply never asked to build. That gap needs an actual quarto
# render pass; nothing in this repo automates it yet (#680).
#
# Usage (from anywhere inside the repo, after a real docs/ build):
#   nix develop --command Rscript -e 'targets::tar_make()'   # from docs/, or
#   nix develop --command Rscript -e \
#     'targets::tar_make(script = "docs/_targets.R", store = "docs/_targets")'
#   nix develop --command Rscript scripts/check_pipeline_errors.R
#
# Exit codes:
#   0  no errored targets
#   1  one or more targets have a non-NA error in tar_meta()
#   2  could not run the check at all (no store, tar_meta() failed, a
#      truncated/malformed meta file, etc.) — this is NOT a pass, never
#      treat it as one
#
# #730: tar_meta() reads the store's meta file with data.table::fread(),
# which on a malformed line (e.g. two writers interleaving a record —
# exactly what happens when two tar_make() runs race one store) does not
# error. It emits a WARNING ("Stopped early on line N. Expected M fields
# but found K.") and silently returns however many rows it managed to
# parse before the bad line. Nothing about that return value distinguishes
# "the pipeline genuinely has fewer targets" from "the read was truncated"
# — both look like a data frame with fewer rows than expected, and the
# `errored <- meta[!is.na(meta$error), ]` line below finds no error among
# the rows it WAS given. The result, observed in #730: tar_make() printed
# "errored pipeline", this script read a truncated 762-row view containing
# neither the errored target nor several others, and printed
# "PASS: no errored targets". A null-ish state (rows that failed to parse)
# was indistinguishable from a legitimate absence (targets that didn't
# error) — see .claude/rules/fail-loud-not-null.md. The withCallingHandlers()
# below promotes any fread warning matching "Stopped early" or "fill=" (the
# two data.table warning families for a truncated/ragged read) to a fatal
# error, so a malformed meta file aborts with exit 2 ("could not run the
# check at all") instead of silently passing on a partial view.

suppressPackageStartupMessages({
  library(targets)
  library(here)
})

# .cpe_read_meta() (#730) -- reads tar_meta(fields = error, targets_only =
# TRUE) from `store_path`, promoting a data.table::fread() truncation
# warning to a fatal error rather than letting a partial parse pass
# silently as a valid (if smaller) result. Errors (native tar_meta() errors,
# or this promoted truncation error) are NOT caught here -- that is the
# caller's job (.cpe_main(), below), the same split .cdf_main()/tar_meta()
# uses in scripts/check_dashboard_freshness.R.
#
# The warning handler below deliberately RECORDS the match and calls
# invokeRestart("muffleWarning") to let fread()'s C-level read finish
# normally, and only raises stop() AFTER withCallingHandlers() returns --
# NOT from inside the handler itself. Raising stop() from inside a warning
# handler unwinds the R call stack via a longjmp through fread()'s C code
# before its own internal cleanup runs, which empirically (while writing
# this file's tests) produced a real, intermittent knock-on failure on the
# NEXT fread() call in the same R session ("Previous fread() session was
# not cleaned up properly" followed by "Couldn't open file ... No such
# file or directory" building an unrelated store moments later). Recording
# then raising afterward avoids interrupting fread() mid-read altogether.
# Pattern-matched on the two data.table warning families that indicate a
# short/ragged read ("Stopped early on line N..." and the "fill=TRUE"
# suggestion fread appends to the same class of warning) -- never on the
# row count, since a short count alone cannot be told apart from a
# legitimately smaller pipeline.
.cpe_read_meta <- function(store_path) {
  truncation_warning <- NULL
  meta <- withCallingHandlers(
    targets::tar_meta(store = store_path, fields = error, targets_only = TRUE),
    warning = function(w) {
      msg <- conditionMessage(w)
      if (grepl("Stopped early|fill=", msg)) {
        truncation_warning <<- msg
        invokeRestart("muffleWarning")
      }
    }
  )
  if (!is.null(truncation_warning)) {
    stop(
      "tar_meta() emitted a data.table::fread() truncation warning while ",
      "reading the store's meta file -- the rows fread() DID manage to ",
      "parse are an INCOMPLETE view of the store, not a complete one with ",
      "fewer targets (#730). Treating this as fatal rather than silently ",
      "passing on a partial read. Original warning: ", truncation_warning,
      call. = FALSE
    )
  }
  meta
}

# .cpe_main() -- orchestrates the check against `store_path`, printing the
# same report this script has always printed, and RETURNING (not
# quit()-ing) an exit-status integer, so it is testable without
# terminating the R session (mirrors .cdf_main() in
# scripts/check_dashboard_freshness.R). The Rscript entry point at the
# bottom of this file calls quit(status = ...) using this return value.
#
# NOT `complete_only = TRUE` (#693). tar_meta()'s own source
# (targets::tar_meta, confirmed against the installed package version in
# this nix shell) does:
#   out <- out[, base::union("name", fields), drop = FALSE]
#   if (complete_only) out <- out[stats::complete.cases(out), , drop = FALSE]
# With `fields = error`, `out` has exactly two columns: name, error.
# `complete.cases()` on that requires BOTH non-NA -- so `complete_only =
# TRUE` silently keeps only the rows whose `error` is NOT NA, i.e. it
# returns the ERRORED set *before* the `errored <- meta[!is.na(meta$error),
# ]` line below even runs. That line was therefore a no-op on the already-
# filtered result, and `nrow(meta)` -- printed as "Complete targets
# checked" -- was actually the errored count, not the inspected count: on
# a clean pipeline it printed 0, one line above "PASS: no errored targets",
# reading as "nothing was inspected" rather than "nothing was wrong". This
# is precisely the "green means nothing changed" failure this script
# exists to prevent (.claude/rules/fail-loud-not-null.md). `targets_only =
# TRUE` is added for the same reason `tar_meta()`'s default
# `targets_only = FALSE` also returns metadata rows for functions and
# other global objects, not just targets -- without it, the count would
# never have meant "targets" even after fixing complete_only.
.cpe_main <- function(store_path = here::here("docs", "_targets")) {
  if (!dir.exists(store_path)) {
    message("!!! No targets store found at '", store_path, "' !!!")
    message("!!! This script only READS an existing store -- run tar_make() first. !!!")
    message("!!! VERIFICATION DID NOT RUN. This is NOT a pass.                      !!!")
    return(2L)
  }

  meta <- tryCatch(
    .cpe_read_meta(store_path),
    error = function(e) {
      message("!!! tar_meta() failed: ", conditionMessage(e), " !!!")
      NULL
    }
  )

  if (is.null(meta)) {
    message("!!! VERIFICATION DID NOT RUN. This is NOT a pass. !!!")
    return(2L)
  }

  errored <- meta[!is.na(meta$error), , drop = FALSE]

  cat(sprintf("Store: %s\n", store_path))
  cat(sprintf("Targets inspected: %d\n", nrow(meta)))
  cat(sprintf("Targets errored:   %d\n", nrow(errored)))

  if (nrow(errored) == 0) {
    cat("PASS: no errored targets\n")
    return(0L)
  }

  cat(sprintf("FAIL: %d errored target(s):\n", nrow(errored)))
  for (i in seq_len(nrow(errored))) {
    cat(sprintf("  [ERROR] %s -- %s\n", errored$name[i], errored$error[i]))
  }
  return(1L)
}

# Only run when this file is the Rscript entry point (sys.nframe() == 0),
# never when source()'d for its functions -- same pattern (and same
# empirical basis) as scripts/check_dashboard_freshness.R:
# `Rscript file.R` gives sys.nframe() == 0 at top level; `source("file.R")`
# gives sys.nframe() > 0 (source() itself adds a frame).
# tests/testthat/test-check-pipeline-errors.R source()s this file and must
# NOT trigger a live run against the real store.
if (sys.nframe() == 0) {
  status <- .cpe_main()
  quit(status = status, save = "no")
}
