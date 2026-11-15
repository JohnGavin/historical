#!/usr/bin/env Rscript
# Hyperliquid volume / cost measurement, run once (#1072 "Test: measure before
# building"). The OUTPUT under audits/ is the home of every count, size and
# time the issue quotes; the issue cites it, never the other way round.
#
# Reuses scripts/fetch_hyperliquid.R (network layer, parsers, market classes):
# there is no second network layer here. The only thing added is a recorder that
# wraps `hl_post` to log rows, JSON bytes, weight and elapsed seconds per request.
#
# Steps (issue #1072):
#   1. Enumerate markets by class; live vs delisted per exchange; traded vs
#      zero 24h volume (allPerpMetas, spotMeta, spotMetaAndAssetCtxs, and one
#      metaAndAssetCtxs per perp exchange for the perp 24h volume).
#   2. Sample ~30 in-scope markets by a COMMITTED rule (HL_SAMPLE_QUOTA and
#      hl_sample_ranks below): within each (class, live/delisted) group, take
#      evenly spaced ranks of the universe order. Universe order is the listing
#      order, used as the age proxy because a market's first-bar date would cost
#      one request per market to learn. Per sampled market: daily bars, 1-hour
#      bars, full funding history (perps).
#   3. Per request: rows, JSON bytes, weight, elapsed; parquet (zstd) bytes/row.
#   4. Scale to all in-scope markets: backfill size and time, weekly increment,
#      yearly growth, share of the rate limit.
#   5. Emit every number the issue quotes.
#
# Usage: Rscript scripts/hl_volume_estimate.R [--audits-dir=audits]
#                                             [--raw-dir=data/raw/hyperliquid]
#                                             [--pace=0.6]
# Exit status: 0 ok (report written) | 3 INDETERMINATE: a sampled request failed,
# was rate-limited, or returned `[]` for a live listed market inside its
# retained window. On 3 NOTHING is written under audits/.

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
  library(jsonlite)
})

.hl_est_dir <- function() {
  a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  cand <- if (length(a) > 0L) dirname(normalizePath(sub("^--file=", "", a[1]))) else character()
  cand <- c(cand, here::here("scripts"))
  cand[file.exists(file.path(cand, "fetch_hyperliquid.R"))][1]
}
source(file.path(.hl_est_dir(), "fetch_hyperliquid.R"))

# ── Constants (one home each) ───────────────────────────────────────
# Rate limit, weight table and pacing live in fetch_hyperliquid.R (one home).
HL_EST_START <- as.Date("2000-01-01")  # earlier than any market: clamp / API decide
HL_EST_STATE_PER_DAY <- 1L              # state snapshots per day
HL_EST_WEEK_BARS <- c(daily = 7, hourly = 168, funding = 168)
HL_EST_YEAR_ROWS <- c(daily = 365, hourly = 8760, funding = 8760)
# Sample quota: (class, delisted) -> k. >= 2 delisted by construction.
HL_SAMPLE_QUOTA <- data.frame(
  market_class = c("main_perp", "main_perp", "builder_perp", "builder_perp", "spot_pair"),
  is_delisted  = c(FALSE, TRUE, FALSE, TRUE, FALSE),
  k            = c(10L, 3L, 5L, 2L, 10L),
  stringsAsFactors = FALSE
)

# ── Pure helpers ────────────────────────────────────────────────────
# Evenly spaced ranks 1..n, k of them (first and last included when k >= 2).
hl_sample_ranks <- function(n, k) {
  if (n <= 0L || k <= 0L) return(integer(0))
  if (k >= n) return(seq_len(n))
  unique(as.integer(round(seq(1, n, length.out = k))))
}

# `markets` is in universe order (listing order); returns the sampled rows.
hl_select_sample <- function(markets, quota = HL_SAMPLE_QUOTA) {
  out <- list()
  for (i in seq_len(nrow(quota))) {
    g <- markets[markets$market_class == quota$market_class[i] &
                   markets$is_delisted == quota$is_delisted[i], ]
    # spot pairs: only those with non-zero 24h volume are in scope
    if (quota$market_class[i] == "spot_pair") g <- g[!is.na(g$traded_24h) & g$traded_24h, ]
    out[[i]] <- g[hl_sample_ranks(nrow(g), quota$k[i]), ]
  }
  bind_rows(out)
}

# metaAndAssetCtxs -> (coin, day_ntl_vlm), joined WITHIN the response by
# position (the documented alignment of universe and contexts for one dex).
hl_parse_perp_volumes <- function(mac) {
  u <- mac[[1]]$universe; ctx <- mac[[2]]
  if (length(u) != length(ctx)) {
    cli::cli_abort("metaAndAssetCtxs universe ({length(u)}) and contexts ({length(ctx)}) differ")
  }
  hl_require_fields(ctx, "dayNtlVlm", "asset ctx")
  data.frame(coin = vapply(u, function(m) as.character(m$name), character(1)),
             day_ntl_vlm = hl_num(lapply(ctx, `[[`, "dayNtlVlm"), "dayNtlVlm"),
             stringsAsFactors = FALSE)
}

