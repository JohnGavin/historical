testthat::local_edition(3)
source(here::here("scripts", "fetch_hyperliquid.R"))

# scripts/fetch_hyperliquid.R (#870, #1072). NO network (except the opt-in
# HD_TEST_LIVE=1 block): every call is mocked from trimmed REAL responses in
# tests/testthat/fixtures/hyperliquid/. Hyperliquid markets are PERPETUAL
# FUTURES and spot pairs, not tokenised shares.

.fx <- function(name) {
  jsonlite::read_json(
    here::here("tests", "testthat", "fixtures", "hyperliquid", name),
    simplifyVector = FALSE
  )
}
.candles <- .fx("candles_sol.json")
.funding <- .fx("funding_sol.json")
.meta_xyz <- .fx("meta_xyz.json")
.mac_core <- .fx("meta_core.json")  # real metaAndAssetCtxs payload: [meta, ctxs]
.meta_core <- .mac_core[[1]]
.dexs <- .fx("perpdexs.json")
.apm <- .fx("allperpmetas.json")            # BTC SOL MATIC(delisted) xyz:* flx:TSLA(delisted)
.spot_meta <- .fx("spotmeta.json")
.spot_ctx <- .fx("spotmetaandassetctxs.json")  # + 2 unlisted @N, 2 outcome #N
.h1 <- .fx("candles_btc_1h_inprogress.json")    # last bar is IN PROGRESS
.matic_1d <- .fx("candles_matic_1d.json")
.matic_1h <- .fx("candles_matic_1h.json")
.empty <- .fx("candles_empty.json")             # real `[]` reply
.f_offset <- .fx("funding_btc_offset.json")     # 2023-05-23T08:23:53Z row
.f_switch <- .fx("funding_btc_switch.json")     # 8h -> 1h switch

# A fetch time inside the last (in-progress) hourly bar.
.fetch_ms <- as.numeric(.h1[[length(.h1)]]$t) + 1
.end <- as.POSIXct(.fetch_ms / 1000, origin = "1970-01-01", tz = "UTC")

# Mock endpoint. Core metaAndAssetCtxs is the real fixture; the builder-dex
# ctxs are SYNTHETIC (no real fixture) and only exercise the parser shape.
.mock_post <- function(overrides = list()) {
  function(body) {
    if (!is.null(overrides[[body$type]])) return(overrides[[body$type]](body))
    switch(body$type,
      allPerpMetas = .apm,
      spotMeta = .spot_meta,
      spotMetaAndAssetCtxs = .spot_ctx,
      metaAndAssetCtxs = if (is.null(body$dex)) .mac_core else {
        list(.meta_xyz, lapply(.meta_xyz$universe, function(u)
          list(openInterest = "10.5", markPx = "100.25")))
      },
      candleSnapshot = {
        src <- if (body$req$interval == "1h") .h1 else .candles
        Filter(function(r) r$t >= body$req$startTime, src)
      },
      fundingHistory = Filter(function(r) r$time >= body$startTime, .funding),
      stop("unmocked type: ", body$type)
    )
  }
}
.no_sleep <- function(s) invisible(NULL)
.run <- function(post, out, ...) {
  suppressMessages(hl_run(post, out_dir = out, sleep_fn = .no_sleep,
                          end = .end, ...))
}

# ── existing behaviour (#870) ──────────────────────────────────────

test_that("dex list: null entry is core, wallet fields are not required", {
  expect_equal(hl_parse_dexs(.dexs)[1], "")
  expect_true("xyz" %in% hl_parse_dexs(.dexs))
})

test_that("universe parse keeps listed coin and strips dex prefix", {
  m <- hl_parse_universe(.meta_xyz, "xyz")
  expect_true("xyz:TSLA" %in% m$coin)
  expect_equal(m$symbol[m$coin == "xyz:TSLA"], "TSLA")
  core <- hl_parse_universe(.meta_core, "")
  expect_true("BTC" %in% core$symbol)
  expect_equal(core$symbol, core$coin)
})

test_that("empty market list fails (falsifiable negative)", {
  expect_error(hl_parse_universe(list(universe = list()), "xyz"),
               class = "hl_empty_markets")
  expect_error(hl_parse_universe(list(), ""), class = "hl_empty_markets")
})

