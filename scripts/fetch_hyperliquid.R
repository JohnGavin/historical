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
# Rate limits are UNVERIFIED; requests are strictly sequential with a polite
# sleep between calls and bounded retries.
#
# Outputs (under --out-dir, default data/dist; gitignored, never committed):
#   perp_daily.parquet          upsert on (dex, coin, date); volume_base is BASE
#                               units (not quote/notional); n_trades, traded
#                               (= n_trades > 0; pre-launch bars kept, flagged),
#                               close_time, market_class, is_delisted
#   perp_hourly.parquet         same columns, keyed (dex, coin, time) (UTC open).
#                               Separate files per interval because the keys
#                               differ (date vs time).
#   spot_daily.parquet / spot_hourly.parquet
#                               spot pairs with non-zero 24h volume; same shape,
#                               instrument_type = "spot"
#   perp_funding_daily.parquet  upsert on (dex, coin, date); sum of hourly
#                               fundingRate + n_hours (partial days visible)
#   perp_funding.parquet        RAW funding rows keyed (dex, coin, time_ms):
#                               interval_hours (8 then 1, read from the gaps),
#                               rate_per_hour, offset_outlier
# Raw JSON responses are kept append-only under --raw-dir (default
# data/raw/hyperliquid/<UTC date>/, gitignored, NEVER uploaded or redistributed);
# the parquet files are derived from them.
#   perp_oi_snapshot.parquet    append, key (dex, coin, fetched_at). Open
#                               interest has NO history on this API: only the
#                               current snapshot exists, so it is never
#                               back-filled into the daily table.
# The deployer-wallet fields of perpDexs are neither read nor persisted.
# Publication of these files is a documented follow-up, not done here.
#
# Usage: Rscript scripts/fetch_hyperliquid.R [--out-dir=data/dist]
#                                            [--start=2023-01-01] [--sleep=0.3]
#                                            [--raw-dir=data/raw/hyperliquid]
#                                            [--intervals=1d,1h] [--spot=true]
#                                            [--funding=true]
#
# Exit status: 0 ok | 1 partial (some markets failed; successes still written)
#              | 3 INDETERMINATE (source unreachable / HTTP error / empty market
#              list / an empty reply for a listed live market). 3 is never "no
#              data" and never 0.

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

# Candle intervals ingested in Phase 1 (#1072): bar length in ms, one home.
# 15m / 5m / 1m are later phases, deliberately not allowed yet.
HL_INTERVALS <- c("1d" = 86400000, "1h" = 3600000)

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

