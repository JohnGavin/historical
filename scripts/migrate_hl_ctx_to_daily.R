#!/usr/bin/env Rscript
# One-off migration (#1082): split the pre-#1082 single file perp_ctx_5m.parquet
# into the daily layout perp_ctx_5m/date=YYYY-MM-DD/<collector>.parquet that
# scripts/poll_hyperliquid_ctx.R now writes.
#
# Usage: Rscript scripts/migrate_hl_ctx_to_daily.R [--dry-run | --apply]
#          [--legacy=data/dist/perp_ctx_5m.parquet] [--out-dir=data/dist]
#   --collector=LABEL is the collector label the rows get (default: env var
#   HL_POLL_COLLECTOR, else "laptop-1"). The legacy `collector` column holds a host
#   name; every legacy value is replaced by the label (the legacy file was written
#   by one machine), in the daily files only: the legacy file itself is untouched.
#   The host name is never printed, written to a file name or stored by this script.
#   --dry-run (the default) reads the legacy file and prints the plan (rows per
#   daily file, overlaps with daily files that already exist); it writes NOTHING.
#   --apply writes the daily files, then verifies them (below).
#
# The legacy file is NEVER deleted, moved or changed: the owner does that after
# checking the result.
#
# No double counting, no loss (how this is decided):
#   - The reader (hl_ctx_read / hl_ctx_open) looks only at the daily files; it
#     ignores the legacy file. So rows exist once, in the daily layout, as soon as
#     they are migrated; before that they are invisible to the reader.
#   - The poller writes daily files from the moment it is updated, so on the day of
#     the switch a daily file may already hold rows that the legacy file also holds
#     (and, after a second --apply, all of them). Rows are matched on the key
#     (dex, coin, fetched_at): a legacy row whose key is already in the daily file is
#     NOT written again (the daily file's row stays), and the count of such rows is
#     reported. Running --apply twice is therefore harmless.
#
# Verification after --apply (any failure is exit 1, and says what differs):
#   - the key set of every touched daily file equals (keys it held before) union
#     (the legacy keys that belong to it), and has no duplicate key;
#   - every legacy row this run wrote is in its daily file with identical values in
#     every legacy column (a row whose key was already there stays as it was);
#   - the number of legacy rows equals the number of distinct legacy keys.
#
# Exit status: 0 ok (dry run, or applied and verified) | 1 verification failed or the
# legacy file has duplicate keys | 2 usage | 3 INDETERMINATE (legacy file missing or
# unreadable).

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
})

.mig_find_poller <- function() {
  from_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  cands <- character()
  if (length(from_file) > 0L) {
    cands <- c(cands, file.path(dirname(normalizePath(sub("^--file=", "", from_file[1]),
                                                       mustWork = FALSE)),
                                "poll_hyperliquid_ctx.R"))
  }
  cands <- c(cands, file.path("scripts", "poll_hyperliquid_ctx.R"))
  if (requireNamespace("here", quietly = TRUE)) {
    cands <- c(cands, here::here("scripts", "poll_hyperliquid_ctx.R"))
  }
  hit <- cands[file.exists(cands)]
  if (length(hit) == 0L) {
    cli::cli_abort(c("x" = "Cannot locate {.file scripts/poll_hyperliquid_ctx.R}",
                     "i" = "tried: {.file {cands}}"))
  }
  hit[1]
}
# Shared helpers (hl_upsert, hl_ctx_write, hl_ctx_day_path, ...); sourcing runs nothing.
source(.mig_find_poller())

.mig_key <- function(x) paste(x$dex, x$coin, sprintf("%.6f", as.numeric(x$fetched_at)), sep = "\r")

