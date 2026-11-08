# Tests for the Alpaca bars loader and the exit-price rule (#1041).
#
# Hermetic: HTTP is mocked with httr2::with_mocked_responses(); every bar is
# SYNTHETIC (invented tickers, invented prices). No network, no credentials
# (dummy key/secret are passed explicitly). testthat edition 3.

testthat::local_edition(3)

# ── HTTP helpers ─────────────────────────────────────────────────────────────

.ab_bar <- function(t, c, v = 1000) {
  list(t = paste0(t, "T05:00:00Z"), o = c, h = c, l = c, c = c, v = v, n = 10,
       vw = c)
}

.ab_resp <- function(bars, token = NULL, status = 200L) {
  httr2::response(
    status_code = status,
    headers = list(`Content-Type` = "application/json"),
    body = charToRaw(jsonlite::toJSON(
      list(bars = bars, next_page_token = token),
      auto_unbox = TRUE, null = "null"
    ))
  )
}

.ab_query <- function(req) httr2::url_parse(req$url)$query

# ── hd_alpaca_bars: pagination, parsing, errors ──────────────────────────────

test_that("hd_alpaca_bars joins two pages and follows next_page_token", {
  seen <- list()
  fake <- function(req) {
    q <- .ab_query(req)
    seen[[length(seen) + 1L]] <<- q
    if (is.null(q$page_token)) {
      .ab_resp(list(AAA = list(.ab_bar("2020-01-02", 10), .ab_bar("2020-01-03", 11))),
               token = "tok1")
    } else {
      expect_equal(q$page_token, "tok1")
      .ab_resp(list(AAA = list(.ab_bar("2020-01-06", 12)),
                    BBB = list(.ab_bar("2020-01-02", 5))))
    }
  }
  out <- httr2::with_mocked_responses(
    fake,
    hd_alpaca_bars(c("AAA", "BBB"), "2020-01-01", "2020-01-31",
                   key = "k", secret = "s")
  )
  expect_length(seen, 2L)
  expect_s3_class(out, "tbl_df")
  expect_named(out, c("symbol", "date", "open", "high", "low", "close",
                      "volume", "trade_count", "vwap"))
  expect_equal(out$symbol, c("AAA", "AAA", "AAA", "BBB"))
  expect_equal(out$date, as.Date(c("2020-01-02", "2020-01-03", "2020-01-06", "2020-01-02")))
  expect_equal(out$close, c(10, 11, 12, 5))
  expect_s3_class(out$date, "Date")
})

test_that("hd_alpaca_bars sends credentials, feed, adjustment and whole-day bounds", {
  seen <- NULL
  fake <- function(req) {
    seen <<- req
    .ab_resp(list())
  }
  httr2::with_mocked_responses(
    fake,
    hd_alpaca_bars("AAA", "2020-01-01", "2020-01-31", key = "KEYX", secret = "SECX")
  )
  expect_equal(seen$headers[["APCA-API-KEY-ID"]], "KEYX")
  expect_equal(seen$headers[["APCA-API-SECRET-KEY"]], "SECX")
  q <- .ab_query(seen)
  expect_equal(q$feed, "sip")
  expect_equal(q$adjustment, "raw")
  expect_equal(q$timeframe, "1Day")
  expect_equal(q$start, "2020-01-01T00:00:00Z")
  expect_equal(q$end, "2020-01-31T23:59:59Z")
  expect_null(q$page_token)
})

test_that("hd_alpaca_bars splits symbols into batches", {
  n_calls <- 0L
  fake <- function(req) {
    n_calls <<- n_calls + 1L
    .ab_resp(list())
  }
  httr2::with_mocked_responses(
    fake,
    hd_alpaca_bars(c("A", "B", "C"), "2020-01-01", "2020-01-31",
                   key = "k", secret = "s", batch_size = 2L)
  )
  expect_equal(n_calls, 2L)
})

test_that("hd_alpaca_bars: an empty response is a zero-row tibble, not an error", {
  fake <- function(req) .ab_resp(list())
  out <- httr2::with_mocked_responses(
    fake,
    hd_alpaca_bars("ZZZZ", "2020-01-01", "2020-01-31", key = "k", secret = "s")
  )
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 0L)
  expect_named(out, c("symbol", "date", "open", "high", "low", "close",
                      "volume", "trade_count", "vwap"))
  expect_s3_class(out$date, "Date")
})

test_that("hd_alpaca_bars: a null bars object is also a zero-row tibble", {
  fake <- function(req) {
    httr2::response(status_code = 200L,
                    body = charToRaw('{"bars":null,"next_page_token":null}'))
  }
  out <- httr2::with_mocked_responses(
    fake,
    hd_alpaca_bars("ZZZZ", "2020-01-01", "2020-01-31", key = "k", secret = "s")
  )
  expect_equal(nrow(out), 0L)
})

