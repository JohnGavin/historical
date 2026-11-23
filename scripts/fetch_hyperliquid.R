#!/usr/bin/env Rscript
# Fetch Hyperliquid perpetual-futures daily candles, funding and OI (#870)
#
# WHAT THIS IS -- READ BEFORE USING THE OUTPUT
#   These are PERPETUAL FUTURES contracts on an on-chain venue (Hyperliquid).
#   They are NOT tokenised shares. A builder-dex market such as "xyz:TSLA" is a
#   perp whose price follows an oracle; it is not the TSLA stock and holds no
#   claim on it. Whether that oracle tracks Yahoo spot closely (the "oracle
#   basis") is UNVERIFIED. This script asserts NO equivalence between a
#   Hyperliquid perp and any spot series; `instrument_type = "perp"` is stamped
#   on every row for that reason.
#
# Source: POST https://api.hyperliquid.xyz/info (JSON body, no auth).
# Rate limit: documented 1200 weight/min per IP (HL_RATE_WEIGHT_PER_MIN). Requests
# are strictly sequential and PACED BY WEIGHT (hl_make_post): after each request
# the script sleeps so the running rate stays at or under pace x 1200/min
# (default pace 0.75). HTTP 429 is handled explicitly: back off (60 s, 3 attempts,
# logged); still limited -> that market is reported failed and the run is
# INDETERMINATE (exit 3), never silently skipped.
#
# Laptop runs: sleep and outages (#1088). A request that gets NO HTTP response (DNS,
# connect, timeout, reset) means the machine is offline, not that the market is bad.
# The fetcher then waits (15 s, 30 s, 60 s, then every 5 min), logs one line per
# wait, and retries the SAME request; a closed lid for an hour or two is ridden
# through. Time the process was suspended (the clock jumps) is logged and not
# counted; only AWAKE offline time counts toward the cap --max-offline-min
# (default 180 = 3 h). Past the cap the run stops cleanly: finished markets are
# written, the unfinished ones are NOT marked failed, exit 3, and the next
# `--resume` run continues. HTTP errors are different: 429 backs off as above, 5xx
# is retried 3 times, any other 4xx fails that market at once.
#
# Long runs are INCREMENTAL and RESUMABLE: parsed rows are upserted every
# --batch completed markets (default 10) and the completed markets are recorded
# in <out-dir>/hl_progress.txt only AFTER their rows are on disk. `--resume`
# skips markets recorded there (same --start/--intervals/--spot/--funding);
# failed markets are never recorded, so a resume retries them. A run that ends
# with status 0 deletes the progress file (the next run starts fresh).
#
# Outputs (under --out-dir, default data/dist; gitignored, never committed):
#   perp_daily.parquet          upsert on (dex, coin, date); volume_base is BASE
#                               units (not quote/notional); n_trades, traded
#                               (= n_trades > 0; pre-launch bars kept, flagged),
#                               close_time, market_class, is_delisted
#   perp_hourly.parquet         same columns, keyed (dex, coin, time) (UTC open).
#                               Separate files per interval because the keys
#                               differ (date vs time).
#   perp_15m.parquet / spot_15m.parquet
#                               same columns, 15-minute bars keyed (dex, coin,
#                               time) (UTC open). The API keeps ~5000 bars
#                               (~52 days), so run regularly (#1080).
#   spot_daily.parquet / spot_hourly.parquet
#                               spot pairs with non-zero 24h volume; same shape,
#                               instrument_type = "spot"
#   perp_funding_daily.parquet  upsert on (dex, coin, date); sum of hourly
#                               fundingRate + n_hours (partial days visible)
#   perp_funding.parquet        RAW funding rows keyed (dex, coin, time_ms):
#                               interval_hours (8 then 1, read from the gaps),
#                               rate_per_hour, offset_outlier. `premium` is NA
#                               when the API sends the string "NaN" (row kept
#                               and counted as n_premium_nan). A DELISTED
#                               market's funding stops at the close time of its
#                               last traded daily bar (it keeps emitting zero
#                               rows afterwards); a delisted market that never
#                               traded gets no funding request.
# Raw JSON responses are kept append-only under --raw-dir (default
# data/raw/hyperliquid/<UTC date>/, gitignored, never committed to git). They ARE
# published, by owner decision (2026-11-22): packed one tar per UTC day, gzipped members,
# to the public Hugging Face dataset under hyperliquid/raw/weekly/ (never file by file:
# a day holds ~10,000 files; scripts/hl_history_guard.R pack). Whether Hyperliquid's
# terms allow redistribution is not located (docs/DATA_SOURCES.md). The parquet files
# are derived from them.
#   perp_oi_snapshot.parquet    append, key (dex, coin, fetched_at). Open
#                               interest has NO history on this API: only the
#                               current snapshot exists, so it is never
#                               back-filled into the daily table.
#   perp_dexs.parquet           exchange reference table (#1084), upsert on dex:
#                               dex ("" = core), full_name (the API's `fullName`;
#                               NA for the core exchange, whose entry is `null`),
#                               fetched_at. Market long names and definitions are
#                               a separate table (scripts/fetch_hl_market_reference.R).
# The deployer-wallet fields of perpDexs are neither read nor persisted.
# This script publishes nothing. The tables are published to the public Hugging Face
# dataset (hyperliquid/<table>.parquet) by .github/workflows/hl-weekly.yml, which runs
# this script on top of the downloaded tables with --start derived from them
# (scripts/hl_history_guard.R start-date), because every run re-requests each market's
# funding history from --start: from the default 2023-01-01 that takes more than 9 hours.
# The one-off seed of the laptop's history is scripts/seed_hl_to_hf.R.
#
# Usage: Rscript scripts/fetch_hyperliquid.R [--out-dir=data/dist]
#                                            [--start=2023-01-01] [--pace=0.75]
#                                            [--raw-dir=data/raw/hyperliquid]
#                                            [--intervals=1d,1h] [--spot=true]
#                                            [--funding=true] [--resume]
#                                            [--batch=10] [--max-markets=N]
#                                            [--dexes=xyz] [--max-offline-min=180]
# (`--sleep` was removed: a fixed sleep cannot respect a weight-based limit.
# `--max-markets` fetches only the first N markets: a bounded smoke test.
# `--dexes=xyz,flx` limits the run to those exchanges (default: all). "" is the
# core exchange and spot pairs, so a run with --dexes skips them.)
#
# Exit status: 0 ok | 1 partial (some markets failed; successes still written)
#              | 3 INDETERMINATE (source unreachable, also past --max-offline-min /
#              HTTP error / rate-limited /
#              empty market list / an empty reply for a listed live market). 3 is
#              never "no data" and never 0.

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
  library(httr2)
  library(jsonlite)
})

HL_URL <- "https://api.hyperliquid.xyz/info"
# Documented API cap on candles per response; the API keeps only the most
# recent 5000 bars per interval (retention is a bar count, not a time window).
# One home: every retained-window calculation derives from this constant.
HL_CANDLE_PAGE_MAX <- 5000L
HL_FUNDING_PAGE_MAX <- 500L  # documented API cap on funding rows per response
.ms_day <- 86400000

# Rate limiting (one home; hl_volume_estimate.R uses these, it defines none).
HL_RATE_WEIGHT_PER_MIN <- 1200   # documented per-IP limit
HL_PACE_FRACTION <- 0.75         # 900 of 1200 weight/min: under the limit with margin
# Weight table (documented): every info request 20; candleSnapshot adds
# 1 per 60 bars returned, fundingHistory 1 per 20 rows returned.
HL_WEIGHT <- c(base = 20, candle_bars_per_unit = 60, funding_rows_per_unit = 20)
HL_429_BACKOFF_S <- 60           # wait after an HTTP 429
HL_429_MAX_ATTEMPTS <- 3L        # attempts per request (first try + retries)
HL_FLUSH_BATCH <- 10L            # completed markets per parquet flush
# Offline waiting (#1088): a request with no HTTP response is "offline", not "this
# market is bad". The fetcher waits and retries the SAME request: these waits in
# seconds, then every HL_OFFLINE_WAIT_MAX_S, until HL_MAX_OFFLINE_MIN minutes of
# AWAKE offline time have passed (override: --max-offline-min=).
HL_OFFLINE_WAITS_S <- c(15, 30, 60)
HL_OFFLINE_WAIT_MAX_S <- 300
HL_MAX_OFFLINE_MIN <- 180
# A wait that took this many seconds longer than asked means the process was
# suspended (laptop asleep); the suspended time is not offline time.
HL_CLOCK_JUMP_SLACK_S <- 60
HL_PROGRESS_FILE <- "hl_progress.txt"

