#!/usr/bin/env Rscript
# Forward poller: Hyperliquid mid / oracle / impact prices, every exchange per run (#1080, #1084)
#
# WHAT THIS IS
#   `metaAndAssetCtxs` returns, for every market on ONE exchange, the current mid
#   price, oracle price, mark price, impact prices, premium, funding, open
#   interest and 24h notional volume. It has NO history: if it is not recorded
#   now it is lost. This script records one snapshot of EVERY exchange per run
#   (the core exchange, dex "", and every add-on exchange): one `perpDexs`
#   request lists the exchanges, then one `metaAndAssetCtxs` request each
#   (1 + 11 = 12 requests today, weight 20 each = 240 of the 1200 per minute the
#   API allows per IP). launchd runs it every 5 minutes (scripts/launchd/).
#   These are PERPETUAL FUTURES, not tokenised shares.
#
# Output (under --out-dir, default data/dist; gitignored, never committed):
#   perp_ctx_5m.parquet  upsert on (dex, coin, fetched_at)
#     fetched_at   UTC time the reply was received (the TRUE time, never snapped)
#     slot         fetched_at floored to 5 minutes, for joining. Gaps (Mac
#                  asleep, run skipped) are expected and are NEVER imputed: a
#                  later study finds them as missing slots.
#     collector    host name (Sys.info()[["nodename"]]) of the machine that
#                  polled, so a second collector can be merged by slot later
#     server_time  the API's own time if the reply carries one, else NA
#                  (metaAndAssetCtxs replies with a bare [meta, ctxs] array)
#     mid_px, oracle_px, mark_px, impact_bid_px, impact_ask_px, premium,
#     funding, open_interest, day_ntl_vlm
#     is_delisted  the universe's `isDelisted` flag (absent on live markets =
#                  FALSE). Rows written before #1084 have NA here: the column
#                  is added on the next upsert, old rows are never rewritten.
#   fetched_at is taken from EACH exchange's own reply, so the exchanges of one
#   run differ by a fraction of a second; they share a `slot`.
#   A null or "NaN" field is stored as NA, the row is kept, and the count is
#   reported; nothing is silently dropped.
# Raw JSON is kept append-only under --raw-dir (default data/raw/hyperliquid/
#   <UTC date>/), exactly like fetch_hyperliquid.R; never uploaded.
#
# Usage: Rscript scripts/poll_hyperliquid_ctx.R [--out-dir=data/dist]
#          [--raw-dir=data/raw/hyperliquid] [--dexes=all] [--pace=0.75]
#   --dexes=all (the default) polls every exchange `perpDexs` lists, the core
#   exchange included. --dexes=main,xyz polls the named ones ("main" = the core
#   exchange, whose API name is the empty string).
#
# Exit status: 0 ok | 2 usage | 3 INDETERMINATE (a request failed, was
#   rate-limited, an unparseable reply, an empty market list, or the 200 s run
#   limit). 3 is never 0. A PARTIAL run (some exchanges polled, some not) is 3:
#   the rows of the exchanges that did succeed ARE written, the failed ones are
#   named in the log, and the next run is the retry. If `perpDexs` itself fails the
#   exchanges of the last perp_dexs.parquet (else the core exchange alone) are
#   polled, and the run is still 3. A non-429 error is retried (3 attempts in
#   all, 15 s request timeout, ~60 s at most, only while the run budget allows);
#   rate limiting is NOT retried (no 60 s back-off) and stops the run: the
#   remaining exchanges are not attempted.

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
})

# Shared helpers (hl_post / hl_make_post / hl_save_raw / hl_num / hl_upsert / ...)
# live in fetch_hyperliquid.R; sourcing it runs nothing (its main is guarded).
.poll_find_fetcher <- function() {
  from_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  cands <- character()
  if (length(from_file) > 0L) {
    cands <- c(cands, file.path(dirname(normalizePath(sub("^--file=", "", from_file[1]),
                                                       mustWork = FALSE)),
                                "fetch_hyperliquid.R"))
  }
  cands <- c(cands, file.path("scripts", "fetch_hyperliquid.R"))
  if (requireNamespace("here", quietly = TRUE)) {
    cands <- c(cands, here::here("scripts", "fetch_hyperliquid.R"))
  }
  hit <- cands[file.exists(cands)]
  if (length(hit) == 0L) {
    cli::cli_abort(c("x" = "Cannot locate {.file scripts/fetch_hyperliquid.R}",
                     "i" = "tried: {.file {cands}}"))
  }
  hit[1]
}
source(.poll_find_fetcher())