test_that("candles parse to a typed daily frame", {
  d <- hl_parse_candles(.candles, "", "SOL")
  expect_equal(nrow(d), length(.candles))
  expect_s3_class(d$date, "Date")
  expect_equal(d$date[1], as.Date("2025-11-01"))  # t = 1761955200000
  expect_true(all(d$instrument_type == "perp"))
  expect_true(all(d$source == "hyperliquid"))
  expect_type(d$close, "double")
  expect_equal(d$close[1], 186.31)
})

test_that("a candle missing a required field errors (no c)", {
  bad <- lapply(.candles, function(r) { r$c <- NULL; r })
  expect_error(hl_parse_candles(bad, "", "SOL"), "missing required field")
})

test_that("non-numeric candle value errors rather than becoming NA", {
  bad <- .candles
  bad[[1]]$o <- "not-a-number"
  expect_error(hl_parse_candles(bad, "", "SOL"), "Non-numeric")
})

test_that("volume_base is the raw base volume, not quote volume", {
  d <- hl_parse_candles(.candles, "", "SOL")
  expect_equal(d$volume_base, as.numeric(vapply(.candles, `[[`, "", "v")))
  expect_false(any(c("volume_quote", "volume", "notional") %in% names(d)))
  # Falsification: if volume were mistaken for notional (v * close) it differs.
  expect_false(isTRUE(all.equal(d$volume_base, d$volume_base * d$close)))
})

test_that("funding aggregates hourly rows per UTC date with hour counts", {
  f <- hl_parse_funding_daily(.funding, "", "SOL")
  expect_equal(sum(f$n_hours), length(.funding))
  expect_equal(sum(f$funding_sum),
               sum(as.numeric(vapply(.funding, `[[`, "", "fundingRate"))))
  expect_true(all(f$n_hours <= 24L))
  expect_equal(f$date[1], as.Date("2025-11-01"))
})

test_that("funding record missing fundingRate errors", {
  bad <- lapply(.funding, function(r) { r$fundingRate <- NULL; r })
  expect_error(hl_parse_funding_daily(bad, "", "SOL"), "missing required field")
})

test_that("OI snapshot carries fetched_at and rejects length mismatch", {
  post <- .mock_post()
  mac <- post(list(type = "metaAndAssetCtxs", dex = "xyz"))
  s <- hl_parse_oi_snapshot(mac, "xyz", "2026-11-01 00:00:00 UTC")
  expect_true(all(s$fetched_at == "2026-11-01 00:00:00 UTC"))
  expect_equal(nrow(s), length(.meta_xyz$universe))
  mac[[2]] <- mac[[2]][-1]
  expect_error(hl_parse_oi_snapshot(mac, "xyz", "t"), "differ")
})

test_that("funding paging stops on a non-advancing page (no infinite loop)", {
  stuck <- function(body) .funding[1:3]  # always returns the same full page
  expect_error(
    hl_fetch_funding("SOL", 0, 4e12, stuck, page_max = 3L, sleep_fn = .no_sleep),
    class = "hl_paging_stalled"
  )
})

test_that("funding paging advances across pages and collects every record", {
  post <- function(body) Filter(function(r) r$time >= body$startTime, .funding)
  out <- hl_fetch_funding("SOL", 0, 4e12, post, page_max = 2L, sleep_fn = .no_sleep)
  expect_equal(length(unique(vapply(out, function(r) r$time, numeric(1)))),
               length(.funding))
})

test_that("upsert twice gives no duplicate rows and new values win", {
  p <- withr::local_tempfile(fileext = ".parquet")
  d <- hl_parse_candles(.candles, "", "SOL")
  hl_upsert(d, p, c("dex", "coin", "date"))
  d2 <- d; d2$close[1] <- 999
  hl_upsert(d2, p, c("dex", "coin", "date"))
  got <- arrow::read_parquet(p)
  expect_equal(nrow(got), nrow(d))
  expect_false(anyDuplicated(got[c("dex", "coin", "date")]) > 0)
  expect_equal(got$close[got$date == d$date[1]], 999)
})

