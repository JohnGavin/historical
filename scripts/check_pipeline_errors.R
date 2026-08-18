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
#   2  could not run the check at all (no store, tar_meta() failed, etc.) —
#      this is NOT a pass, never treat it as one

suppressPackageStartupMessages({
  library(targets)
  library(here)
})

store_path <- here::here("docs", "_targets")

if (!dir.exists(store_path)) {
  message("!!! No targets store found at '", store_path, "' !!!")
  message("!!! This script only READS an existing store -- run tar_make() first. !!!")
  message("!!! VERIFICATION DID NOT RUN. This is NOT a pass.                      !!!")
  quit(status = 2, save = "no")
}

meta <- tryCatch(
  targets::tar_meta(store = store_path, fields = error, complete_only = TRUE),
  error = function(e) {
    message("!!! tar_meta() failed: ", conditionMessage(e), " !!!")
    NULL
  }
)

if (is.null(meta)) {
  message("!!! VERIFICATION DID NOT RUN. This is NOT a pass. !!!")
  quit(status = 2, save = "no")
}

errored <- meta[!is.na(meta$error), , drop = FALSE]

cat(sprintf("Store: %s\n", store_path))
cat(sprintf("Complete targets checked: %d\n", nrow(meta)))

if (nrow(errored) == 0) {
  cat("PASS: no errored targets\n")
  quit(status = 0, save = "no")
}

cat(sprintf("FAIL: %d errored target(s):\n", nrow(errored)))
for (i in seq_len(nrow(errored))) {
  cat(sprintf("  [ERROR] %s -- %s\n", errored$name[i], errored$error[i]))
}
quit(status = 1, save = "no")
