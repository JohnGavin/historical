#!/usr/bin/env Rscript
# Weekly Hyperliquid history on Hugging Face: download, guard, start date, pack (#1088)
#
# WHAT THIS IS
#   The public Hugging Face dataset holds the Hyperliquid history tables
#   (hyperliquid/<table>.parquet). The weekly workflow (.github/workflows/hl-weekly.yml)
#   downloads them, runs scripts/fetch_hyperliquid.R on top (an upsert), checks that
#   nothing was lost, packs the run's raw replies and publishes. This file holds the four
#   small steps that are not the fetcher, so the workflow YAML stays plain:
#
#   download   every expected table, and the seed marker, from HF into --dir. The job
#              refuses to run before the owner's seed: no marker = exit 3. A table that
#              is absent, unreadable, or has FEWER rows than the marker recorded at seed
#              time is a failed download = exit 3. (F4: fetch_hyperliquid.R's upsert
#              writes only the new rows when its target file is absent, so a run that
#              started from a missing table would publish a table that has lost history.)
#   guard      for every table: new rows >= old rows, earliest date <= old earliest, and
#              the old key set is a subset of the new key set. Any violation = exit 1.
#              Also used by scripts/seed_hl_to_hf.R, against BOTH inputs of a merge.
#   start-date the date to pass to fetch_hyperliquid.R as --start, so a weekly run asks
#              the API only for what is new. The fetcher re-requests the whole funding
#              history since --start for every market; from 2023-01-01 that took more
#              than 9 hours on the laptop (measured 2026-11-22, still running), longer
#              than the 6 hours a GitHub job may run. Derived from the tables, never typed.
#   pack       one tar per UTC day of raw replies, each member gzipped on its own, so one
#              reply can be read without unpacking the day. Hugging Face allows under
#              10,000 files per folder, and a day holds about 10,000 raw files.
#
# Usage (every directory is given, none is guessed):
#   Rscript scripts/hl_history_guard.R download   --dir=D
#   Rscript scripts/hl_history_guard.R guard      --old-dir=D --new-dir=D
#   Rscript scripts/hl_history_guard.R start-date --dir=D        (prints YYYY-MM-DD)
#   Rscript scripts/hl_history_guard.R pack       --raw-dir=D --out-dir=D --name=N
#
# Exit status: 0 PASS | 1 FAIL (guard violation, pack could not be read back) | 2 usage |
#   3 INDETERMINATE (not downloaded, not seeded, a table unreadable, nothing to pack).
#   1 outranks 3. 3 is never 0.

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
})

.hist_find <- function(name) {
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
# The Hugging Face read client (hl_drain_hf_client) is the drain's own: one client, not two.
source(.hist_find("drain_hl_ctx_kv.R"))

HL_HIST_ROOT <- "hyperliquid"
HL_HIST_MARKER <- "_seeded.json"
HL_HIST_RAW_SUBDIR <- "raw/weekly"
HL_HIST_START_MARGIN_DAYS <- 3L           # overlap, so a late bar or a re-stated bar is refetched
HL_HIST_FLOOR_START <- as.Date("2023-01-01")  # the fetcher's own default start

# One home for the table list. `key` = the upsert key of fetch_hyperliquid.R and
# fetch_hl_market_reference.R; `when` = the column whose minimum is the table's earliest
# date (NA where a new row replaces an old one, so the minimum may legitimately move);
# `required` = the weekly job refuses to start without it. The two reference tables and
# spot_15m are required only when the seed marker lists them.
HL_HIST_TABLES <- data.frame(
  table    = c("perp_daily", "perp_hourly", "perp_15m", "spot_daily", "spot_hourly", "spot_15m",
               "perp_funding", "perp_funding_daily", "perp_oi_snapshot", "perp_dexs", "perp_markets"),
  key      = c("dex,coin,date", "dex,coin,time", "dex,coin,time", "dex,coin,date", "dex,coin,time",
               "dex,coin,time", "dex,coin,time_ms", "dex,coin,date", "dex,coin,fetched_at",
               "dex", "dex,coin"),
  when     = c("date", "time", "time", "date", "time", "time", "time_ms", "date", "fetched_at",
               NA, NA),
  required = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, FALSE, FALSE),
  stringsAsFactors = FALSE
)
# The tables whose latest bar says how far the history reaches.
HL_HIST_FRESH <- c("perp_daily", "perp_hourly", "perp_15m", "perp_funding")