HL_CTX_SLOT_SECONDS <- 300L        # slot width: 5 minutes, one home
HL_CTX_FILE <- "perp_ctx_5m.parquet"
HL_CTX_KEYS <- c("dex", "coin", "fetched_at")
HL_CTX_TRIES <- 3L                 # attempts per run on non-429 errors
HL_CTX_RETRY_DELAY_S <- c(5, 10)   # waits between attempts
HL_CTX_REQUEST_TIMEOUT_S <- 15     # per request: 3 x 15 + 15 s of waits ~ 60 s
HL_CTX_BUDGET_S <- 200             # whole-run limit in R; the wrapper's is 240
# A new request (or a retry) starts only if at least this many seconds of the
# budget remain: a full request timeout plus margin, so a started request always
# ends inside the budget and the rows collected so far are written.
HL_CTX_MIN_REMAINING_S <- HL_CTX_REQUEST_TIMEOUT_S + 10
HL_CTX_DEXES_ALL <- "all"
HL_CTX_MAIN_TOKEN <- "main"        # command-line spelling of the core exchange
HL_DEXS_FILE <- "perp_dexs.parquet"  # written by fetch_hyperliquid.R (#1084)

# Floor a time to the slot width (UTC, POSIXct in and out).
hl_ctx_slot <- function(t) {
  as.POSIXct(floor(as.numeric(t) / HL_CTX_SLOT_SECONDS) * HL_CTX_SLOT_SECONDS,
             origin = "1970-01-01", tz = "UTC")
}

# One field of every asset context as numeric. A MISSING key or JSON null becomes
# NA (counted by the caller); "NaN" becomes NA; any other non-numeric text aborts
# (hl_num), so a malformed value never turns into a silent NA.
.ctx_field <- function(ctx, field, pick = NULL) {
  raw <- vapply(ctx, function(r) {
    v <- r[[field]]
    if (!is.null(pick) && !is.null(v)) v <- if (length(v) >= pick) v[[pick]] else NULL
    if (is.null(v)) NA_character_ else as.character(v)
  }, character(1))
  hl_num(raw, field, nan_ok = TRUE)
}

# metaAndAssetCtxs -> one row per market. Contexts are joined to the universe BY
# POSITION, which the API defines for this call (same length, same order); a
# length mismatch aborts. `server_time_ms` is read only if the reply carries one.
hl_parse_ctx <- function(mac, dex, fetched_at, collector = Sys.info()[["nodename"]]) {
  if (!is.list(mac) || length(mac) != 2L) {
    cli::cli_abort("metaAndAssetCtxs payload must be [meta, ctxs]")
  }
  u <- mac[[1]]$universe
  ctx <- mac[[2]]
  if (length(u) == 0L) {
    cli::cli_abort("Empty market list for dex {.val {dex}}", class = "hl_empty_markets")
  }
  if (length(u) != length(ctx)) {
    cli::cli_abort("universe ({length(u)}) and asset contexts ({length(ctx)}) differ")
  }
  hl_require_fields(u, "name", "universe")
  srv <- mac[[1]]$time %||% mac[[1]]$serverTime
  fetched_at <- as.POSIXct(fetched_at, tz = "UTC")
  data.frame(
    dex = dex,
    coin = vapply(u, function(m) as.character(m$name), character(1)),
    fetched_at = fetched_at,
    slot = hl_ctx_slot(fetched_at),
    collector = as.character(collector),
    server_time = if (is.null(srv)) as.POSIXct(NA, tz = "UTC") else
      as.POSIXct(as.numeric(srv) / 1000, origin = "1970-01-01", tz = "UTC"),
    mid_px = .ctx_field(ctx, "midPx"),
    oracle_px = .ctx_field(ctx, "oraclePx"),
    mark_px = .ctx_field(ctx, "markPx"),
    impact_bid_px = .ctx_field(ctx, "impactPxs", pick = 1L),
    impact_ask_px = .ctx_field(ctx, "impactPxs", pick = 2L),
    premium = .ctx_field(ctx, "premium"),
    funding = .ctx_field(ctx, "funding"),
    open_interest = .ctx_field(ctx, "openInterest"),
    day_ntl_vlm = .ctx_field(ctx, "dayNtlVlm"),
    is_delisted = vapply(u, function(m) isTRUE(m$isDelisted), logical(1)),
    stringsAsFactors = FALSE
  )
}