# Counts by (instrument, class, exchange): live / delisted / traded / zero 24h.
hl_enumeration_table <- function(markets) {
  markets |>
    mutate(exchange = ifelse(instrument_type == "spot", "spot",
                             ifelse(nzchar(dex), dex, "core"))) |>
    group_by(instrument_type, market_class, exchange) |>
    summarise(listed = dplyr::n(),
              live = sum(!is_delisted),
              delisted = sum(is_delisted),
              traded_24h = sum(traded_24h %in% TRUE),
              zero_24h = sum(traded_24h %in% FALSE),
              no_volume_info = sum(is.na(traded_24h)),
              .groups = "drop")
}

# Request log -> per-type totals.
hl_request_summary <- function(log) {
  log |>
    group_by(type) |>
    summarise(requests = dplyr::n(), failed = sum(!ok),
              rows = sum(rows, na.rm = TRUE),
              json_bytes = sum(bytes, na.rm = TRUE),
              weight = sum(weight), seconds = sum(elapsed), .groups = "drop")
}

# Scale the sample to all in-scope markets. `sample` has one row per sampled
# market (group, and per-dataset rows / weight / json bytes); `counts` has
# N per group; `bpr` is parquet bytes per row by dataset and instrument.
hl_scale <- function(sample, counts, bpr, state_bytes, n_state_requests) {
  groups <- c("perp_live", "perp_delisted", "spot_live")
  gm <- function(col, g) {
    v <- sample[[col]][sample$group == g]
    v <- v[!is.na(v)]
    if (length(v) == 0L) NA_real_ else mean(v)
  }
  pooled_perp <- function(col) {
    v <- sample[[col]][sample$group %in% c("perp_live", "perp_delisted")]
    v <- v[!is.na(v)]
    if (length(v) == 0L) 0 else mean(v)
  }
  # mean per group, falling back to the pooled perp mean for a group w/o sample
  m <- function(col, g) {
    x <- gm(col, g)
    if (is.na(x)) pooled_perp(col) else x
  }
  n <- function(g) as.numeric(counts[[g]])
  rows <- list()
  for (g in groups) {
    ds <- c("daily", "hourly", if (g != "spot_live") "funding")
    for (d in ds) {
      rows[[length(rows) + 1L]] <- data.frame(
        group = g, dataset = d, markets = n(g),
        rows_per_market = m(paste0(d, "_rows"), g),
        weight_per_market = m(paste0(d, "_weight"), g),
        json_bytes_per_market = m(paste0(d, "_json"), g),
        stringsAsFactors = FALSE)
    }
  }
  b <- bind_rows(rows) |>
    mutate(instrument = ifelse(group == "spot_live", "spot", "perp"),
           bytes_per_row = vapply(seq_len(dplyr::n()), function(i) {
             v <- bpr$bytes_per_row[bpr$instrument == instrument[i] & bpr$dataset == dataset[i]]
             if (length(v) == 0L || is.na(v[1])) {
               v <- bpr$bytes_per_row[bpr$dataset == dataset[i]]
             }
             if (length(v) == 0L) NA_real_ else mean(v, na.rm = TRUE)
           }, numeric(1)),
           backfill_weight = markets * weight_per_market,
           backfill_rows = markets * rows_per_market,
           backfill_json_mb = markets * json_bytes_per_market / 1e6,
           backfill_parquet_mb = backfill_rows * bytes_per_row / 1e6)
  # weekly incremental: live markets only (delisted are not polled again)
  wk <- b |>
    filter(group != "perp_delisted") |>
    mutate(week_rows = HL_EST_WEEK_BARS[dataset],
           week_weight = markets * vapply(seq_len(dplyr::n()), function(i) {
             hl_weight(if (dataset[i] == "funding") "fundingHistory" else "candleSnapshot",
                       HL_EST_WEEK_BARS[[dataset[i]]])
           }, numeric(1)),
           year_rows = HL_EST_YEAR_ROWS[dataset],
           year_parquet_mb = markets * year_rows * bytes_per_row / 1e6,
           year_json_mb = markets * year_rows * (json_bytes_per_market / rows_per_market) / 1e6)
  # Saving of the delisted-funding cap, measured on the sampled delisted perps
  # (each has an uncapped control fetch) and scaled by their market count.
  ctl <- sample[sample$group == "perp_delisted" & !is.na(sample$funding_weight_uncapped), ]
  per <- function(unc, cap) if (nrow(ctl) == 0L) 0 else mean(ctl[[unc]] - ctl[[cap]])
  saved_weight <- n("perp_delisted") * per("funding_weight_uncapped", "funding_weight")
  saved_rows <- n("perp_delisted") * per("funding_rows_uncapped", "funding_rows")
  state_weight_day <- n_state_requests * hl_weight("info") * HL_EST_STATE_PER_DAY
  budget_week <- HL_RATE_WEIGHT_PER_MIN * 60 * 24 * 7
  totals <- list(
    backfill_weight = sum(b$backfill_weight),
    backfill_minutes_at_limit = sum(b$backfill_weight) / HL_RATE_WEIGHT_PER_MIN,
    cap_sampled_delisted = nrow(ctl),
    cap_weight_saved = saved_weight,
    cap_rows_saved = saved_rows,
    cap_minutes_saved = saved_weight / HL_RATE_WEIGHT_PER_MIN,
    backfill_weight_uncapped = sum(b$backfill_weight) + saved_weight,
    backfill_minutes_uncapped = (sum(b$backfill_weight) + saved_weight) / HL_RATE_WEIGHT_PER_MIN,
    backfill_json_mb = sum(b$backfill_json_mb),
    backfill_parquet_mb = sum(b$backfill_parquet_mb, na.rm = TRUE),
    weekly_weight = sum(wk$week_weight) + state_weight_day * 7,
    weekly_minutes_at_limit = (sum(wk$week_weight) + state_weight_day * 7) / HL_RATE_WEIGHT_PER_MIN,
    weekly_share_of_limit_pct = 100 * (sum(wk$week_weight) + state_weight_day * 7) / budget_week,
    yearly_parquet_mb = sum(wk$year_parquet_mb, na.rm = TRUE) ,
    yearly_json_mb = sum(wk$year_json_mb, na.rm = TRUE) + state_bytes * 365 / 1e6,
    state_snapshot_json_bytes = state_bytes,
    state_snapshot_weight_per_day = state_weight_day
  )
  list(by_group_dataset = b, weekly = wk, totals = totals)
}