test_that("hl_run happy path writes every table, status 0", {
  out <- withr::local_tempdir()
  res <- .run(.mock_post(), out)
  expect_equal(res$status, 0L)
  daily <- arrow::read_parquet(file.path(out, "perp_daily.parquet"))
  expect_true(all(c("", "xyz") %in% daily$dex))
  for (f in c("perp_hourly", "spot_daily", "spot_hourly", "perp_funding_daily",
              "perp_funding", "perp_oi_snapshot")) {
    expect_true(file.exists(file.path(out, paste0(f, ".parquet"))), info = f)
  }
  # idempotent re-run
  res2 <- .run(.mock_post(), out)
  expect_equal(nrow(arrow::read_parquet(file.path(out, "perp_daily.parquet"))),
               nrow(daily))
})

test_that("source unreachable is INDETERMINATE (3), writes nothing", {
  out <- withr::local_tempdir()
  down <- function(body) hl_unavailable("connection refused")
  res <- suppressMessages(hl_run(down, out_dir = out, sleep_fn = .no_sleep))
  expect_equal(res$status, 3L)
  expect_length(list.files(out), 0L)
})

test_that("empty market list is INDETERMINATE (3), not 'no data'", {
  out <- withr::local_tempdir()
  post <- .mock_post(list(allPerpMetas = function(body) list()))
  res <- suppressMessages(hl_run(post, out_dir = out, sleep_fn = .no_sleep))
  expect_equal(res$status, 3L)
  expect_length(list.files(out), 0L)
})

test_that("every market failing as unavailable after listing is status 3", {
  out <- withr::local_tempdir()
  post <- .mock_post(list(
    candleSnapshot = function(body) hl_unavailable("HTTP 429"),
    metaAndAssetCtxs = function(body) hl_unavailable("HTTP 429")
  ))
  res <- suppressMessages(hl_run(post, out_dir = out, sleep_fn = .no_sleep))
  expect_equal(res$status, 3L)
})

test_that("per-market failure is isolated: others written, status 1", {
  out <- withr::local_tempdir()
  base <- .mock_post()
  post <- function(body) {
    if (body$type == "candleSnapshot" && body$req$coin == "xyz:TSLA") {
      cli::cli_abort("boom")
    }
    base(body)
  }
  res <- .run(post, out)
  expect_equal(res$status, 1L)
  expect_equal(res$failed$item, "xyz:xyz:TSLA")
  daily <- arrow::read_parquet(file.path(out, "perp_daily.parquet"))
  expect_false("xyz:TSLA" %in% daily$coin)
  expect_true("BTC" %in% daily$coin)
})

# ── Phase 1 (#1072): interval ──────────────────────────────────────

test_that("an unknown interval aborts (snapshot)", {
  expect_snapshot(error = TRUE, hl_fetch_candles("BTC", 0, 1e12, interval = "5m"))
  expect_snapshot(error = TRUE, hl_parse_candles(.candles, "", "SOL", interval = "15m"))
  expect_error(hl_fetch_candles("BTC", 0, 1e12, interval = "5m"),
               class = "hl_bad_interval")
  # Red/green: the two allowed intervals do not abort.
  post <- function(body) list()
  expect_no_error(hl_fetch_candles("BTC", 0, 1e12, post, interval = "1h"))
  expect_no_error(hl_fetch_candles("BTC", 0, 1e12, post, interval = "1d"))
})

test_that("candles are ONE request per market per interval, start = end - 5000 bars", {
  seen <- list()
  post <- function(body) { seen[[length(seen) + 1L]] <<- body; list() }
  end_ms <- 1.8e12
  hl_fetch_candles("BTC", 0, end_ms, post, interval = "1h")
  expect_length(seen, 1L)
  expect_equal(seen[[1]]$req$startTime, end_ms - HL_CANDLE_PAGE_MAX * 3600000)
  expect_equal(seen[[1]]$req$interval, "1h")
  # a start later than the retained window wins; a delisted market is not clamped
  hl_fetch_candles("BTC", end_ms - 1000, end_ms, post, interval = "1h")
  expect_equal(seen[[2]]$req$startTime, end_ms - 1000)
  hl_fetch_candles("MATIC", 5, end_ms, post, interval = "1h", clamp = FALSE)
  expect_equal(seen[[3]]$req$startTime, 5)
})