# Number of NA cells per numeric field (reported, never dropped).
hl_ctx_na_counts <- function(df) {
  num <- setdiff(names(df)[vapply(df, is.numeric, logical(1))], character())
  vapply(df[num], function(x) sum(is.na(x)), integer(1))
}

# Body of the request for one exchange. The core exchange ("") is asked WITHOUT a
# `dex` field, exactly as fetch_hyperliquid.R does.
hl_ctx_body <- function(dex) {
  if (nzchar(dex)) list(type = "metaAndAssetCtxs", dex = dex) else list(type = "metaAndAssetCtxs")
}

# One request with retries. A non-429 error is retried up to `tries` times in
# total, waiting `retry_delay_s` between attempts (default 5 s then 10 s; with the
# 15 s request timeout the worst case is about 60 s). Never retried: HTTP 429 (the
# next run is the retry), the R time limit, and anything the run budget does not
# allow (`time_left()` seconds remain; a retry needs its delay plus a full request
# timeout). Returns list(value, error, attempts, rate_limited).
.ctx_request <- function(post_fn, body, tries, retry_delay_s, sleep_fn, time_left) {
  attempts <- 0L
  repeat {
    attempts <- attempts + 1L
    res <- tryCatch(post_fn(body), error = function(e) e)
    if (!inherits(res, "error")) {
      return(list(value = res, error = NULL, attempts = attempts, rate_limited = FALSE))
    }
    rl <- inherits(res, "hl_rate_limited")
    delay <- retry_delay_s[min(attempts, length(retry_delay_s))]
    retryable <- !rl && !grepl("time limit", conditionMessage(res), fixed = TRUE) &&
      attempts < tries && time_left() >= delay + HL_CTX_MIN_REMAINING_S
    if (!retryable) {
      return(list(value = NULL, error = conditionMessage(res), attempts = attempts,
                  rate_limited = rl))
    }
    cli::cli_alert_warning("attempt {attempts} of {tries} failed ({conditionMessage(res)}); retrying in {delay} s")
    sleep_fn(delay)
  }
}

# Exchanges of the last perp_dexs.parquet (fetch_hyperliquid.R), else just the
# core exchange: the fallback when `perpDexs` cannot be read.
.ctx_known_dexes <- function(out_dir) {
  path <- file.path(out_dir, HL_DEXS_FILE)
  known <- if (file.exists(path)) arrow::read_parquet(path)$dex else character()
  unique(c("", as.character(known[!is.na(known)])))
}