# Markdown pipe table, no dependencies.
hl_md_table <- function(df) {
  fmt <- function(x) {
    if (is.numeric(x)) {
      ifelse(is.na(x), "", ifelse(abs(x - round(x)) < 1e-9 & abs(x) < 1e15,
                                  format(round(x), big.mark = ",", trim = TRUE, scientific = FALSE),
                                  format(signif(x, 4), trim = TRUE, scientific = FALSE)))
    } else {
      x <- as.character(x); x[is.na(x)] <- ""; x
    }
  }
  cells <- lapply(df, fmt)
  hdr <- paste0("| ", paste(names(df), collapse = " | "), " |")
  sep <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  body <- vapply(seq_len(nrow(df)), function(i) {
    paste0("| ", paste(vapply(cells, `[`, "", i), collapse = " | "), " |")
  }, character(1))
  c(hdr, sep, body)
}

# ── Recorder: logs every request made through the paced post ─────────
# Pacing, weight and 429 back-off are hl_make_post()'s (fetch_hyperliquid.R);
# the recorder only turns its per-attempt observations into a request log.
hl_make_recorder <- function(raw_dir, pace = HL_PACE_FRACTION, sleep_fn = Sys.sleep,
                             post = hl_post) {
  env <- new.env()
  env$log <- list()
  observer <- function(e) {
    b <- e$body
    env$log[[length(env$log) + 1L]] <- data.frame(
      type = b$type,
      target = as.character(b$coin %||% b$req$coin %||% b$dex %||% ""),
      interval = as.character(b$req$interval %||% ""),
      rows = e$rows, bytes = e$bytes, weight = e$weight, elapsed = e$elapsed,
      ok = e$ok, error = e$error, stringsAsFactors = FALSE)
  }
  list(post = hl_make_post(raw_dir, pace = pace, sleep_fn = sleep_fn,
                           post = post, observer = observer),
       log = function() bind_rows(env$log))
}

# ── Measurement of one sampled market ───────────────────────────────
hl_parquet_bytes <- function(df, dir) {
  if (nrow(df) == 0L) return(0)
  p <- tempfile(tmpdir = dir, fileext = ".parquet")
  arrow::write_parquet(df, p, compression = "zstd")
  file.size(p)
}

