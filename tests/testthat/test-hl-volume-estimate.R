testthat::local_edition(3)
source(here::here("scripts", "hl_volume_estimate.R"))

# scripts/hl_volume_estimate.R (#1072). NO network: the recorder wraps an
# injected `post` that serves trimmed REAL responses from the fixtures of
# test-fetch-hyperliquid.R. The metaAndAssetCtxs contexts are SYNTHETIC (no
# real fixture) and only exercise the parser shape.

.fx <- function(name) {
  jsonlite::read_json(
    here::here("tests", "testthat", "fixtures", "hyperliquid", name),
    simplifyVector = FALSE
  )
}
.apm <- .fx("allperpmetas.json")
.spot_meta <- .fx("spotmeta.json")
.spot_ctx <- .fx("spotmetaandassetctxs.json")
.h1 <- .fx("candles_btc_1h_inprogress.json")
.d1 <- .fx("candles_sol.json")
.f_switch <- .fx("funding_btc_switch.json")
.empty <- .fx("candles_empty.json")
.end <- as.POSIXct((as.numeric(.h1[[length(.h1)]]$t) + 1) / 1000,
                   origin = "1970-01-01", tz = "UTC")

# Fake network: honours `on_response` like hl_post, so bytes are recorded.
.fake_post <- function(overrides = list()) {
  function(body, on_response = NULL) {
    res <- if (!is.null(overrides[[body$type]])) {
      overrides[[body$type]](body)
    } else {
      switch(body$type,
        allPerpMetas = .apm,
        spotMeta = .spot_meta,
        spotMetaAndAssetCtxs = .spot_ctx,
        metaAndAssetCtxs = {
          m <- Filter(function(x) {
            dex <- sub(":.*$", "", x$universe[[1]]$name)
            if (is.null(body$dex)) !grepl(":", x$universe[[1]]$name) else dex == body$dex
          }, .apm)[[1]]
          list(list(universe = m$universe),
               lapply(m$universe, function(u)
                 list(dayNtlVlm = if (isTRUE(u$isDelisted)) "0.0" else "5000.5")))
        },
        candleSnapshot = if (body$req$interval == "1h") .h1 else .d1,
        fundingHistory = Filter(function(r) r$time >= body$startTime, .f_switch),
        stop("unmocked type: ", body$type))
    }
    if (!is.null(on_response)) {
      on_response(body, jsonlite::toJSON(res, auto_unbox = TRUE, null = "null"))
    }
    res
  }
}
.rec <- function(post = .fake_post(), ...) {
  hl_make_recorder(withr::local_tempdir(.local_envir = parent.frame()),
                   sleep_fn = function(s) invisible(NULL), post = post, ...)
}

test_that("snapshot: weight table (documented formula)", {
  expect_snapshot(print(c(
    info = hl_weight("allPerpMetas"),
    candles_5000 = hl_weight("candleSnapshot", HL_CANDLE_PAGE_MAX),
    candles_168 = hl_weight("candleSnapshot", 168),
    funding_500 = hl_weight("fundingHistory", HL_FUNDING_PAGE_MAX),
    funding_168 = hl_weight("fundingHistory", 168)
  )))
})

test_that("sample ranks are evenly spaced, deterministic, include both ends", {
  expect_equal(hl_sample_ranks(100, 5), hl_sample_ranks(100, 5))   # no random draw
  r <- hl_sample_ranks(100, 5)
  expect_equal(c(min(r), max(r)), c(1L, 100L))
  expect_equal(hl_sample_ranks(3, 10), 1:3)       # fewer markets than quota: all
  expect_length(hl_sample_ranks(0, 5), 0L)
  # Red: a different n gives different ranks (the rule depends on the universe)
  expect_false(identical(hl_sample_ranks(100, 5), hl_sample_ranks(90, 5)))
})

test_that("snapshot: sample ranks for a realistic group", {
  expect_snapshot(print(hl_sample_ranks(179, 10)))
})

test_that("the sample takes delisted markets and only traded spot pairs", {
  mk <- bind_rows(
    hl_parse_perp_markets(.apm),
    hl_parse_spot_markets(.spot_meta, .spot_ctx)$markets
  )
  mk$traded_24h[mk$instrument_type == "perp"] <- TRUE
  s <- hl_select_sample(mk)
  expect_gte(sum(s$is_delisted), 2L)
  expect_false("@3" %in% s$coin)       # zero 24h volume
  expect_true(all(c("BTC", "PURR/USDC") %in% s$coin))
  expect_equal(nrow(s), nrow(unique(s)))
})

