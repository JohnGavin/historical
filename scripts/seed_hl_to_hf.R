#!/usr/bin/env Rscript
# One-off seed: the laptop's Hyperliquid history -> the public Hugging Face dataset (#1088)
#
# WHAT THIS IS
#   The weekly workflow (.github/workflows/hl-weekly.yml) starts from the tables on Hugging
#   Face and refuses to run until this script has been applied once. Run it ONCE, by the
#   owner, from the machine that holds the history, with --apply.
#
#   DRY RUN IS THE DEFAULT: nothing is uploaded, and nothing is written outside a temporary
#   folder. It prints, per table, the local rows, the Hugging Face rows, the merged rows and
#   the earliest date, per raw day the file count and packed size, the total upload size and
#   the number of commits. Read it, then re-run with --apply.
#
#   It never overwrites: for every table it downloads the Hugging Face copy (if there is
#   one), takes the UNION with the local copy on the table's key (local rows win a clash),
#   and refuses to publish unless the guard of scripts/hl_history_guard.R passes against BOTH
#   inputs (rows not fewer, earliest date not later, every old key still there).
#
#   Raw replies: each UTC day folder of --raw-dir is packed into ONE tar of individually
#   gzipped members, hyperliquid/raw/weekly/date=<day>/seed.tar (Hugging Face allows under
#   10,000 files per folder; a day holds about 10,000). A day whose seed.tar is already on
#   Hugging Face is NOT overwritten and is reported as skipped. ctx_poll/ is NOT handled
#   here: the laptop's 5-minute raw files (<collector>_<HHMMSS>.json.gz, one per run) are in
#   a different layout from the Worker's daily jsonl.gz, and converting them is a later step.
#   The laptop's own perp_ctx_5m/ files are not uploaded either, for the same reason.
#
#   Then it writes the seed marker hyperliquid/_seeded.json (the tables with their row counts
#   and date range, the raw days; no host, path or account) and publishes everything with
#   scripts/hf_upload_commit.sh: ONE commit (read back identical). Hugging Face recommends
#   fewer than 100 files per commit and has no hard limit; a seed that would need more than
#   HL_SEED_MAX_FILES files is refused (exit 3) rather than split.
#
#   It refuses (exit 3) while a fetch is running: hl_progress.txt present in --data-dir, or a
#   fetch_hyperliquid.R / fetch_hl_market_reference.R process alive. A table copied mid-run
#   would be a half-written history.
#
# Usage (both directories are required and absolute; there are no defaults):
#   Rscript scripts/seed_hl_to_hf.R --data-dir=/abs/data/dist --raw-dir=/abs/data/raw/hyperliquid
#   ... --apply     publish (needs HF_TOKEN in the environment and the `hf` CLI)
#
# Exit status: 0 PASS (dry run complete, or published and read back) | 1 FAIL (a guard
#   violation, the upload failed) | 2 usage | 3 INDETERMINATE (a fetch is running, a
#   required table is on neither side, Hugging Face unreachable, token or `hf` absent with
#   --apply, too many files). 1 outranks 3. 3 is never 0.

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
})

.seed_find <- function(name) {
  from_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  cands <- character()
  if (length(from_file) > 0L) {
    cands <- c(cands, file.path(dirname(normalizePath(sub("^--file=", "", from_file[1]),
                                                       mustWork = FALSE)), name))
  }
  cands <- c(cands, file.path("scripts", name))
  if (requireNamespace("here", quietly = TRUE)) cands <- c(cands, here::here("scripts", name))
  hit <- cands[file.exists(cands)]
  if (length(hit) == 0L) {
    cli::cli_abort(c("x" = "Cannot locate {.file scripts/{name}}", "i" = "tried: {.file {cands}}"))
  }
  hit[1]
}
source(.seed_find("hl_history_guard.R"))
# HL_PROGRESS_FILE (the fetcher's resume marker) has one home: the fetcher.
source(.seed_find("fetch_hyperliquid.R"))

HL_SEED_MAX_FILES <- 90L              # Hugging Face: keep a commit under about 100 files
HL_SEED_ARCHIVE_NAME <- "seed"
HL_SEED_FORMAT <- "hl-seed-v1"

# A fetch is running if its progress file is there or one of its processes is alive. The
# pattern's first letters are bracketed so the pgrep's own command line (and the shell that
# runs it) do not match it. Returns TRUE / FALSE / NA (could not ask).
hl_seed_fetch_running <- function() {
  res <- suppressWarnings(system2("pgrep", c("-f", shQuote("[f]etch_hyperliquid[.]R|[f]etch_hl_market_reference[.]R")),
                                  stdout = TRUE, stderr = TRUE))
  status <- attr(res, "status")
  if (is.null(status)) return(TRUE)
  if (identical(as.integer(status), 1L)) return(FALSE)
  NA
}