# Returns list(summary = 1-row data.frame, daily, hourly, funding, problems).
# Problems: failures or `[]` for a live market (INDETERMINATE, exit 3).
hl_measure_market <- function(m, rec, end_ms, tmp_dir) {
  start_ms <- as.numeric(as.POSIXct(HL_EST_START, tz = "UTC")) * 1000
  coin <- m$coin; itype <- m$instrument_type; delisted <- m$is_delisted
  problems <- character()
  one <- function(expr, what) {
    tryCatch(expr, error = function(e) {
      problems <<- c(problems, sprintf("%s %s: %s", coin, what, conditionMessage(e)))
      NULL
    })
  }
  res <- list()
  for (itv in c("1d", "1h")) {
    raw <- one(hl_fetch_candles(coin, start_ms, end_ms, rec$post, interval = itv,
                                clamp = !delisted), paste("candles", itv))
    if (is.null(raw)) next
    if (length(raw) == 0L && !delisted) {
      problems <- c(problems, sprintf("%s: empty %s reply for a live market (INDETERMINATE)", coin, itv))
    }
    dp <- hl_drop_in_progress(raw, end_ms)
    res[[itv]] <- hl_parse_candles(dp$kept, m$dex, coin, itv, itype)
    res[[paste0(itv, "_dropped")]] <- dp$n_dropped
  }
  fund <- NULL
  cap <- "none"; cap_end_ms <- NA_real_
  ctrl <- c(rows = NA_real_, weight = NA_real_, requests = 0)
  if (itype == "perp") {
    # Delisted: funding stops at the last traded daily bar (the cap under test).
    mf <- one(hl_fetch_market_funding(coin, delisted, res[["1d"]], start_ms, end_ms,
                                      rec$post),
              "funding")
    raw <- if (is.null(mf)) NULL else mf$raw
    if (!is.null(mf)) { cap <- mf$cap; cap_end_ms <- mf$end_ms }
    if (!is.null(raw)) {
      if (length(raw) == 0L && !delisted) {
        problems <- c(problems, sprintf("%s: empty funding reply for a live market (INDETERMINATE)", coin))
      }
      fund <- one(hl_parse_funding_raw(raw, m$dex, coin), "funding parse")
    }
  }
  # Everything the capped run asked for is in the log NOW; the control below is
  # logged after this point and kept out of the per-market (scaled) figures.
  log_main <- rec$log()
  lg <- log_main |> filter(target == coin)
  if (itype == "perp" && delisted && cap != "none") {
    # CONTROL: the same market's funding fetched uncapped (to now), measured, so
    # the saving is observed on the sample and not assumed.
    raw_u <- one(hl_fetch_funding(coin, start_ms, end_ms, rec$post),
                  "funding uncapped control")
    if (!is.null(raw_u)) {
      lg_u <- rec$log()[-seq_len(nrow(log_main)), ]
      lg_u <- lg_u[lg_u$ok, ]
      ctrl <- c(rows = length(raw_u), weight = sum(lg_u$weight), requests = nrow(lg_u))
    }
  }
  agg <- function(type, itv = NULL) {
    x <- lg[lg$type == type & lg$ok, ]
    if (!is.null(itv)) x <- x[x$interval == itv, ]
    c(requests = nrow(x), rows = sum(x$rows, na.rm = TRUE), weight = sum(x$weight),
      json = sum(x$bytes, na.rm = TRUE), seconds = sum(x$elapsed))
  }
  d <- agg("candleSnapshot", "1d"); h <- agg("candleSnapshot", "1h"); f <- agg("fundingHistory")
  daily <- res[["1d"]]; hourly <- res[["1h"]]
  first_traded <- if (!is.null(daily) && any(daily$traded)) min(daily$date[daily$traded]) else as.Date(NA)
  switch_time <- as.POSIXct(NA, tz = "UTC"); f_first <- as.POSIXct(NA, tz = "UTC")
  n_out <- NA_integer_
  n_after <- NA_integer_; n_zero_after <- NA_integer_
  if (!is.null(fund) && nrow(fund) > 0L && !is.null(daily) && nrow(daily) > 0L) {
    # Delisted markets keep emitting funding rows after their last candle; count
    # them, and how many are exactly zero (observed 2026-11-15 on MATIC).
    after <- fund$time > max(daily$close_time)
    n_after <- sum(after)
    n_zero_after <- sum(after & fund$funding_rate == 0)
  }
  if (!is.null(fund) && nrow(fund) > 0L) {
    f_first <- min(fund$time)
    n_out <- sum(fund$offset_outlier)
    i8 <- which(fund$interval_hours == 8)
    i1 <- which(fund$interval_hours == 1)
    # boundary: first hourly row that follows an 8-hourly row
    if (length(i8) > 0L && length(i1) > 0L && any(i1 > max(i8))) {
      switch_time <- fund$time[min(i1[i1 > max(i8)])]
    }
  }
  list(
    summary = data.frame(
      coin = coin, market_class = m$market_class, instrument_type = itype,
      is_delisted = delisted,
      daily_rows = nrow(daily %||% data.frame()), daily_requests = d[["requests"]],
      daily_weight = d[["weight"]], daily_json = d[["json"]],
      first_bar = if (!is.null(daily) && nrow(daily) > 0L) min(daily$date) else as.Date(NA),
      first_traded_daily = first_traded,
      hourly_rows = nrow(hourly %||% data.frame()), hourly_requests = h[["requests"]],
      hourly_weight = h[["weight"]], hourly_json = h[["json"]],
      hourly_first = if (!is.null(hourly) && nrow(hourly) > 0L) min(hourly$time) else as.POSIXct(NA, tz = "UTC"),
      funding_rows = if (itype == "perp") nrow(fund %||% data.frame()) else NA_integer_,
      funding_requests = if (itype == "perp") f[["requests"]] else NA_real_,
      funding_weight = if (itype == "perp") f[["weight"]] else NA_real_,
      funding_json = if (itype == "perp") f[["json"]] else NA_real_,
      funding_first = f_first, funding_switch_8h_to_1h = switch_time,
      offset_outliers = n_out,
      funding_rows_after_last_bar = n_after,
      funding_zero_rows_after_last_bar = n_zero_after,
      funding_cap = cap, funding_cap_end = cap_end_ms,
      funding_rows_uncapped = ctrl[["rows"]], funding_weight_uncapped = ctrl[["weight"]],
      control_requests = ctrl[["requests"]], control_weight = if (is.na(ctrl[["weight"]])) 0 else ctrl[["weight"]],
      stringsAsFactors = FALSE),
    daily = daily, hourly = hourly, funding = fund, problems = problems,
    parquet = c(daily = hl_parquet_bytes(daily %||% data.frame(), tmp_dir),
                hourly = hl_parquet_bytes(hourly %||% data.frame(), tmp_dir),
                funding = hl_parquet_bytes(fund %||% data.frame(), tmp_dir))
  )
}