test_that("hourly bars key on UTC `time`; daily on `date`", {
  h <- hl_parse_candles(.h1, "", "BTC", "1h")
  expect_s3_class(h$time, "POSIXct")
  expect_false("date" %in% names(h))
  expect_equal(attr(h$time, "tzone"), "UTC")
  expect_equal(as.numeric(h$time[1]) * 1000, as.numeric(.h1[[1]]$t))
  expect_true("date" %in% names(hl_parse_candles(.candles, "", "SOL", "1d")))
})

test_that("an unknown instrument type aborts (snapshot)", {
  expect_snapshot(error = TRUE,
                  hl_parse_candles(.candles, "", "SOL", instrument_type = "future"))
  expect_equal(unique(hl_parse_candles(.candles, "", "@1", instrument_type = "spot")$instrument_type),
               "spot")
})

# ── bar fields ─────────────────────────────────────────────────────

test_that("n and T are parsed; traded = n > 0; pre-launch bars are kept", {
  bars <- .candles
  bars[[1]]$n <- 0; bars[[1]]$v <- "0.0"   # pre-launch shape
  d <- hl_parse_candles(bars, "", "SOL")
  expect_equal(nrow(d), length(bars))           # kept, not dropped
  expect_false(d$traded[1])
  expect_true(all(d$traded[-1]))
  expect_equal(d$n_trades[2], 122993)
  expect_equal(as.numeric(d$close_time[1]) * 1000, 1762041599999)
  # Red: a bar missing `n` is an error, not an assumed trade count
  nob <- lapply(.candles, function(r) { r$n <- NULL; r })
  expect_error(hl_parse_candles(nob, "", "SOL"), "missing required field")
})

test_that("the in-progress bar is dropped and counted", {
  dp <- hl_drop_in_progress(.h1, .fetch_ms)
  expect_equal(dp$n_dropped, 1L)
  expect_equal(length(dp$kept), length(.h1) - 1L)
  expect_true(all(vapply(dp$kept, function(r) as.numeric(r$T), 1) <= .fetch_ms))
  # Red: a fetch time after every close drops nothing (the guard can go red)
  expect_equal(hl_drop_in_progress(.h1, 4e12)$n_dropped, 0L)
})

test_that("hl_run reports dropped in-progress bars and stores none of them", {
  out <- withr::local_tempdir()
  res <- .run(.mock_post(), out)
  expect_gt(res$n_in_progress_dropped, 0L)
  h <- arrow::read_parquet(file.path(out, "perp_hourly.parquet"))
  expect_true(all(as.numeric(h$close_time) * 1000 <= .fetch_ms))
})

# ── empty reply / null reply ───────────────────────────────────────

test_that("the real `[]` reply parses to zero rows", {
  expect_length(.empty, 0L)
  expect_equal(nrow(hl_parse_candles(.empty, "", "BTC", "1h")), 0L)
})

test_that("`[]` for a listed live market is INDETERMINATE, never a silent success", {
  out <- withr::local_tempdir()
  base <- .mock_post()
  post <- function(body) {
    if (body$type == "candleSnapshot" && body$req$coin == "BTC") return(.empty)
    base(body)
  }
  res <- .run(post, out)
  expect_equal(res$status, 3L)
  expect_true(":BTC" %in% res$failed$item)
  expect_match(res$failed$reason[res$failed$item == ":BTC"], "empty candle reply")
  # others were still written
  expect_true("SOL" %in% arrow::read_parquet(file.path(out, "perp_daily.parquet"))$coin)
  expect_snapshot(error = TRUE, hl_empty_reply("candle", "BTC"))
})

test_that("`[]` for a DELISTED market is not flagged (its window is outside retention)", {
  out <- withr::local_tempdir()
  base <- .mock_post()
  post <- function(body) {
    if (body$type %in% c("candleSnapshot", "fundingHistory") &&
        (body$req$coin %||% body$coin) == "MATIC") return(.empty)
    base(body)
  }
  res <- .run(post, out)
  expect_equal(res$status, 0L)
})

