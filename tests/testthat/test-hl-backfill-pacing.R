testthat::local_edition(3)
source(here::here("scripts", "fetch_hyperliquid.R"))

# Rate-limit pacing, HTTP 429 back-off and resumable incremental writes for the
# backfill (#1072). NO network and NO waiting: the clock and sleep are injected,
# and the endpoint is a trimmed REAL-response fixture mock (the same fixtures as
# test-fetch-hyperliquid.R). Hyperliquid markets are perpetual futures and spot
# pairs, not tokenised shares.

.fx <- function(name) {
  jsonlite::read_json(
    here::here("tests", "testthat", "fixtures", "hyperliquid", name),
    simplifyVector = FALSE
  )
}
.candles <- .fx("candles_sol.json")
.funding <- .fx("funding_sol.json")
.meta_xyz <- .fx("meta_xyz.json")
.mac_core <- .fx("meta_core.json")
.apm <- .fx("allperpmetas.json")
.spot_meta <- .fx("spotmeta.json")
.spot_ctx <- .fx("spotmetaandassetctxs.json")
.h1 <- .fx("candles_btc_1h_inprogress.json")
.fetch_ms <- as.numeric(.h1[[length(.h1)]]$t) + 1
.end <- as.POSIXct(.fetch_ms / 1000, origin = "1970-01-01", tz = "UTC")