# ── Orchestration ───────────────────────────────────────────────────
hl_estimate <- function(post_fn_recorder, end = Sys.time(), tmp_dir = tempdir()) {
  rec <- post_fn_recorder
  t_start <- proc.time()[["elapsed"]]
  end_ms <- floor(as.numeric(end) * 1000)
  problems <- character()

  # 1. enumerate + state snapshot
  enum <- hl_enumerate_markets(rec$post)
  markets <- enum$markets
  perp_dexs <- unique(markets$dex[markets$instrument_type == "perp"])
  vols <- list()
  for (d in perp_dexs) {
    body <- if (nzchar(d)) list(type = "metaAndAssetCtxs", dex = d) else list(type = "metaAndAssetCtxs")
    vols[[d]] <- hl_parse_perp_volumes(rec$post(body))
  }
  vols <- bind_rows(vols)
  pv <- match(markets$coin, vols$coin)
  perp <- markets$instrument_type == "perp"
  markets$day_ntl_vlm[perp] <- vols$day_ntl_vlm[pv[perp]]
  markets$traded_24h[perp] <- markets$day_ntl_vlm[perp] > 0
  state_log <- rec$log()
  # The daily state snapshot is allPerpMetas + metaAndAssetCtxs per exchange +
  # spotMetaAndAssetCtxs (spotMeta is only needed here to classify).
  state_snapshot <- state_log[state_log$type %in% c("allPerpMetas", "spotMetaAndAssetCtxs", "metaAndAssetCtxs"), ]

  # 2./3. sample and measure
  smp <- hl_select_sample(markets)
  dir.create(tmp_dir, showWarnings = FALSE, recursive = TRUE)
  results <- list()
  for (i in seq_len(nrow(smp))) {
    cli::cli_alert_info("[{i}/{nrow(smp)}] {smp$coin[i]} ({smp$market_class[i]}, {if (smp$is_delisted[i]) 'delisted' else 'live'})")
    r <- hl_measure_market(smp[i, ], rec, end_ms, tmp_dir)
    problems <- c(problems, r$problems)
    results[[i]] <- r
  }
  list(markets = markets, out_of_scope = enum$out_of_scope, sample = smp,
       results = results, log = rec$log(), problems = problems,
       state_snapshot = state_snapshot, end_ms = end_ms,
       wall_s = proc.time()[["elapsed"]] - t_start)
}

hl_group <- function(instrument_type, is_delisted) {
  ifelse(instrument_type == "spot", "spot_live",
         ifelse(is_delisted, "perp_delisted", "perp_live"))
}

hl_assemble <- function(est) {
  S <- bind_rows(lapply(est$results, `[[`, "summary")) |>
    mutate(group = hl_group(instrument_type, is_delisted))
  bpr_rows <- list()
  for (i in seq_along(est$results)) {
    r <- est$results[[i]]; s <- r$summary
    for (ds in c("daily", "hourly", "funding")) {
      nr <- c(daily = s$daily_rows, hourly = s$hourly_rows, funding = s$funding_rows)[[ds]]
      if (!is.na(nr) && nr > 0) {
        bpr_rows[[length(bpr_rows) + 1L]] <- data.frame(
          instrument = s$instrument_type, dataset = ds, rows = nr,
          parquet_bytes = r$parquet[[ds]], stringsAsFactors = FALSE)
      }
    }
  }
  bpr <- bind_rows(bpr_rows) |>
    group_by(instrument, dataset) |>
    summarise(rows = sum(rows), parquet_bytes = sum(parquet_bytes),
              bytes_per_row = sum(parquet_bytes) / sum(rows), .groups = "drop")
  mk <- est$markets
  counts <- list(
    perp_live = sum(mk$instrument_type == "perp" & !mk$is_delisted),
    perp_delisted = sum(mk$instrument_type == "perp" & mk$is_delisted),
    spot_live = sum(mk$instrument_type == "spot" & mk$traded_24h %in% TRUE))
  st <- est$state_snapshot
  scale <- hl_scale(S, counts, bpr, state_bytes = sum(st$bytes, na.rm = TRUE),
                    n_state_requests = nrow(st))
  list(S = S, bpr = bpr, counts = counts, scale = scale,
       enumeration = hl_enumeration_table(mk), requests = hl_request_summary(est$log))
}