# Local rows win a clash on the key.
hl_seed_merge <- function(local_path, hf_path, spec) {
  loc <- arrow::read_parquet(local_path)
  hf <- arrow::read_parquet(hf_path)
  dplyr::bind_rows(loc, hf) |>
    dplyr::distinct(dplyr::across(dplyr::all_of(spec$key)), .keep_all = TRUE) |>
    dplyr::arrange(dplyr::across(dplyr::all_of(spec$key)))
}

hl_seed_preflight <- function() {
  if (!nzchar(Sys.getenv("HF_TOKEN", unset = ""))) {
    return("HF_TOKEN is not set in the environment (a cached login is not accepted)")
  }
  if (!nzchar(Sys.which("hf"))) {
    return("the `hf` CLI is not on PATH (pip install --upgrade huggingface_hub)")
  }
  NULL
}

hl_seed_upload <- function(stage_dir, message) {
  script <- .seed_find("hf_upload_commit.sh")
  as.integer(system2("bash", c(shQuote(script), shQuote(stage_dir), shQuote(message)),
                     env = "HD_HF_REPO_VISIBILITY=public"))
}

.seed_stats <- function(path, spec) {
  d <- hl_hist_read_cols(path, spec)
  if (is.na(spec$when)) return(list(rows = nrow(d), earliest = NA_character_, latest = NA_character_))
  list(rows = nrow(d), earliest = .hist_day(.hist_min(d[[spec$when]])),
       latest = .hist_day(.hist_max(d[[spec$when]])))
}

.seed_refuse <- function(reason) {
  cli::cli_alert_danger("INDETERMINATE: {reason}")
  list(status = 3L, reason = reason, tables = NULL, days = NULL, files = character(),
       bytes = 0, commits = 0L)
}