# Candle intervals ingested (#1072, #1080): bar length in ms, one home.
# The API keeps the last HL_CANDLE_PAGE_MAX bars per interval, so 15m reaches
# back only ~52 days: it must be fetched regularly or that history is lost.
# 5m / 1m are later phases, deliberately not allowed yet.
HL_INTERVALS <- c("1d" = 86400000, "1h" = 3600000, "15m" = 900000)
# Intervals fetched when --intervals is absent: 15m is opt-in (behaviour of a
# plain run is unchanged).
HL_DEFAULT_INTERVALS <- c("1d", "1h")
# Output-file suffix per interval (hl_bars_path). The historical "daily" and
# "hourly" names are kept so existing files and consumers do not move.
HL_BAR_FILE_SUFFIX <- c("1d" = "daily", "1h" = "hourly", "15m" = "15m")

# Market classes (one vocabulary). Only the first three are in scope.
HL_MARKET_CLASSES <- c("main_perp", "builder_perp", "spot_pair",
                       "spot_unlisted", "outcome")
HL_IN_SCOPE_CLASSES <- c("main_perp", "builder_perp", "spot_pair")
HL_INSTRUMENT_TYPES <- c("perp", "spot")

# Funding timestamps are normally within ms of the hour; a row further past the
# hour than this (minutes) is FLAGGED (`offset_outlier`), never floored.
HL_FUNDING_OFFSET_MAX_MIN <- 5
# Funding interval lengths seen on the API (hours); each row's interval is the
# nearest of these to its gap from the previous row, never a hard-coded date.
HL_FUNDING_INTERVALS_H <- c(1, 8)

# ── Network layer ───────────────────────────────────────────────────
# `post_fn(body)` takes a named list and returns parsed JSON
# (simplifyVector = FALSE). Tests inject their own; this is the real one.
hl_unavailable <- function(msg) {
  cli::cli_abort(c("x" = "Hyperliquid source unavailable", "i" = msg),
                 class = "hl_source_unavailable")
}

# No HTTP response at all (DNS, connect, timeout, reset). It IS a
# hl_source_unavailable (callers that do not wait see no change), but
# hl_make_post can tell it from an HTTP error and wait the outage out (#1088).
hl_transport_failure <- function(msg) {
  cli::cli_abort(c("x" = "Hyperliquid source unavailable", "i" = msg),
                 class = c("hl_transport_error", "hl_source_unavailable"))
}

# `on_response(body, text)` (optional) receives the raw response text, used to
# keep raw JSON append-only (see hl_make_post / hl_save_raw).
hl_post <- function(body, url = HL_URL, timeout = 30, max_tries = 3,
                    on_response = NULL) {
  # 429 is NOT retried here (httr2 would retry it after 1-2 s, far too soon):
  # hl_make_post backs off explicitly. Only 5xx is retried; every HTTP status is
  # inspected below instead of raised by httr2.
  resp <- tryCatch(
    httr2::request(url) |>
      httr2::req_body_json(body, auto_unbox = TRUE, null = "null") |>
      httr2::req_timeout(timeout) |>
      httr2::req_retry(max_tries = max_tries,
                       is_transient = function(r) httr2::resp_status(r) %in%
                         c(500L, 502L, 503L, 504L),
                       backoff = ~ 2^.x) |>
      httr2::req_error(is_error = function(r) FALSE) |>
      httr2::req_perform(),
    # req_error(is_error = FALSE) means every error that reaches here has NO HTTP
    # response at all (DNS, connect, timeout, reset): the network, not the market.
    error = function(e) hl_transport_failure(conditionMessage(e))
  )
  status <- httr2::resp_status(resp)
  if (status == 429L) {
    cli::cli_abort(c("x" = "Hyperliquid rate limit (HTTP 429)",
                     "i" = "the request was refused for exceeding the per-IP weight limit"),
                   class = c("hl_rate_limited", "hl_source_unavailable"))
  }
  if (status >= 400L) hl_unavailable(sprintf("HTTP %d", status))
  text <- httr2::resp_body_string(resp)
  if (!is.null(on_response)) on_response(body, text)
  jsonlite::fromJSON(text, simplifyVector = FALSE)
}

# Filesystem-safe tag for a coin / dex name ("xyz:TSLA", "@107", "PURR/USDC").
hl_file_tag <- function(x) {
  x <- gsub("@", "at", x, fixed = TRUE)
  x <- gsub("#", "hash", x, fixed = TRUE)
  gsub("[^A-Za-z0-9._-]", "_", x)
}