# ── Report ──────────────────────────────────────────────────────────
hl_write_report <- function(est, A, audits_dir, date_utc, git_sha) {
  dir.create(audits_dir, showWarnings = FALSE, recursive = TRUE)
  stem <- file.path(audits_dir, paste0("hl_volume_estimate_", date_utc))
  tot <- A$scale$totals
  mk <- est$markets
  fmt_min <- function(x) sprintf("%.0f min (%.1f h)", x, x / 60)
  delisted_by_ex <- A$enumeration |>
    filter(instrument_type == "perp") |>
    group_by(exchange) |>
    summarise(listed = sum(listed), live = sum(live), delisted = sum(delisted), .groups = "drop")
  oos <- est$out_of_scope
  log <- est$log
  tot_req <- nrow(log); tot_w <- sum(log$weight); tot_s <- sum(log$elapsed)
  S <- A$S
  headline <- data.frame(
    metric = c("Listed perps (all exchanges)", "  of which live", "  of which delisted",
               "Spot pairs in spotMeta.universe", "  of which traded in 24h (in scope)",
               "Out of scope: unlisted spot contexts", "Out of scope: outcome markets",
               "Sampled markets", "Requests made (this run)", "Weight used (this run)",
               "Seconds inside requests (this run, excl. pacing sleeps)",
               "Wall seconds (this run, incl. pacing sleeps)",
               "Backfill weight, all in-scope markets (delisted funding capped)",
               "Backfill time at 1200 weight/min (capped)",
               "Delisted perps whose funding stops at the last traded bar",
               "  sampled delisted perps: capped", "  sampled delisted perps: no traded bar (no funding requested)",
               "Backfill weight if uncapped (sample-measured control)",
               "Backfill weight saved by the cap", "Backfill time saved by the cap (min)",
               "Funding rows saved by the cap",
               "Uncapped control requests (in this run's totals above)",
               "Uncapped control weight (in this run's totals above)",
               "Backfill raw JSON (MB)", "Backfill parquet zstd (MB)",
               "Weekly incremental weight (live + daily state snapshot)",
               "Weekly incremental time at the limit",
               "Weekly share of the weekly rate budget (%)",
               "Yearly growth, parquet (MB)", "Yearly growth, raw JSON (MB)",
               "State snapshot JSON (bytes per snapshot)",
               "State snapshot weight per day"),
    value = c(sum(mk$instrument_type == "perp"), A$counts$perp_live, A$counts$perp_delisted,
              sum(mk$instrument_type == "spot"), A$counts$spot_live,
              oos$n[oos$market_class == "spot_unlisted"], oos$n[oos$market_class == "outcome"],
              nrow(S), tot_req, tot_w, round(tot_s), round(est$wall_s),
              round(tot$backfill_weight), round(tot$backfill_minutes_at_limit, 1),
              A$counts$perp_delisted,
              sum(S$funding_cap == "capped", na.rm = TRUE),
              sum(S$funding_cap == "no_traded_bar", na.rm = TRUE),
              round(tot$backfill_weight_uncapped), round(tot$cap_weight_saved),
              round(tot$cap_minutes_saved, 1), round(tot$cap_rows_saved),
              sum(S$control_requests), sum(S$control_weight),
              round(tot$backfill_json_mb, 1), round(tot$backfill_parquet_mb, 1),
              round(tot$weekly_weight), round(tot$weekly_minutes_at_limit, 2),
              round(tot$weekly_share_of_limit_pct, 2),
              round(tot$yearly_parquet_mb, 1), round(tot$yearly_json_mb, 1),
              tot$state_snapshot_json_bytes, tot$state_snapshot_weight_per_day),
    stringsAsFactors = FALSE)
  headline$value <- as.numeric(headline$value)

  sample_tbl <- S |>
    transmute(coin, class = market_class, delisted = is_delisted,
              first_bar = as.character(first_bar),
              first_traded_daily = as.character(first_traded_daily),
              daily_rows, daily_weight, hourly_rows, hourly_weight,
              funding_rows, funding_requests, funding_weight)
  fund_tbl <- S |>
    filter(instrument_type == "perp") |>
    transmute(coin, delisted = is_delisted,
              funding_start = format(funding_first, "%Y-%m-%d %H:%M", tz = "UTC"),
              switch_8h_to_1h = format(funding_switch_8h_to_1h, "%Y-%m-%d %H:%M", tz = "UTC"),
              funding_rows, funding_requests, offset_outliers,
              rows_after_last_bar = funding_rows_after_last_bar,
              zero_rows_after_last_bar = funding_zero_rows_after_last_bar,
              cap = funding_cap, funding_weight,
              rows_uncapped = funding_rows_uncapped,
              weight_uncapped = funding_weight_uncapped)
  outlier_rows <- bind_rows(lapply(est$results, function(r) {
    f <- r$funding
    if (is.null(f) || nrow(f) == 0L) return(NULL)
    f[f$offset_outlier, c("coin", "time", "offset_min")]
  }))
  req_tbl <- A$requests |> mutate(seconds = round(seconds, 1))
  bpr_tbl <- A$bpr |> mutate(bytes_per_row = round(bytes_per_row, 1))
  scale_tbl <- A$scale$by_group_dataset |>
    transmute(group, dataset, markets, rows_per_market = round(rows_per_market),
              weight_per_market = round(weight_per_market, 1),
              json_mb_per_market = round(json_bytes_per_market / 1e6, 3),
              bytes_per_row = round(bytes_per_row, 1),
              backfill_weight = round(backfill_weight),
              backfill_parquet_mb = round(backfill_parquet_mb, 1))
  btc <- S[S$coin == "BTC", ]

  lines <- c(
    sprintf("# Hyperliquid volume estimate, %s", date_utc),
    "",
    sprintf("Generated by `scripts/hl_volume_estimate.R` at %s UTC, commit `%s`. Issue: [#1072](https://github.com/JohnGavin/historical/issues/1072).",
            format(Sys.time(), "%Y-%m-%d %H:%M", tz = "UTC"), git_sha),
    "",
    "This file is the home of every count, size and time the issue quotes.",
    sprintf("Machine-readable copies: `%s.json` (all tables) and `%s_requests.csv` (one row per request).",
            basename(stem), basename(stem)),
    "",
    "Hyperliquid markets are perpetual futures and spot pairs, not tokenised shares. Raw responses stay local under `data/raw/` and are never uploaded.",
    "",
    "## Headline numbers",
    "",
    hl_md_table(headline),
    "",
    "## 1. Markets by class and exchange",
    "",
    "Perps from `allPerpMetas` (exchange read from the coin prefix; `isDelisted` flag); 24h volume from one `metaAndAssetCtxs` per exchange. Spot pairs are the `spotMeta.universe`; contexts joined by `coin`. `no_volume_info` counts markets absent from the 24h snapshot (typically delisted).",
    "",
    hl_md_table(as.data.frame(A$enumeration)),
    "",
    "Perp totals per exchange:",
    "",
    hl_md_table(as.data.frame(delisted_by_ex)),
    "",
    "Out of scope (counted, never fetched):",
    "",
    hl_md_table(oos),
    "",
    "## 2. Sample",
    "",
    "Rule (committed in `HL_SAMPLE_QUOTA` and `hl_sample_ranks()`): within each (class, live or delisted) group, in universe order, take evenly spaced ranks; spot pairs only among those with non-zero 24h volume. Universe order is the listing order, used as the age proxy (a first-bar date would cost one request per market).",
    "",
    hl_md_table(as.data.frame(HL_SAMPLE_QUOTA)),
    "",
    hl_md_table(as.data.frame(sample_tbl)),
    "",
    "## 3. Cost per request type (this run)",
    "",
    "Weight is computed from the documented table (every request 20; candles +1 per 60 bars; funding +1 per 20 rows), not read from the server.",
    "",
    hl_md_table(as.data.frame(req_tbl)),
    "",
    "Parquet (zstd) bytes per row, measured on the sampled frames:",
    "",
    hl_md_table(as.data.frame(bpr_tbl)),
    "",
    "## 4. Scaled to all in-scope markets",
    "",
    "Means per group from the sample, multiplied by the group's market count (live perps, delisted perps, traded spot pairs). Weekly and yearly figures cover live markets only; delisted markets are backfilled once.",
    "",
    hl_md_table(as.data.frame(scale_tbl)),
    "",
    sprintf("Delisted funding cap: backfill %s weight (%s) capped vs %s weight (%s) uncapped; the cap saves %s weight, %s funding rows and %s min at the limit, extrapolated from %d sampled delisted perps (each with an uncapped control) to %d delisted perps.",
            format(round(tot$backfill_weight), big.mark = ","), fmt_min(tot$backfill_minutes_at_limit),
            format(round(tot$backfill_weight_uncapped), big.mark = ","), fmt_min(tot$backfill_minutes_uncapped),
            format(round(tot$cap_weight_saved), big.mark = ","), format(round(tot$cap_rows_saved), big.mark = ","),
            format(round(tot$cap_minutes_saved), big.mark = ","),
            as.integer(tot$cap_sampled_delisted), as.integer(A$counts$perp_delisted)),
    "",
    sprintf("Backfill: %s weight, %s at 1200 weight/min. Weekly incremental: %s weight, %s at the limit, %.2f%% of the weekly rate budget.",
            format(round(tot$backfill_weight), big.mark = ","), fmt_min(tot$backfill_minutes_at_limit),
            format(round(tot$weekly_weight), big.mark = ","), fmt_min(tot$weekly_minutes_at_limit),
            tot$weekly_share_of_limit_pct),
    "",
    "## 5. Numbers the issue quotes",
    "",
    "Funding start and the 8-hourly to hourly boundary per sampled perp (read from the gaps between rows):",
    "",
    hl_md_table(as.data.frame(fund_tbl)),
    "",
    if (nrow(btc) == 1L) sprintf("BTC: first daily bar %s, first traded daily bar %s, funding from %s in %s request(s) (%s rows), 8h to 1h boundary %s.",
            btc$first_bar, btc$first_traded_daily,
            format(btc$funding_first, "%Y-%m-%d", tz = "UTC"), btc$funding_requests,
            btc$funding_rows, format(btc$funding_switch_8h_to_1h, "%Y-%m-%d %H:%M", tz = "UTC"))
    else "BTC was not in the sample.",
    "",
    "Owner decision on #1075: a delisted market's funding stops at the close time of its last traded daily bar (`cap = capped`); a delisted market with no traded bar gets no funding request (`cap = no_traded_bar`, counted, not a failure). Live markets run to now (`cap = none`). Without the cap a delisted market keeps returning hourly funding rows of exactly 0 to the present (observed on MATIC: 19,120 zero rows after its last candle).",
    "",
    "`rows_after_last_bar` counts funding rows later than the market's last daily bar (about 0 under the cap); `zero_rows_after_last_bar` those with a rate of exactly 0. `rows_uncapped` and `weight_uncapped` are a CONTROL: the same market's funding fetched to now, measured in this run on each sampled delisted perp, so the saving is observed and not assumed. `funding_weight` and `funding_rows` are the capped fetch.",
    "",
    "Funding rows more than 5 minutes past the hour (flagged, not floored):",
    "",
    if (nrow(outlier_rows) > 0L) hl_md_table(as.data.frame(outlier_rows |> mutate(time = format(time, "%Y-%m-%d %H:%M:%S", tz = "UTC"), offset_min = round(offset_min, 1)))) else "None in the sample.",
    "",
    sprintf("State snapshot (1 `allPerpMetas` + %d `metaAndAssetCtxs` + 1 `spotMetaAndAssetCtxs`): %s bytes of JSON, %d requests, weight %d.",
            length(unique(mk$dex[mk$instrument_type == "perp"])),
            format(tot$state_snapshot_json_bytes, big.mark = ","), nrow(est$state_snapshot),
            as.integer(sum(est$state_snapshot$weight))),
    "",
    sprintf("Requests this run: %d total, %d failed, weight %d, %.0f s inside requests, %.0f s wall including pacing.",
            tot_req, sum(!log$ok), tot_w, tot_s, est$wall_s),
    "",
    "## Method and limits",
    "",
    "- The sample is about 30 of the in-scope markets; every scaled figure is an extrapolation from it, not a measurement of all markets.",
    "- Funding history is paged by the last row time plus one; `(coin, time)` is asserted unique.",
    "- The delisted-funding cap saving is measured on the sampled delisted perps only (each has an uncapped control fetch, whose requests are included in this run's request and weight totals) and scaled by their count; the cap itself applies to every delisted perp.",
    "- Delisted markets are fetched without the end-minus-5000-bars start: a window clamped to now returns `[]` for them (observed on MATIC hourly).",
    "- Bars whose close time is after the fetch time are dropped (the in-progress bar).",
    "- Exit 3 (and no file written here) if any sampled request failed or a live listed market returned `[]`."
  )
  writeLines(lines, paste0(stem, ".md"))
  utils::write.csv(log, paste0(stem, "_requests.csv"), row.names = FALSE)
  jsonlite::write_json(
    list(date_utc = date_utc, commit = git_sha, headline = headline,
         enumeration = A$enumeration, out_of_scope = oos, sample = sample_tbl,
         requests = A$requests, parquet_bytes_per_row = A$bpr,
         scaled = A$scale$by_group_dataset, totals = A$scale$totals,
         funding = fund_tbl, offset_outliers = outlier_rows),
    paste0(stem, ".json"), auto_unbox = TRUE, digits = NA, pretty = TRUE, na = "null")
  invisible(stem)
}

