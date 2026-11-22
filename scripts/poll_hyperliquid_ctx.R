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
#     fetched_at   UTC time the request was made (the TRUE time, never snapped)
#     slot         fetched_at floored to 5 minutes, for joining. Gaps (Mac
#                  asleep, run skipped) are expected and are NEVER imputed: a
#                  later study finds them as missing slots.
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
#   unparseable reply, or an empty market list). 3 is never 0.
#   Rate limiting is NOT retried here (no 60 s back-off): the next run is the retry.

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
  if (length(hit) == 0L) stop("cannot locate scripts/fetch_hyperliquid.R", call. = FALSE)
  hit[1]
}
source(.poll_find_fetcher())

HL_CTX_SLOT_SECONDS <- 300L        # slot width: 5 minutes, one home
HL_CTX_FILE <- "perp_ctx_5m.parquet"
HL_CTX_KEYS <- c("dex", "coin", "fetched_at")

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
hl_parse_ctx <- function(mac, dex, fetched_at) {
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

# One poll. `post_fn(body)` returns parsed JSON (injectable). `now` is the request
# time (a function so tests can fix it). Returns list(status, n_rows, n_na, reason).
# Status 3 for ANY failure: the request errored, was rate-limited, the reply did
# not parse, or the universe was empty. Never 0 on a failed request.
hl_ctx_poll <- function(post_fn, out_dir = "data/dist", dex = "xyz",
                        now = function() Sys.time()) {
  fail <- function(why) {
    cli::cli_alert_danger("INDETERMINATE: {why}")
    list(status = 3L, n_rows = 0L, n_na = integer(), reason = why)
  }
  fetched_at <- now()
  mac <- tryCatch(post_fn(list(type = "metaAndAssetCtxs", dex = dex)),
                  error = function(e) e)
  if (inherits(mac, "error")) return(fail(conditionMessage(mac)))
  df <- tryCatch(hl_parse_ctx(mac, dex, fetched_at), error = function(e) e)
  if (inherits(df, "error")) return(fail(conditionMessage(df)))
  hl_upsert(df, file.path(out_dir, HL_CTX_FILE), HL_CTX_KEYS)
  na <- hl_ctx_na_counts(df)
  cli::cli_alert_success("{nrow(df)} market{?s} for dex {.val {dex}}, slot {format(df$slot[1], tz = 'UTC', usetz = TRUE)}")
  if (any(na > 0L)) {
    cli::cli_alert_info("NA cells kept (null or \"NaN\"): {paste(names(na)[na > 0L], na[na > 0L], sep = '=', collapse = ', ')}")
  }
  list(status = 0L, n_rows = nrow(df), n_na = na, reason = "")
}

# Returns the exit status (the guard below quits with it); testable.
.poll_hyperliquid_ctx_main <- function(args = commandArgs(trailingOnly = TRUE),
                                       post_fn = NULL) {
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
  pace <- suppressWarnings(as.numeric(opt("pace", HL_PACE_FRACTION)))
  if (is.na(pace) || pace <= 0 || pace > 1) {
    message("usage: --pace must be a number in (0, 1]")
    return(2L)
  }
  if (is.null(post_fn)) {
    # max_attempts = 1: a 429 is not backed off for 60 s inside a 5-minute job.
    post_fn <- hl_make_post(opt("raw-dir", "data/raw/hyperliquid"), pace = pace,
                            max_attempts = 1L)
  }
  res <- hl_ctx_poll(post_fn, out_dir = opt("out-dir", "data/dist"), dex = opt("dex", "xyz"))
  res$status
}

if (sys.nframe() == 0L) {
  quit(save = "no", status = .poll_hyperliquid_ctx_main())
}
