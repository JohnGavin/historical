#!/usr/bin/env Rscript
# scripts/dedupe_research_log_2026-09.R
#
# One-off, reviewable dedupe of the research-log store (issue #860).
#
# hd_rlog_uuid() used to draw from base R's seeded RNG, which is
# deterministic under `targets`' per-target seed -- every rebuild of the
# OLMAR research-log target (R/plan_olmar.R) re-emitted the SAME uuids,
# producing duplicate rows across all 5 tables. #860's own fix makes
# hd_rlog_uuid() seed-independent going forward; this script is the
# one-off cleanup of the 7 rows that were ALREADY duplicated before that
# fix landed. KEEP THIS SCRIPT -- it is the audit record of the cleanup,
# not a throwaway.
#
# For each duplicate uuid (2+ rows sharing the same uuid within a table):
#   - the row with the EARLIEST timestamp is always KEPT unchanged.
#   - a later row whose content is IDENTICAL to the kept row (ignoring
#     auto-generated per-run metadata: timestamp, git_commit,
#     sandbox_image_hash, results_db_run_date) is a pure re-emission and
#     is DROPPED -- it adds no information.
#   - a later row whose content DIFFERS is NOT a pure duplicate -- it is a
#     genuinely different computation that happened to collide on uuid
#     because of the bug. Silently dropping it would destroy real data
#     (see .claude/rules/research-log-honesty.md and .claude/rules/
#     fail-loud-not-null.md). It is instead REKEYED: assigned a fresh,
#     now-collision-safe uuid via the FIXED hd_rlog_uuid(), with every
#     other field (including parent_uuid, timestamp, git_commit) left
#     untouched. This was discovered empirically while writing this
#     script: robustness uuid ab37de2c (Testing panel, parent 160f3b06)
#     carries sharpe=0.802 in the 2026-05-23 occurrence and sharpe=0.553
#     in the 2026-06-16 occurrence -- a real difference, not noise.
#
# Usage:
#   Rscript scripts/dedupe_research_log_2026-09.R           # dry-run (default)
#   Rscript scripts/dedupe_research_log_2026-09.R --apply    # write changes
#
# Dry-run prints the full summary table and makes NO filesystem changes.
# --apply performs the DROP/REKEY actions and rewrites the affected
# parquet files, then re-prints the summary with the actions actually
# taken. Run from the repo root inside the project's nix shell:
#   nix develop --command Rscript scripts/dedupe_research_log_2026-09.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

args <- commandArgs(trailingOnly = TRUE)
apply_changes <- "--apply" %in% args

suppressPackageStartupMessages(library(pkgload))
load_all("packages/historicaldata", quiet = TRUE)

base_dir <- hd_rlog_path()
tables <- hd_rlog_tables()

AUTO_GEN_COLS <- c("timestamp", "git_commit", "sandbox_image_hash", "results_db_run_date")

read_table_with_files <- function(tbl) {
  table_dir <- file.path(base_dir, tbl)
  files <- list.files(table_dir, pattern = "\\.parquet$", full.names = TRUE)
  purrr::map_dfr(files, function(f) {
    d <- read_parquet(f)
    d$.__file <- f
    d$.__row_in_file <- seq_len(nrow(d))
    d
  })
}

rows_equal_ignoring_autogen <- function(row_a, row_b) {
  cols <- setdiff(names(row_a), c(AUTO_GEN_COLS, ".__file", ".__row_in_file"))
  identical(as.list(row_a[, cols, drop = FALSE]), as.list(row_b[, cols, drop = FALSE]))
}

action_rows <- list()

for (tbl in tables) {
  d <- read_table_with_files(tbl)
  if (nrow(d) == 0L) next
  dupe_uuids <- unique(d$uuid[duplicated(d$uuid)])
  if (length(dupe_uuids) == 0L) next

  for (u in dupe_uuids) {
    grp <- d[d$uuid == u, ]
    grp <- grp[order(grp$timestamp), ]
    kept <- grp[1L, ]
    action_rows[[length(action_rows) + 1L]] <- tibble::tibble(
      table = tbl, file = kept$.__file, row_in_file = kept$.__row_in_file,
      uuid = u, timestamp = as.character(kept$timestamp),
      git_commit = kept$git_commit, action = "KEEP (first occurrence)",
      new_uuid = NA_character_
    )
    for (i in seq(2L, nrow(grp))) {
      cand <- grp[i, ]
      is_dup <- rows_equal_ignoring_autogen(kept, cand)
      action <- if (is_dup) "DROP" else "REKEY"
      new_uuid <- if (action == "REKEY") hd_rlog_uuid() else NA_character_
      action_rows[[length(action_rows) + 1L]] <- tibble::tibble(
        table = tbl, file = cand$.__file, row_in_file = cand$.__row_in_file,
        uuid = u, timestamp = as.character(cand$timestamp),
        git_commit = cand$git_commit, action = action, new_uuid = new_uuid
      )
    }
  }
}