hl_hist_spec <- function(table) {
  i <- match(table, HL_HIST_TABLES$table)
  if (is.na(i)) cli::cli_abort(c("x" = "Unknown table {.val {table}}"), class = "hl_hist_unknown_table")
  list(table = table, key = strsplit(HL_HIST_TABLES$key[i], ",", fixed = TRUE)[[1]],
       when = HL_HIST_TABLES$when[i], required = HL_HIST_TABLES$required[i])
}

.hist_cols <- function(spec) unique(c(spec$key, if (!is.na(spec$when)) spec$when))

# Only the key (and date) columns are read: cheap even for the funding table.
hl_hist_read_cols <- function(path, spec) {
  as.data.frame(arrow::read_parquet(path, col_select = dplyr::all_of(.hist_cols(spec))))
}

# A key or date value as "YYYY-MM-DD": Date, POSIXct, epoch milliseconds, or an ISO string.
.hist_day <- function(x) {
  if (length(x) == 0L || all(is.na(x))) return(NA_character_)
  if (inherits(x, "Date")) return(format(x, "%Y-%m-%d"))
  if (inherits(x, "POSIXct")) return(format(x, "%Y-%m-%d", tz = "UTC"))
  if (is.numeric(x)) return(format(as.POSIXct(x / 1000, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%d"))
  substr(as.character(x), 1L, 10L)
}
.hist_min <- function(x) if (all(is.na(x))) NA else min(x, na.rm = TRUE)
.hist_max <- function(x) if (all(is.na(x))) NA else max(x, na.rm = TRUE)

# ── Guard ───────────────────────────────────────────────────────────
# One table. Returns a one-row data.frame; `verdict` is PASS or FAIL, `why` says what.
# An unreadable table or a missing key column is not decided here: it aborts, and
# hl_hist_guard() reports UNDECIDED.
hl_hist_guard_one <- function(old_path, new_path, spec) {
  row <- function(verdict, why, old_rows = NA_integer_, new_rows = NA_integer_,
                  old_first = NA_character_, new_first = NA_character_, lost = NA_integer_) {
    data.frame(table = spec$table, old_rows = old_rows, new_rows = new_rows,
               old_earliest = old_first, new_earliest = new_first, lost_keys = lost,
               verdict = verdict, why = why, stringsAsFactors = FALSE)
  }
  if (!file.exists(new_path)) return(row("FAIL", "the table is missing from the new set"))
  old <- hl_hist_read_cols(old_path, spec)
  new <- hl_hist_read_cols(new_path, spec)
  why <- character()
  if (nrow(new) < nrow(old)) why <- c(why, sprintf("rows fell from %d to %d", nrow(old), nrow(new)))
  o_first <- n_first <- NA_character_
  if (!is.na(spec$when)) {
    o_min <- .hist_min(old[[spec$when]])
    n_min <- .hist_min(new[[spec$when]])
    o_first <- .hist_day(o_min)
    n_first <- .hist_day(n_min)
    if (!is.na(o_first) && (is.na(n_first) || n_min > o_min)) {
      why <- c(why, sprintf("earliest date moved from %s to %s", o_first, n_first))
    }
  }
  lost <- nrow(dplyr::anti_join(dplyr::distinct(old[spec$key]), dplyr::distinct(new[spec$key]),
                                by = spec$key))
  if (lost > 0L) why <- c(why, sprintf("%d old key(s) are not in the new table", lost))
  row(if (length(why) == 0L) "PASS" else "FAIL", paste(why, collapse = "; "),
      nrow(old), nrow(new), o_first, n_first, lost)
}

# Every registry table that exists in `old_dir`, compared with the same table in `new_dir`.
# Returns list(status, tbl). 1 FAIL outranks 3 UNDECIDED. A guard that found no table to
# compare is UNDECIDED, never a pass.
hl_hist_guard <- function(old_dir, new_dir) {
  names_old <- HL_HIST_TABLES$table[file.exists(file.path(old_dir, paste0(HL_HIST_TABLES$table, ".parquet")))]
  rows <- lapply(names_old, function(t) {
    tryCatch(hl_hist_guard_one(file.path(old_dir, paste0(t, ".parquet")),
                               file.path(new_dir, paste0(t, ".parquet")), hl_hist_spec(t)),
             error = function(e) {
               data.frame(table = t, old_rows = NA_integer_, new_rows = NA_integer_,
                          old_earliest = NA_character_, new_earliest = NA_character_,
                          lost_keys = NA_integer_, verdict = "UNDECIDED",
                          why = conditionMessage(e), stringsAsFactors = FALSE)
             })
  })
  tbl <- dplyr::bind_rows(rows)
  status <- if (nrow(tbl) == 0L) 3L else if (any(tbl$verdict == "FAIL")) 1L else
    if (any(tbl$verdict == "UNDECIDED")) 3L else 0L
  list(status = status, tbl = tbl)
}

# ── Start date ──────────────────────────────────────────────────────
# The oldest of the four "latest bar" dates, less the overlap, never before the floor.
# Aborts if a table is missing or empty (the caller turns that into exit 3).
hl_hist_start_date <- function(dir, margin_days = HL_HIST_START_MARGIN_DAYS,
                               floor_date = HL_HIST_FLOOR_START) {
  latest <- vapply(HL_HIST_FRESH, function(t) {
    spec <- hl_hist_spec(t)
    path <- file.path(dir, paste0(t, ".parquet"))
    if (!file.exists(path)) cli::cli_abort(c("x" = "{.file {path}} is missing"), class = "hl_hist_missing")
    d <- .hist_max(hl_hist_read_cols(path, spec)[[spec$when]])
    if (is.na(d)) cli::cli_abort(c("x" = "{.val {t}} has no rows"), class = "hl_hist_empty")
    as.numeric(as.Date(.hist_day(d)))
  }, numeric(1))
  max(as.Date(min(latest) - margin_days, origin = "1970-01-01"), floor_date)
}

# ── Pack ────────────────────────────────────────────────────────────
.hist_day_dirs <- function(raw_dir) {
  d <- list.dirs(raw_dir, recursive = FALSE, full.names = FALSE)
  sort(d[grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", d)])
}

# Raw files that are NOT packed into the public dataset: a basename matching this regex stays
# on the laptop only. The saved copy of the trade.xyz specification page (spec_ prefix) is a
# third-party document; its parsed columns stay public in perp_markets.parquet. Owner
# decision 2026-11-23, Refs #1088. Excluded files are never touched on disk.
HL_HIST_RAW_EXCLUDE <- "^spec_"

# The raw files of one day folder, split into those to pack and those excluded (relative paths).
.hist_raw_split <- function(src) {
  files <- sort(list.files(src, recursive = TRUE))
  excl <- grepl(HL_HIST_RAW_EXCLUDE, basename(files))
  list(pack = files[!excl], excluded = files[excl])
}

# Gzip one file on its own (a gzip member, readable with gunzip or R's gzfile).
.hist_gzip_file <- function(src, dest) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  con <- gzfile(dest, "wb")
  tryCatch(writeBin(readBin(src, "raw", file.size(src)), con), finally = close(con))
  invisible(dest)
}

# One tar per UTC day folder of `raw_dir` (ctx_poll/ and anything else that is not a
# YYYY-MM-DD folder is left alone), at <out_dir>/date=<day>/<name>.tar. Each member is a
# gzipped copy of one raw file, named <file>.gz. `skip_days` are not packed. The tar is
# listed back and its member count must equal the packed file count, else it aborts. Files
# matching HL_HIST_RAW_EXCLUDE are not packed and are counted in `excluded`.
# Returns data.frame(day, files, excluded, bytes_in, bytes_out, path).
hl_hist_pack_days <- function(raw_dir, out_dir, name, skip_days = character()) {
  if (!grepl("^[A-Za-z0-9._-]+$", name)) {
    cli::cli_abort(c("x" = "Invalid archive name {.val {name}}"), class = "hl_hist_bad_arg")
  }
  days <- setdiff(.hist_day_dirs(raw_dir), skip_days)
  out <- lapply(days, function(day) {
    src <- file.path(raw_dir, day)
    sp <- .hist_raw_split(src)
    files <- sp$pack
    if (length(files) == 0L) return(NULL)
    gz_dir <- tempfile("hl_pack_")
    on.exit(unlink(gz_dir, recursive = TRUE), add = TRUE)
    for (f in files) .hist_gzip_file(file.path(src, f), file.path(gz_dir, paste0(f, ".gz")))
    dest <- file.path(out_dir, paste0("date=", day), paste0(name, ".tar"))
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    tmp <- paste0(dest, ".tmp")
    owd <- setwd(gz_dir)
    tryCatch(utils::tar(tmp, files = paste0(files, ".gz"), compression = "none", tar = "internal"),
             finally = setwd(owd))
    n_in_tar <- length(utils::untar(tmp, list = TRUE))
    if (n_in_tar != length(files)) {
      unlink(tmp)
      cli::cli_abort(c("x" = "{day}: the tar holds {n_in_tar} member{?s}, expected {length(files)}"),
                     class = "hl_hist_pack_mismatch")
    }
    file.rename(tmp, dest)
    data.frame(day = day, files = length(files), excluded = length(sp$excluded),
               bytes_in = sum(file.size(file.path(src, files))),
               bytes_out = file.size(dest), path = dest, stringsAsFactors = FALSE)
  })
  out <- dplyr::bind_rows(out)
  if (nrow(out) == 0L) {
    return(data.frame(day = character(), files = integer(), excluded = integer(), bytes_in = numeric(),
                      bytes_out = numeric(), path = character(), stringsAsFactors = FALSE))
  }
  out
}

# ── Download ────────────────────────────────────────────────────────
# `client` = list(hf_list(path), hf_download(path, dest)). Returns list(status, tbl, why,
# marker). status 0 only if the marker is on HF and EVERY expected table (the required
# ones, plus every table the marker lists) was downloaded, reads, and has at least the
# rows the marker recorded at seed time.
hl_hist_download <- function(client, dir, root = HL_HIST_ROOT) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  marker_rel <- paste0(root, "/", HL_HIST_MARKER)
  on_hf <- client$hf_list(root)
  if (!(marker_rel %in% on_hf)) {
    return(list(status = 3L, tbl = NULL, marker = NULL,
                why = "no seed marker on Hugging Face: the job refuses to run before the owner's seed (scripts/seed_hl_to_hf.R --apply)"))
  }
  marker_path <- tempfile("hl_marker_", fileext = ".json")
  client$hf_download(marker_rel, marker_path)
  marker <- jsonlite::fromJSON(marker_path, simplifyVector = FALSE)
  if (!is.list(marker$tables) || length(marker$tables) == 0L) {
    return(list(status = 3L, tbl = NULL, marker = marker, why = "the seed marker lists no tables"))
  }
  expected <- union(HL_HIST_TABLES$table[HL_HIST_TABLES$required], names(marker$tables))
  rows <- lapply(expected, function(t) {
    rel <- sprintf("%s/%s.parquet", root, t)
    dest <- file.path(dir, paste0(t, ".parquet"))
    res <- function(ok, why, n = NA_integer_, seeded = NA_integer_) {
      data.frame(table = t, ok = ok, rows = n, rows_at_seed = seeded, why = why, stringsAsFactors = FALSE)
    }
    if (!(rel %in% on_hf)) return(res(FALSE, "not on Hugging Face"))
    got <- tryCatch({ client$hf_download(rel, dest); NULL }, error = function(e) conditionMessage(e))
    if (!is.null(got)) return(res(FALSE, paste("download failed:", got)))
    n <- tryCatch(nrow(hl_hist_read_cols(dest, hl_hist_spec(t))), error = function(e) e)
    if (inherits(n, "error")) return(res(FALSE, paste("unreadable (truncated?):", conditionMessage(n))))
    seeded <- marker$tables[[t]]$rows
    seeded <- if (is.null(seeded)) NA_integer_ else as.integer(seeded)
    if (!is.na(seeded) && n < seeded) {
      return(res(FALSE, sprintf("%d rows, fewer than the %d recorded at seed", n, seeded), n, seeded))
    }
    res(TRUE, "", n, seeded)
  })
  tbl <- dplyr::bind_rows(rows)
  list(status = if (all(tbl$ok)) 0L else 3L, tbl = tbl, marker = marker,
       why = if (all(tbl$ok)) "" else "not every expected table downloaded completely")
}

# ── Command line ────────────────────────────────────────────────────
.hist_usage <- paste0(
  "usage: hl_history_guard.R download --dir=D | guard --old-dir=D --new-dir=D | ",
  "start-date --dir=D | pack --raw-dir=D --out-dir=D --name=N")
.hist_required <- list(download = "dir", guard = c("old-dir", "new-dir"), `start-date` = "dir",
                       pack = c("raw-dir", "out-dir", "name"))

.hist_main <- function(args = commandArgs(trailingOnly = TRUE), client = NULL) {
  cmd <- if (length(args) > 0L) args[1] else ""
  opts <- args[-1]
  need <- .hist_required[[cmd]]
  if (is.null(need)) { message(.hist_usage); return(2L) }
  bad <- opts[!grepl(paste0("^--(", paste(need, collapse = "|"), ")=.+$"), opts)]
  val <- vapply(need, function(n) {
    hit <- grep(paste0("^--", n, "="), opts, value = TRUE)
    if (length(hit) == 0L) NA_character_ else sub(paste0("^--", n, "="), "", hit[1])
  }, character(1))
  if (length(bad) > 0L || anyNA(val)) {
    message(.hist_usage, "\nmissing or unknown argument(s)", if (length(bad) > 0L) paste(":", paste(bad, collapse = " ")))
    return(2L)
  }
  undecided <- function(e) { message("INDETERMINATE: ", conditionMessage(e)); 3L }

  if (cmd == "download") {
    if (is.null(client)) client <- hl_drain_hf_client()
    res <- tryCatch(hl_hist_download(client, val[["dir"]]), error = function(e) e)
    if (inherits(res, "error")) return(undecided(res))
    if (!is.null(res$tbl)) print(res$tbl, row.names = FALSE)
    if (res$status != 0L) message("INDETERMINATE: ", res$why)
    return(res$status)
  }
  if (cmd == "guard") {
    res <- tryCatch(hl_hist_guard(val[["old-dir"]], val[["new-dir"]]), error = function(e) e)
    if (inherits(res, "error")) return(undecided(res))
    print(res$tbl, row.names = FALSE)
    if (res$status == 1L) message("FAIL: the new tables lose history; nothing may be published")
    if (res$status == 3L) message("INDETERMINATE: a table could not be compared, or none was found")
    return(res$status)
  }
  if (cmd == "start-date") {
    d <- tryCatch(hl_hist_start_date(val[["dir"]]), error = function(e) e)
    if (inherits(d, "error")) return(undecided(d))
    cat(format(d, "%Y-%m-%d"), "\n", sep = "")
    return(0L)
  }
  # pack
  res <- tryCatch(hl_hist_pack_days(val[["raw-dir"]], val[["out-dir"]], val[["name"]]),
                  hl_hist_pack_mismatch = function(e) e, error = function(e) e)
  if (inherits(res, "hl_hist_pack_mismatch")) { message("FAIL: ", conditionMessage(res)); return(1L) }
  if (inherits(res, "error")) return(undecided(res))
  if (nrow(res) == 0L) {
    message("INDETERMINATE: no raw day folder with files in ", val[["raw-dir"]], ": a fetch that left no raw replies is not a clean run")
    return(3L)
  }
  print(res[c("day", "files", "bytes_in", "bytes_out")], row.names = FALSE)
  0L
}

if (sys.nframe() == 0L) {
  quit(save = "no", status = .hist_main())
}