# Returns list(status, applied, n_legacy, plan (data.frame: date, collector, path,
# n_legacy, n_existing, n_overlap, n_new), reason).
hl_ctx_migrate_legacy <- function(legacy, out_dir, apply = FALSE,
                                  collector = hl_ctx_collector(), upsert_fn = hl_upsert) {
  if (!file.exists(legacy)) {
    return(list(status = 3L, applied = FALSE, n_legacy = NA_integer_, plan = NULL,
                reason = sprintf("legacy file not found: %s (already moved?)", legacy)))
  }
  old <- tryCatch(as.data.frame(arrow::read_parquet(legacy)), error = function(e) e)
  if (inherits(old, "error")) {
    return(list(status = 3L, applied = FALSE, n_legacy = NA_integer_, plan = NULL,
                reason = sprintf("legacy file unreadable: %s", conditionMessage(old))))
  }
  need <- c(HL_CTX_KEYS, "collector")
  if (!all(need %in% names(old))) {
    return(list(status = 3L, applied = FALSE, n_legacy = nrow(old), plan = NULL,
                reason = sprintf("legacy file lacks column(s): %s",
                                 paste(setdiff(need, names(old)), collapse = ", "))))
  }
  if (anyDuplicated(old[HL_CTX_KEYS]) > 0L) {
    return(list(status = 1L, applied = FALSE, n_legacy = nrow(old), plan = NULL,
                reason = "legacy file has duplicate (dex, coin, fetched_at) keys"))
  }
  n_legacy_collectors <- length(unique(old$collector))
  old$collector <- collector                   # host name -> configured label
  old$.date <- format(old$fetched_at, "%Y-%m-%d", tz = "UTC")
  old$.path <- hl_ctx_day_path(out_dir, old$.date, old$collector)
  groups <- split(old, old$.path)

  plan <- do.call(rbind, lapply(groups, function(g) {
    path <- g$.path[1]
    existing <- if (file.exists(path)) as.data.frame(arrow::read_parquet(path)) else NULL
    n_overlap <- if (is.null(existing)) 0L else sum(.mig_key(g) %in% .mig_key(existing))
    data.frame(date = g$.date[1], collector = g$collector[1], path = path,
               n_legacy = nrow(g), n_existing = if (is.null(existing)) 0L else nrow(existing),
               n_overlap = n_overlap, n_new = nrow(g) - n_overlap,
               stringsAsFactors = FALSE)
  }))
  rownames(plan) <- NULL
  plan <- plan[order(plan$date, plan$collector), , drop = FALSE]

  if (!apply) {
    return(list(status = 0L, applied = FALSE, n_legacy = nrow(old), plan = plan, reason = "",
                n_legacy_collectors = n_legacy_collectors))
  }

  problems <- character()
  for (g in groups) {
    path <- g$.path[1]
    before <- if (file.exists(path)) as.data.frame(arrow::read_parquet(path)) else NULL
    rows <- g[setdiff(names(g), c(".date", ".path"))]
    fresh <- if (is.null(before)) rows else rows[!(.mig_key(rows) %in% .mig_key(before)), , drop = FALSE]
    upsert_fn(fresh, path, HL_CTX_KEYS)

    after <- as.data.frame(arrow::read_parquet(path))
    want <- union(if (is.null(before)) character() else .mig_key(before), .mig_key(rows))
    got <- .mig_key(after)
    if (anyDuplicated(got) > 0L || !setequal(got, want) || length(got) != length(want)) {
      problems <- c(problems, sprintf("%s: key set differs (%d rows, expected %d)",
                                      path, length(got), length(want)))
      next
    }
    # Values: every row this run wrote, in every legacy column, identical in the daily
    # file. (A legacy row whose key was already there is the daily file's own row, and
    # stays; it is counted as an overlap, not compared.)
    a <- after[match(.mig_key(fresh), got), names(fresh), drop = FALSE]
    same <- all(vapply(names(fresh), function(cn) {
      isTRUE(all.equal(a[[cn]], fresh[[cn]], tolerance = 0, check.attributes = FALSE))
    }, logical(1)))
    if (!same) problems <- c(problems, sprintf("%s: values differ from the legacy rows", path))
  }
  if (length(unique(.mig_key(old))) != nrow(old)) {
    problems <- c(problems, "legacy row count differs from its distinct key count")
  }
  list(status = if (length(problems) == 0L) 0L else 1L, applied = TRUE,
       n_legacy = nrow(old), plan = plan, reason = paste(problems, collapse = "; "),
       n_legacy_collectors = n_legacy_collectors)
}

.migrate_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  flags <- c("--dry-run", "--apply")
  opts <- args[grepl("^--(legacy|out-dir|collector)=.+$", args)]
  bad <- setdiff(args, c(flags, opts))
  if (length(bad) > 0L || all(c("--dry-run", "--apply") %in% args)) {
    message("usage: migrate_hl_ctx_to_daily.R [--dry-run | --apply] [--legacy=FILE] [--out-dir=DIR] [--collector=LABEL]\n",
            if (length(bad) > 0L) paste0("unknown argument(s): ", paste(bad, collapse = " "))
            else "give at most one of --dry-run and --apply")
    return(2L)
  }
  opt <- function(name, default) {
    hit <- grep(paste0("^--", name, "="), opts, value = TRUE)
    if (length(hit) == 0L) default else sub(paste0("^--", name, "="), "", hit[1])
  }
  out_dir <- opt("out-dir", "data/dist")
  legacy <- opt("legacy", file.path(out_dir, HL_CTX_LEGACY_FILE))
  apply <- "--apply" %in% args
  res <- tryCatch(hl_ctx_migrate_legacy(legacy, out_dir, apply = apply,
                                           collector = opt("collector", hl_ctx_collector())),
                  error = function(e) list(status = 3L, applied = FALSE, plan = NULL,
                                           n_legacy = NA_integer_, reason = conditionMessage(e)))
  if (!is.null(res$plan)) {
    cat(sprintf("%s: %d legacy rows -> %d daily file(s)\n",
                if (apply) "APPLY" else "DRY RUN (nothing written)", res$n_legacy, nrow(res$plan)))
    print(res$plan[c("date", "collector", "n_legacy", "n_existing", "n_overlap", "n_new")],
          row.names = FALSE)
    cat(sprintf("legacy collector value(s) mapped to the label: %d\n", res$n_legacy_collectors))
    cat(sprintf("overlap with existing daily files: %d row(s)\n", sum(res$plan$n_overlap)))
  }
  if (nzchar(res$reason)) {
    message(if (res$status == 3L) "INDETERMINATE: " else "FAIL: ", res$reason)
  } else if (apply) {
    cat("verified: key sets and values match; the legacy file is untouched (delete it yourself)\n")
  }
  res$status
}

if (sys.nframe() == 0L) {
  quit(save = "no", status = .migrate_main())
}
