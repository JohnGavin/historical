#!/usr/bin/env Rscript
# Daily drain: Cloudflare KV -> a staging folder for Hugging Face (#1088)
#
# WHAT THIS IS
#   The Cloudflare Worker (cloudflare/hl-ctx-collector/worker.js) stores one KV value
#   per 5-minute slot, key `ctx/<YYYY-MM-DD>/<HHMM>`, kept 10 days. This script turns
#   those values into the project's own files, in a staging folder that
#   scripts/hf_upload_commit.sh then publishes as ONE commit:
#     <out-dir>/hyperliquid/perp_ctx_5m/date=<d>/cf-1.parquet     the parsed rows
#     <out-dir>/hyperliquid/raw/ctx_poll/date=<d>/cf-1.jsonl.gz   one raw document per
#                                                                 line (one per slot)
#   Parsing is poll_hyperliquid_ctx.R's own code (hl_parse_ctx, hl_ctx_write), sourced.
#
# NO PROGRESS MARKER. Every run lists the KV keys (every UTC day still in the 10-day
# window), lists what Hugging Face holds for those days, and builds any day where KV
# has slots that Hugging Face lacks. The slot ledger of a day is its raw file on
# Hugging Face: a slot is "on HF" when its document is in that file, whether its
# replies parsed or not, so a slot that only failed is not re-read for ever. Days
# already complete are not touched; a changed day is rebuilt as the old HF file plus
# the new slots (rows upserted on dex, coin, fetched_at; documents de-duplicated by
# slot), so a late, repeated or partial run loses nothing and duplicates nothing.
#
# Nothing here uploads: the HF token is not read by this script (reads of the public
# dataset need none). Upload is a separate step with its own checks.
#
# Env (never printed): CF_ACCOUNT_ID, CF_KV_NAMESPACE_ID, CF_API_TOKEN (a token with
# account-level Workers KV Storage read). Cloudflare REST API, verified against its
# docs 2026-11-22: GET .../keys?prefix=&limit=&cursor= (list), GET .../values/<key>
# (raw bytes). The bulk-get call is text-only ("binary values are not supported"), so
# values are read one by one, paced under the 1,200-requests-per-5-minutes limit.
#
# Usage: Rscript scripts/drain_hl_ctx_kv.R [--out-dir=hf_stage]
#
# Exit status: 0 PASS (every listed key is on HF or is now staged) | 1 FAIL (a listed
#   key could not be read, was corrupt, or was named for a different slot) | 2 usage |
#   3 INDETERMINATE (not configured, or KV/HF could not be listed or read, so a day
#   could not be decided). 1 outranks 3. 3 is never 0.

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
})

