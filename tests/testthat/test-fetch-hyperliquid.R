testthat::local_edition(3)
source(here::here("scripts", "fetch_hyperliquid.R"))

# scripts/fetch_hyperliquid.R (#870). NO network: every call is mocked from
# trimmed real responses in tests/testthat/fixtures/hyperliquid/. Hyperliquid
# markets are PERPETUAL FUTURES, not tokenised shares.

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

# Mock endpoint. Core metaAndAssetCtxs is the real fixture; the xyz ctxs are
# SYNTHETIC (no real fixture) and only exercise the parser shape.
.mock_post <- function(overrides = list()) {
  function(body) {
    if (!is.null(overrides[[body$type]])) return(overrides[[body$type]](body))
    switch(body$type,
      perpDexs = list(NULL, list(name = "xyz", fullName = "XYZ")),
      meta = if (is.null(body$dex)) .meta_core else .meta_xyz,
      metaAndAssetCtxs = if (is.null(body$dex)) .mac_core else {
        list(.meta_xyz, lapply(.meta_xyz$universe, function(u)
          list(openInterest = "10.5", markPx = "100.25")))
      },
      candleSnapshot = Filter(function(r) r$t >= body$req$startTime, .candles),
      fundingHistory = Filter(function(r) r$time >= body$startTime, .funding),
      stop("unmocked type: ", body$type)
    )
  }
}
.no_sleep <- function(s) invisible(NULL)

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

test_that("paging stops on a non-advancing page (no infinite loop)", {
  stuck <- function(body) .candles[1:3]  # always returns the same full page
  expect_error(
    hl_fetch_candles("SOL", 0, 4e12, stuck, page_max = 3L, sleep_fn = .no_sleep),
    class = "hl_paging_stalled"
  )
})

test_that("paging advances across pages and collects every record", {
  post <- function(body) Filter(function(r) r$t >= body$req$startTime, .candles)
  out <- hl_fetch_candles("SOL", 0, 4e12, post, page_max = 2L, sleep_fn = .no_sleep)
  expect_equal(length(unique(vapply(out, function(r) r$t, numeric(1)))),
               length(.candles))
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

test_that("hl_run happy path writes all three tables, status 0", {
  out <- withr::local_tempdir()
  res <- suppressMessages(hl_run(.mock_post(), out_dir = out, sleep_fn = .no_sleep,
                                  end = as.POSIXct("2026-11-01", tz = "UTC")))
  expect_equal(res$status, 0L)
  daily <- arrow::read_parquet(file.path(out, "perp_daily.parquet"))
  expect_true(all(c("", "xyz") %in% daily$dex))
  expect_true(file.exists(file.path(out, "perp_funding_daily.parquet")))
  expect_true(file.exists(file.path(out, "perp_oi_snapshot.parquet")))
  # idempotent re-run
  res2 <- suppressMessages(hl_run(.mock_post(), out_dir = out, sleep_fn = .no_sleep,
                                  end = as.POSIXct("2026-11-01", tz = "UTC")))
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

test_that("empty core market list is INDETERMINATE (3), not 'no data'", {
  out <- withr::local_tempdir()
  post <- .mock_post(list(meta = function(body) list(universe = list())))
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
  res <- suppressMessages(hl_run(post, out_dir = out, sleep_fn = .no_sleep,
                                 end = as.POSIXct("2026-11-01", tz = "UTC")))
  expect_equal(res$status, 1L)
  expect_equal(res$failed$item, "xyz:xyz:TSLA")
  daily <- arrow::read_parquet(file.path(out, "perp_daily.parquet"))
  expect_false("xyz:TSLA" %in% daily$coin)
  expect_true("BTC" %in% daily$coin)
})
