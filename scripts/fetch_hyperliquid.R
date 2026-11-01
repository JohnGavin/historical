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
#                               units (not quote/notional)
#   perp_funding_daily.parquet  upsert on (dex, coin, date); sum of hourly
#                               fundingRate + n_hours (partial days visible)
#   perp_oi_snapshot.parquet    append, key (dex, coin, fetched_at). Open
#                               interest has NO history on this API: only the
#                               current snapshot exists, so it is never
#                               back-filled into the daily table.
# The deployer-wallet fields of perpDexs are neither read nor persisted.
# Publication of these files is a documented follow-up, not done here.
#
# Usage: Rscript scripts/fetch_hyperliquid.R [--out-dir=data/dist]
#                                            [--start=2023-01-01] [--sleep=0.3]
#
# Exit status: 0 ok | 1 partial (some markets failed; successes still written)
#              | 3 INDETERMINATE (source unreachable / HTTP error / empty market
#              list). 3 is never "no data" and never 0.

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
  library(httr2)
  library(jsonlite)
})

HL_URL <- "https://api.hyperliquid.xyz/info"
HL_CANDLE_PAGE_MAX <- 5000L  # documented API cap on candles per response
HL_FUNDING_PAGE_MAX <- 500L  # documented API cap on funding rows per response
.ms_day <- 86400000

# ── Network layer ───────────────────────────────────────────────────
# `post_fn(body)` takes a named list and returns parsed JSON
# (simplifyVector = FALSE). Tests inject their own; this is the real one.
hl_unavailable <- function(msg) {
  cli::cli_abort(c("x" = "Hyperliquid source unavailable", "i" = msg),
                 class = "hl_source_unavailable")
}

hl_post <- function(body, url = HL_URL, timeout = 30, max_tries = 3) {
  resp <- tryCatch(
    httr2::request(url) |>
      httr2::req_body_json(body, auto_unbox = TRUE, null = "null") |>
      httr2::req_timeout(timeout) |>
      httr2::req_retry(max_tries = max_tries, backoff = ~ 2^.x) |>
      httr2::req_perform(),
    error = function(e) hl_unavailable(conditionMessage(e))
  )
  jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = FALSE)
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

hl_fetch_candles <- function(coin, start_ms, end_ms, post_fn = hl_post,
                             page_max = HL_CANDLE_PAGE_MAX, ...) {
  hl_page(
    function(s) post_fn(list(type = "candleSnapshot",
                             req = list(coin = coin, interval = "1d",
                                        startTime = s, endTime = end_ms))),
    function(r) as.numeric(r$t), start_ms, end_ms, page_max, ...
  )
}