test_that("a delisted market is fetched with its own start, a live one is clamped", {
  starts <- list()
  base <- .mock_post()
  post <- function(body) {
    if (body$type == "candleSnapshot" && body$req$interval == "1h") {
      starts[[body$req$coin]] <<- body$req$startTime
    }
    base(body)
  }
  .run(post, withr::local_tempdir())
  start_ms <- as.numeric(as.POSIXct(as.Date("2023-01-01"), tz = "UTC")) * 1000
  expect_equal(starts[["MATIC"]], start_ms)
  expect_gt(starts[["BTC"]], start_ms)
})

test_that("a `null` reply (unknown coin) is an error, not an empty window (snapshot)", {
  expect_snapshot(error = TRUE, hl_fetch_candles("NOSUCH", 0, 1e12, function(b) NULL))
  expect_error(hl_fetch_candles("NOSUCH", 0, 1e12, function(b) NULL),
               class = "hl_null_reply")
  expect_error(hl_fetch_funding("NOSUCH", 0, 1e12, function(b) NULL),
               class = "hl_null_reply")
})

# ── market classes ─────────────────────────────────────────────────

test_that("coins are classified by prefix AND universe membership", {
  un <- c("PURR/USDC", "@1")
  got <- hl_classify_coin(c("BTC", "xyz:TSLA", "PURR/USDC", "@1", "@999", "#363660"), un)
  expect_equal(got, c("main_perp", "builder_perp", "spot_pair", "spot_pair",
                      "spot_unlisted", "outcome"))
  expect_true(all(got %in% HL_MARKET_CLASSES))
  # Red: the same `@1` is unlisted once it leaves the universe
  expect_equal(hl_classify_coin("@1", "PURR/USDC"), "spot_unlisted")
})

test_that("an unrecognised market form aborts (snapshot)", {
  expect_snapshot(error = TRUE, hl_classify_coin("weird thing!"))
  expect_snapshot(error = TRUE, hl_classify_coin("PURR/USDC", character()))
  expect_error(hl_classify_coin("#abc"), class = "hl_unknown_market_class")
})

test_that("allPerpMetas parses to perps with the delisted flag and exchange", {
  p <- hl_parse_perp_markets(.apm)
  expect_equal(p$market_class[p$coin == "BTC"], "main_perp")
  expect_equal(p$market_class[p$coin == "xyz:TSLA"], "builder_perp")
  expect_equal(p$dex[p$coin == "xyz:TSLA"], "xyz")
  expect_equal(p$dex[p$coin == "BTC"], "")
  expect_true(p$is_delisted[p$coin == "MATIC"])
  expect_true(p$is_delisted[p$coin == "flx:TSLA"])
  expect_false(p$is_delisted[p$coin == "BTC"])
  expect_true(all(p$instrument_type == "perp"))
})

test_that("allPerpMetas guards abort on empty or non-perp input (snapshot)", {
  expect_snapshot(error = TRUE, hl_parse_perp_markets(list()))
  expect_snapshot(error = TRUE, hl_parse_perp_markets(list(list(universe = list()))))
  expect_snapshot(error = TRUE,
                  hl_parse_perp_markets(list(list(universe = list(list(name = "@1"))))))
})

test_that("spot markets: universe pairs, 24h volume, out-of-scope counted", {
  s <- hl_parse_spot_markets(.spot_meta, .spot_ctx)
  expect_setequal(s$markets$coin, c("PURR/USDC", "@1", "@3"))
  expect_true(all(s$markets$instrument_type == "spot"))
  expect_true(s$markets$traded_24h[s$markets$coin == "@1"])
  expect_false(s$markets$traded_24h[s$markets$coin == "@3"])
  oos <- stats::setNames(s$out_of_scope$n, s$out_of_scope$market_class)
  expect_equal(oos[["spot_unlisted"]], 2L)
  expect_equal(oos[["outcome"]], 2L)
})

