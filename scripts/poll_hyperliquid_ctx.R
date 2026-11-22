#!/usr/bin/env Rscript
# Forward poller: Hyperliquid mid / oracle / impact prices, one request per run (#1080)
#
# WHAT THIS IS
#   `metaAndAssetCtxs` returns, for every market on ONE exchange (default the
#   builder exchange "xyz", trade.xyz), the current mid price, oracle price, mark
#   price, impact prices, premium, funding, open interest and 24h notional
#   volume. It has NO history: if it is not recorded now it is lost. This script
#   records one snapshot per run; launchd runs it every 5 minutes
#   (scripts/launchd/). These are PERPETUAL FUTURES, not tokenised shares.
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
#   A null or "NaN" field is stored as NA, the row is kept, and the count is
#   reported; nothing is silently dropped.
# Raw JSON is kept append-only under --raw-dir (default data/raw/hyperliquid/
#   <UTC date>/), exactly like fetch_hyperliquid.R; never uploaded.
#
# Usage: Rscript scripts/poll_hyperliquid_ctx.R [--out-dir=data/dist]
#          [--raw-dir=data/raw/hyperliquid] [--dex=xyz] [--pace=0.75]
#
# Exit status: 0 ok | 2 usage | 3 INDETERMINATE (request failed, rate-limited,
#   unparseable reply, an empty market list, or the 200 s run limit). 3 is never 0.
#   A non-429 error is retried (3 attempts in all, ~60 s at most); rate limiting
#   is NOT (no 60 s back-off): the next run is the retry.

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
    stringsAsFactors = FALSE
  )
}

# Number of NA cells per numeric field (reported, never dropped).
hl_ctx_na_counts <- function(df) {
  num <- setdiff(names(df)[vapply(df, is.numeric, logical(1))], character())
  vapply(df[num], function(x) sum(is.na(x)), integer(1))
}

# One poll. `post_fn(body)` returns parsed JSON (injectable). `now` is a clock
# function (injectable); it is read AFTER the reply is received, so fetched_at is
# the time the data was in hand, not the time the request started.
# A non-429 request error is retried up to `tries` times in total, waiting
# `retry_delay_s` between attempts (default 5 s then 10 s; with the 15 s request
# timeout the worst case is about 60 s). Never retried: HTTP 429 (the next run is
# the retry) and the run-wide time limit. Returns
# list(status, n_rows, n_na, reason, attempts).
# Status 3 for ANY failure: the request errored on every attempt, was
# rate-limited, the reply did not parse, or the universe was empty. Never 0 on a
# failed request.
hl_ctx_poll <- function(post_fn, out_dir = "data/dist", dex = "xyz",
                        now = function() Sys.time(),
                        collector = Sys.info()[["nodename"]],
                        tries = HL_CTX_TRIES, retry_delay_s = HL_CTX_RETRY_DELAY_S,
                        sleep_fn = Sys.sleep) {
  attempts <- 0L
  fail <- function(why) {
    cli::cli_alert_danger("INDETERMINATE: {why}")
    list(status = 3L, n_rows = 0L, n_na = integer(), reason = why, attempts = attempts)
  }
  repeat {
    attempts <- attempts + 1L
    mac <- tryCatch(post_fn(list(type = "metaAndAssetCtxs", dex = dex)),
                    error = function(e) e)
    if (!inherits(mac, "error")) break
    retryable <- !inherits(mac, "hl_rate_limited") &&
      !grepl("time limit", conditionMessage(mac), fixed = TRUE)
    if (!retryable || attempts >= tries) return(fail(conditionMessage(mac)))
    delay <- retry_delay_s[min(attempts, length(retry_delay_s))]
    cli::cli_alert_warning("attempt {attempts} of {tries} failed ({conditionMessage(mac)}); retrying in {delay} s")
    sleep_fn(delay)
  }
  fetched_at <- now()
  df <- tryCatch(hl_parse_ctx(mac, dex, fetched_at, collector), error = function(e) e)
  if (inherits(df, "error")) return(fail(conditionMessage(df)))
  hl_upsert(df, file.path(out_dir, HL_CTX_FILE), HL_CTX_KEYS)
  na <- hl_ctx_na_counts(df)
  cli::cli_alert_success("{nrow(df)} market{?s} for dex {.val {dex}}, slot {format(df$slot[1], tz = 'UTC', usetz = TRUE)}")
  if (any(na > 0L)) {
    cli::cli_alert_info("NA cells kept (null or \"NaN\"): {paste(names(na)[na > 0L], na[na > 0L], sep = '=', collapse = ', ')}")
  }
  list(status = 0L, n_rows = nrow(df), n_na = na, reason = "", attempts = attempts)
}

# Returns the exit status (the guard below quits with it); testable.
.poll_hyperliquid_ctx_main <- function(args = commandArgs(trailingOnly = TRUE),
                                       post_fn = NULL, budget_s = HL_CTX_BUDGET_S,
                                       sleep_fn = Sys.sleep) {
  known <- c("out-dir", "raw-dir", "dex", "pace")
  bad <- args[!grepl(paste0("^--(", paste(known, collapse = "|"), ")=.+$"), args)]
  if (length(bad) > 0L) {
    message("usage: poll_hyperliquid_ctx.R [--out-dir=D] [--raw-dir=D] [--dex=NAME] [--pace=P]\n",
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
  if (is.null(post_fn)) {
    # max_attempts = 1: a 429 is not backed off for 60 s inside a 5-minute job.
    # sleep_fn no-op: one request per run needs no pacing, and a pace sleep would
    # delay the reply that fetched_at is taken from. `timeout`/`max_tries` go to
    # hl_post: a request is cut at 15 s and 5xx retries are done here, not there.
    post_fn <- hl_make_post(opt("raw-dir", "data/raw/hyperliquid"), pace = pace,
                            max_attempts = 1L, sleep_fn = function(s) invisible(NULL),
                            timeout = HL_CTX_REQUEST_TIMEOUT_S, max_tries = 1)
  }
  # Whole-run time limit: R signals an error at the limit, which hl_ctx_poll turns
  # into status 3 (never 0). The wrapper has a harder, outer deadline.
  setTimeLimit(elapsed = budget_s, transient = TRUE)
  on.exit(setTimeLimit(elapsed = Inf), add = TRUE)
  res <- tryCatch(
    hl_ctx_poll(post_fn, out_dir = opt("out-dir", "data/dist"), dex = opt("dex", "xyz"),
                sleep_fn = sleep_fn),
    error = function(e) {
      message("INDETERMINATE: ", conditionMessage(e))
      list(status = 3L)
    })
  res$status
}

if (sys.nframe() == 0L) {
  quit(save = "no", status = .poll_hyperliquid_ctx_main())
}