test_that("hd_alpaca_bars aborts with the HTTP status and API message on non-200", {
  fake <- function(req) {
    httr2::response(
      status_code = 403L,
      headers = list(`Content-Type` = "application/json"),
      body = charToRaw('{"message":"subscription does not permit querying recent SIP data"}')
    )
  }
  expect_snapshot(
    error = TRUE,
    httr2::with_mocked_responses(
      fake,
      hd_alpaca_bars(c("AAA", "BBB"), "2020-01-01", "2020-01-31",
                     key = "k", secret = "s")
    )
  )
  fake_text <- function(req) {
    httr2::response(status_code = 500L, body = charToRaw("upstream exploded"))
  }
  expect_error(
    suppressWarnings(httr2::with_mocked_responses(
      fake_text,
      hd_alpaca_bars("AAA", "2020-01-01", "2020-01-31", key = "k", secret = "s")
    )),
    "HTTP 500"
  )
})

test_that("hd_alpaca_bars aborts on a 200 response that is not JSON", {
  fake <- function(req) httr2::response(status_code = 200L, body = charToRaw("<html>oops</html>"))
  expect_error(
    httr2::with_mocked_responses(
      fake,
      hd_alpaca_bars("AAA", "2020-01-01", "2020-01-31", key = "k", secret = "s")
    ),
    "not valid JSON"
  )
})

test_that("hd_alpaca_bars aborts on bad input and missing credentials", {
  expect_snapshot(error = TRUE, hd_alpaca_bars(character(), "2020-01-01", "2020-01-31", key = "k", secret = "s"))
  expect_snapshot(error = TRUE, hd_alpaca_bars("A", "2020-02-01", "2020-01-31", key = "k", secret = "s"))
  withr::local_envvar(ALPACA_KEY = NA, ALPACA_SECRET = NA)
  expect_snapshot(error = TRUE, hd_alpaca_bars("A", "2020-01-01", "2020-01-31"))
})

# ── cache path helpers ───────────────────────────────────────────────────────

test_that("hd_alpaca_bars_data_dir: defaults and honours the env var", {
  withr::local_envvar(ALPACA_BARS_DIR = NA)
  expect_equal(hd_alpaca_bars_data_dir(), path.expand("~/.cache/historical/alpaca_exit_bars"))
  withr::local_envvar(ALPACA_BARS_DIR = "/tmp/custom_alpaca_dir")
  expect_equal(hd_alpaca_bars_data_dir(), "/tmp/custom_alpaca_dir")
})

test_that("hd_alpaca_exit_bars_path: aborts naming the fetch script when absent", {
  tmp <- withr::local_tempdir()
  expect_snapshot(
    error = TRUE,
    hd_alpaca_exit_bars_path(tmp),
    transform = function(x) gsub(tmp, "<TMP>", x, fixed = TRUE)
  )
  file.create(file.path(tmp, "alpaca_exit_bars.parquet"))
  expect_equal(hd_alpaca_exit_bars_path(tmp),
               file.path(tmp, "alpaca_exit_bars.parquet"))
})

# ── hd_sp500_exits ───────────────────────────────────────────────────────────

test_that("hd_sp500_exits: only tickers whose last spell ended; a returning ticker is not an exit", {
  m <- tibble::tibble(
    date = as.Date(rep(c("2020-01-01", "2020-02-01", "2020-03-01", "2020-04-01"), each = 3)),
    ticker = c("A", "B", "C",
               "A", "B", "D",
               "A", "C", "D",
               "A", "C", "D")
  )
  e <- hd_sp500_exits(m)
  expect_equal(e$ticker, "B")
  expect_equal(e$first_member_date, as.Date("2020-01-01"))
  expect_equal(e$last_member_date, as.Date("2020-02-01"))
  expect_equal(e$index_exit_date, as.Date("2020-03-01"))
})

# ── Exit-price rule: synthetic bars ──────────────────────────────────────────

.ep_weekdays <- function(from, n) {
  d <- seq(as.Date(from), by = "day", length.out = n * 2L + 7L)
  d[!(format(d, "%u") %in% c("6", "7"))][seq_len(n)]
}

# Bars on `n` weekdays ending on `last`, with prices from `close` (recycled).
.ep_bars <- function(sym, last, n, close = 100, volume = 1000) {
  last <- as.Date(last)
  d <- seq(last - 3L * n, last, by = "day")
  d <- d[!(format(d, "%u") %in% c("6", "7"))]
  d <- utils::tail(d, n)
  tibble::tibble(symbol = sym, date = d,
                 close = rep_len(close, length(d)),
                 volume = rep_len(volume, length(d)))
}