test_that("spot contexts are joined by coin, never by position", {
  base <- hl_parse_spot_markets(.spot_meta, .spot_ctx)$markets
  rev_ctx <- list(.spot_ctx[[1]], rev(.spot_ctx[[2]]))   # contexts in reverse order
  shuf <- hl_parse_spot_markets(.spot_meta, rev_ctx)$markets
  expect_false(identical(vapply(rev_ctx[[2]], `[[`, "", "coin")[1:3],
                         vapply(.spot_ctx[[2]], `[[`, "", "coin")[1:3]))
  expect_equal(shuf$day_ntl_vlm[match(base$coin, shuf$coin)], base$day_ntl_vlm)
  expect_equal(base$day_ntl_vlm[base$coin == "@1"], 112097.170272)
  # Red: a positional join of the reversed contexts would give @1 another volume
  pos <- hl_num(lapply(rev_ctx[[2]], `[[`, "dayNtlVlm"), "x")[seq_len(nrow(base))]
  expect_false(isTRUE(all.equal(pos, base$day_ntl_vlm)))
})

test_that("spot guards abort on empty universe or bad payload (snapshot)", {
  expect_snapshot(error = TRUE, hl_parse_spot_markets(list(universe = list()), .spot_ctx))
  expect_snapshot(error = TRUE, hl_parse_spot_markets(.spot_meta, list(1, 2, 3)))
})

test_that("hl_run writes spot bars as instrument_type spot, traded pairs only", {
  out <- withr::local_tempdir()
  res <- .run(.mock_post(), out)
  sp <- arrow::read_parquet(file.path(out, "spot_daily.parquet"))
  expect_true(all(sp$instrument_type == "spot"))
  expect_setequal(unique(sp$coin), c("PURR/USDC", "@1"))   # @3 has zero 24h volume
  expect_equal(res$out_of_scope$n[res$out_of_scope$market_class == "outcome"], 2L)
  pd <- arrow::read_parquet(file.path(out, "perp_daily.parquet"))
  expect_true(all(pd$instrument_type == "perp"))
})

test_that("delisted markets are fetched but flagged", {
  out <- withr::local_tempdir()
  .run(.mock_post(), out)
  pd <- arrow::read_parquet(file.path(out, "perp_daily.parquet"))
  expect_true(all(pd$is_delisted[pd$coin == "MATIC"]))
  expect_true(all(pd$is_delisted[pd$coin == "flx:TSLA"]))
  expect_false(any(pd$is_delisted[pd$coin == "BTC"]))
  expect_equal(unique(pd$market_class[pd$coin == "xyz:TSLA"]), "builder_perp")
})

# ── raw funding ────────────────────────────────────────────────────

test_that("raw funding keeps every row and reads 8h -> 1h from the gaps", {
  f <- hl_parse_funding_raw(.f_switch, "", "BTC")
  expect_equal(nrow(f), length(.f_switch))
  expect_setequal(f$interval_hours, c(8, 1))
  switch_time <- as.POSIXct("2023-06-08 00:00:30", tz = "UTC")
  expect_true(all(f$interval_hours[f$time < switch_time] == 8))
  expect_true(all(f$interval_hours[f$time > switch_time] == 1))
  expect_equal(f$rate_per_hour, f$funding_rate / f$interval_hours)
  expect_true(all(is.finite(f$premium)))
  expect_false(anyDuplicated(f[c("coin", "time_ms")]) > 0)
})

test_that("a funding offset past the hour above the threshold is FLAGGED, not floored", {
  f <- hl_parse_funding_raw(.f_offset, "", "BTC")
  expect_equal(nrow(f), 3L)                    # not dropped
  expect_equal(f$offset_outlier, c(FALSE, TRUE, FALSE))
  expect_equal(f$offset_min[2], 23.9, tolerance = 0.01)   # 08:23:53 -> not floored
  expect_equal(f$time_ms[2], 1684830233040)
  expect_equal(f$interval_hours, c(8, 8, 8))   # a 24 min offset does not change it
  # Red: the switch slice (rows ms past the hour) flags nothing
  expect_false(any(hl_parse_funding_raw(.f_switch, "", "BTC")$offset_outlier))
})

