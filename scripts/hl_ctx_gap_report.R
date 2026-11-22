#!/usr/bin/env Rscript
# Gap report for the 5-minute Hyperliquid snapshots (#1088)
#
# Per UTC day of the Cloudflare KV window: how many 5-minute slots were due, how many
# are on Hugging Face, how many are in KV, and
#   kv_not_hf  slots KV holds that HF does not (the drain failed or has not run): ALWAYS
#              a FAIL, because that data is on a 10-day timer
#   never      slots due that are in neither place (the Worker did not run, or its run
#              left nothing): a FAIL above 2% of the day's due slots
# "On HF" means the slot's document is in the day's raw file `cf-1.jsonl.gz` there, the
# same ledger the drain uses, whether or not its replies parsed.
#
# Slots are due from the FIRST slot seen anywhere in the window (so days before
# collection started are not gaps) to `now` minus a lag (default 60 minutes: the daily
# drain has not had time to carry the newest slots, and the Worker's run is not late).
#
# Env (never printed): CF_ACCOUNT_ID, CF_KV_NAMESPACE_ID, CF_API_TOKEN; the HF dataset is
# public and read without a token.
#
# Usage: Rscript scripts/hl_ctx_gap_report.R [--days=10] [--lag-minutes=60]
# Exit status: 0 PASS | 1 FAIL | 2 usage | 3 INDETERMINATE (not configured, a listing or
#   download failed, or no slot exists anywhere yet, so there is nothing to judge).

suppressPackageStartupMessages(library(cli))

.gap_find <- function(name) {
  from_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  cands <- character()
  if (length(from_file) > 0L) {
    cands <- c(cands, file.path(dirname(normalizePath(sub("^--file=", "", from_file[1]),
                                                       mustWork = FALSE)), name))
  }
  cands <- c(cands, file.path("scripts", name))
  if (requireNamespace("here", quietly = TRUE)) cands <- c(cands, here::here("scripts", name))
  hit <- cands[file.exists(cands)]
  if (length(hit) == 0L) cli::cli_abort(c("x" = "Cannot locate {.file scripts/{name}}"))
  hit[1]
}
source(.gap_find("drain_hl_ctx_kv.R"))

HL_GAP_NEVER_FAIL_FRACTION <- 0.02

# `client` as in drain_hl_ctx_kv.R. `now` is a POSIXct. Returns list(status, table).
# Aborts only for a failure to read KV or HF (the caller turns that into 3).
hl_gap_report <- function(client, now = Sys.time(), days = 10L, lag_minutes = 60,
                          collector = HL_DRAIN_COLLECTOR, work_dir = tempfile("hl_gap_"),
                          never_fail_fraction = HL_GAP_NEVER_FAIL_FRACTION) {
  now <- as.POSIXct(now, tz = "UTC")
  today <- as.Date(format(now, "%Y-%m-%d", tz = "UTC"))
  window <- format(today - rev(seq_len(days) - 1L), "%Y-%m-%d")

  keys <- hl_drain_key_parse(client$kv_list(HL_DRAIN_KV_PREFIX)$name)
  kv_ids <- keys$slot_id[!is.na(keys$slot_id) & keys$day %in% window]
  hf_ids <- lapply(stats::setNames(window, window), function(d) {
    h <- hl_drain_hf_day(client, d, work_dir, collector)
    h$ids[!is.na(h$ids)]
  })
  seen <- c(kv_ids, unlist(hf_ids, use.names = FALSE))
  if (length(seen) == 0L) {
    cli::cli_abort(c("x" = "No slot in KV or on HF for the last {days} days",
                     "i" = "collection has not started (or the window is wrong): nothing to judge"))
  }
  first <- min(hl_drain_slot_time(seen))
  last_due <- as.POSIXct(floor((as.numeric(now) - lag_minutes * 60) / HL_CTX_SLOT_SECONDS) *
                           HL_CTX_SLOT_SECONDS, origin = "1970-01-01", tz = "UTC")

  rows <- lapply(window, function(d) {
    start <- as.POSIXct(paste0(d, " 00:00:00"), tz = "UTC")
    from <- max(start, first)
    to <- min(start + 86400 - HL_CTX_SLOT_SECONDS, last_due)
    due <- if (to < from) character() else {
      t <- seq(from, to, by = HL_CTX_SLOT_SECONDS)
      paste0(d, "/", format(t, "%H%M", tz = "UTC"))
    }
    on_hf <- hf_ids[[d]]
    in_kv <- kv_ids[startsWith(kv_ids, paste0(d, "/"))]
    kv_not_hf <- setdiff(in_kv, on_hf)
    # a slot newer than `last_due` is not yet judged either way
    kv_not_hf <- kv_not_hf[hl_drain_slot_time(kv_not_hf) <= last_due]
    never <- setdiff(due, union(in_kv, on_hf))
    never_pct <- if (length(due) == 0L) 0 else 100 * length(never) / length(due)
    status <- if (length(kv_not_hf) > 0L || (length(due) > 0L && length(never) / length(due) > never_fail_fraction)) {
      "FAIL"
    } else {
      "PASS"
    }
    data.frame(day = d, due = length(due), on_hf = length(on_hf), in_kv = length(in_kv),
               kv_not_hf = length(kv_not_hf), never = length(never),
               never_pct = round(never_pct, 1), status = status, stringsAsFactors = FALSE)
  })
  tab <- do.call(rbind, rows)
  list(status = if (any(tab$status == "FAIL")) 1L else 0L, table = tab)
}

.gap_main <- function(args = commandArgs(trailingOnly = TRUE), client = NULL,
                      now = Sys.time(), env = Sys.getenv) {
  known <- "^--(days|lag-minutes)=[0-9]+$"
  bad <- args[!grepl(known, args)]
  if (length(bad) > 0L) {
    message("usage: hl_ctx_gap_report.R [--days=10] [--lag-minutes=60]\nunknown or malformed argument(s): ",
            paste(bad, collapse = " "))
    return(2L)
  }
  opt <- function(name, default) {
    hit <- grep(paste0("^--", name, "="), args, value = TRUE)
    if (length(hit) == 0L) default else as.numeric(sub(paste0("^--", name, "="), "", hit[1]))
  }
  days <- opt("days", 10)
  if (days < 1 || days > 60) {
    message("usage: --days must be between 1 and 60")
    return(2L)
  }
  if (is.null(client)) {
    vars <- c("CF_ACCOUNT_ID", "CF_KV_NAMESPACE_ID", "CF_API_TOKEN")
    val <- vapply(vars, function(v) env(v, unset = ""), character(1))
    if (any(!nzchar(val))) {
      message("INDETERMINATE: not configured; missing: ", paste(vars[!nzchar(val)], collapse = ", "))
      return(3L)
    }
    client <- hl_drain_client(val[["CF_ACCOUNT_ID"]], val[["CF_KV_NAMESPACE_ID"]], val[["CF_API_TOKEN"]])
  }
  res <- tryCatch(hl_gap_report(client, now = now, days = as.integer(days),
                                lag_minutes = opt("lag-minutes", 60)),
                  error = function(e) {
                    message("INDETERMINATE: ", conditionMessage(e))
                    NULL
                  })
  if (is.null(res)) return(3L)
  print(res$table, row.names = FALSE)
  if (res$status == 0L) {
    message("PASS: no slot is in KV but not on HF; never-collected slots are within 2% on every day")
  } else {
    message("FAIL: see the rows marked FAIL (kv_not_hf is always a failure; never_pct above 2 is a failure)")
  }
  res$status
}

if (sys.nframe() == 0L) {
  quit(save = "no", status = .gap_main())
}