# 2023-03-17 is a Friday.
.ep_exit <- function(ticker, first = "2015-06-01", exit = "2023-03-17") {
  tibble::tibble(ticker = ticker,
                 first_member_date = as.Date(first),
                 index_exit_date = as.Date(exit))
}

test_that("hd_alpaca_exit_rule holds the #1041 constants", {
  r <- hd_alpaca_exit_rule()
  expect_equal(r$panel_start, as.Date("2016-01-04"))
  expect_equal(r$window_days, 30L)
  expect_equal(r$max_gap_trading_days, 5L)
  expect_equal(r$crash_drop, 0.5)
  expect_equal(r$crash_lookback, 60L)
})

test_that("SIVB shape: last trade 6 weekdays before the exit is a failure candidate", {
  # Last bar Thu 2023-03-09; weekdays 10,13,14,15,16,17 March = 6 > 5.
  bars <- .ep_bars("SIV", "2023-03-09", 120)
  out <- hd_alpaca_exit_prices(bars, .ep_exit("SIV"))
  expect_equal(out$last_trade_date, as.Date("2023-03-09"))
  expect_equal(out$gap_trading_days, 6L)
  expect_equal(out$ret_60d, 0)
  expect_true(out$failure_candidate)
  expect_equal(out$exit_price_upper, 100)
  expect_equal(out$exit_price_lower, 0)
  expect_true(out$has_bars)
})

test_that("gap of exactly 5 trading days is NOT a failure candidate (strictly more than 5)", {
  bars <- .ep_bars("EDGE", "2023-03-10", 120)  # Fri 10 -> Fri 17 = 5 weekdays
  out <- hd_alpaca_exit_prices(bars, .ep_exit("EDGE"))
  expect_equal(out$gap_trading_days, 5L)
  expect_false(out$failure_candidate)
  expect_equal(out$exit_price_lower, out$exit_price_upper)
})

test_that("SBNY shape: a zero-volume flat tail is cut, the last real trade is used", {
  real <- .ep_bars("SBN", "2023-03-03", 120, close = 72, volume = 5000)
  tail_dates <- .ep_weekdays("2023-03-06", 200)  # runs far past exit + 30 days
  tail <- tibble::tibble(symbol = "SBN", date = tail_dates, close = 70, volume = 0)
  bars <- rbind(real, tail)
  out <- hd_alpaca_exit_prices(bars, .ep_exit("SBN"))
  expect_equal(out$last_trade_date, as.Date("2023-03-03"))
  expect_equal(out$last_close, 72)
  expect_equal(out$gap_trading_days, 10L)
  expect_true(out$failure_candidate)
  expect_equal(out$exit_price_lower, 0)
})

test_that("takeover shape: trades to the exit date at a flat price is NOT a failure candidate", {
  bars <- .ep_bars("TWT", "2023-03-17", 120, close = 54)
  out <- hd_alpaca_exit_prices(bars, .ep_exit("TWT"))
  expect_equal(out$last_trade_date, as.Date("2023-03-17"))
  expect_equal(out$gap_trading_days, 0L)
  expect_false(out$failure_candidate)
  expect_equal(out$exit_price_upper, 54)
  expect_equal(out$exit_price_lower, 54)
})

test_that("crash shape: a fall of more than 50% over 60 trading days is a failure candidate", {
  # 61 bars: 100 then 40 -> -60% over 60 bars, trading to the exit date.
  n <- 61L
  bars <- .ep_bars("CRA", "2023-03-17", n, close = c(100, rep(70, n - 2L), 40))
  out <- hd_alpaca_exit_prices(bars, .ep_exit("CRA"))
  expect_equal(out$gap_trading_days, 0L)
  expect_equal(out$ret_60d, -0.6)
  expect_true(out$failure_candidate)
  expect_equal(out$exit_price_lower, 0)
  expect_equal(out$exit_price_upper, 40)
})

test_that("a fall of 40% over 60 trading days is NOT a failure candidate", {
  n <- 61L
  bars <- .ep_bars("DIP", "2023-03-17", n, close = c(100, rep(80, n - 2L), 60))
  out <- hd_alpaca_exit_prices(bars, .ep_exit("DIP"))
  expect_equal(out$ret_60d, -0.4)
  expect_false(out$failure_candidate)
})

test_that("fewer than 61 trade bars: ret_60d is NA and does not flag", {
  bars <- .ep_bars("NEW", "2023-03-17", 30, close = c(100, rep(10, 29)))
  out <- hd_alpaca_exit_prices(bars, .ep_exit("NEW"))
  expect_true(is.na(out$ret_60d))
  expect_false(out$failure_candidate)
})