# Returns list(status, reason, tables, days, files, bytes, commits, uploaded).
# `client` = list(hf_list, hf_download) (the public dataset, read only). `upload_fn(stage, msg)`
# returns an exit status; `running_fn()` TRUE/FALSE/NA; `merge_fn(local, hf, spec)` a data
# frame; `preflight_fn()` NULL or a reason (called only with apply = TRUE).
hl_seed_run <- function(data_dir, raw_dir, client, stage_dir = tempfile("hl_seed_stage_"),
                        work_dir = tempfile("hl_seed_work_"), apply = FALSE,
                        upload_fn = hl_seed_upload, running_fn = hl_seed_fetch_running,
                        merge_fn = hl_seed_merge, preflight_fn = hl_seed_preflight,
                        now = Sys.time(), max_files = HL_SEED_MAX_FILES) {
  # 1. Refuse while a fetch is running (before anything is read).
  if (file.exists(file.path(data_dir, HL_PROGRESS_FILE))) {
    return(.seed_refuse(paste0(HL_PROGRESS_FILE, " is present in the data folder: a fetch is (or was) running; wait for it, or delete the marker if no fetch is running"))) # nolint
  }
  running <- running_fn()
  if (is.na(running)) return(.seed_refuse("could not tell whether a fetch is running (pgrep failed)"))
  if (running) return(.seed_refuse("a fetch_hyperliquid.R or fetch_hl_market_reference.R process is running; wait for it"))
  if (apply) {
    why <- preflight_fn()
    if (!is.null(why)) return(.seed_refuse(why))
  }

  stage_root <- file.path(stage_dir, HL_HIST_ROOT)
  dir.create(stage_root, recursive = TRUE, showWarnings = FALSE)
  dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
  on_hf <- client$hf_list(HL_HIST_ROOT)

  # 2. Tables: union with the Hugging Face copy, guard against BOTH inputs.
  rows <- lapply(HL_HIST_TABLES$table, function(t) {
    spec <- hl_hist_spec(t)
    loc <- file.path(data_dir, paste0(t, ".parquet"))
    rel <- sprintf("%s/%s.parquet", HL_HIST_ROOT, t)
    hf_path <- file.path(work_dir, rel)
    stg <- file.path(stage_root, paste0(t, ".parquet"))
    out <- list(table = t, local_rows = NA_integer_, hf_rows = NA_integer_, merged_rows = NA_integer_,
                earliest = NA_character_, latest = NA_character_, verdict = "PASS", why = "")
    have_loc <- file.exists(loc)
    have_hf <- rel %in% on_hf
    if (!have_loc && !have_hf) {
      out$verdict <- if (spec$required) "UNDECIDED" else "ABSENT"
      out$why <- if (spec$required) "required table is on neither side" else "not present anywhere (optional)"
      return(as.data.frame(out))
    }
    r <- tryCatch({
      if (have_loc) out$local_rows <- nrow(hl_hist_read_cols(loc, spec))
      if (have_hf) {
        client$hf_download(rel, hf_path)
        out$hf_rows <- nrow(hl_hist_read_cols(hf_path, spec))
      }
      verdicts <- list()
      if (have_loc && have_hf) {
        merged <- merge_fn(loc, hf_path, spec)
        tmp <- paste0(stg, ".tmp")
        arrow::write_parquet(merged, tmp)
        file.rename(tmp, stg)
      } else if (have_loc) {
        file.copy(loc, stg, overwrite = TRUE)
      }
      if (have_loc) verdicts$local <- hl_hist_guard_one(loc, stg, spec)
      if (have_hf && have_loc) verdicts$hf <- hl_hist_guard_one(hf_path, stg, spec)
      fin <- if (have_loc) stg else hf_path
      st <- .seed_stats(fin, spec)
      out$merged_rows <- st$rows; out$earliest <- st$earliest; out$latest <- st$latest
      bad <- Filter(function(v) v$verdict != "PASS", verdicts)
      if (length(bad) > 0L) {
        out$verdict <- "FAIL"
        out$why <- paste(vapply(names(bad), function(n) paste0("vs ", n, ": ", bad[[n]]$why), ""), collapse = "; ")
      }
      NULL
    }, error = function(e) e)
    if (inherits(r, "error")) { out$verdict <- "UNDECIDED"; out$why <- conditionMessage(r) }
    as.data.frame(out)
  })
  tables <- dplyr::bind_rows(rows)

  # 3. Raw day folders: one seed.tar per day, never over an existing one.
  days <- .hist_day_dirs(raw_dir)
  on_hf_day <- vapply(days, function(d) {
    sprintf("%s/%s/date=%s/%s.tar", HL_HIST_ROOT, HL_HIST_RAW_SUBDIR, d, HL_SEED_ARCHIVE_NAME) %in%
      client$hf_list(sprintf("%s/%s/date=%s", HL_HIST_ROOT, HL_HIST_RAW_SUBDIR, d))
  }, logical(1))
  n_files <- vapply(days, function(d) length(list.files(file.path(raw_dir, d), recursive = TRUE)), integer(1))
  raw_fail <- NULL
  packed <- tryCatch(
    hl_hist_pack_days(raw_dir, file.path(stage_root, HL_HIST_RAW_SUBDIR), HL_SEED_ARCHIVE_NAME,
                      skip_days = days[on_hf_day]),
    hl_hist_pack_mismatch = function(e) { raw_fail <<- list(status = "FAIL", why = conditionMessage(e)); NULL },
    error = function(e) { raw_fail <<- list(status = "UNDECIDED", why = conditionMessage(e)); NULL })
  day_tbl <- data.frame(day = days, files = unname(n_files), on_hf = unname(on_hf_day),
                        stringsAsFactors = FALSE)
  day_tbl$packed_mb <- NA_real_
  day_tbl$action <- ifelse(day_tbl$files == 0L, "empty, skipped",
                           ifelse(day_tbl$on_hf, "seed.tar already on HF, skipped", "pack"))
  if (!is.null(packed) && nrow(packed) > 0L) {
    day_tbl$packed_mb[match(packed$day, day_tbl$day)] <- round(packed$bytes_out / 1e6, 1)
  }

  # 4. Verdict so far, then the marker and the plan.
  status <- if (any(tables$verdict == "FAIL") || identical(raw_fail$status, "FAIL")) 1L else
    if (any(tables$verdict == "UNDECIDED") || !is.null(raw_fail)) 3L else 0L
  reason <- c(
    if (any(tables$verdict == "FAIL")) "a table failed the guard",
    if (any(tables$verdict == "UNDECIDED")) "a required table is missing or could not be compared",
    if (!is.null(raw_fail)) paste("raw packing:", raw_fail$why))
  files <- character(); bytes <- 0
  if (status == 0L) {
    have <- tables[!is.na(tables$merged_rows), , drop = FALSE]
    marker <- list(
      format = HL_SEED_FORMAT,
      seeded_at = format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      tables = stats::setNames(lapply(seq_len(nrow(have)), function(i) {
        list(rows = have$merged_rows[i], earliest = have$earliest[i], latest = have$latest[i])
      }), have$table),
      raw_days = list(count = length(days), first = if (length(days)) days[1] else NA_character_,
                      last = if (length(days)) days[length(days)] else NA_character_))
    jsonlite::write_json(marker, file.path(stage_root, HL_HIST_MARKER), auto_unbox = TRUE,
                         pretty = TRUE, na = "null")
    files <- sort(list.files(stage_dir, recursive = TRUE))
    bytes <- sum(file.size(file.path(stage_dir, files)))
    if (length(files) > max_files) {
      status <- 3L
      reason <- sprintf("%d files to upload, more than the %d a single commit may carry; splitting is not implemented", length(files), max_files)
    }
  }
  res <- list(status = status, reason = paste(reason, collapse = "; "), tables = tables, days = day_tbl,
              files = files, bytes = bytes, commits = if (status == 0L) 1L else 0L, uploaded = FALSE)

  # 5. Publish, only with --apply and only when everything passed.
  if (apply && status == 0L) {
    code <- upload_fn(stage_dir, sprintf("data: hyperliquid history seed (Refs #1088)"))
    res$status <- if (code == 0L) 0L else if (code == 3L) 3L else 1L
    res$uploaded <- code == 0L
    if (code != 0L) res$reason <- sprintf("hf_upload_commit.sh exited %d", code)
  }
  res
}