hl_fetch_funding <- function(coin, start_ms, end_ms, post_fn = hl_post,
                             page_max = HL_FUNDING_PAGE_MAX, ...) {
  hl_page(
    function(s) post_fn(list(type = "fundingHistory", coin = coin,
                             startTime = s, endTime = end_ms)),
    function(r) as.numeric(r$time), start_ms, end_ms, page_max, ...
  )
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

hl_empty_daily <- function() {
  data.frame(date = as.Date(character()), dex = character(), coin = character(),
             symbol = character(), instrument_type = character(),
             source = character(), open = numeric(), high = numeric(),
             low = numeric(), close = numeric(), volume_base = numeric(),
             stringsAsFactors = FALSE)
}

# candleSnapshot -> daily data.frame. `v` is BASE volume (units of the asset),
# stored as volume_base; it is never converted to notional here.
hl_parse_candles <- function(x, dex = "", coin) {
  if (length(x) == 0L) return(hl_empty_daily())
  hl_require_fields(x, c("t", "o", "h", "l", "c", "v"), "candle")
  t_ms <- hl_num(lapply(x, `[[`, "t"), "t")
  data.frame(
    date = as.Date(as.POSIXct(t_ms / 1000, origin = "1970-01-01", tz = "UTC")),
    dex = dex,
    coin = coin,
    symbol = hl_bare_symbol(coin),
    instrument_type = "perp",
    source = "hyperliquid",
    open = hl_num(lapply(x, `[[`, "o"), "o"),
    high = hl_num(lapply(x, `[[`, "h"), "h"),
    low = hl_num(lapply(x, `[[`, "l"), "l"),
    close = hl_num(lapply(x, `[[`, "c"), "c"),
    volume_base = hl_num(lapply(x, `[[`, "v"), "v"),
    stringsAsFactors = FALSE
  ) |>
    distinct(date, .keep_all = TRUE) |>
    arrange(date)
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
hl_run <- function(post_fn = hl_post, out_dir = "data/dist",
                   start = as.Date("2023-01-01"), end = Sys.time(),
                   sleep_fn = Sys.sleep, sleep = 0.3,
                   now = format(Sys.time(), tz = "UTC", usetz = TRUE)) {
  start_ms <- as.numeric(as.POSIXct(start, tz = "UTC")) * 1000
  end_ms <- floor(as.numeric(end) * 1000)

  indeterminate <- function(why) {
    cli::cli_alert_danger("INDETERMINATE: {why}")
    list(status = 3L, failed = data.frame(), n_markets = 0L, reason = why)
  }

  dexs <- tryCatch(hl_parse_dexs(post_fn(list(type = "perpDexs"))),
                   error = function(e) e)
  if (inherits(dexs, "error")) return(indeterminate(conditionMessage(dexs)))

  markets <- list()
  failed <- list()
  for (d in dexs) {
    body <- if (nzchar(d)) list(type = "meta", dex = d) else list(type = "meta")
    m <- tryCatch(hl_parse_universe(post_fn(body), d), error = function(e) e)
    if (inherits(m, "error")) {
      if (!nzchar(d)) return(indeterminate(paste("core market list:", conditionMessage(m))))
      failed[[paste0("dex:", d)]] <- list(reason = conditionMessage(m),
                                          unavailable = inherits(m, "hl_source_unavailable"))
      next
    }
    markets[[length(markets) + 1L]] <- m
    sleep_fn(sleep)
  }
  markets <- bind_rows(markets)
  if (nrow(markets) == 0L) return(indeterminate("empty market list"))

  daily <- list(); funding <- list(); n_ok <- 0L
  for (i in seq_len(nrow(markets))) {
    dex <- markets$dex[i]; coin <- markets$coin[i]
    r <- tryCatch({
      c_raw <- hl_fetch_candles(coin, start_ms, end_ms, post_fn,
                                sleep_fn = sleep_fn, sleep = sleep)
      sleep_fn(sleep)
      f_raw <- hl_fetch_funding(coin, start_ms, end_ms, post_fn,
                                sleep_fn = sleep_fn, sleep = sleep)
      sleep_fn(sleep)
      list(d = hl_parse_candles(c_raw, dex, coin),
           f = hl_parse_funding_daily(f_raw, dex, coin))
    }, error = function(e) e)
    key <- paste0(dex, ":", coin)
    if (inherits(r, "error")) {
      failed[[key]] <- list(reason = conditionMessage(r),
                            unavailable = inherits(r, "hl_source_unavailable"))
      cli::cli_alert_danger("{key}: FAILED ({conditionMessage(r)})")
    } else {
      daily[[key]] <- r$d; funding[[key]] <- r$f; n_ok <- n_ok + 1L
    }
  }

  # Open-interest snapshot: one call per dex, current values only.
  oi <- list()
  for (d in unique(markets$dex)) {
    body <- if (nzchar(d)) list(type = "metaAndAssetCtxs", dex = d) else list(type = "metaAndAssetCtxs")
    s <- tryCatch(hl_parse_oi_snapshot(post_fn(body), d, now), error = function(e) e)
    if (inherits(s, "error")) {
      failed[[paste0("oi:", d)]] <- list(reason = conditionMessage(s),
                                         unavailable = inherits(s, "hl_source_unavailable"))
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

  hl_upsert(bind_rows(daily), file.path(out_dir, "perp_daily.parquet"),
            c("dex", "coin", "date"))
  hl_upsert(bind_rows(funding), file.path(out_dir, "perp_funding_daily.parquet"),
            c("dex", "coin", "date"))
  hl_upsert(bind_rows(oi), file.path(out_dir, "perp_oi_snapshot.parquet"),
            c("dex", "coin", "fetched_at"))

  list(status = if (nrow(failed_df) > 0L) 1L else 0L,
       failed = failed_df, n_markets = nrow(markets))
}

.fetch_hyperliquid_main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  opt <- function(name, default) {
    hit <- grep(paste0("^--", name, "="), args, value = TRUE)
    if (length(hit) == 0L) default else sub(paste0("^--", name, "="), "", hit[1])
  }
  cli_h1("Hyperliquid perp fetch (perpetual futures, NOT tokenised shares)")
  res <- hl_run(out_dir = opt("out-dir", "data/dist"),
                start = as.Date(opt("start", "2023-01-01")),
                sleep = as.numeric(opt("sleep", "0.3")))
  if (res$status == 3L) quit(save = "no", status = 3L)
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