test_that("known_failed forces TRUE, with or without bars", {
  bars <- .ep_bars("TWT", "2023-03-17", 120, close = 54)
  ex <- rbind(.ep_exit("TWT"), .ep_exit("OLD", exit = "2008-09-15", first = "1990-01-01"))
  out <- hd_alpaca_exit_prices(bars, ex, known_failed = c("TWT", "OLD"))
  twt <- out[out$ticker == "TWT", ]
  expect_true(twt$failure_candidate)
  expect_equal(twt$exit_price_lower, 0)
  expect_equal(twt$exit_price_upper, 54)
  old <- out[out$ticker == "OLD", ]
  expect_false(old$has_bars)
  expect_true(old$failure_candidate)
  expect_equal(old$exit_price_lower, 0)
  expect_true(is.na(old$exit_price_upper))
  # Without the override the same takeover is not a failure candidate.
  expect_false(hd_alpaca_exit_prices(bars, .ep_exit("TWT"))$failure_candidate)
})

test_that("no bars and not known: has_bars FALSE and failure unknown (NA), never a price", {
  bars <- .ep_bars("OTHER", "2023-03-17", 10)
  out <- hd_alpaca_exit_prices(bars, .ep_exit("MISSING"))
  expect_false(out$has_bars)
  expect_true(is.na(out$failure_candidate))
  expect_true(is.na(out$last_close))
  expect_true(is.na(out$exit_price_upper))
  expect_true(is.na(out$exit_price_lower))
})

test_that("ticker recycling: bars outside the membership span +/- 30 days are ignored", {
  ex <- .ep_exit("REC", first = "2019-01-01", exit = "2020-06-15")
  mine <- .ep_bars("REC", "2020-06-15", 120, close = 20)
  # A later company reusing the symbol, trading well after exit + 30 days.
  later <- tibble::tibble(symbol = "REC", date = .ep_weekdays("2021-03-01", 50),
                          close = 900, volume = 1e6)
  # An earlier company, long before the span.
  earlier <- tibble::tibble(symbol = "REC", date = .ep_weekdays("2016-02-01", 50),
                            close = 5, volume = 1e6)
  out <- hd_alpaca_exit_prices(rbind(earlier, mine, later), ex)
  expect_equal(out$last_trade_date, as.Date("2020-06-15"))
  expect_equal(out$last_close, 20)
  expect_false(out$failure_candidate)
  # Only a later company's bars -> nothing usable.
  out2 <- hd_alpaca_exit_prices(rbind(earlier, later), ex)
  expect_false(out2$has_bars)
})

test_that("bars up to exit + 30 days count; later ones do not", {
  ex <- .ep_exit("DEM", first = "2015-06-01", exit = "2023-03-17")
  # Demoted name that keeps trading: bars every weekday to mid-May.
  bars <- .ep_bars("DEM", "2023-05-15", 200, close = 30)
  out <- hd_alpaca_exit_prices(bars, ex)
  # exit + 30 days = 2023-04-16 (a Sunday), so the last in-window bar is Fri 14 April.
  expect_equal(out$last_trade_date, as.Date("2023-04-14"))
  expect_equal(out$gap_trading_days, 0L)
})

test_that("hd_alpaca_exit_prices validates its inputs", {
  bars <- .ep_bars("AAA", "2023-03-17", 10)
  expect_snapshot(error = TRUE, hd_alpaca_exit_prices(data.frame(x = 1), .ep_exit("AAA")))
  bad <- bars
  bad$volume[1] <- NA
  expect_snapshot(error = TRUE, hd_alpaca_exit_prices(bad, .ep_exit("AAA")))
  expect_snapshot(error = TRUE, hd_alpaca_exit_prices(bars, rbind(.ep_exit("AAA"), .ep_exit("AAA"))))
})

test_that("hd_alpaca_exit_coverage counts exits, priced exits and failure candidates by year", {
  px <- tibble::tibble(
    ticker = c("A", "B", "C", "D"),
    index_exit_date = as.Date(c("2016-05-01", "2016-06-01", "2017-01-01", "2010-01-01")),
    has_bars = c(TRUE, TRUE, TRUE, FALSE),
    failure_candidate = c(TRUE, FALSE, TRUE, NA)
  )
  cov <- hd_alpaca_exit_coverage(px)
  expect_equal(cov$exit_year, c(2010L, 2016L, 2017L))
  expect_equal(cov$n_exits, c(1L, 2L, 1L))
  expect_equal(cov$n_with_bars, c(0L, 2L, 1L))
  expect_equal(cov$n_failure_candidates, c(0L, 1L, 1L))
})