# ── Command line ────────────────────────────────────────────────────
.seed_usage <- "usage: seed_hl_to_hf.R --data-dir=/abs/path --raw-dir=/abs/path [--dry-run | --apply]"

.seed_main <- function(args = commandArgs(trailingOnly = TRUE), client = NULL, ...) {
  known <- grepl("^--(data-dir|raw-dir)=.+$", args) | args %in% c("--apply", "--dry-run")
  if (any(!known) || sum(args %in% c("--apply", "--dry-run")) > 1L) {
    message(.seed_usage, "\nunknown or conflicting argument(s): ", paste(args[!known], collapse = " "))
    return(2L)
  }
  opt <- function(name) {
    hit <- grep(paste0("^--", name, "="), args, value = TRUE)
    if (length(hit) == 0L) NA_character_ else sub(paste0("^--", name, "="), "", hit[1])
  }
  dirs <- c(`data-dir` = opt("data-dir"), `raw-dir` = opt("raw-dir"))
  if (anyNA(dirs)) { message(.seed_usage, "\nboth --data-dir and --raw-dir are required (no defaults)"); return(2L) }
  if (any(!startsWith(dirs, "/"))) { message(.seed_usage, "\nboth directories must be absolute paths"); return(2L) }
  if (any(!dir.exists(dirs))) {
    message("not a folder: ", paste(dirs[!dir.exists(dirs)], collapse = ", "))
    return(2L)
  }
  data_dir <- normalizePath(dirs[["data-dir"]]); raw_dir <- normalizePath(dirs[["raw-dir"]])
  apply <- "--apply" %in% args
  cat("Resolved paths (read only", if (apply) ", publishing with --apply" else ", DRY RUN", "):\n", sep = "")
  cat("  data-dir: ", data_dir, "\n  raw-dir:  ", raw_dir, "\n\n", sep = "")
  if (is.null(client)) client <- hl_drain_hf_client()
  res <- tryCatch(hl_seed_run(data_dir, raw_dir, client, apply = apply, ...),
                  error = function(e) .seed_refuse(conditionMessage(e)))
  if (!is.null(res$tables)) {
    cat("Tables (union of the local and the Hugging Face copy):\n")
    print(res$tables[c("table", "local_rows", "hf_rows", "merged_rows", "earliest", "latest", "verdict", "why")],
          row.names = FALSE)
    cat("\nRaw day folders (one seed.tar per day, gzipped members):\n")
    print(res$days[c("day", "files", "packed_mb", "action")], row.names = FALSE)
    cat(sprintf("\nUpload: %d file(s), %.1f MB, %d commit(s)\n", length(res$files), res$bytes / 1e6, res$commits))
  }
  if (res$status == 0L && !apply) cat("DRY RUN: nothing was uploaded. Re-run with --apply to publish.\n")
  if (res$status == 0L && apply) cat("PASS: published and read back identical.\n")
  if (res$status == 1L) message("FAIL: ", res$reason)
  if (res$status == 3L) message("INDETERMINATE: ", res$reason)
  res$status
}

if (sys.nframe() == 0L) {
  quit(save = "no", status = .seed_main())
}