.mock_post <- function() {
  function(body) {
    switch(body$type,
      allPerpMetas = .apm,
      perpDexs = .fx("perpdexs.json"),
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

# Wraps a post_fn and logs every request: the coin of each daily-candle request
# is one market fetched.
.spy <- function(base = .mock_post()) {
  env <- new.env(); env$coins <- character(); env$types <- character()
  list(
    post = function(body) {
      env$types <- c(env$types, body$type)
      if (body$type == "candleSnapshot" && body$req$interval == "1d") {
        env$coins <- c(env$coins, body$req$coin)
      }
      base(body)
    },
    coins = function() env$coins,
    types = function() env$types
  )
}

# A crash that tryCatch(error = ) inside hl_run does NOT catch (not an error).
.crash <- function() {
  stop(structure(class = c("hl_test_crash", "condition"),
                 list(message = "simulated crash", call = NULL)))
}
.crash_after <- function(k, base = .mock_post()) {
  n <- 0L
  function(body) {
    if (body$type == "candleSnapshot" && body$req$interval == "1d") {
      n <<- n + 1L
      if (n > k) .crash()
    }
    base(body)
  }
}
.run <- function(post, out, ...) {
  suppressMessages(hl_run(post, out_dir = out, end = .end, ...))
}
.progress_keys <- function(out) {
  p <- file.path(out, HL_PROGRESS_FILE)
  if (file.exists(p)) readLines(p)[-1] else character()
}
.daily_coins <- function(out) {
  sort(unique(arrow::read_parquet(file.path(out, "perp_daily.parquet"))$coin))
}

# Fake endpoint with a virtual clock: sleeping advances the clock, the request
# itself takes `req_s` virtual seconds.
.vclock <- function(req_s = 0) {
  env <- new.env(); env$t <- 0; env$slept <- numeric(); env$seen <- 0L
  fake <- function(rows) {
    function(body, on_response = NULL) {
      env$seen <- env$seen + 1L
      env$t <- env$t + req_s
      if (is.function(rows)) rows(env$seen, body) else vector("list", rows)
    }
  }
  list(env = env, fake = fake,
       clock = function() env$t,
       sleep = function(s) { env$slept <- c(env$slept, s); env$t <- env$t + s })
}

# ── pacing ─────────────────────────────────────────────────────────

test_that("pacing sleeps weight / (pace x 1200/60) per request (snapshot)", {
  v <- .vclock()
  post <- hl_make_post(withr::local_tempdir(), sleep_fn = v$sleep, clock = v$clock,
                       post = v$fake(function(i, body) {
                         vector("list", c(0, 6000, 500)[i])
                       }))
  post(list(type = "allPerpMetas"))                                   # weight 20
  post(list(type = "candleSnapshot",
            req = list(coin = "BTC", interval = "1h")))               # 20 + 100
  post(list(type = "fundingHistory", coin = "BTC"))                   # 20 + 25
  expect_snapshot(print(round(v$env$slept, 4)))
  expect_equal(v$env$slept, c(20, 120, 45) / (HL_RATE_WEIGHT_PER_MIN * 0.75 / 60))
  # The observed running rate is the pace, under the documented limit.
  expect_equal(hl_weight_rate(post), HL_RATE_WEIGHT_PER_MIN * 0.75)
  expect_lt(hl_weight_rate(post), HL_RATE_WEIGHT_PER_MIN)
})

test_that("time already spent inside a request is deducted from the sleep", {
  v <- .vclock(req_s = 1)
  post <- hl_make_post(withr::local_tempdir(), sleep_fn = v$sleep, clock = v$clock,
                       post = v$fake(0))
  post(list(type = "allPerpMetas"))
  expect_equal(v$env$slept, 20 / (HL_RATE_WEIGHT_PER_MIN * 0.75 / 60) - 1)
  # A request slower than its budget sleeps 0, never a negative number.
  expect_equal(hl_pace_seconds(20, 5), 0)
})

test_that("an invalid pace aborts (snapshot)", {
  expect_snapshot(error = TRUE, hl_make_post(tempdir(), pace = 2))
  expect_snapshot(error = TRUE, hl_make_post(tempdir(), pace = 0))
})

# ── HTTP 429 ───────────────────────────────────────────────────────

test_that("hl_post turns HTTP 429 into hl_rate_limited, other 4xx into unavailable (snapshot)", {
  resp <- function(status) {
    function(req) httr2::response(status_code = status,
                                  headers = list(`Content-Type` = "application/json"),
                                  body = charToRaw("{}"))
  }
  expect_snapshot(error = TRUE, httr2::with_mocked_responses(
    resp(429L), hl_post(list(type = "spotMeta"))))
  expect_error(httr2::with_mocked_responses(resp(429L), hl_post(list(type = "spotMeta"))),
               class = "hl_rate_limited")
  expect_error(httr2::with_mocked_responses(resp(400L), hl_post(list(type = "spotMeta"))),
               class = "hl_source_unavailable")
  # Green: a 200 still parses.
  got <- httr2::with_mocked_responses(resp(200L), hl_post(list(type = "spotMeta")))
  expect_equal(length(got), 0L)
})

.limited <- function() {
  rlang::abort("HTTP 429", class = c("hl_rate_limited", "hl_source_unavailable"))
}

test_that("a 429 backs off, then the request succeeds", {
  v <- .vclock()
  ok <- v$fake(0)
  post <- hl_make_post(withr::local_tempdir(), sleep_fn = v$sleep, clock = v$clock,
                       post = function(body, on_response = NULL) {
                         if (v$env$seen == 0L) { v$env$seen <- 1L; .limited() }
                         ok(body, on_response)
                       })
  expect_message(got <- post(list(type = "allPerpMetas")), "backing off 60 s")
  expect_equal(got, list())
  # pace sleep after the refused attempt, the 60 s back-off, pace sleep after success
  expect_equal(v$env$slept, c(20 / 15, HL_429_BACKOFF_S, 20 / 15))
})

test_that("persistent 429 aborts as rate-limited after the bounded attempts (snapshot)", {
  v <- .vclock()
  n <- 0L
  post <- hl_make_post(withr::local_tempdir(), sleep_fn = v$sleep, clock = v$clock,
                       post = function(body, on_response = NULL) { n <<- n + 1L; .limited() })
  expect_snapshot(error = TRUE,
                  suppressMessages(post(list(type = "allPerpMetas"))))
  expect_equal(n, HL_429_MAX_ATTEMPTS)
  # back off between attempts only: 2 back-offs for 3 attempts
  expect_equal(sum(v$env$slept == HL_429_BACKOFF_S), HL_429_MAX_ATTEMPTS - 1L)
  expect_error(suppressMessages(post(list(type = "allPerpMetas"))),
               class = "hl_rate_limited")
})

test_that("a non-429 error is not retried", {
  n <- 0L
  post <- hl_make_post(withr::local_tempdir(), sleep_fn = function(s) NULL,
                       post = function(body, on_response = NULL) {
                         n <<- n + 1L
                         hl_unavailable("connection refused")
                       })
  expect_error(post(list(type = "allPerpMetas")), class = "hl_source_unavailable")
  expect_equal(n, 1L)
})

# ── hl_run: argument checks ────────────────────────────────────────

test_that("invalid batch / max_markets abort (snapshot)", {
  expect_snapshot(error = TRUE, hl_run(.mock_post(), out_dir = tempdir(), batch = 0))
  expect_snapshot(error = TRUE, hl_run(.mock_post(), out_dir = tempdir(), max_markets = 0))
})

# ── hl_run: a market that is rate-limited is failed, never skipped ──

test_that("a rate-limited market is reported failed and the run is INDETERMINATE (snapshot)", {
  out <- withr::local_tempdir()
  base <- .mock_post()
  post <- function(body) {
    if (body$type == "candleSnapshot" && body$req$coin == "SOL") .limited()
    base(body)
  }
  res <- .run(post, out)
  expect_equal(res$status, 3L)
  expect_equal(res$failed$item, ":SOL")
  expect_false(":SOL" %in% .progress_keys(out))
  expect_false("SOL" %in% .daily_coins(out))
  expect_snapshot(print(res[c("status", "n_done", "n_skipped", "n_failed", "n_not_attempted")]))
})

test_that("repeated rate limiting stops the run; the rest is counted, not skipped silently", {
  out <- withr::local_tempdir()
  base <- .mock_post()
  post <- function(body) {
    if (body$type == "candleSnapshot") .limited()
    base(body)
  }
  res <- .run(post, out, max_rate_limited = 2L)
  expect_equal(res$status, 3L)
  expect_equal(res$n_failed, 2L)
  expect_equal(res$n_done, 0L)
  expect_equal(res$n_not_attempted, res$n_markets - 2L)
  expect_gt(res$n_not_attempted, 0L)
})

# ── incremental, resumable writes ──────────────────────────────────

test_that("an interrupted run leaves the first k markets on disk and recorded", {
  out <- withr::local_tempdir()
  k <- 2L
  first_k <- hl_enumerate_markets(.mock_post())$markets$coin[seq_len(k)]
  r <- tryCatch(.run(.crash_after(k), out, batch = 1L), hl_test_crash = function(c) "crashed")
  expect_identical(r, "crashed")
  expect_equal(.daily_coins(out), sort(first_k))
  expect_equal(.progress_keys(out), paste0(":", first_k))
  # funding is written with its market, too
  expect_equal(sort(unique(arrow::read_parquet(file.path(out, "perp_funding.parquet"))$coin)),
               sort(first_k))
})

test_that("buffered markets are flushed on exit even when the batch is not full", {
  out <- withr::local_tempdir()
  k <- 2L
  r <- tryCatch(.run(.crash_after(k), out, batch = 50L), hl_test_crash = function(c) "crashed")
  expect_identical(r, "crashed")
  expect_length(.progress_keys(out), k)
  expect_length(.daily_coins(out), k)
})

test_that("a resumed run skips finished markets and does not request them again", {
  out <- withr::local_tempdir()
  k <- 2L
  first_k <- hl_enumerate_markets(.mock_post())$markets$coin[seq_len(k)]
  tryCatch(.run(.crash_after(k), out, batch = 1L), hl_test_crash = function(c) NULL)
  spy <- .spy()
  expect_message(res <- hl_run(spy$post, out_dir = out, end = .end, resume = TRUE),
                 "skipping 2 market")
  expect_equal(res$status, 0L)
  expect_equal(res$n_skipped, k)
  expect_equal(res$n_done, res$n_markets - k)
  expect_false(any(first_k %in% spy$coins()))
  expect_length(spy$coins(), res$n_markets - k)
  # the finished run is complete: progress file is gone, all markets on disk
  expect_length(.progress_keys(out), 0L)
  fresh <- withr::local_tempdir()
  .run(.mock_post(), fresh)
  expect_equal(.daily_coins(out), .daily_coins(fresh))
  expect_equal(nrow(arrow::read_parquet(file.path(out, "perp_hourly.parquet"))),
               nrow(arrow::read_parquet(file.path(fresh, "perp_hourly.parquet"))))
  expect_equal(nrow(arrow::read_parquet(file.path(out, "perp_funding.parquet"))),
               nrow(arrow::read_parquet(file.path(fresh, "perp_funding.parquet"))))
})

test_that("a failed market is not recorded as done and is retried on resume", {
  out <- withr::local_tempdir()
  base <- .mock_post()
  broken <- function(body) {
    if (body$type == "candleSnapshot" && body$req$coin == "SOL") cli::cli_abort("boom")
    base(body)
  }
  r1 <- .run(broken, out)
  expect_equal(r1$status, 1L)
  expect_false(":SOL" %in% .progress_keys(out))
  expect_length(.progress_keys(out), r1$n_markets - 1L)
  spy <- .spy()
  r2 <- .run(spy$post, out, resume = TRUE)
  expect_equal(spy$coins(), "SOL")
  expect_equal(r2$status, 0L)
  expect_equal(c(r2$n_done, r2$n_skipped), c(1L, r1$n_markets - 1L))
  expect_true("SOL" %in% .daily_coins(out))
})

test_that("without --resume every market is fetched again (safe, idempotent)", {
  out <- withr::local_tempdir()
  base <- .mock_post()
  broken <- function(body) {
    if (body$type == "candleSnapshot" && body$req$coin == "SOL") cli::cli_abort("boom")
    base(body)
  }
  .run(broken, out)                      # leaves a progress file
  spy <- .spy()
  r <- .run(spy$post, out)
  expect_equal(r$n_skipped, 0L)
  expect_length(spy$coins(), r$n_markets)
})

test_that("a progress file from another configuration is ignored", {
  out <- withr::local_tempdir()
  base <- .mock_post()
  broken <- function(body) {
    if (body$type == "candleSnapshot" && body$req$coin == "SOL") cli::cli_abort("boom")
    base(body)
  }
  .run(broken, out)
  spy <- .spy()
  expect_message(r <- hl_run(spy$post, out_dir = out, end = .end, resume = TRUE,
                             intervals = "1d"),
                 "different configuration")
  expect_equal(r$n_skipped, 0L)
})

test_that("--max-markets keeps only the first N markets", {
  out <- withr::local_tempdir()
  spy <- .spy()
  r <- .run(spy$post, out, max_markets = 3L)
  expect_equal(r$n_markets, 3L)
  expect_length(spy$coins(), 3L)
})

# ── progress lines ─────────────────────────────────────────────────

test_that("each market prints a progress line with elapsed time and weight rate (snapshot)", {
  v <- .vclock()
  base <- .mock_post()
  post <- hl_make_post(withr::local_tempdir(), sleep_fn = v$sleep, clock = v$clock,
                       post = function(body, on_response = NULL) base(body))
  msgs <- character()
  out <- withr::local_tempdir()
  withCallingHandlers(
    hl_run(post, out_dir = out, end = .end, max_markets = 2L),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    })
  lines <- grep("^\\[[0-9]+/[0-9]+\\]", msgs, value = TRUE)
  expect_length(lines, 2L)
  # Wall elapsed time varies run to run; the rest of the line is deterministic.
  expect_snapshot(cat(sub("elapsed [0-9:]+", "elapsed H:MM:SS", lines), sep = ""))
  expect_match(lines, "weight/min", fixed = TRUE)
})
