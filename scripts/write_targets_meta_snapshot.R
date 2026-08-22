#!/usr/bin/env Rscript
# scripts/write_targets_meta_snapshot.R — writes docs/_targets_meta_snapshot.csv
# (#695 Check 3 CI gap).
#
# Companion writer to scripts/check_dashboard_freshness.R's Check 3 fallback
# reader (.cdf_read_meta_snapshot() there). See that file's "Metadata
# snapshot" section header comment for the full file-format and
# snapshot-age-as-a-hard-failure design; this script is deliberately thin --
# it sources check_dashboard_freshness.R for the shared constants/helpers
# (.cdf_meta_snapshot_path(), .cdf_write_meta_snapshot()) rather than
# duplicating the CSV format here, so the writer and the reader can never
# drift out of sync with each other.
#
# CALLER CONTRACT -- this script does NOT re-verify build cleanliness itself.
# scripts/build.sh is the only caller and gates the call: it only invokes
# this script when BOTH tar_make() (Step 1) and scripts/check_pipeline_errors.R
# (Step 2) are clean. A snapshot written from a store with errored targets
# would encode wrong build times for whatever failed -- see build.sh's own
# comment at the call site for the exact gate.
#
# MAIN CHECKOUT ONLY, same reasoning as scripts/check_pipeline_errors.R and
# scripts/check_dashboard_freshness.R --data-staleness: it reads a real
# docs/_targets store, and a worktree must never build (or read) a store
# that could race the main checkout's (see .claude/CLAUDE.md).
#
# This script does NOT commit or push the file it writes -- same discipline
# as scripts/build.sh --render (see that script's header): the snapshot is
# left in the working tree for a human to review and commit. Committing a
# build artifact automatically would remove the one signal (a human decided
# this snapshot is worth publishing) that currently also gates --render.
#
# Usage:
#   nix develop --command Rscript scripts/write_targets_meta_snapshot.R
#
# Exit codes:
#   0  wrote docs/_targets_meta_snapshot.csv from the live store
#   1  could not write the snapshot: no store, tar_meta() failed, or the
#      write itself failed (e.g. a real target literally named
#      "__generated_at__" -- see check_dashboard_freshness.R). NOT a pass.

suppressPackageStartupMessages({
  library(here)
})

source(here::here("scripts", "check_dashboard_freshness.R"))

repo_root <- here::here()
store_path <- file.path(repo_root, "docs", "_targets")
snapshot_path <- .cdf_meta_snapshot_path(repo_root)

cat("=== scripts/write_targets_meta_snapshot.R ===\n")
cat(sprintf("Store:    %s\n", store_path))
cat(sprintf("Snapshot: %s\n", snapshot_path))
cat("\n")

if (!dir.exists(store_path)) {
  cat(sprintf("!!! No targets store found at '%s' !!!\n", store_path))
  cat("!!! This script only READS an existing store -- run tar_make() first (scripts/build.sh Step 1). !!!\n")
  cat("!!! SNAPSHOT NOT WRITTEN. This is NOT a pass. !!!\n")
  quit(status = 1, save = "no")
}

meta <- tryCatch(
  targets::tar_meta(store = store_path, fields = time, targets_only = TRUE),
  error = function(e) {
    cat("!!! targets::tar_meta() failed -- cannot write the snapshot. !!!\n")
    cat(rlang::cnd_message(e), "\n")
    NULL
  }
)
if (is.null(meta)) {
  cat("!!! SNAPSHOT NOT WRITTEN. This is NOT a pass. !!!\n")
  quit(status = 1, save = "no")
}

meta_time <- stats::setNames(meta$time, meta$name)

result <- tryCatch(
  {
    .cdf_write_meta_snapshot(meta_time, snapshot_path, generated_at = Sys.time())
    TRUE
  },
  error = function(e) {
    cat("!!! Failed to write the metadata snapshot. !!!\n")
    cat(rlang::cnd_message(e), "\n")
    FALSE
  }
)

if (!isTRUE(result)) {
  cat("!!! SNAPSHOT NOT WRITTEN. This is NOT a pass. !!!\n")
  quit(status = 1, save = "no")
}

cat(sprintf("PASS: wrote %d target time(s) + 1 generated_at row to %s\n", length(meta_time), snapshot_path))
cat("Nothing was committed or pushed -- review the file and commit it yourself if it looks right.\n")
quit(status = 0, save = "no")