# Append-only raw store: <raw_dir>/<UTC date>/<type>_<coin-or-dex>_<interval>.json.
# An existing file is NEVER overwritten: a time suffix (then a counter) is added.
#   `stem` / `ext` (optional) name a non-API file, e.g. a saved web page (#1084).
hl_save_raw <- function(body, text, raw_dir, now = Sys.time(), stem = NULL,
                        ext = "json") {
  now <- as.POSIXct(now, tz = "UTC")
  day_dir <- file.path(raw_dir, format(now, "%Y-%m-%d", tz = "UTC"))
  dir.create(day_dir, recursive = TRUE, showWarnings = FALSE)
  if (is.null(stem)) {
    tag <- body$coin %||% body$req$coin %||% body$dex %||% "all"
    itv <- body$req$interval %||% "na"
    stem <- sprintf("%s_%s_%s", body$type, hl_file_tag(tag), itv)
  }
  path <- file.path(day_dir, paste0(stem, ".", ext))
  if (file.exists(path)) {
    hms <- format(now, "%H%M%S", tz = "UTC")
    path <- file.path(day_dir, sprintf("%s_%s.%s", stem, hms, ext))
    k <- 1L
    while (file.exists(path)) {
      path <- file.path(day_dir, sprintf("%s_%s_%d.%s", stem, hms, k, ext))
      k <- k + 1L
    }
  }
  writeBin(charToRaw(text), path)  # exact response bytes
  invisible(path)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

hl_bad_arg <- function(what, why) {
  cli::cli_abort(c("x" = "Invalid {.arg {what}}", "i" = why),
                 class = "hl_bad_arg")
}

# Documented weight of one request (`rows` = rows returned, for the two paged
# types; NA counts as 0).
hl_weight <- function(type, rows = 0) {
  rows <- ifelse(is.na(rows), 0, rows)
  extra <- switch(type,
    candleSnapshot = floor(rows / HL_WEIGHT[["candle_bars_per_unit"]]),
    fundingHistory = floor(rows / HL_WEIGHT[["funding_rows_per_unit"]]),
    0)
  HL_WEIGHT[["base"]] + extra
}

# Seconds to sleep after a request of `weight` that took `elapsed` s, so the
# rate stays at or under pace x HL_RATE_WEIGHT_PER_MIN.
hl_pace_seconds <- function(weight, elapsed, pace = HL_PACE_FRACTION) {
  max(0, weight / (HL_RATE_WEIGHT_PER_MIN * pace / 60) - elapsed)
}

# Real network post_fn: records every response under `raw_dir`, PACES by weight
# and BACKS OFF on HTTP 429. `post`, `sleep_fn` and `clock` are injectable so
# tests never wait. `observer(entry)` (optional) sees every attempt (the volume
# estimate builds its request log from it). The returned function carries its
# running weight total in attr "hl_state" (see hl_weight_rate()).
# `capture_raw = TRUE` (the 5-minute poller, #1082) writes NO per-reply file: the
# reply's exact text is returned in attr "raw_text" of the parsed reply, and the
# caller writes one file per run. The default FALSE is the weekly fetch exactly as
# it was: one plain .json per reply under raw_dir, no attribute.
hl_make_post <- function(raw_dir, pace = HL_PACE_FRACTION, sleep_fn = Sys.sleep,
                         clock = function() proc.time()[["elapsed"]],
                         backoff_s = HL_429_BACKOFF_S,
                         max_attempts = HL_429_MAX_ATTEMPTS,
                         post = hl_post, observer = NULL, capture_raw = FALSE,
                         max_offline_min = 0,
                         wall = function() as.numeric(Sys.time()), ...) {
  force(raw_dir)
  if (!is.numeric(max_offline_min) || length(max_offline_min) != 1L ||
      is.na(max_offline_min) || max_offline_min < 0) {
    hl_bad_arg("max_offline_min", "must be a number >= 0 (0 = do not wait)")
  }
  if (!is.numeric(pace) || length(pace) != 1L || is.na(pace) || pace <= 0 || pace > 1) {
    hl_bad_arg("pace", "must be a number in (0, 1]")
  }
  state <- new.env()
  state$weight <- 0; state$t0 <- NA_real_; state$requests <- 0L
  state$n_429 <- 0L; state$clock <- clock
  fn <- function(body) {
    attempt <- 0L
    off <- NULL  # the current outage: since (wall secs), awake (secs waited), n
    repeat {
      attempt <- attempt + 1L
      t0 <- clock()
      if (is.na(state$t0)) state$t0 <- t0
      bytes <- NA_integer_
      raw_text <- NULL
      res <- tryCatch(
        post(body, ..., on_response = function(b, text) {
          bytes <<- nchar(text, type = "bytes")
          if (capture_raw) raw_text <<- text else hl_save_raw(b, text, raw_dir)
        }),
        error = function(e) e
      )
      el <- clock() - t0
      if (inherits(res, "hl_transport_error") && max_offline_min > 0) {
        if (!is.null(observer)) {
          observer(list(body = body, rows = NA_integer_, bytes = bytes, weight = 0,
                        elapsed = el, ok = FALSE, error = conditionMessage(res)))
        }
        if (is.null(off)) off <- list(since = wall(), awake = 0, n = 0L)
        if (off$awake >= max_offline_min * 60) {
          cli::cli_abort(c("x" = "Hyperliquid unreachable for {round(off$awake / 60)} min of awake time",
                           "i" = "the cap is {max_offline_min} min (--max-offline-min); no market is marked failed, progress is kept: run again with --resume"),
                         class = c("hl_offline_exhausted", "hl_source_unavailable"))
        }
        w <- if (off$n < length(HL_OFFLINE_WAITS_S)) HL_OFFLINE_WAITS_S[off$n + 1L] else
          HL_OFFLINE_WAIT_MAX_S
        message(sprintf("network down since %s, waiting; next try in %d s (%s)",
                        format(as.POSIXct(off$since, origin = "1970-01-01", tz = "UTC"),
                               "%Y-%m-%d %H:%M:%S UTC"),
                        as.integer(w), conditionMessage(res)))
        w0 <- wall()
        sleep_fn(w)
        took <- wall() - w0
        if (took > w + HL_CLOCK_JUMP_SLACK_S) {
          message(sprintf("clock jumped %d min: the machine was asleep (not counted as offline time)",
                          as.integer(round((took - w) / 60))))
          took <- w
        }
        off$awake <- off$awake + max(took, 0)
        off$n <- off$n + 1L
        next
      }
      ok <- !inherits(res, "error")
      rows <- if (ok && body$type %in% c("candleSnapshot", "fundingHistory") &&
                    is.list(res)) length(res) else NA_integer_
      w <- hl_weight(body$type, rows)
      state$weight <- state$weight + w
      state$requests <- state$requests + 1L
      if (!is.null(observer)) {
        observer(list(body = body, rows = rows, bytes = bytes, weight = w,
                      elapsed = el, ok = ok,
                      error = if (ok) "" else conditionMessage(res)))
      }
      sleep_fn(hl_pace_seconds(w, el, pace))
      if (ok) {
        if (!is.null(off)) {
          message(sprintf("network back after %d min awake offline", as.integer(round(off$awake / 60))))
        }
        if (capture_raw && !is.null(raw_text)) attr(res, "raw_text") <- raw_text
        return(res)
      }
      if (!inherits(res, "hl_rate_limited")) rlang::cnd_signal(res)
      state$n_429 <- state$n_429 + 1L
      if (attempt >= max_attempts) {
        cli::cli_abort(c("x" = "Hyperliquid still rate-limited after {attempt} attempt{?s}",
                         "i" = "backed off {backoff_s} s between attempts; the market is reported failed, never skipped"),
                       class = c("hl_rate_limited", "hl_source_unavailable"))
      }
      message(sprintf("HTTP 429 on %s: backing off %s s (attempt %d of %d)",
                      body$type, format(backoff_s), attempt, max_attempts))
      sleep_fn(backoff_s)
    }
  }
  attr(fn, "hl_state") <- state
  fn
}

# Observed weight per minute since the first request of a post_fn made by
# hl_make_post(); NA for any other post_fn or before the first request.
hl_weight_rate <- function(post_fn) {
  st <- attr(post_fn, "hl_state")
  if (is.null(st) || is.na(st$t0)) return(NA_real_)
  el <- st$clock() - st$t0
  if (el <= 0) return(NA_real_)
  st$weight / el * 60
}

# Generic start-time pager with a no-progress guard. `fetch_page(start_ms)`
# returns a list of records; `time_of(rec)` gives its ms timestamp. A page that
# is full (>= page_max) is followed by another request starting after its last
# record; if that start does not advance, abort rather than loop forever.
hl_page <- function(fetch_page, time_of, start_ms, end_ms, page_max,
                    max_pages = 1000L) {
  out <- list()
  cur <- start_ms
  for (i in seq_len(max_pages)) {
    page <- fetch_page(cur)
    if (length(page) == 0L) break
    out <- c(out, page)
    tmax <- max(vapply(page, time_of, numeric(1)))
    nxt <- tmax + 1
    if (nxt <= cur) {
      cli::cli_abort(c("x" = "Paging did not advance",
                       "i" = "page max time {tmax} <= request start {cur}"),
                     class = "hl_paging_stalled")
    }
    if (length(page) < page_max || nxt > end_ms) break
    cur <- nxt
  }
  out
}

hl_check_interval <- function(interval) {
  if (!is.character(interval) || length(interval) != 1L ||
      !interval %in% names(HL_INTERVALS)) {
    cli::cli_abort(c("x" = "Unsupported candle interval {.val {interval}}",
                     "i" = "Allowed: {.val {names(HL_INTERVALS)}}"),
                   class = "hl_bad_interval")
  }
  invisible(interval)
}

# `null` (unknown coin) is an ERROR, distinct from `[]` (empty window).
hl_reply_list <- function(x, what) {
  if (is.null(x)) {
    cli::cli_abort(c("x" = "{what}: reply was null",
                     "i" = "an unknown coin returns null; this is not an empty window"),
                   class = "hl_null_reply")
  }
  x
}

# ONE request per market per interval (the API keeps only the last
# HL_CANDLE_PAGE_MAX bars, so there is no candle pagination). With
# `clamp = TRUE` (live markets) the start is end - 5000 bars; a delisted market
# keeps its caller's `start_ms` because its retained bars are old.
hl_fetch_candles <- function(coin, start_ms, end_ms, post_fn = hl_post,
                             interval = "1d", clamp = TRUE) {
  hl_check_interval(interval)
  s <- if (clamp) {
    max(start_ms, end_ms - HL_CANDLE_PAGE_MAX * HL_INTERVALS[[interval]])
  } else {
    start_ms
  }
  hl_reply_list(
    post_fn(list(type = "candleSnapshot",
                 req = list(coin = coin, interval = interval,
                            startTime = s, endTime = end_ms))),
    paste("candleSnapshot", coin)
  )
}

# Pages by last `time + 1`; afterwards `(coin, time)` MUST be unique (an
# inclusive startTime would repeat the boundary row).
hl_fetch_funding <- function(coin, start_ms, end_ms, post_fn = hl_post,
                             page_max = HL_FUNDING_PAGE_MAX, ...) {
  out <- hl_page(
    function(s) hl_reply_list(
      post_fn(list(type = "fundingHistory", coin = coin,
                   startTime = s, endTime = end_ms)),
      paste("fundingHistory", coin)),
    function(r) as.numeric(r$time), start_ms, end_ms, page_max, ...
  )
  times <- vapply(out, function(r) as.numeric(r$time), numeric(1))
  if (anyDuplicated(times) > 0L) {
    cli::cli_abort(c("x" = "{coin}: duplicate funding timestamps after paging",
                     "i" = "{sum(duplicated(times))} repeated {.field time} value{?s}"),
                   class = "hl_duplicate_keys")
  }
  out
}

# ── Pure parsers (no network) ───────────────────────────────────────
# "xyz:TSLA" -> "TSLA"; bare "SOL" unchanged.
hl_bare_symbol <- function(coin) sub("^[^:]+:", "", coin)

# Strict numeric conversion: a non-missing input that fails to parse is an
# error, never a silent NA.
# `nan_ok = TRUE` is an explicit opt-in for ONE field family: the exact string
# "NaN" (case-sensitive; the API's only spelling in the raw replies, #1072)
# becomes NA. Every other non-numeric text ("nan", "NaN ", "Inf", "") still
# aborts. Only `premium` opts in.
hl_num <- function(x, what, nan_ok = FALSE) {
  x <- unlist(x, use.names = FALSE)
  if (is.numeric(x)) return(as.numeric(x))
  # Validate the text BEFORE converting, so as.numeric() never warns and a bad
  # value is an explicit error rather than a hidden coercion.
  num_re <- "^[-+]?([0-9]+\\.?[0-9]*|\\.[0-9]+)([eE][-+]?[0-9]+)?$"
  x <- as.character(x)
  if (nan_ok) x[!is.na(x) & x == "NaN"] <- NA_character_
  if (any(!is.na(x) & !grepl(num_re, x))) {
    cli::cli_abort("Non-numeric value in {.field {what}}")
  }
  as.numeric(x)
}

hl_require_fields <- function(recs, fields, what) {
  for (r in recs) {
    miss <- setdiff(fields, names(r))
    if (length(miss) > 0L) {
      cli::cli_abort(c("x" = "{what} record missing required field{?s}: {miss}"))
    }
  }
  invisible(TRUE)
}

# perpDexs -> character vector of dex names, "" = core dex (the null entry).
# Only `name` is read; wallet/deployer fields are ignored by design.
hl_parse_dexs <- function(x) {
  if (!is.list(x) || length(x) == 0L) {
    cli::cli_abort("perpDexs payload is empty or not a list")
  }
  vapply(x, function(d) if (is.null(d)) "" else as.character(d$name), character(1))
}

# perpDexs -> exchange reference table (#1084): dex ("" = core), full_name,
# fetched_at. Only `name` and `fullName` are read; the deployer / wallet /
# fee-recipient fields and the OI-cap list are never touched. The core exchange
# is the `null` first entry: the reply gives it neither a name nor a full name,
# so its full_name is NA (never typed in). A missing or empty `fullName` is NA.
# A duplicate exchange name aborts rather than silently keeping one.
hl_parse_perp_dexs <- function(x, fetched_at) {
  if (!is.list(x) || length(x) == 0L) {
    cli::cli_abort("perpDexs payload is empty or not a list")
  }
  rows <- lapply(x, function(d) {
    if (is.null(d)) return(list(dex = "", full_name = NA_character_))
    if (is.null(d$name) || !nzchar(as.character(d$name))) {
      cli::cli_abort("perpDexs entry has no {.field name}")
    }
    fn <- d$fullName
    list(dex = as.character(d$name),
         full_name = if (is.null(fn) || !nzchar(as.character(fn))) {
           NA_character_
         } else {
           as.character(fn)
         })
  })
  out <- data.frame(dex = vapply(rows, `[[`, character(1), "dex"),
                    full_name = vapply(rows, `[[`, character(1), "full_name"),
                    fetched_at = as.POSIXct(fetched_at, tz = "UTC"),
                    stringsAsFactors = FALSE)
  if (anyDuplicated(out$dex) > 0L) {
    cli::cli_abort(c("x" = "perpDexs lists an exchange twice",
                     "i" = "{.val {unique(out$dex[duplicated(out$dex)])}}"),
                   class = "hl_duplicate_keys")
  }
  out
}

# meta -> data.frame of markets for one dex. Empty universe is an error.
hl_parse_universe <- function(meta, dex = "") {
  u <- meta$universe
  if (is.null(u) || length(u) == 0L) {
    cli::cli_abort("Empty market list for dex {.val {dex}}",
                   class = "hl_empty_markets")
  }
  hl_require_fields(u, "name", "universe")
  data.frame(
    dex = dex,
    coin = vapply(u, function(m) as.character(m$name), character(1)),
    stringsAsFactors = FALSE
  ) |>
    mutate(symbol = hl_bare_symbol(coin))
}

# ── Market classes ──────────────────────────────────────────────────
# Classify by PREFIX and UNIVERSE MEMBERSHIP, never by prefix alone.
#   main_perp     bare name (BTC)
#   builder_perp  dex:NAME (xyz:TSLA)
#   spot_pair     "@N" or canonical "BASE/QUOTE" listed in spotMeta.universe
#   spot_unlisted "@N" NOT in spotMeta.universe (out of scope, counted)
#   outcome       "#<encoding>" HIP-4 outcome market (out of scope, counted)
# Any other form aborts: a new coin form must be a conscious decision.
hl_classify_coin <- function(coin, spot_universe = character()) {
  one <- function(cn) {
    if (grepl("^#[0-9]+$", cn)) return("outcome")
    if (grepl("^@[0-9]+$", cn)) {
      return(if (cn %in% spot_universe) "spot_pair" else "spot_unlisted")
    }
    if (grepl("^[^/@#:]+/[^/@#:]+$", cn) && cn %in% spot_universe) return("spot_pair")
    if (grepl("^[A-Za-z0-9._-]+:[A-Za-z0-9._-]+$", cn)) return("builder_perp")
    if (grepl("^[A-Za-z0-9._-]+$", cn)) return("main_perp")
    cli::cli_abort(c("x" = "Unrecognised market form {.val {cn}}",
                     "i" = "known classes: {.val {HL_MARKET_CLASSES}}"),
                   class = "hl_unknown_market_class")
  }
  vapply(coin, one, character(1), USE.NAMES = FALSE)
}

hl_empty_markets <- function() {
  data.frame(dex = character(), coin = character(), symbol = character(),
             market_class = character(), instrument_type = character(),
             is_delisted = logical(), day_ntl_vlm = numeric(),
             traded_24h = logical(), stringsAsFactors = FALSE)
}

# allPerpMetas -> perp markets, all exchanges (one request). The list is one
# meta per exchange; the exchange is read from the coin prefix. `isDelisted`
# is absent on live markets. Delisted markets are kept, flagged.
hl_parse_perp_markets <- function(apm) {
  if (!is.list(apm) || length(apm) == 0L) {
    cli::cli_abort("allPerpMetas payload is empty or not a list",
                   class = "hl_empty_markets")
  }
  rows <- lapply(apm, function(m) {
    u <- m$universe
    if (is.null(u) || length(u) == 0L) {
      cli::cli_abort("allPerpMetas holds an exchange with an empty universe",
                     class = "hl_empty_markets")
    }
    hl_require_fields(u, "name", "universe")
    data.frame(
      coin = vapply(u, function(r) as.character(r$name), character(1)),
      is_delisted = vapply(u, function(r) isTRUE(r$isDelisted), logical(1)),
      stringsAsFactors = FALSE
    )
  })
  df <- bind_rows(rows)
  cls <- hl_classify_coin(df$coin)
  if (!all(cls %in% c("main_perp", "builder_perp"))) {
    cli::cli_abort("allPerpMetas holds a non-perp market form",
                   class = "hl_unknown_market_class")
  }
  df |>
    mutate(dex = ifelse(cls == "builder_perp", sub(":.*$", "", coin), ""),
           symbol = hl_bare_symbol(coin), market_class = cls,
           instrument_type = "perp", day_ntl_vlm = NA_real_,
           traded_24h = NA) |>
    select(dex, coin, symbol, market_class, instrument_type, is_delisted,
           day_ntl_vlm, traded_24h)
}

# spotMeta (pair universe) + spotMetaAndAssetCtxs (contexts) -> list(
#   markets = spot pairs with 24h volume; out_of_scope = counts by class).
# Contexts are joined to the universe BY `coin`, never by position: there are
# more contexts than pairs and their order is not the universe order.
hl_parse_spot_markets <- function(spot_meta, spot_ctxs) {
  u <- spot_meta$universe
  if (is.null(u) || length(u) == 0L) {
    cli::cli_abort("spotMeta universe is empty", class = "hl_empty_markets")
  }
  if (!is.list(spot_ctxs) || length(spot_ctxs) != 2L) {
    cli::cli_abort("spotMetaAndAssetCtxs payload must be [meta, ctxs]")
  }
  ctx <- spot_ctxs[[2]]
  hl_require_fields(u, "name", "spotMeta universe")
  hl_require_fields(ctx, c("coin", "dayNtlVlm"), "spot asset ctx")
  universe <- vapply(u, function(r) as.character(r$name), character(1))
  ctx_coin <- vapply(ctx, function(r) as.character(r$coin), character(1))
  ctx_class <- hl_classify_coin(ctx_coin, universe)
  vlm <- stats::setNames(hl_num(lapply(ctx, `[[`, "dayNtlVlm"), "dayNtlVlm"),
                         ctx_coin)
  markets <- data.frame(
    dex = "", coin = universe, symbol = universe,
    market_class = "spot_pair", instrument_type = "spot", is_delisted = FALSE,
    day_ntl_vlm = unname(vlm[universe]), stringsAsFactors = FALSE
  ) |>
    mutate(traded_24h = day_ntl_vlm > 0)
  oos <- table(factor(ctx_class[!ctx_class %in% HL_IN_SCOPE_CLASSES],
                      levels = setdiff(HL_MARKET_CLASSES, HL_IN_SCOPE_CLASSES)))
  list(markets = markets,
       out_of_scope = data.frame(market_class = names(oos), n = as.integer(oos),
                                 stringsAsFactors = FALSE))
}

# One request each for allPerpMetas, spotMeta, spotMetaAndAssetCtxs.
hl_enumerate_markets <- function(post_fn = hl_post) {
  perps <- hl_parse_perp_markets(post_fn(list(type = "allPerpMetas")))
  spot <- hl_parse_spot_markets(post_fn(list(type = "spotMeta")),
                                post_fn(list(type = "spotMetaAndAssetCtxs")))
  list(markets = bind_rows(perps, spot$markets), out_of_scope = spot$out_of_scope)
}

hl_empty_bars <- function(interval = "1d") {
  hl_check_interval(interval)
  df <- data.frame(dex = character(), coin = character(),
                   symbol = character(), instrument_type = character(),
                   source = character(), open = numeric(), high = numeric(),
                   low = numeric(), close = numeric(), volume_base = numeric(),
                   n_trades = numeric(), traded = logical(),
                   stringsAsFactors = FALSE)
  key <- if (interval == "1d") {
    list(date = as.Date(character()))
  } else {
    list(time = as.POSIXct(character(), tz = "UTC"))
  }
  df <- cbind(as.data.frame(key), df)
  df$close_time <- as.POSIXct(character(), tz = "UTC")
  df
}
hl_empty_daily <- function() hl_empty_bars("1d")

# Drop the in-progress bar(s): every bar whose close time `T` is later than the
# fetch time. Returns list(kept, n_dropped); the caller reports the count.
hl_drop_in_progress <- function(x, fetch_ms) {
  if (length(x) == 0L) return(list(kept = x, n_dropped = 0L))
  hl_require_fields(x, "T", "candle")
  close_ms <- hl_num(lapply(x, `[[`, "T"), "T")
  keep <- close_ms <= fetch_ms
  list(kept = x[keep], n_dropped = sum(!keep))
}

# candleSnapshot -> bars data.frame. `v` is BASE volume (units of the asset),
# stored as volume_base; it is never converted to notional here. Pre-launch
# bars (v = 0, n = 0) are KEPT and flagged `traded = n > 0`. Daily bars key on
# `date`; hourly bars on `time` (UTC bar open).
hl_parse_candles <- function(x, dex = "", coin, interval = "1d",
                             instrument_type = "perp") {
  hl_check_interval(interval)
  if (!instrument_type %in% HL_INSTRUMENT_TYPES) {
    cli::cli_abort(c("x" = "Unsupported instrument type {.val {instrument_type}}",
                     "i" = "Allowed: {.val {HL_INSTRUMENT_TYPES}}"),
                   class = "hl_bad_instrument_type")
  }
  if (length(x) == 0L) return(hl_empty_bars(interval))
  hl_require_fields(x, c("t", "T", "o", "h", "l", "c", "v", "n"), "candle")
  t_ms <- hl_num(lapply(x, `[[`, "t"), "t")
  n_trades <- hl_num(lapply(x, `[[`, "n"), "n")
  t_posix <- as.POSIXct(t_ms / 1000, origin = "1970-01-01", tz = "UTC")
  body <- data.frame(
    dex = dex,
    coin = coin,
    symbol = hl_bare_symbol(coin),
    instrument_type = instrument_type,
    source = "hyperliquid",
    open = hl_num(lapply(x, `[[`, "o"), "o"),
    high = hl_num(lapply(x, `[[`, "h"), "h"),
    low = hl_num(lapply(x, `[[`, "l"), "l"),
    close = hl_num(lapply(x, `[[`, "c"), "c"),
    volume_base = hl_num(lapply(x, `[[`, "v"), "v"),
    n_trades = n_trades,
    traded = n_trades > 0,
    close_time = as.POSIXct(hl_num(lapply(x, `[[`, "T"), "T") / 1000,
                            origin = "1970-01-01", tz = "UTC"),
    stringsAsFactors = FALSE
  )
  key <- if (interval == "1d") {
    data.frame(date = as.Date(t_posix))
  } else {
    data.frame(time = t_posix)
  }
  keyname <- names(key)
  out <- cbind(key, body)
  out <- out[!duplicated(out[[keyname]]), , drop = FALSE]
  out <- out[order(out[[keyname]]), , drop = FALSE]
  rownames(out) <- NULL
  out
}

# Hourly fundingHistory -> one row per UTC date: sum of fundingRate and the
# number of hourly observations (24 = full day; fewer = partial day).
hl_parse_funding_daily <- function(x, dex = "", coin) {
  if (length(x) == 0L) {
    return(data.frame(date = as.Date(character()), dex = character(),
                      coin = character(), funding_sum = numeric(),
                      n_hours = integer(), stringsAsFactors = FALSE))
  }
  hl_require_fields(x, c("fundingRate", "time"), "funding")
  df <- data.frame(
    time_ms = hl_num(lapply(x, `[[`, "time"), "time"),
    rate = hl_num(lapply(x, `[[`, "fundingRate"), "fundingRate")
  )
  df$date <- as.Date(as.POSIXct(df$time_ms / 1000, origin = "1970-01-01", tz = "UTC"))
  df |>
    distinct(time_ms, .keep_all = TRUE) |>
    group_by(date) |>
    summarise(funding_sum = sum(rate), n_hours = dplyr::n(), .groups = "drop") |>
    mutate(dex = dex, coin = coin, .before = 1L) |>
    select(date, dex, coin, funding_sum, n_hours) |>
    arrange(date)
}

# Close time (ms) of the LAST bar with n > 0, from parsed daily bars; NA when
# the market has no traded bar (or no bar at all). Rounded: T arrives as an
# integer ms and the seconds round trip must not leave float dust.
hl_last_traded_close_ms <- function(daily) {
  if (is.null(daily) || nrow(daily) == 0L || !any(daily$traded)) return(NA_real_)
  round(as.numeric(max(daily$close_time[daily$traded])) * 1000)
}

# Funding for ONE market (owner decision on #1075): a delisted market keeps
# emitting hourly funding rows of exactly 0 after its last trade (observed on
# MATIC: 19,120 zero rows after the last candle), so its funding history stops
# at the close time of its last traded daily bar. A live market runs to `end_ms`.
# `cap`: "none" (live), "capped" (delisted, endTime = last traded bar close), or
# "no_traded_bar" (delisted, nothing ever traded: NO funding request is made).
# "no_traded_bar" is a known, counted state and neither a failure nor
# INDETERMINATE: the market's own bars say nothing traded, so there is nothing
# to fund; the caller reports the count.
hl_fetch_market_funding <- function(coin, delisted, daily, start_ms, end_ms,
                                    post_fn = hl_post, ...) {
  cap <- "none"; f_end <- end_ms
  if (isTRUE(delisted)) {
    last_ms <- hl_last_traded_close_ms(daily)
    if (is.na(last_ms)) {
      return(list(raw = list(), cap = "no_traded_bar", end_ms = NA_real_))
    }
    cap <- "capped"; f_end <- min(end_ms, last_ms)
  }
  list(raw = hl_fetch_funding(coin, start_ms, f_end, post_fn, ...),
       cap = cap, end_ms = f_end)
}

hl_empty_funding <- function() {
  data.frame(dex = character(), coin = character(), time_ms = numeric(),
             time = as.POSIXct(character(), tz = "UTC"),
             funding_rate = numeric(), premium = numeric(),
             interval_hours = numeric(), rate_per_hour = numeric(),
             offset_min = numeric(), offset_outlier = logical(),
             stringsAsFactors = FALSE)
}

# fundingHistory -> RAW rows (not summed). `interval_hours` is derived from the
# gap to the previous row (nearest of HL_FUNDING_INTERVALS_H; the first row
# takes its successor's), so the 8h -> 1h switch is read from the data, not a
# hard-coded date; `rate_per_hour = funding_rate / interval_hours`. A single row
# has no gap, so its interval and per-hour rate are NA (never guessed).
# `offset_min` is minutes past the hour; rows above HL_FUNDING_OFFSET_MAX_MIN
# are FLAGGED in `offset_outlier`, not floored and not dropped.
# `premium` may be the string "NaN" in the reply (#1072): stored as NA, row kept.
# `fundingRate` stays strict (no NaN seen in the data): a NaN rate aborts rather
# than silently entering `funding_sum`.
hl_parse_funding_raw <- function(x, dex = "", coin) {
  if (length(x) == 0L) return(hl_empty_funding())
  hl_require_fields(x, c("fundingRate", "premium", "time"), "funding")
  time_ms <- hl_num(lapply(x, `[[`, "time"), "time")
  if (anyDuplicated(time_ms) > 0L) {
    cli::cli_abort(c("x" = "{coin}: duplicate (coin, time) funding rows"),
                   class = "hl_duplicate_keys")
  }
  o <- order(time_ms)
  rate <- hl_num(lapply(x, `[[`, "fundingRate"), "fundingRate")[o]
  prem <- hl_num(lapply(x, `[[`, "premium"), "premium", nan_ok = TRUE)[o]
  time_ms <- time_ms[o]
  gap_h <- c(NA_real_, diff(time_ms)) / 3600000
  nearest <- function(g) {
    if (is.na(g)) return(NA_real_)
    HL_FUNDING_INTERVALS_H[which.min(abs(HL_FUNDING_INTERVALS_H - g))]
  }
  itv <- vapply(gap_h, nearest, numeric(1))
  if (length(itv) > 1L) itv[1] <- itv[2]
  offset_min <- (time_ms %% 3600000) / 60000
  data.frame(
    dex = dex, coin = coin, time_ms = time_ms,
    time = as.POSIXct(time_ms / 1000, origin = "1970-01-01", tz = "UTC"),
    funding_rate = rate, premium = prem,
    interval_hours = itv, rate_per_hour = rate / itv,
    offset_min = offset_min,
    offset_outlier = offset_min > HL_FUNDING_OFFSET_MAX_MIN,
    stringsAsFactors = FALSE
  )
}

# metaAndAssetCtxs -> current open-interest snapshot (no history exists).
hl_parse_oi_snapshot <- function(mac, dex = "", fetched_at) {
  if (!is.list(mac) || length(mac) != 2L) {
    cli::cli_abort("metaAndAssetCtxs payload must be [meta, ctxs]")
  }
  u <- mac[[1]]$universe
  ctx <- mac[[2]]
  if (length(u) == 0L || length(u) != length(ctx)) {
    cli::cli_abort("universe ({length(u)}) and asset contexts ({length(ctx)}) differ")
  }
  hl_require_fields(ctx, c("openInterest", "markPx"), "asset ctx")
  data.frame(
    fetched_at = fetched_at,
    dex = dex,
    coin = vapply(u, function(m) as.character(m$name), character(1)),
    open_interest_base = hl_num(lapply(ctx, `[[`, "openInterest"), "openInterest"),
    mark_px = hl_num(lapply(ctx, `[[`, "markPx"), "markPx"),
    stringsAsFactors = FALSE
  ) |>
    mutate(symbol = hl_bare_symbol(coin), instrument_type = "perp",
           source = "hyperliquid")
}

# ── Idempotent upsert ───────────────────────────────────────────────
# New rows win over existing rows with the same key. Atomic write via rename.
hl_upsert <- function(new, path, keys) {
  if (nrow(new) == 0L) return(invisible(path))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  combined <- if (file.exists(path)) {
    bind_rows(new, arrow::read_parquet(path))
  } else {
    new
  }
  combined <- combined |>
    distinct(across(all_of(keys)), .keep_all = TRUE) |>
    arrange(across(all_of(keys)))
  tmp <- paste0(path, ".tmp")
  arrow::write_parquet(combined, tmp)
  file.rename(tmp, path)
  invisible(path)
}

# ── Orchestration ───────────────────────────────────────────────────
# Returns list(status, failed, n_markets). Status 3 is raised for: dex list or
# core market list unreachable, an empty market list, or EVERY market failing
# because the source was unavailable. Per-market failures are isolated; what
# succeeded is written; status 1 reports them.
hl_bars_path <- function(out_dir, instrument_type, interval) {
  hl_check_interval(interval)
  file.path(out_dir, sprintf("%s_%s.parquet", instrument_type,
                             HL_BAR_FILE_SUFFIX[[interval]]))
}

# Keep only markets whose exchange is in `dexes` (NULL = all, behaviour
# unchanged). "" is the core exchange; spot pairs also have dex "", so a
# `dexes` without "" drops them. An unknown exchange name selects nothing and
# the caller's empty-market-list check turns that into INDETERMINATE.
hl_filter_dexes <- function(markets, dexes = NULL) {
  if (is.null(dexes)) return(markets)
  if (!is.character(dexes) || length(dexes) == 0L || anyNA(dexes)) {
    hl_bad_arg("dexes", "must be NULL or a character vector of exchange names")
  }
  markets[markets$dex %in% dexes, , drop = FALSE]
}

# An EMPTY reply for a listed, non-delisted market inside its retained window is
# INDETERMINATE (class hl_empty_reply), never a silent zero-row success.
hl_empty_reply <- function(what, coin) {
  cli::cli_abort(c("x" = "{coin}: empty {what} reply for a listed, live market",
                   "i" = "INDETERMINATE: cannot tell 'no data' from 'window outside retention'"),
                 class = "hl_empty_reply")
}

# ── Progress file (resume) ──────────────────────────────────────────
# Line 1: "# config: <fingerprint>"; then one done market key per line. A key is
# appended only AFTER that market's rows were upserted to parquet.
hl_run_fingerprint <- function(start, intervals, spot, funding) {
  paste(as.character(start), paste(sort(intervals), collapse = ","),
        spot, funding, sep = "|")
}

# Done keys recorded for the SAME configuration; a file of another configuration
# is stale and is removed (its markets were fetched with different settings).
hl_read_progress <- function(path, fp) {
  if (!file.exists(path)) return(character())
  lines <- readLines(path, warn = FALSE)
  if (length(lines) == 0L || !identical(lines[1], paste0("# config: ", fp))) {
    message("Resume: progress file is from a different configuration; starting fresh")
    file.remove(path)
    return(character())
  }
  lines[-1]
}

hl_append_progress <- function(path, fp, keys) {
  if (length(keys) == 0L) return(invisible(path))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (!file.exists(path)) writeLines(paste0("# config: ", fp), path)
  cat(paste0(keys, "\n"), file = path, sep = "", append = TRUE)
  invisible(path)
}

hl_fmt_hms <- function(s) {
  s <- round(s)
  sprintf("%d:%02d:%02d", s %/% 3600, (s %% 3600) %/% 60, s %% 60)
}

# Returns list(status, failed, n_markets, n_done, n_skipped, n_failed,
# n_not_attempted, n_in_progress_dropped, out_of_scope, ...).
# Status 3 (INDETERMINATE) is raised for: an unreachable / empty market list,
# EVERY request failing as unavailable, any live market with an empty reply, a
# market still rate-limited (HTTP 429) after its back-off attempts, or
# `max_rate_limited` consecutive rate-limited markets (the run stops; the rest
# is counted in n_not_attempted). Successes are still written. Other per-market
# failures are isolated and give status 1.
#
# Writes are INCREMENTAL: every `batch` completed markets (and on exit, also on
# an interrupt) the buffered rows are upserted and the markets are recorded in
# the progress file. A batch, not each market, because every upsert rewrites
# the whole parquet file (the hourly file reaches millions of rows); at ~35 s
# per market the worst case loss of a hard kill is `batch` markets, minutes.
# `resume = TRUE` skips markets recorded as done; `max_markets` keeps only the
# first N markets (smoke test).
hl_run <- function(post_fn = hl_post, out_dir = "data/dist",
                   start = as.Date("2023-01-01"), end = Sys.time(),
                   now = format(Sys.time(), tz = "UTC", usetz = TRUE),
                   intervals = HL_DEFAULT_INTERVALS, spot = TRUE,
                   funding = TRUE, resume = FALSE, batch = HL_FLUSH_BATCH,
                   max_markets = NULL, max_rate_limited = 3L, dexes = NULL) {
  invisible(lapply(intervals, hl_check_interval))
  if (!is.numeric(batch) || length(batch) != 1L || is.na(batch) || batch < 1) {
    hl_bad_arg("batch", "must be a whole number >= 1")
  }
  if (!is.null(max_markets) &&
      (!is.numeric(max_markets) || length(max_markets) != 1L ||
         is.na(max_markets) || max_markets < 1)) {
    hl_bad_arg("max_markets", "must be NULL or a whole number >= 1")
  }
  start_ms <- as.numeric(as.POSIXct(start, tz = "UTC")) * 1000
  end_ms <- floor(as.numeric(end) * 1000)
  t_run <- Sys.time()

  indeterminate <- function(why) {
    cli::cli_alert_danger("INDETERMINATE: {why}")
    list(status = 3L, failed = data.frame(), n_markets = 0L, reason = why,
         n_in_progress_dropped = 0L, out_of_scope = data.frame())
  }

  enum <- tryCatch(hl_enumerate_markets(post_fn), error = function(e) e)
  if (inherits(enum, "error")) return(indeterminate(conditionMessage(enum)))
  markets <- enum$markets
  if (!spot) markets <- markets[markets$instrument_type == "perp", ]
  markets <- hl_filter_dexes(markets, dexes)
  # Spot: only pairs with non-zero 24h volume are fetched (issue #1072, Phase 1).
  markets <- markets[markets$instrument_type == "perp" |
                       (!is.na(markets$traded_24h) & markets$traded_24h), ]
  if (!is.null(max_markets)) markets <- utils::head(markets, max_markets)
  if (nrow(markets) == 0L) return(indeterminate("empty market list"))
  failed <- list()

  fp <- hl_run_fingerprint(start, intervals, spot, funding)
  prog_path <- file.path(out_dir, HL_PROGRESS_FILE)
  if (resume) {
    done_keys <- hl_read_progress(prog_path, fp)
  } else {
    done_keys <- character()
    if (file.exists(prog_path)) file.remove(prog_path)
  }
  mk_keys <- paste0(markets$dex, ":", markets$coin)
  todo <- which(!mk_keys %in% done_keys)
  n_skipped <- nrow(markets) - length(todo)
  if (n_skipped > 0L) {
    message(sprintf("Resume: skipping %d market(s) already done; %d to fetch",
                    n_skipped, length(todo)))
  }

  # Buffer of completed markets, flushed to parquet + progress file.
  new_buf <- function() list(bars = list(), funding_raw = list(),
                             funding_daily = list(), done = character())
  buf <- new_buf()
  flush <- function() {
    if (length(buf$done) == 0L) return(invisible(NULL))
    b <- buf
    # Parsed parquet is DERIVED from the raw JSON kept under data/raw/ (see
    # hl_make_post); nothing here is ever uploaded.
    for (nm in names(b$bars)) {
      parts <- strsplit(nm, " ", fixed = TRUE)[[1]]
      keyc <- if (parts[2] == "1d") "date" else "time"
      hl_upsert(bind_rows(b$bars[[nm]]), hl_bars_path(out_dir, parts[1], parts[2]),
                c("dex", "coin", keyc))
    }
    hl_upsert(bind_rows(b$funding_daily), file.path(out_dir, "perp_funding_daily.parquet"),
              c("dex", "coin", "date"))
    hl_upsert(bind_rows(b$funding_raw), file.path(out_dir, "perp_funding.parquet"),
              c("dex", "coin", "time_ms"))
    # Only now are these markets complete.
    hl_append_progress(prog_path, fp, b$done)
    buf <<- new_buf()
    invisible(NULL)
  }
  on.exit(flush(), add = TRUE)

  n_ok <- 0L; n_dropped <- 0L; cap_rows <- list()
  n_rl_streak <- 0L; aborted_rl <- FALSE; n_premium_nan <- 0L
  aborted_offline <- FALSE
  for (j in seq_along(todo)) {
    i <- todo[j]
    dex <- markets$dex[i]; coin <- markets$coin[i]
    itype <- markets$instrument_type[i]; delisted <- markets$is_delisted[i]
    cls <- markets$market_class[i]
    key <- mk_keys[i]
    r <- tryCatch({
      out <- list(bars = list(), n_dropped = 0L, cap = "none")
      # Daily bars FIRST: a delisted market's funding end time comes from them.
      for (itv in intervals[order(intervals != "1d")]) {
        c_raw <- hl_fetch_candles(coin, start_ms, end_ms, post_fn,
                                  interval = itv, clamp = !delisted)
        if (length(c_raw) == 0L && !delisted) hl_empty_reply("candle", coin)
        dp <- hl_drop_in_progress(c_raw, end_ms)
        out$n_dropped <- out$n_dropped + dp$n_dropped
        out$bars[[itv]] <- hl_parse_candles(dp$kept, dex, coin, itv, itype) |>
          mutate(market_class = cls, is_delisted = delisted)
      }
      if (funding && itype == "perp") {
        daily <- out$bars[["1d"]]
        if (is.null(daily) && delisted) {
          # `--intervals` without 1d: the cap still needs the daily bars (not stored)
          d_raw <- hl_fetch_candles(coin, start_ms, end_ms, post_fn,
                                    interval = "1d", clamp = FALSE)
          daily <- hl_parse_candles(hl_drop_in_progress(d_raw, end_ms)$kept,
                                    dex, coin, "1d", itype)
        }
        mf <- hl_fetch_market_funding(coin, delisted, daily, start_ms, end_ms,
                                      post_fn)
        out$cap <- mf$cap
        out$cap_end_ms <- mf$end_ms
        f_raw <- mf$raw
        if (length(f_raw) == 0L && !delisted) hl_empty_reply("funding", coin)
        out$f_raw <- hl_parse_funding_raw(f_raw, dex, coin)
        out$n_premium_nan <- sum(is.na(out$f_raw$premium))
        out$f_daily <- hl_parse_funding_daily(f_raw, dex, coin)
      }
      out
    }, error = function(e) e)
    if (inherits(r, "hl_offline_exhausted")) {
      # The network stayed down past the cap (#1088): this market is NOT bad and
      # neither are the rest. Stop; flush() below records what is done; a
      # --resume run continues from here.
      aborted_offline <- TRUE
      cli::cli_alert_danger("{key}: not fetched, network unreachable ({conditionMessage(r)})")
      break
    }
    if (inherits(r, "error")) {
      rl <- inherits(r, "hl_rate_limited")
      failed[[key]] <- list(reason = conditionMessage(r),
                            unavailable = inherits(r, "hl_source_unavailable"),
                            indeterminate = inherits(r, "hl_empty_reply") || rl)
      n_rl_streak <- if (rl) n_rl_streak + 1L else 0L
      outcome <- "FAILED"
      cli::cli_alert_danger("{key}: FAILED ({conditionMessage(r)})")
    } else {
      n_rl_streak <- 0L
      for (itv in names(r$bars)) {
        buf$bars[[paste(itype, itv)]][[key]] <- r$bars[[itv]]
      }
      if (!is.null(r$f_raw)) {
        buf$funding_raw[[key]] <- r$f_raw; buf$funding_daily[[key]] <- r$f_daily
        n_premium_nan <- n_premium_nan + r$n_premium_nan
      }
      n_dropped <- n_dropped + r$n_dropped
      if (r$cap != "none") {
        cap_rows[[key]] <- data.frame(item = key, cap = r$cap,
                                      funding_end_ms = r$cap_end_ms,
                                      stringsAsFactors = FALSE)
      }
      buf$done <- c(buf$done, key)
      n_ok <- n_ok + 1L
      outcome <- "done"
      if (length(buf$done) >= batch) flush()
    }
    rate <- hl_weight_rate(post_fn)
    message(sprintf("[%d/%d] %s %s | elapsed %s | %s weight/min", j, length(todo), key,
                    outcome, hl_fmt_hms(as.numeric(difftime(Sys.time(), t_run, units = "secs"))),
                    if (is.na(rate)) "n/a" else format(round(rate))))
    if (n_rl_streak >= max_rate_limited) {
      aborted_rl <- TRUE
      break
    }
  }
  flush()
  n_failed <- length(failed)
  n_not_attempted <- length(todo) - n_ok - n_failed
  message(sprintf("Markets: %d done, %d skipped as already done, %d failed, %d not attempted",
                  n_ok, n_skipped, n_failed, n_not_attempted))
  cli::cli_inform("Dropped {n_dropped} in-progress bar{?s} (close time after fetch time)")
  funding_cap <- if (length(cap_rows) > 0L) {
    bind_rows(cap_rows)
  } else {
    data.frame(item = character(), cap = character(),
               funding_end_ms = numeric(), stringsAsFactors = FALSE)
  }
  n_capped <- sum(funding_cap$cap == "capped")
  n_no_traded <- sum(funding_cap$cap == "no_traded_bar")
  if (funding) {
    cli::cli_inform(c(
      "Funding capped at the last traded bar for {n_capped} delisted market{?s}",
      "i" = "{n_no_traded} delisted market{?s} with no traded bar: no funding requested (not a failure)"
    ))
    cli::cli_inform("{n_premium_nan} funding row{?s} with premium \"NaN\" stored as NA (rows kept)")
  }

  # Open-interest snapshot: one call per perp exchange, current values only
  # (skipped when the run stopped on repeated rate limiting).
  oi <- list()
  if (!aborted_rl && !aborted_offline) {
    for (d in unique(markets$dex[markets$instrument_type == "perp"])) {
      body <- if (nzchar(d)) list(type = "metaAndAssetCtxs", dex = d) else list(type = "metaAndAssetCtxs")
      s <- tryCatch(hl_parse_oi_snapshot(post_fn(body), d, now), error = function(e) e)
      if (inherits(s, "error")) {
        failed[[paste0("oi:", d)]] <- list(reason = conditionMessage(s),
                                           unavailable = inherits(s, "hl_source_unavailable"),
                                           indeterminate = inherits(s, "hl_rate_limited"))
      } else {
        oi[[d]] <- s
      }
    }
    hl_upsert(bind_rows(oi), file.path(out_dir, "perp_oi_snapshot.parquet"),
              c("dex", "coin", "fetched_at"))

    # Exchange reference table (#1084): one request, upsert on dex. A failure is
    # reported like an OI failure (never silently skipped).
    dx <- tryCatch(hl_parse_perp_dexs(post_fn(list(type = "perpDexs")), Sys.time()),
                   error = function(e) e)
    if (inherits(dx, "error")) {
      failed[["perpDexs"]] <- list(reason = conditionMessage(dx),
                                   unavailable = inherits(dx, "hl_source_unavailable"),
                                   indeterminate = inherits(dx, "hl_rate_limited"))
    } else {
      hl_upsert(dx, file.path(out_dir, "perp_dexs.parquet"), "dex")
    }
  }

  failed_df <- data.frame(
    item = names(failed),
    reason = vapply(failed, `[[`, character(1), "reason"),
    stringsAsFactors = FALSE
  )
  all_unavailable <- n_ok == 0L && length(failed) > 0L &&
    all(vapply(failed, `[[`, logical(1), "unavailable"))
  if (all_unavailable) {
    ind <- indeterminate("every request failed: source unavailable")
    ind[c("failed", "n_markets", "n_done", "n_skipped", "n_failed", "n_not_attempted")] <-
      list(failed_df, nrow(markets), n_ok, n_skipped, n_failed, n_not_attempted)
    return(ind)
  }
  any_indeterminate <- aborted_rl || aborted_offline ||
    any(vapply(failed, `[[`, logical(1), "indeterminate"))
  status <- if (any_indeterminate) 3L else if (nrow(failed_df) > 0L) 1L else 0L
  if (aborted_rl) {
    cli::cli_alert_danger("INDETERMINATE: stopped after {max_rate_limited} consecutive rate-limited markets; {n_not_attempted} not attempted")
  }
  if (aborted_offline) {
    cli::cli_alert_danger("INDETERMINATE: network unreachable past the offline cap; {n_not_attempted} not attempted; run again with --resume")
  }
  # A run that finished clean is complete: the next run starts fresh.
  if (status == 0L && file.exists(prog_path)) file.remove(prog_path)

  list(status = status,
       failed = failed_df, n_markets = nrow(markets),
       n_done = n_ok, n_skipped = n_skipped, n_failed = n_failed,
       n_not_attempted = n_not_attempted,
       n_in_progress_dropped = n_dropped, out_of_scope = enum$out_of_scope,
       n_premium_nan = n_premium_nan, n_funding_capped = n_capped, n_funding_no_traded_bar = n_no_traded,
       funding_cap = funding_cap)
}

.fetch_hyperliquid_main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  opt <- function(name, default) {
    hit <- grep(paste0("^--", name, "="), args, value = TRUE)
    if (length(hit) == 0L) default else sub(paste0("^--", name, "="), "", hit[1])
  }
  if (any(grepl("^--sleep", args))) {
    cli_alert_warning("--sleep was removed and is ignored: requests are paced by weight (--pace)")
  }
  mm <- opt("max-markets", NA_character_)
  dx <- opt("dexes", NA_character_)
  cli_h1("Hyperliquid fetch (perpetual futures and spot pairs, NOT tokenised shares)")
  max_off <- suppressWarnings(as.numeric(opt("max-offline-min", HL_MAX_OFFLINE_MIN)))
  if (is.na(max_off) || max_off < 0) {
    cli_alert_danger("--max-offline-min must be a number >= 0 (minutes)")
    quit(save = "no", status = 2L)
  }
  res <- hl_run(post_fn = hl_make_post(opt("raw-dir", "data/raw/hyperliquid"),
                                       pace = as.numeric(opt("pace", HL_PACE_FRACTION)),
                                       max_offline_min = max_off),
                out_dir = opt("out-dir", "data/dist"),
                start = as.Date(opt("start", "2023-01-01")),
                intervals = strsplit(opt("intervals", paste(HL_DEFAULT_INTERVALS, collapse = ",")), ",", fixed = TRUE)[[1]],
                spot = !identical(opt("spot", "true"), "false"),
                funding = !identical(opt("funding", "true"), "false"),
                dexes = if (is.na(dx)) NULL else strsplit(dx, ",", fixed = TRUE)[[1]],
                resume = "--resume" %in% args,
                batch = as.integer(opt("batch", HL_FLUSH_BATCH)),
                max_markets = if (is.na(mm)) NULL else as.integer(mm))
  if (res$status == 3L) {
    if (nrow(res$failed) > 0L) print(res$failed, row.names = FALSE)
    quit(save = "no", status = 3L)
  }
  if (res$status == 1L) {
    cli_alert_danger("{nrow(res$failed)} item(s) failed")
    print(res$failed, row.names = FALSE)
    quit(save = "no", status = 1L)
  }
  cli_alert_success("{res$n_done} markets written, {res$n_skipped} skipped as already done")
  invisible(TRUE)
}

if (sys.nframe() == 0L) {
  .fetch_hyperliquid_main()
}