test_that("recorder logs rows, bytes, weight and paces to the rate limit", {
  slept <- numeric()
  rec <- hl_make_recorder(withr::local_tempdir(),
                          sleep_fn = function(s) slept <<- c(slept, s),
                          post = .fake_post())
  rec$post(list(type = "candleSnapshot",
                req = list(coin = "BTC", interval = "1h", startTime = 0, endTime = 1)))
  lg <- rec$log()
  expect_equal(lg$rows, length(.h1))
  expect_gt(lg$bytes, 10)
  expect_equal(lg$weight, 20)
  expect_true(lg$ok)
  expect_equal(slept, 20 / (HL_RATE_WEIGHT_PER_MIN * HL_PACE_FRACTION / 60), tolerance = 0.05)
  # Red: the pacing stays under the limit (weight per minute implied by the sleep)
  expect_lt(lg$weight / slept * 60, HL_RATE_WEIGHT_PER_MIN)
})

test_that("recorder logs a failed request, then rethrows it", {
  bad <- function(body, on_response = NULL) hl_unavailable("HTTP 429")
  rec <- hl_make_recorder(withr::local_tempdir(), sleep_fn = function(s) NULL, post = bad)
  expect_error(rec$post(list(type = "spotMeta")), class = "hl_source_unavailable")
  expect_false(rec$log()$ok)
  expect_match(rec$log()$error, "429")
})

test_that("perp volumes parse by name inside one response; mismatch aborts (snapshot)", {
  mac <- .fake_post()(list(type = "metaAndAssetCtxs"))
  v <- hl_parse_perp_volumes(mac)
  expect_equal(v$coin, c("BTC", "MATIC", "SOL"))
  expect_equal(v$day_ntl_vlm, c(5000.5, 0, 5000.5))   # delisted MATIC has no volume
  mac[[2]] <- mac[[2]][-1]
  expect_snapshot(error = TRUE, hl_parse_perp_volumes(mac))
})

test_that("end to end on fixtures: report, json and request log are written", {
  rec <- .rec()
  est <- hl_estimate(rec, end = .end, tmp_dir = withr::local_tempdir())
  expect_length(est$problems, 0L)
  A <- hl_assemble(est)
  expect_equal(nrow(A$S), 8L)
  expect_true(all(c("perp_live", "perp_delisted", "spot_live") %in% A$S$group))
  # the 8h -> 1h boundary is read from the funding gaps of the real fixture
  btc <- A$S[A$S$coin == "BTC", ]
  expect_equal(format(btc$funding_switch_8h_to_1h, "%Y-%m-%d %H:%M", tz = "UTC"),
               "2023-06-08 01:00")
  expect_true(all(is.finite(unlist(A$scale$totals))))
  expect_gt(A$scale$totals$backfill_weight, 0)
  d <- withr::local_tempdir()
  stem <- hl_write_report(est, A, d, "2026-11-15", "abc1234")
  for (ext in c(".md", ".json")) expect_true(file.exists(paste0(stem, ext)))
  expect_true(file.exists(paste0(stem, "_requests.csv")))
  md <- readLines(paste0(stem, ".md"))
  expect_true(any(grepl("^## Headline numbers", md)))
  expect_true(any(grepl("BTC: first daily bar", md)))
})

test_that("snapshot: scaled totals on fixtures", {
  rec <- .rec()
  est <- hl_estimate(rec, end = .end, tmp_dir = withr::local_tempdir())
  A <- hl_assemble(est)
  tot <- lapply(A$scale$totals, function(x) signif(x, 4))
  expect_snapshot(print(tot[c("backfill_weight", "weekly_weight", "state_snapshot_weight_per_day")]))
  expect_snapshot(print(A$counts))
})

test_that("`[]` for a live listed market makes the run INDETERMINATE (problems)", {
  post <- .fake_post(list(candleSnapshot = function(body) {
    if (body$req$coin == "BTC") .empty else .h1
  }))
  est <- hl_estimate(.rec(post), end = .end, tmp_dir = withr::local_tempdir())
  expect_true(any(grepl("BTC: empty 1d reply for a live market", est$problems)))
  expect_snapshot(print(est$problems))
})

test_that("a failed sampled request is reported as a problem, not swallowed", {
  post <- .fake_post(list(fundingHistory = function(body) hl_unavailable("HTTP 429")))
  est <- hl_estimate(.rec(post), end = .end, tmp_dir = withr::local_tempdir())
  expect_gt(length(est$problems), 0L)
  expect_true(any(grepl("429", est$problems)))
})

test_that("markdown table helper renders a pipe table", {
  expect_snapshot(cat(hl_md_table(data.frame(a = c(1, 2.5), b = c("x", NA))), sep = "\n"))
})