.hl_estimate_main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  opt <- function(name, default) {
    hit <- grep(paste0("^--", name, "="), args, value = TRUE)
    if (length(hit) == 0L) default else sub(paste0("^--", name, "="), "", hit[1])
  }
  audits_dir <- opt("audits-dir", "audits")
  raw_dir <- opt("raw-dir", "data/raw/hyperliquid")
  rec <- hl_make_recorder(raw_dir, pace = as.numeric(opt("pace", HL_PACE_FRACTION)))
  tmp <- tempfile("hl_est_")
  cli_h1("Hyperliquid volume estimate (#1072)")
  est <- tryCatch(hl_estimate(rec, tmp_dir = tmp), error = function(e) e)
  if (inherits(est, "error")) {
    cli_alert_danger("INDETERMINATE: {conditionMessage(est)}")
    failed_log <- rec$log()
    if (nrow(failed_log) > 0L) {
      dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
      utils::write.csv(failed_log, file.path(raw_dir, "estimate_failed_requests.csv"), row.names = FALSE)
    }
    quit(save = "no", status = 3L)
  }
  if (length(est$problems) > 0L) {
    cli_alert_danger("INDETERMINATE: {length(est$problems)} problem(s)")
    for (p in est$problems) cli_alert_danger(p)
    dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
    utils::write.csv(est$log, file.path(raw_dir, "estimate_failed_requests.csv"), row.names = FALSE)
    quit(save = "no", status = 3L)
  }
  A <- hl_assemble(est)
  # the commit of THIS script's repository, not of the caller's working directory
  sha <- tryCatch(system2("git", c("-C", .hl_est_dir(), "rev-parse", "--short", "HEAD"), stdout = TRUE),
                  error = function(e) "unknown")
  stem <- hl_write_report(est, A, audits_dir, format(Sys.time(), "%Y-%m-%d", tz = "UTC"), sha[1])
  cli_alert_success("wrote {stem}.md / .json / _requests.csv")
  invisible(TRUE)
}

if (sys.nframe() == 0L) {
  .hl_estimate_main()
}