# `on_response(body, text)` (optional) receives the raw response text, used to
# keep raw JSON append-only (see hl_make_post / hl_save_raw).
hl_post <- function(body, url = HL_URL, timeout = 30, max_tries = 3,
                    on_response = NULL) {
  resp <- tryCatch(
    httr2::request(url) |>
      httr2::req_body_json(body, auto_unbox = TRUE, null = "null") |>
      httr2::req_timeout(timeout) |>
      httr2::req_retry(max_tries = max_tries, backoff = ~ 2^.x) |>
      httr2::req_perform(),
    error = function(e) hl_unavailable(conditionMessage(e))
  )
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
hl_save_raw <- function(body, text, raw_dir, now = Sys.time()) {
  now <- as.POSIXct(now, tz = "UTC")
  day_dir <- file.path(raw_dir, format(now, "%Y-%m-%d", tz = "UTC"))
  dir.create(day_dir, recursive = TRUE, showWarnings = FALSE)
  tag <- body$coin %||% body$req$coin %||% body$dex %||% "all"
  itv <- body$req$interval %||% "na"
  stem <- sprintf("%s_%s_%s", body$type, hl_file_tag(tag), itv)
  path <- file.path(day_dir, paste0(stem, ".json"))
  if (file.exists(path)) {
    hms <- format(now, "%H%M%S", tz = "UTC")
    path <- file.path(day_dir, sprintf("%s_%s.json", stem, hms))
    k <- 1L
    while (file.exists(path)) {
      path <- file.path(day_dir, sprintf("%s_%s_%d.json", stem, hms, k))
      k <- k + 1L
    }
  }
  writeBin(charToRaw(text), path)  # exact response bytes
  invisible(path)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Real network post_fn that records every response under `raw_dir`.
hl_make_post <- function(raw_dir, ...) {
  force(raw_dir)
  function(body) {
    hl_post(body, ..., on_response = function(b, text) {
      hl_save_raw(b, text, raw_dir)
    })
  }
}

# Generic start-time pager with a no-progress guard. `fetch_page(start_ms)`
# returns a list of records; `time_of(rec)` gives its ms timestamp. A page that
# is full (>= page_max) is followed by another request starting after its last
# record; if that start does not advance, abort rather than loop forever.
hl_page <- function(fetch_page, time_of, start_ms, end_ms, page_max,
                    sleep_fn = Sys.sleep, sleep = 0.3, max_pages = 1000L) {
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
    sleep_fn(sleep)
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
hl_num <- function(x, what) {
  x <- unlist(x, use.names = FALSE)
  out <- suppressWarnings(as.numeric(x))
  if (any(is.na(out) & !is.na(x))) {
    cli::cli_abort("Non-numeric value in {.field {what}}")
  }
  out
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
  prem <- hl_num(lapply(x, `[[`, "premium"), "premium")[o]
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
  file.path(out_dir, sprintf("%s_%s.parquet", instrument_type,
                             if (interval == "1d") "daily" else "hourly"))
}

# An EMPTY reply for a listed, non-delisted market inside its retained window is
# INDETERMINATE (class hl_empty_reply), never a silent zero-row success.
hl_empty_reply <- function(what, coin) {
  cli::cli_abort(c("x" = "{coin}: empty {what} reply for a listed, live market",
                   "i" = "INDETERMINATE: cannot tell 'no data' from 'window outside retention'"),
                 class = "hl_empty_reply")
}

# Returns list(status, failed, n_markets, n_in_progress_dropped, out_of_scope).
# Status 3 (INDETERMINATE) is raised for: an unreachable / empty market list,
# EVERY request failing as unavailable, or any live market with an empty reply
# (successes are still written). Other per-market failures are isolated and
# give status 1.
hl_run <- function(post_fn = hl_post, out_dir = "data/dist",
                   start = as.Date("2023-01-01"), end = Sys.time(),
                   sleep_fn = Sys.sleep, sleep = 0.3,
                   now = format(Sys.time(), tz = "UTC", usetz = TRUE),
                   intervals = names(HL_INTERVALS), spot = TRUE,
                   funding = TRUE) {
  invisible(lapply(intervals, hl_check_interval))
  start_ms <- as.numeric(as.POSIXct(start, tz = "UTC")) * 1000
  end_ms <- floor(as.numeric(end) * 1000)

  indeterminate <- function(why) {
    cli::cli_alert_danger("INDETERMINATE: {why}")
    list(status = 3L, failed = data.frame(), n_markets = 0L, reason = why,
         n_in_progress_dropped = 0L, out_of_scope = data.frame())
  }

  enum <- tryCatch(hl_enumerate_markets(post_fn), error = function(e) e)
  if (inherits(enum, "error")) return(indeterminate(conditionMessage(enum)))
  markets <- enum$markets
  if (!spot) markets <- markets[markets$instrument_type == "perp", ]
  # Spot: only pairs with non-zero 24h volume are fetched (issue #1072, Phase 1).
  markets <- markets[markets$instrument_type == "perp" |
                       (!is.na(markets$traded_24h) & markets$traded_24h), ]
  if (nrow(markets) == 0L) return(indeterminate("empty market list"))
  failed <- list()

  bars <- list(); funding_raw <- list(); funding_daily <- list()
  n_ok <- 0L; n_dropped <- 0L
  for (i in seq_len(nrow(markets))) {
    dex <- markets$dex[i]; coin <- markets$coin[i]
    itype <- markets$instrument_type[i]; delisted <- markets$is_delisted[i]
    cls <- markets$market_class[i]
    key <- paste0(dex, ":", coin)
    r <- tryCatch({
      out <- list(bars = list(), n_dropped = 0L)
      for (itv in intervals) {
        c_raw <- hl_fetch_candles(coin, start_ms, end_ms, post_fn,
                                  interval = itv, clamp = !delisted)
        sleep_fn(sleep)
        if (length(c_raw) == 0L && !delisted) hl_empty_reply("candle", coin)
        dp <- hl_drop_in_progress(c_raw, end_ms)
        out$n_dropped <- out$n_dropped + dp$n_dropped
        out$bars[[itv]] <- hl_parse_candles(dp$kept, dex, coin, itv, itype) |>
          mutate(market_class = cls, is_delisted = delisted)
      }
      if (funding && itype == "perp") {
        f_raw <- hl_fetch_funding(coin, start_ms, end_ms, post_fn,
                                  sleep_fn = sleep_fn, sleep = sleep)
        sleep_fn(sleep)
        if (length(f_raw) == 0L && !delisted) hl_empty_reply("funding", coin)
        out$f_raw <- hl_parse_funding_raw(f_raw, dex, coin)
        out$f_daily <- hl_parse_funding_daily(f_raw, dex, coin)
      }
      out
    }, error = function(e) e)
    if (inherits(r, "error")) {
      failed[[key]] <- list(reason = conditionMessage(r),
                            unavailable = inherits(r, "hl_source_unavailable"),
                            indeterminate = inherits(r, "hl_empty_reply"))
      cli::cli_alert_danger("{key}: FAILED ({conditionMessage(r)})")
    } else {
      for (itv in names(r$bars)) {
        bars[[paste(itype, itv)]][[key]] <- r$bars[[itv]]
      }
      if (!is.null(r$f_raw)) {
        funding_raw[[key]] <- r$f_raw; funding_daily[[key]] <- r$f_daily
      }
      n_dropped <- n_dropped + r$n_dropped
      n_ok <- n_ok + 1L
    }
  }
  cli::cli_inform("Dropped {n_dropped} in-progress bar{?s} (close time after fetch time)")

  # Open-interest snapshot: one call per perp exchange, current values only.
  oi <- list()
  for (d in unique(markets$dex[markets$instrument_type == "perp"])) {
    body <- if (nzchar(d)) list(type = "metaAndAssetCtxs", dex = d) else list(type = "metaAndAssetCtxs")
    s <- tryCatch(hl_parse_oi_snapshot(post_fn(body), d, now), error = function(e) e)
    if (inherits(s, "error")) {
      failed[[paste0("oi:", d)]] <- list(reason = conditionMessage(s),
                                         unavailable = inherits(s, "hl_source_unavailable"),
                                         indeterminate = FALSE)
    } else {
      oi[[d]] <- s
    }
    sleep_fn(sleep)
  }

  failed_df <- data.frame(
    item = names(failed),
    reason = vapply(failed, `[[`, character(1), "reason"),
    stringsAsFactors = FALSE
  )
  all_unavailable <- n_ok == 0L && length(failed) > 0L &&
    all(vapply(failed, `[[`, logical(1), "unavailable"))
  if (all_unavailable) return(indeterminate("every request failed: source unavailable"))
  any_indeterminate <- any(vapply(failed, `[[`, logical(1), "indeterminate"))

  # Parsed parquet is DERIVED from the raw JSON kept under data/raw/ (see
  # hl_make_post); nothing here is ever uploaded.
  for (nm in names(bars)) {
    parts <- strsplit(nm, " ", fixed = TRUE)[[1]]
    keyc <- if (parts[2] == "1d") "date" else "time"
    hl_upsert(bind_rows(bars[[nm]]), hl_bars_path(out_dir, parts[1], parts[2]),
              c("dex", "coin", keyc))
  }
  hl_upsert(bind_rows(funding_daily), file.path(out_dir, "perp_funding_daily.parquet"),
            c("dex", "coin", "date"))
  hl_upsert(bind_rows(funding_raw), file.path(out_dir, "perp_funding.parquet"),
            c("dex", "coin", "time_ms"))
  hl_upsert(bind_rows(oi), file.path(out_dir, "perp_oi_snapshot.parquet"),
            c("dex", "coin", "fetched_at"))

  list(status = if (any_indeterminate) 3L else if (nrow(failed_df) > 0L) 1L else 0L,
       failed = failed_df, n_markets = nrow(markets),
       n_in_progress_dropped = n_dropped, out_of_scope = enum$out_of_scope)
}

.fetch_hyperliquid_main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  opt <- function(name, default) {
    hit <- grep(paste0("^--", name, "="), args, value = TRUE)
    if (length(hit) == 0L) default else sub(paste0("^--", name, "="), "", hit[1])
  }
  cli_h1("Hyperliquid fetch (perpetual futures and spot pairs, NOT tokenised shares)")
  res <- hl_run(post_fn = hl_make_post(opt("raw-dir", "data/raw/hyperliquid")),
                out_dir = opt("out-dir", "data/dist"),
                start = as.Date(opt("start", "2023-01-01")),
                sleep = as.numeric(opt("sleep", "0.3")),
                intervals = strsplit(opt("intervals", "1d,1h"), ",", fixed = TRUE)[[1]],
                spot = !identical(opt("spot", "true"), "false"),
                funding = !identical(opt("funding", "true"), "false"))
  if (res$status == 3L) {
    if (nrow(res$failed) > 0L) print(res$failed, row.names = FALSE)
    quit(save = "no", status = 3L)
  }
  if (res$status == 1L) {
    cli_alert_danger("{nrow(res$failed)} item(s) failed")
    print(res$failed, row.names = FALSE)
    quit(save = "no", status = 1L)
  }
  cli_alert_success("{res$n_markets} markets written")
  invisible(TRUE)
}

if (sys.nframe() == 0L) {
  .fetch_hyperliquid_main()
}