# One poll of every requested exchange. `post_fn(body)` returns parsed JSON
# (injectable). `now` is a clock function (injectable); it is read AFTER each reply
# is received, so fetched_at is the time the data was in hand, not the time the
# request started. `dexes` is "all" (the exchanges `perpDexs` lists) or a character
# vector of exchange names, "" = the core exchange. `deadline` (POSIXct, optional)
# is the end of the run budget: no request starts without HL_CTX_MIN_REMAINING_S
# left, and the exchanges not reached are reported, not hidden.
# The rows of all exchanges that succeeded are upserted in ONE write.
# Returns list(status, n_rows, n_na, reason, attempts, by_dex, not_attempted).
# Status 3 for ANY failure or omission: a request errored on every attempt, was
# rate-limited, a reply did not parse, a universe was empty, the budget ran out,
# or `perpDexs` could not be read. A partial run writes what it has and is still
# 3; never 0 unless every exchange was polled.
hl_ctx_poll <- function(post_fn, out_dir = "data/dist", dexes = HL_CTX_DEXES_ALL,
                        now = function() Sys.time(),
                        collector = Sys.info()[["nodename"]],
                        tries = HL_CTX_TRIES, retry_delay_s = HL_CTX_RETRY_DELAY_S,
                        sleep_fn = Sys.sleep, deadline = NULL) {
  if (!is.character(dexes) || length(dexes) == 0L || anyNA(dexes)) {
    hl_bad_arg("dexes", "must be \"all\" or a character vector of exchange names")
  }
  time_left <- function() {
    if (is.null(deadline)) Inf else as.numeric(difftime(deadline, Sys.time(), units = "secs"))
  }
  attempts <- 0L
  problems <- character()
  note_problem <- function(msg) {
    problems <<- c(problems, msg)
    cli::cli_alert_danger("INDETERMINATE: {msg}")
  }
  req <- function(body) {
    r <- .ctx_request(post_fn, body, tries, retry_delay_s, sleep_fn, time_left)
    attempts <<- attempts + r$attempts
    r
  }

  if (identical(dexes, HL_CTX_DEXES_ALL)) {
    r <- if (time_left() >= HL_CTX_MIN_REMAINING_S) {
      req(list(type = "perpDexs"))
    } else {
      list(error = "run budget exhausted before the exchange list was read")
    }
    listed <- if (is.null(r$error)) {
      tryCatch(hl_parse_dexs(r$value), error = function(e) e)
    } else {
      simpleError(r$error)
    }
    if (inherits(listed, "error")) {
      dexes <- .ctx_known_dexes(out_dir)
      note_problem(sprintf("perpDexs: %s (polling the last known exchanges: %s)",
                           conditionMessage(listed),
                           paste0("'", dexes, "'", collapse = ", ")))
    } else {
      dexes <- unique(listed)
    }
  }

  frames <- list()
  not_attempted <- character()
  stopped <- FALSE
  for (d in dexes) {
    if (stopped || time_left() < HL_CTX_MIN_REMAINING_S) {
      not_attempted <- c(not_attempted, d)
      next
    }
    r <- req(hl_ctx_body(d))
    if (!is.null(r$error)) {
      note_problem(sprintf("dex '%s': %s", d, r$error))
      if (r$rate_limited) stopped <- TRUE
      next
    }
    fetched_at <- now()
    df <- tryCatch(hl_parse_ctx(r$value, d, fetched_at, collector), error = function(e) e)
    if (inherits(df, "error")) {
      note_problem(sprintf("dex '%s': %s", d, conditionMessage(df)))
      next
    }
    frames[[paste0("dex:", d)]] <- df
  }
  if (length(not_attempted) > 0L) {
    note_problem(sprintf("not attempted (run budget or rate limit): %s",
                         paste0("'", not_attempted, "'", collapse = ", ")))
  }

  df <- bind_rows(frames)
  by_dex <- if (nrow(df) > 0L) {
    df |>
      group_by(dex) |>
      summarise(n_rows = dplyr::n(), n_delisted = sum(is_delisted), .groups = "drop") |>
      as.data.frame()
  } else {
    data.frame(dex = character(), n_rows = integer(), n_delisted = integer())
  }
  na <- integer()
  if (nrow(df) > 0L) {
    hl_upsert(df, file.path(out_dir, HL_CTX_FILE), HL_CTX_KEYS)
    na <- hl_ctx_na_counts(df)
    cli::cli_alert_success("{nrow(df)} market{?s} over {nrow(by_dex)} exchange{?s}, slot {format(df$slot[1], tz = 'UTC', usetz = TRUE)}; {sum(df$is_delisted)} delisted")
    if (any(na > 0L)) {
      cli::cli_alert_info("NA cells kept (null or \"NaN\"): {paste(names(na)[na > 0L], na[na > 0L], sep = '=', collapse = ', ')}")
    }
  }
  list(status = if (length(problems) == 0L) 0L else 3L,
       n_rows = nrow(df), n_na = na, reason = paste(problems, collapse = "; "),
       attempts = attempts, by_dex = by_dex, not_attempted = not_attempted)
}