action_df <- if (length(action_rows) > 0L) dplyr::bind_rows(action_rows) else tibble::tibble()

cat("\n=== research-log dedupe summary (issue #860) ===\n")
if (nrow(action_df) == 0L) {
  cat("No duplicate uuids found. Nothing to do.\n")
} else {
  print_df <- action_df
  print_df$file <- basename(print_df$file)
  print(as.data.frame(print_df[, c("table", "uuid", "timestamp", "git_commit", "file", "action", "new_uuid")]))
  n_drop  <- sum(action_df$action == "DROP")
  n_rekey <- sum(action_df$action == "REKEY")
  n_keep  <- sum(action_df$action == "KEEP (first occurrence)")
  cat(sprintf("\nTotals: %d kept (first occurrence), %d dropped (pure duplicates), %d rekeyed (differing content)\n",
              n_keep, n_drop, n_rekey))
  if (n_rekey > 0L) {
    cat("\nNOTE: REKEY rows had content differing from the first occurrence beyond\n")
    cat("auto-generated metadata (timestamp/git_commit/sandbox_image_hash/results_db_run_date).\n")
    cat("These are genuinely distinct data points that collided on uuid due to #860's\n")
    cat("bug -- they are re-keyed with a fresh (now-fixed) uuid, never dropped.\n")
  }
}

if (!apply_changes) {
  cat("\nDRY RUN -- no files were changed. Re-run with --apply to write changes.\n")
} else if (nrow(action_df) > 0L) {
  cat("\nAPPLYING changes...\n")
  # Only touch files that have at least one DROP or REKEY action -- a file
  # whose only action rows are KEEP (first occurrence) must NOT be
  # rewritten: re-serialising parquet changes file bytes (footer metadata)
  # even when every row value is unchanged, which would show up as a
  # spurious modification in the PR diff for a file nothing happened to.
  affected_files <- unique(action_df$file[action_df$action %in% c("DROP", "REKEY")])
  for (f in affected_files) {
    d <- read_parquet(f)
    f_actions <- action_df[action_df$file == f, ]
    drop_rows <- f_actions$row_in_file[f_actions$action == "DROP"]
    rekey_actions <- f_actions[f_actions$action == "REKEY", ]
    if (nrow(rekey_actions) > 0L) {
      for (i in seq_len(nrow(rekey_actions))) {
        ridx <- rekey_actions$row_in_file[i]
        d$uuid[ridx] <- rekey_actions$new_uuid[i]
      }
    }
    if (length(drop_rows) > 0L) {
      d <- d[-drop_rows, , drop = FALSE]
    }
    if (nrow(d) == 0L) {
      file.remove(f)
      cat("  deleted (all rows were pure duplicates):", basename(f), "\n")
    } else {
      # If a REKEY changed the file's first-row uuid, rename the file to
      # match hd_rlog_append()'s own <first-uuid>_<timestamp>.parquet
      # convention -- otherwise the filename would keep pointing at a
      # uuid no longer present in the file, confusing future audits.
      ts_suffix <- sub("^[^_]+_", "", basename(f))
      new_first_uuid <- d$uuid[1L]
      new_path <- file.path(dirname(f), paste0(new_first_uuid, "_", ts_suffix))
      arrow::write_parquet(d, new_path, compression = "zstd")
      if (!identical(new_path, f)) {
        file.remove(f)
        cat("  rewrote + renamed (", nrow(d), " row(s) remaining): ",
            basename(f), " -> ", basename(new_path), "\n", sep = "")
      } else {
        cat("  rewrote (", nrow(d), " row(s) remaining):", basename(f), "\n", sep = "")
      }
    }
  }
  cat("\nDone. Re-run without --apply on the result to confirm 0 duplicate uuids remain.\n")
}