.drain_find <- function(name) {
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
source(.drain_find("poll_hyperliquid_ctx.R"))

HL_DRAIN_COLLECTOR <- "cf-1"
HL_DRAIN_FORMAT <- "hl-ctx-v1"
HL_DRAIN_KV_PREFIX <- "ctx/"
HL_DRAIN_HF_REPO <- "JohnGavin/finance-data"
HL_DRAIN_HF_ROOT <- "hyperliquid"
HL_DRAIN_KV_RATE <- 1100L          # requests per window: under the 1,200 per 5 minutes limit
HL_DRAIN_KV_WINDOW_S <- 300
HL_DRAIN_EXPIRY_GRACE_S <- 3600    # a 404 on a key due to expire within this is "expired", not a failure
HL_DRAIN_SLOTS_PER_DAY <- as.integer(86400L / HL_CTX_SLOT_SECONDS)

# ── Keys and slots ──────────────────────────────────────────────────
# KV key names -> day, hhmm, slot_id ("YYYY-MM-DD/HHMM"); NA for a name that is not ours.
hl_drain_key_parse <- function(names) {
  m <- regmatches(names, regexec("^ctx/([0-9]{4}-[0-9]{2}-[0-9]{2})/([0-9]{4})$", names))
  ok <- lengths(m) == 3L
  day <- ifelse(ok, vapply(m, function(x) if (length(x) == 3L) x[2] else NA_character_, ""), NA_character_)
  hhmm <- ifelse(ok, vapply(m, function(x) if (length(x) == 3L) x[3] else NA_character_, ""), NA_character_)
  data.frame(name = names, day = day, hhmm = hhmm,
             slot_id = ifelse(ok, paste0(day, "/", hhmm), NA_character_),
             stringsAsFactors = FALSE)
}

# "2026-11-22/1205" -> POSIXct (UTC).
hl_drain_slot_time <- function(slot_id) {
  if (length(slot_id) == 0L) return(as.POSIXct(numeric(), origin = "1970-01-01", tz = "UTC"))
  as.POSIXct(paste0(substr(slot_id, 1L, 10L), " ", substr(slot_id, 12L, 13L), ":",
                    substr(slot_id, 14L, 15L), ":00"), tz = "UTC")
}

# A header's ISO slot ("2026-11-22T12:05:00.000Z") -> slot_id.
hl_drain_iso_slot_id <- function(iso) {
  paste0(substr(iso, 1L, 10L), "/", substr(iso, 12L, 13L), substr(iso, 15L, 16L))
}

# Slot ids of the documents in JSON lines (NA for a line that does not start like one of ours).
hl_drain_line_slot_ids <- function(lines) {
  head <- substr(lines, 1L, 160L)
  pat <- '^\\{"collector":"[^"]*","slot":"([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}):([0-9]{2}):[0-9.]+Z".*$'
  ids <- sub(pat, "\\1/\\2\\3", head)
  ids[!grepl(pat, head)] <- NA_character_
  ids
}

# ── Unframing a KV value ────────────────────────────────────────────
.drain_corrupt <- function(why) {
  cli::cli_abort(c("x" = "Corrupt KV value: {why}"), class = "hl_drain_corrupt")
}

# Header line (JSON), newline, then the bodies as raw bytes in header order, each of the
# header's `bytes` length. Returns list(header, bodies). Aborts (class hl_drain_corrupt)
# if the header is not what the Worker writes or the lengths do not add up exactly.
hl_drain_unframe <- function(value) {
  if (!is.raw(value) || length(value) == 0L) .drain_corrupt("empty value")
  nl <- which(value == as.raw(10L))[1]
  if (is.na(nl)) .drain_corrupt("no header line")
  header <- tryCatch(jsonlite::fromJSON(rawToChar(value[seq_len(nl - 1L)]), simplifyVector = FALSE),
                     error = function(e) .drain_corrupt("header is not JSON"))
  if (!is.list(header) || !identical(header$format, HL_DRAIN_FORMAT)) .drain_corrupt("unknown format")
  if (!is.character(header$collector) || length(header$collector) != 1L) .drain_corrupt("no collector")
  if (!is.character(header$slot) || !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:", header$slot)) {
    .drain_corrupt("no slot")
  }
  if (!is.list(header$replies)) .drain_corrupt("no reply list")
  for (r in header$replies) {
    if (!is.character(r$dex) || !is.character(r$fetched_at_us) ||
        !grepl("^[0-9]{12,}$", r$fetched_at_us) || !is.numeric(r$status) ||
        !is.logical(r$ok) || !is.numeric(r$bytes) || r$bytes < 0) {
      .drain_corrupt("a reply entry is malformed")
    }
  }
  bytes <- vapply(header$replies, function(r) as.numeric(r$bytes), numeric(1))
  rest <- value[-seq_len(nl)]
  if (sum(bytes) != length(rest)) {
    .drain_corrupt(sprintf("header says %.0f body bytes, value holds %d", sum(bytes), length(rest)))
  }
  ends <- cumsum(bytes)
  starts <- ends - bytes + 1
  bodies <- Map(function(s, e) if (e < s) raw(0) else rest[s:e], starts, ends)
  list(header = header, bodies = bodies)
}

# ── One slot -> one raw document and its parsed rows ────────────────
# A reply is ok only if it was HTTP 200, is valid UTF-8 JSON and parses (hl_parse_ctx).
# An ok reply's text is embedded as sent (newlines, which JSON ignores between tokens,
# become spaces so the document stays on ONE line); a 200 that does not parse is kept as
# a JSON string for audit with ok false; any other status has "reply": null.
# Returns list(line, frames, n_ok, n_failed).
hl_drain_doc <- function(header, bodies, collector = HL_DRAIN_COLLECTOR) {
  frames <- list()
  entries <- character()
  n_ok <- 0L
  for (i in seq_along(header$replies)) {
    r <- header$replies[[i]]
    body <- bodies[[i]]
    at <- as.POSIXct(as.numeric(r$fetched_at_us) / 1e6, origin = "1970-01-01", tz = "UTC")
    ok <- FALSE
    reply_json <- "null"
    if (isTRUE(r$ok) && length(body) > 0L && !any(body == as.raw(0L))) {
      txt <- gsub("[\r\n]+", " ", rawToChar(body))
      if (validUTF8(txt)) {
        parsed <- if (isTRUE(jsonlite::validate(txt))) {
          tryCatch(hl_parse_ctx(jsonlite::fromJSON(txt, simplifyVector = FALSE), r$dex, at, collector),
                   error = function(e) e)
        } else {
          simpleError("not JSON")
        }
        if (inherits(parsed, "error")) {
          reply_json <- .ctx_json_str(txt)
        } else {
          ok <- TRUE
          reply_json <- txt
          frames[[length(frames) + 1L]] <- parsed
        }
      }
    }
    n_ok <- n_ok + as.integer(ok)
    entries <- c(entries, sprintf('{"dex":%s,"fetched_at_us":"%s","status":%d,"ok":%s,"reply":%s}',
                                  .ctx_json_str(r$dex), r$fetched_at_us, as.integer(r$status),
                                  if (ok) "true" else "false", reply_json))
  }
  perp_ok <- isTRUE(header$perp_dexs$ok)
  line <- sprintf('{"collector":%s,"slot":%s,"perp_dexs_ok":%s,"truncated":%s,"replies":[%s]}',
                  .ctx_json_str(collector), .ctx_json_str(header$slot),
                  if (perp_ok) "true" else "false",
                  if (isTRUE(header$truncated)) "true" else "false",
                  paste(entries, collapse = ","))
  list(line = line, frames = frames, n_ok = n_ok, n_failed = length(entries) - n_ok)
}

# ── Gzip JSON-lines files ───────────────────────────────────────────
hl_drain_read_lines <- function(path) {
  txt <- hl_ctx_raw_text(path)
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  lines[nzchar(lines)]
}

hl_drain_write_lines <- function(lines, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  con <- gzfile(tmp, "wb")
  tryCatch(writeBin(charToRaw(paste0(paste(lines, collapse = "\n"), "\n")), con),
           finally = close(con))
  file.rename(tmp, path)
  invisible(path)
}

# ── Pacing ──────────────────────────────────────────────────────────
# Returns a function to call BEFORE every KV request: at most `max_requests` in any
# `window_s` seconds. `now` (seconds) and `sleep` are injectable.
hl_drain_pacer <- function(max_requests = HL_DRAIN_KV_RATE, window_s = HL_DRAIN_KV_WINDOW_S,
                           now = function() as.numeric(Sys.time()), sleep = Sys.sleep) {
  stamps <- numeric()
  function() {
    t <- now()
    stamps <<- stamps[stamps > t - window_s]
    if (length(stamps) >= max_requests) {
      wait <- stamps[1] + window_s - t
      if (wait > 0) sleep(wait)
      t <- now()
      stamps <<- stamps[stamps > t - window_s]
    }
    stamps <<- c(stamps, t)
    invisible(NULL)
  }
}

# ── HTTP, behind small functions (tests replace the whole client) ───
# A client is list(kv_list(prefix) -> data.frame(name, expiration),
#                  kv_get(name) -> list(status, body = raw),
#                  hf_list(path) -> character(repo paths of the files in that folder),
#                  hf_download(path, dest) -> TRUE, aborts otherwise).
.drain_http_abort <- function(what, status, detail = NULL) {
  cli::cli_abort(c("x" = "{what} failed (HTTP {status})", "i" = detail),
                 class = "hl_drain_http_error")
}

.drain_retry <- function(req) {
  req |>
    httr2::req_retry(max_tries = 3,
                     is_transient = function(r) httr2::resp_status(r) %in% c(429L, 500L, 502L, 503L, 504L)) |>
    httr2::req_error(is_error = function(r) FALSE)
}

hl_drain_kv_client <- function(account, namespace, token, pace = hl_drain_pacer()) {
  base <- sprintf("https://api.cloudflare.com/client/v4/accounts/%s/storage/kv/namespaces/%s",
                  account, namespace)
  perform <- function(url, query = list()) {
    pace()
    httr2::request(url) |>
      httr2::req_url_query(!!!query) |>
      httr2::req_auth_bearer_token(token) |>
      httr2::req_timeout(60) |>
      .drain_retry() |>
      httr2::req_perform()
  }
  list(
    kv_list = function(prefix) {
      pages <- list()
      cursor <- ""
      repeat {
        query <- c(list(prefix = prefix, limit = 1000L), if (nzchar(cursor)) list(cursor = cursor))
        resp <- perform(paste0(base, "/keys"), query)
        if (httr2::resp_status(resp) != 200L) .drain_http_abort("KV key list", httr2::resp_status(resp))
        body <- httr2::resp_body_json(resp)
        if (!isTRUE(body$success)) .drain_http_abort("KV key list", httr2::resp_status(resp), "success is not true")
        pages[[length(pages) + 1L]] <- data.frame(
          name = vapply(body$result, function(k) as.character(k$name), character(1)),
          expiration = vapply(body$result, function(k) as.numeric(k$expiration %||% NA_real_), numeric(1)),
          stringsAsFactors = FALSE)
        cursor <- body$result_info$cursor %||% ""
        if (!nzchar(cursor)) break
      }
      bind_rows(pages)
    },
    kv_get = function(name) {
      resp <- perform(paste0(base, "/values/", utils::URLencode(name, reserved = TRUE)))
      st <- httr2::resp_status(resp)
      list(status = st, body = if (st == 200L) httr2::resp_body_raw(resp) else raw(0))
    }
  )
}

hl_drain_hf_client <- function(repo = HL_DRAIN_HF_REPO) {
  enc <- function(path) {
    paste(vapply(strsplit(path, "/", fixed = TRUE)[[1]], utils::URLencode, character(1), reserved = TRUE),
          collapse = "/")
  }
  list(
    hf_list = function(path) {
      resp <- httr2::request(sprintf("https://huggingface.co/api/datasets/%s/tree/main/%s", repo, enc(path))) |>
        httr2::req_timeout(60) |> .drain_retry() |> httr2::req_perform()
      st <- httr2::resp_status(resp)
      if (st == 404L) return(character())          # no such folder yet
      if (st != 200L) .drain_http_abort("HF tree listing", st)
      items <- httr2::resp_body_json(resp)
      files <- Filter(function(x) identical(x$type, "file"), items)
      vapply(files, function(x) as.character(x$path), character(1))
    },
    hf_download = function(path, dest) {
      dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
      part <- paste0(dest, ".part")
      resp <- httr2::request(sprintf("https://huggingface.co/datasets/%s/resolve/main/%s", repo, enc(path))) |>
        httr2::req_timeout(900) |> .drain_retry() |> httr2::req_perform(path = part)
      st <- httr2::resp_status(resp)
      if (st != 200L) {
        unlink(part)
        .drain_http_abort("HF download", st)
      }
      file.rename(part, dest)
      invisible(TRUE)
    }
  )
}

hl_drain_client <- function(account, namespace, token, repo = HL_DRAIN_HF_REPO) {
  c(hl_drain_kv_client(account, namespace, token), hl_drain_hf_client(repo))
}

# ── What Hugging Face holds for one day ─────────────────────────────
hl_drain_hf_path <- function(kind, date, collector = HL_DRAIN_COLLECTOR) {
  if (kind == "raw") {
    sprintf("%s/raw/%s/date=%s/%s.jsonl.gz", HL_DRAIN_HF_ROOT, HL_CTX_RAW_SUBDIR, date, collector)
  } else {
    sprintf("%s/%s/date=%s/%s.parquet", HL_DRAIN_HF_ROOT, HL_CTX_DIR, date, collector)
  }
}

# The day's raw file on HF, downloaded into `cache_dir` if it exists. Returns
# list(exists, lines, ids): `ids` are the slot ids of its documents (NA for a line that
# is not one of ours: kept, reported).
hl_drain_hf_day <- function(client, date, cache_dir, collector = HL_DRAIN_COLLECTOR) {
  rel <- hl_drain_hf_path("raw", date, collector)
  if (!(rel %in% client$hf_list(dirname(rel)))) {
    return(list(exists = FALSE, lines = character(), ids = character()))
  }
  dest <- file.path(cache_dir, rel)
  client$hf_download(rel, dest)
  lines <- hl_drain_read_lines(dest)
  list(exists = TRUE, lines = lines, ids = hl_drain_line_slot_ids(lines))
}

# ── The drain ───────────────────────────────────────────────────────
# Returns list(status, days (data.frame), staged (files), undecided, messages).
hl_drain_run <- function(client, stage_dir, work_dir = tempfile("hl_drain_"),
                         now = function() Sys.time(), collector = HL_DRAIN_COLLECTOR,
                         expiry_grace_s = HL_DRAIN_EXPIRY_GRACE_S) {
  dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)
  listed <- client$kv_list(HL_DRAIN_KV_PREFIX)
  keys <- cbind(hl_drain_key_parse(listed$name), expiration = listed$expiration)
  odd <- is.na(keys$day)
  if (any(odd)) cli::cli_alert_warning("{sum(odd)} KV key{?s} not named ctx/<date>/<HHMM>: ignored")
  keys <- keys[!odd, , drop = FALSE]
  days <- sort(unique(keys$day))
  stage_root <- file.path(stage_dir, HL_DRAIN_HF_ROOT)

  rows <- list()
  n_fail <- 0L
  undecided <- character()
  for (d in days) {
    k <- keys[keys$day == d, , drop = FALSE]
    k <- k[order(k$slot_id), , drop = FALSE]
    hf <- tryCatch(hl_drain_hf_day(client, d, work_dir, collector), error = function(e) e)
    if (inherits(hf, "error")) {
      undecided <- c(undecided, sprintf("%s: %s", d, conditionMessage(hf)))
      cli::cli_alert_danger("{d}: cannot read Hugging Face ({conditionMessage(hf)})")
      rows[[d]] <- data.frame(day = d, kv = nrow(k), hf = NA_integer_, built = 0L,
                              unreadable = 0L, corrupt = 0L, expired = 0L)
      next
    }
    todo <- k[!(k$slot_id %in% hf$ids), , drop = FALSE]
    r <- list(day = d, kv = nrow(k), hf = sum(!is.na(hf$ids)), built = 0L,
              unreadable = 0L, corrupt = 0L, expired = 0L)
    new_lines <- character()
    new_ids <- character()
    frames <- list()
    for (i in seq_len(nrow(todo))) {
      name <- todo$name[i]
      got <- tryCatch(client$kv_get(name), error = function(e) e)
      if (inherits(got, "error") || !(got$status %in% c(200L, 404L))) {
        r$unreadable <- r$unreadable + 1L
        cli::cli_alert_danger("{name}: could not be read ({if (inherits(got, 'error')) conditionMessage(got) else paste('HTTP', got$status)})")
        next
      }
      if (got$status == 404L) {
        due <- todo$expiration[i]
        if (!is.na(due) && due - as.numeric(now()) < expiry_grace_s) {
          r$expired <- r$expired + 1L       # fell out of the window while we ran
        } else {
          r$unreadable <- r$unreadable + 1L
          cli::cli_alert_danger("{name}: listed but not found (HTTP 404)")
        }
        next
      }
      un <- tryCatch(hl_drain_unframe(got$body), error = function(e) e)
      bad <- if (inherits(un, "error")) conditionMessage(un) else if (
        !identical(un$header$collector, collector)) "collector label differs" else if (
        !identical(hl_drain_iso_slot_id(un$header$slot), todo$slot_id[i])) "slot differs from the key" else NULL
      if (!is.null(bad)) {
        r$corrupt <- r$corrupt + 1L
        cli::cli_alert_danger("{name}: {bad}")
        next
      }
      doc <- hl_drain_doc(un$header, un$bodies, collector)
      new_lines <- c(new_lines, doc$line)
      new_ids <- c(new_ids, todo$slot_id[i])
      frames <- c(frames, doc$frames)
      r$built <- r$built + 1L
    }
    n_fail <- n_fail + r$unreadable + r$corrupt
    rows[[d]] <- as.data.frame(r)
    if (length(new_lines) == 0L) next

    # The day's raw file: old HF documents + the new ones, one per slot, in slot order.
    lines <- c(hf$lines, new_lines)
    ids <- c(hf$ids, new_ids)
    keep <- !is.na(ids) & !duplicated(ids)
    keep <- keep | is.na(ids)                    # a line of unknown shape is kept, never dropped
    lines <- lines[keep]
    ids <- ids[keep]
    ord <- order(is.na(ids), ids)
    hl_drain_write_lines(lines[ord], file.path(stage_root, "raw", HL_CTX_RAW_SUBDIR,
                                               paste0("date=", d), paste0(collector, ".jsonl.gz")))

    # The parsed rows: upsert into the HF file of each UTC date they fall on.
    df <- bind_rows(frames)
    if (nrow(df) > 0L) {
      for (dd in unique(format(df$fetched_at, "%Y-%m-%d", tz = "UTC"))) {
        target <- hl_ctx_day_path(stage_root, dd, collector)
        if (!file.exists(target)) {
          rel <- hl_drain_hf_path("parquet", dd, collector)
          if (rel %in% client$hf_list(dirname(rel))) client$hf_download(rel, target)
        }
      }
      hl_ctx_write(df, stage_root)
    }
  }

  days_tbl <- bind_rows(rows)
  staged <- sort(list.files(stage_dir, recursive = TRUE))
  status <- if (n_fail > 0L) 1L else if (length(undecided) > 0L) 3L else 0L
  list(status = status, days = days_tbl, staged = staged, undecided = undecided)
}