# Command-line exchange list -> hl_ctx_poll's `dexes`; NULL when malformed.
.ctx_parse_dexes <- function(txt) {
  if (identical(txt, HL_CTX_DEXES_ALL)) return(HL_CTX_DEXES_ALL)
  parts <- strsplit(txt, ",", fixed = TRUE)[[1]]
  if (length(parts) == 0L || !all(grepl("^[A-Za-z0-9_.-]+$", parts))) return(NULL)
  unique(ifelse(parts == HL_CTX_MAIN_TOKEN, "", parts))
}

# Returns the exit status (the guard below quits with it); testable.
.poll_hyperliquid_ctx_main <- function(args = commandArgs(trailingOnly = TRUE),
                                       post_fn = NULL, budget_s = HL_CTX_BUDGET_S,
                                       sleep_fn = Sys.sleep) {
  known <- c("out-dir", "raw-dir", "dexes", "pace")
  bad <- args[!grepl(paste0("^--(", paste(known, collapse = "|"), ")=.+$"), args)]
  if (length(bad) > 0L) {
    message("usage: poll_hyperliquid_ctx.R [--out-dir=D] [--raw-dir=D] [--dexes=all|main,xyz,...] [--pace=P]\n",
            "unknown or malformed argument(s): ", paste(bad, collapse = " "))
    return(2L)
  }
  opt <- function(name, default) {
    hit <- grep(paste0("^--", name, "="), args, value = TRUE)
    if (length(hit) == 0L) default else sub(paste0("^--", name, "="), "", hit[1])
  }
  pace_txt <- as.character(opt("pace", HL_PACE_FRACTION))
  pace <- if (grepl("^([0-9]+\\.?[0-9]*|\\.[0-9]+)$", pace_txt)) as.numeric(pace_txt) else NA_real_
  if (is.na(pace) || pace <= 0 || pace > 1) {
    message("usage: --pace must be a number in (0, 1]")
    return(2L)
  }
  dexes <- .ctx_parse_dexes(opt("dexes", HL_CTX_DEXES_ALL))
  if (is.null(dexes)) {
    message("usage: --dexes must be \"all\" or a comma-separated list of exchange names ",
            "(\"main\" = the core exchange)")
    return(2L)
  }
  if (is.null(post_fn)) {
    # max_attempts = 1: a 429 is not backed off for 60 s inside a 5-minute job.
    # sleep_fn no-op: 12 requests of weight 20 (240 of the 1200/min limit) need no
    # pacing, and a pace sleep would delay the reply that fetched_at is taken
    # from. `timeout`/`max_tries` go to hl_post: a request is cut at 15 s and 5xx
    # retries are done here, not there.
    post_fn <- hl_make_post(opt("raw-dir", "data/raw/hyperliquid"), pace = pace,
                            max_attempts = 1L, sleep_fn = function(s) invisible(NULL),
                            timeout = HL_CTX_REQUEST_TIMEOUT_S, max_tries = 1)
  }
  # Whole-run time limit: the deadline stops new requests early and keeps what was
  # collected; R's own limit is the backstop (an error, turned into status 3,
  # never 0). The wrapper has a harder, outer deadline.
  setTimeLimit(elapsed = budget_s, transient = TRUE)
  on.exit(setTimeLimit(elapsed = Inf), add = TRUE)
  res <- tryCatch(
    hl_ctx_poll(post_fn, out_dir = opt("out-dir", "data/dist"), dexes = dexes,
                sleep_fn = sleep_fn, deadline = Sys.time() + budget_s),
    error = function(e) {
      message("INDETERMINATE: ", conditionMessage(e))
      list(status = 3L)
    })
  res$status
}

if (sys.nframe() == 0L) {
  quit(save = "no", status = .poll_hyperliquid_ctx_main())
}