test_that("a single funding row has no gap: interval and rate_per_hour are NA", {
  f <- hl_parse_funding_raw(.f_offset[2], "", "BTC")
  expect_true(is.na(f$interval_hours))
  expect_true(is.na(f$rate_per_hour))
})

test_that("duplicate (coin, time) funding rows abort (snapshot)", {
  expect_snapshot(error = TRUE,
                  hl_parse_funding_raw(c(.f_offset, .f_offset[2]), "", "BTC"))
  expect_error(hl_parse_funding_raw(c(.f_offset, .f_offset[2]), "", "BTC"),
               class = "hl_duplicate_keys")
})

test_that("paging that repeats a boundary row aborts (snapshot)", {
  k <- 0L
  post <- function(body) {
    k <<- k + 1L
    switch(k, .funding[1:2], .funding[2:3], list())  # row 2 repeats
  }
  expect_snapshot(error = TRUE,
                  hl_fetch_funding("SOL", 0, 4e12, post, page_max = 2L,
                                   sleep_fn = .no_sleep))
  # Green: a clean pager (start = last time + 1) yields no duplicates
  clean <- function(body) Filter(function(r) r$time >= body$startTime, .funding)
  out <- hl_fetch_funding("SOL", 0, 4e12, clean, page_max = 2L, sleep_fn = .no_sleep)
  expect_false(anyDuplicated(vapply(out, function(r) r$time, 1)) > 0)
})

test_that("hl_run writes the raw funding table beside the daily sums", {
  out <- withr::local_tempdir()
  .run(.mock_post(), out)
  raw <- arrow::read_parquet(file.path(out, "perp_funding.parquet"))
  expect_gt(nrow(raw), 0L)
  expect_false(anyDuplicated(raw[c("dex", "coin", "time_ms")]) > 0)
  expect_true(all(c("interval_hours", "rate_per_hour", "offset_outlier") %in% names(raw)))
})

# ── raw JSON, append-only ──────────────────────────────────────────

test_that("raw responses are dated, tagged, and never overwritten", {
  d <- withr::local_tempdir()
  body <- list(type = "candleSnapshot", req = list(coin = "xyz:TSLA", interval = "1h"))
  t0 <- as.POSIXct("2026-11-15 10:00:00", tz = "UTC")
  p1 <- hl_save_raw(body, "[1]", d, t0)
  p2 <- hl_save_raw(body, "[2]", d, t0)
  p3 <- hl_save_raw(body, "[3]", d, t0)
  expect_equal(basename(dirname(p1)), "2026-11-15")
  expect_equal(basename(p1), "candleSnapshot_xyz_TSLA_1h.json")
  expect_length(unique(c(p1, p2, p3)), 3L)
  .read_raw <- function(p) rawToChar(readBin(p, "raw", file.size(p)))
  expect_equal(.read_raw(p1), "[1]")   # first file untouched
  expect_equal(.read_raw(p2), "[2]")
  expect_equal(.read_raw(p3), "[3]")
})

test_that("coin tags are filesystem safe", {
  expect_equal(hl_file_tag("@107"), "at107")
  expect_equal(hl_file_tag("PURR/USDC"), "PURR_USDC")
  expect_equal(hl_file_tag("#363660"), "hash363660")
})

test_that("hl_make_post records the raw text of every real response", {
  d <- withr::local_tempdir()
  post <- hl_make_post(d)
  got <- httr2::with_mocked_responses(
    function(req) httr2::response(status_code = 200,
                                  headers = list(`Content-Type` = "application/json"),
                                  body = charToRaw('{"a":1}')),
    post(list(type = "spotMeta"))
  )
  expect_equal(got$a, 1)
  f <- list.files(d, recursive = TRUE, full.names = TRUE)
  expect_length(f, 1L)
  expect_match(basename(f), "^spotMeta_all_na\\.json$")
  expect_equal(rawToChar(readBin(f, "raw", file.size(f))), '{"a":1}')
})

test_that("data/raw/ is gitignored (raw data is never committed)", {
  gi <- readLines(here::here(".gitignore"))
  expect_true("data/raw/" %in% gi)
})

# ── opt-in live test ───────────────────────────────────────────────