# ── Command line ────────────────────────────────────────────────────
.drain_main <- function(args = commandArgs(trailingOnly = TRUE), client = NULL,
                        env = Sys.getenv) {
  bad <- args[!grepl("^--out-dir=.+$", args)]
  if (length(bad) > 0L) {
    message("usage: drain_hl_ctx_kv.R [--out-dir=hf_stage]\nunknown or malformed argument(s): ",
            paste(bad, collapse = " "))
    return(2L)
  }
  out_dir <- if (length(args) > 0L) sub("^--out-dir=", "", args[1]) else "hf_stage"
  if (is.null(client)) {
    vars <- c("CF_ACCOUNT_ID", "CF_KV_NAMESPACE_ID", "CF_API_TOKEN")
    val <- vapply(vars, function(v) env(v, unset = ""), character(1))
    if (any(!nzchar(val))) {
      message("INDETERMINATE: not configured; missing: ", paste(vars[!nzchar(val)], collapse = ", "))
      return(3L)
    }
    client <- hl_drain_client(val[["CF_ACCOUNT_ID"]], val[["CF_KV_NAMESPACE_ID"]], val[["CF_API_TOKEN"]])
  }
  res <- tryCatch(hl_drain_run(client, out_dir), error = function(e) {
    message("INDETERMINATE: ", conditionMessage(e))
    NULL
  })
  if (is.null(res)) return(3L)
  if (nrow(res$days) > 0L) print(res$days, row.names = FALSE)
  cli::cli_alert_info("{length(res$staged)} file{?s} staged under {.file {out_dir}}")
  if (res$status == 1L) message("FAIL: a listed KV key could not be read or was corrupt")
  if (res$status == 3L) message("INDETERMINATE: ", paste(res$undecided, collapse = "; "))
  res$status
}

if (sys.nframe() == 0L) {
  quit(save = "no", status = .drain_main())
}