test_that("LIVE: hourly BTC candles come back and the in-progress bar is detectable", {
  skip_if_not(identical(Sys.getenv("HD_TEST_LIVE"), "1"), "HD_TEST_LIVE != 1")
  now_ms <- floor(as.numeric(Sys.time()) * 1000)
  x <- hl_fetch_candles("BTC", 0, now_ms, hl_post, interval = "1h")
  expect_gt(length(x), 100L)
  expect_gte(hl_drop_in_progress(x, now_ms)$n_dropped, 1L)
})

# ── output-shape snapshots (parsers on real fixtures) ───────────────
# These pin the exact parsed shape so an accidental schema or value drift is
# a visible diff, not a silent change.

test_that("snapshot: perp market table from allPerpMetas", {
  expect_snapshot(print(hl_parse_perp_markets(.apm)))
})

test_that("snapshot: spot market table and out-of-scope counts", {
  s <- hl_parse_spot_markets(.spot_meta, .spot_ctx)
  expect_snapshot(print(s$markets))
  expect_snapshot(print(s$out_of_scope))
})

test_that("snapshot: hourly bars incl. n_trades, traded and close_time", {
  h <- hl_parse_candles(.h1, "", "BTC", "1h")
  expect_snapshot(print(h[c("time", "coin", "open", "close", "n_trades", "traded", "close_time")]))
})

test_that("snapshot: delisted MATIC daily and hourly bars", {
  expect_snapshot(print(hl_parse_candles(.matic_1d, "", "MATIC")[c("date", "close", "n_trades", "traded")]))
  expect_snapshot(print(hl_parse_candles(.matic_1h, "", "MATIC", "1h")[c("time", "close", "traded")]))
})

test_that("snapshot: funding offset slice keeps and flags the 24-minute row", {
  f <- hl_parse_funding_raw(.f_offset, "", "BTC")
  expect_snapshot(print(f[c("time", "funding_rate", "interval_hours", "offset_min", "offset_outlier")]))
})

test_that("snapshot: funding 8h -> 1h switch read from the gaps", {
  f <- hl_parse_funding_raw(.f_switch, "", "BTC")
  r <- rle(f$interval_hours)
  expect_snapshot(print(data.frame(interval_hours = r$values, n_rows = r$lengths)))
  expect_snapshot(print(f[f$time >= as.POSIXct("2023-06-07 23:00:00", tz = "UTC") &
                            f$time <= as.POSIXct("2023-06-08 02:00:00", tz = "UTC"),
                          c("time", "interval_hours", "rate_per_hour")]))
})

test_that("snapshot: hl_run summary (happy path, and the `[]` live-market case)", {
  ok <- .run(.mock_post(), withr::local_tempdir())
  expect_snapshot(print(ok[c("status", "n_markets", "n_in_progress_dropped")]))
  expect_snapshot(print(ok$out_of_scope))
  base <- .mock_post()
  post <- function(body) {
    if (body$type == "candleSnapshot" && body$req$coin == "BTC") return(.empty)
    base(body)
  }
  bad <- .run(post, withr::local_tempdir())
  expect_snapshot(print(bad$failed, row.names = FALSE))
})

test_that("snapshot: output files written by hl_run", {
  out <- withr::local_tempdir()
  .run(.mock_post(), out)
  expect_snapshot(print(sort(list.files(out))))
  expect_snapshot(print(names(arrow::read_parquet(file.path(out, "perp_hourly.parquet")))))
  expect_snapshot(print(names(arrow::read_parquet(file.path(out, "perp_funding.parquet")))))
})

test_that("snapshot: raw store layout (dated dir, never overwritten)", {
  d <- withr::local_tempdir()
  t0 <- as.POSIXct("2026-11-15 10:00:00", tz = "UTC")
  body <- list(type = "fundingHistory", coin = "@107", startTime = 0)
  hl_save_raw(body, "[]", d, t0)
  hl_save_raw(body, "[]", d, t0)
  hl_save_raw(list(type = "allPerpMetas"), "[]", d, t0)
  expect_snapshot(print(sort(list.files(d, recursive = TRUE))))
})
