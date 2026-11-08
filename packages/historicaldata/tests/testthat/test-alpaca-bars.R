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

# Assets: Alpaca asset-list rows (symbol, name, status).
.ep_assets <- function(...) {
  rows <- list(...)
  tibble::tibble(
    symbol = vapply(rows, `[[`, "", 1L),
    name   = vapply(rows, `[[`, "", 2L),
    status = vapply(rows, `[[`, "", 3L)
  )
}
.ep_no_assets <- function() .ep_assets(c("ZZZ", "Unrelated Corp", "active"))

# A later bar for an unrelated symbol: the "last date in the fetched bars"
# that decides too_recent. 2023-12-29 is far past every test exit.
.ep_clock <- function() .ep_bars("CLK", "2023-12-29", 5)

.ep_px <- function(bars, exits, assets = .ep_no_assets(), clock = TRUE, ...) {
  if (clock) bars <- rbind(bars, .ep_clock())
  hd_alpaca_exit_prices(bars, exits, assets, ...)
}

test_that("hd_alpaca_exit_rule holds the #1041 constants", {
  r <- hd_alpaca_exit_rule()
  expect_equal(r$panel_start, as.Date("2016-01-04"))
  expect_equal(r$window_days, 30L)
  expect_equal(r$crash_drop, 0.30)
  expect_equal(r$crash_lookback, 60L)
  expect_equal(r$too_recent_weekdays, 5L)
  expect_null(r$max_gap_trading_days)
})

test_that("failure_candidate, SIVB shape: stops before the exit and fell 52%", {
  # Last bar Thu 2023-03-09; weekdays 10,13,14,15,16,17 March = 6.
  bars <- .ep_bars("SIV", "2023-03-09", 120, close = c(rep(100, 119), 48))
  out <- .ep_px(bars, .ep_exit("SIV"))
  expect_equal(out$exit_type, "failure_candidate")
  expect_equal(out$last_trade_date, as.Date("2023-03-09"))
  expect_equal(out$gap_trading_days, 6L)
  expect_equal(out$ret_60d, -0.52)
  expect_true(out$failure_candidate)
  expect_equal(out$exit_price_upper, 48)
  expect_equal(out$exit_price_lower, 0)
  expect_true(out$has_bars)
  expect_true(is.na(out$new_ticker))
})

test_that("failure_candidate, SBNY shape: -43%, stops 3 days before exit, zero-volume flat tail cut", {
  real <- .ep_bars("SBN", "2023-03-14", 120, close = c(rep(100, 119), 57), volume = 5000)
  tail_dates <- .ep_weekdays("2023-03-15", 200)  # runs far past exit + 30 days
  tail <- tibble::tibble(symbol = "SBN", date = tail_dates, close = 57, volume = 0)
  out <- .ep_px(rbind(real, tail), .ep_exit("SBN"))
  expect_equal(out$last_trade_date, as.Date("2023-03-14"))
  expect_equal(out$last_close, 57)
  expect_equal(out$ret_60d, -0.43)
  expect_equal(out$exit_type, "failure_candidate")
  expect_equal(out$exit_price_lower, 0)
  expect_equal(out$exit_price_upper, 57)
})

test_that("a stopped name that fell 25% is a takeover, not a failure (threshold is 30%)", {
  bars <- .ep_bars("DIP", "2023-03-14", 120, close = c(rep(100, 119), 75))
  out <- .ep_px(bars, .ep_exit("DIP"))
  expect_equal(out$ret_60d, -0.25)
  expect_equal(out$exit_type, "takeover")
  expect_false(out$failure_candidate)
})

test_that("takeover, NBL shape: -2%, stops 6 weekdays before exit is a takeover (gap does not matter)", {
  bars <- .ep_bars("NBL", "2023-03-09", 120, close = c(rep(100, 119), 98))
  out <- .ep_px(bars, .ep_exit("NBL"))
  expect_equal(out$gap_trading_days, 6L)
  expect_equal(out$exit_type, "takeover")
  expect_false(out$failure_candidate)
  expect_equal(out$exit_price_upper, 98)
  expect_equal(out$exit_price_lower, 98)
})

test_that("takeover, TWTR shape: +31% to the last trade", {
  bars <- .ep_bars("TWT", "2023-03-16", 120, close = c(rep(40, 119), 52.4))
  out <- .ep_px(bars, .ep_exit("TWT"))
  expect_equal(out$exit_type, "takeover")
  expect_equal(out$ret_60d, 0.31)
  expect_equal(out$exit_price_upper, 52.4)
  expect_equal(out$exit_price_lower, 52.4)
})

test_that("fewer than 61 trade bars: ret_60d is NA and the name is not flagged", {
  bars <- .ep_bars("NEW", "2023-03-16", 30, close = c(100, rep(10, 29)))
  out <- .ep_px(bars, .ep_exit("NEW"))
  expect_true(is.na(out$ret_60d))
  expect_equal(out$exit_type, "takeover")
})

test_that("demotion: -80% but still trading after the exit; priced at the exit date, not exit + 30", {
  d <- .ep_weekdays("2022-09-01", 150)           # runs to ~ 2023-03-28 (past exit)
  d <- d[d <= as.Date("2023-04-14")]
  bars <- tibble::tibble(symbol = "DEM", date = d,
                         close = ifelse(d <= as.Date("2023-03-17"), 100, 20),
                         volume = 1000)
  out <- .ep_px(bars, .ep_exit("DEM"))
  expect_equal(out$exit_type, "demotion")
  expect_true(max(bars$date) > as.Date("2023-03-17"))
  expect_equal(out$exit_price_upper, 100)
  expect_equal(out$exit_price_lower, 100)
  expect_false(out$failure_candidate)
  # Informational columns still describe the last trade in the window.
  expect_gt(out$last_trade_date, as.Date("2023-03-17"))
  expect_equal(out$last_close, 20)
})

test_that("bars up to exit + 30 days count; later ones do not", {
  ex <- .ep_exit("DEM", first = "2015-06-01", exit = "2023-03-17")
  bars <- .ep_bars("DEM", "2023-05-15", 200, close = 30)
  out <- .ep_px(bars, ex)
  # exit + 30 days = 2023-04-16 (a Sunday), so the last in-window bar is Fri 14 April.
  expect_equal(out$last_trade_date, as.Date("2023-04-14"))
  expect_equal(out$gap_trading_days, 0L)
  expect_equal(out$exit_type, "demotion")
})

test_that("ticker_change, FI shape: inactive 'Fiserv, Inc.' and active 'Fiserv, Inc. Common Stock'", {
  bars <- .ep_bars("FI", "2023-03-16", 120, close = c(rep(100, 119), 47))
  assets <- .ep_assets(
    c("FI", "Fiserv, Inc.", "inactive"),
    c("FISV", "Fiserv, Inc. Common Stock", "active"),
    c("ZZZ", "Unrelated Corp", "active")
  )
  out <- .ep_px(bars, .ep_exit("FI"), assets)
  expect_equal(out$exit_type, "ticker_change")
  expect_equal(out$new_ticker, "FISV")
  expect_true(is.na(out$exit_price_upper))
  expect_true(is.na(out$exit_price_lower))
  expect_false(out$failure_candidate)
})

test_that("a same-name asset that is INACTIVE is not a ticker change", {
  bars <- .ep_bars("FI", "2023-03-16", 120, close = c(rep(100, 119), 47))
  assets <- .ep_assets(c("FI", "Fiserv, Inc.", "inactive"),
                       c("FISV", "Fiserv, Inc. Common Stock", "inactive"))
  out <- .ep_px(bars, .ep_exit("FI"), assets)
  expect_equal(out$exit_type, "failure_candidate")
})

test_that("ticker_change_ambiguous: several active same-name symbols, none chosen", {
  bars <- .ep_bars("OLD", "2023-03-16", 120, close = 50)
  assets <- .ep_assets(
    c("OLD", "Acme Holdings Inc", "inactive"),
    c("ACMA", "Acme Holdings, Inc. Class A Common Stock", "active"),
    c("ACMB", "Acme Holdings, Inc. Class B Common Stock", "active")
  )
  out <- .ep_px(bars, .ep_exit("OLD"), assets)
  expect_equal(out$exit_type, "ticker_change_ambiguous")
  expect_true(is.na(out$new_ticker))
  expect_true(is.na(out$exit_price_upper))
})

test_that("too_recent: exit within 5 weekdays of the last fetched bar", {
  bars <- .ep_bars("REC", "2023-03-16", 120, close = 50)
  # Latest bar anywhere is Tue 2023-03-21: 2 weekdays after the exit.
  out <- .ep_px(rbind(bars, .ep_bars("CLK", "2023-03-21", 5)), .ep_exit("REC"), clock = FALSE)
  expect_equal(out$exit_type, "too_recent")
  expect_true(is.na(out$failure_candidate))
  expect_true(is.na(out$exit_price_upper))
  # Exactly 5 weekdays after is still too recent; 6 is not.
  five <- .ep_px(rbind(bars, .ep_bars("CLK", "2023-03-24", 5)), .ep_exit("REC"), clock = FALSE)
  six <- .ep_px(rbind(bars, .ep_bars("CLK", "2023-03-27", 5)), .ep_exit("REC"), clock = FALSE)
  expect_equal(five$exit_type, "too_recent")
  expect_equal(six$exit_type, "takeover")
})

test_that("known_failed forces failure_candidate, with or without bars", {
  bars <- .ep_bars("TWT", "2023-03-16", 120, close = 54)
  ex <- rbind(.ep_exit("TWT"), .ep_exit("OLD", exit = "2008-09-15", first = "1990-01-01"))
  out <- .ep_px(bars, ex, known_failed = c("TWT", "OLD"))
  twt <- out[out$ticker == "TWT", ]
  expect_equal(twt$exit_type, "failure_candidate")
  expect_true(twt$failure_candidate)
  expect_equal(twt$exit_price_lower, 0)
  expect_equal(twt$exit_price_upper, 54)
  old <- out[out$ticker == "OLD", ]
  expect_false(old$has_bars)
  expect_equal(old$exit_type, "failure_candidate")
  expect_true(old$failure_candidate)
  expect_equal(old$exit_price_lower, 0)
  expect_true(is.na(old$exit_price_upper))
  # Without the override the same shape is a takeover.
  expect_equal(.ep_px(bars, .ep_exit("TWT"))$exit_type, "takeover")
})

test_that("no bars and not known: no_bars, failure unknown (NA), never a price", {
  bars <- .ep_bars("OTHER", "2023-03-17", 10)
  out <- .ep_px(bars, .ep_exit("MISSING"))
  expect_equal(out$exit_type, "no_bars")
  expect_false(out$has_bars)
  expect_true(is.na(out$failure_candidate))
  expect_true(is.na(out$last_close))
  expect_true(is.na(out$exit_price_upper))
  expect_true(is.na(out$exit_price_lower))
})

test_that("ticker recycling: bars outside the membership span +/- 30 days are ignored", {
  ex <- .ep_exit("REC", first = "2019-01-01", exit = "2020-06-15")
  mine <- .ep_bars("REC", "2020-06-12", 120, close = 20)
  later <- tibble::tibble(symbol = "REC", date = .ep_weekdays("2021-03-01", 50),
                          close = 900, volume = 1e6)
  earlier <- tibble::tibble(symbol = "REC", date = .ep_weekdays("2016-02-01", 50),
                            close = 5, volume = 1e6)
  out <- .ep_px(rbind(earlier, mine, later), ex)
  expect_equal(out$last_trade_date, as.Date("2020-06-12"))
  expect_equal(out$last_close, 20)
  expect_equal(out$exit_type, "takeover")
  out2 <- .ep_px(rbind(earlier, later), ex)
  expect_false(out2$has_bars)
})

test_that("red run guard: with the old 50% threshold the SBNY shape would NOT be flagged", {
  # Documents why crash_drop is 0.30: -43% is a real failure the old rule missed.
  bars <- .ep_bars("SBN", "2023-03-14", 120, close = c(rep(100, 119), 57))
  old <- hd_alpaca_exit_rule()
  old$crash_drop <- 0.50
  expect_equal(.ep_px(bars, .ep_exit("SBN"), rule = old)$exit_type, "takeover")
  expect_equal(.ep_px(bars, .ep_exit("SBN"))$exit_type, "failure_candidate")
})

test_that(".hd_normalise_company_name strips legal-form and share-class words", {
  f <- .hd_normalise_company_name
  expect_equal(f(c("Fiserv, Inc.", "Fiserv, Inc. Common Stock")), c("fiserv", "fiserv"))
  expect_equal(f("The Walt Disney Company"), "walt disney")
  expect_equal(f("Acme Holdings, Inc. Class A Common Stock"), "acme")
  expect_equal(f("Foo plc Ordinary Shares"), "foo")
  expect_equal(f("Coca-Cola Co"), "coca cola")
  expect_true(is.na(f(NA_character_)))
})

test_that("hd_alpaca_exit_prices validates its inputs", {
  bars <- .ep_bars("AAA", "2023-03-17", 10)
  ex <- .ep_exit("AAA")
  as <- .ep_no_assets()
  expect_snapshot(error = TRUE, hd_alpaca_exit_prices(data.frame(x = 1), ex, as))
  bad <- bars
  bad$volume[1] <- NA
  expect_snapshot(error = TRUE, hd_alpaca_exit_prices(bad, ex, as))
  expect_snapshot(error = TRUE, hd_alpaca_exit_prices(bars, rbind(ex, ex), as))
  expect_snapshot(error = TRUE, hd_alpaca_exit_prices(bars, ex, data.frame(symbol = "A")))
})

test_that("hd_alpaca_exit_coverage counts exits, priced exits, failures and each exit type by year", {
  px <- tibble::tibble(
    ticker = c("A", "B", "C", "D"),
    index_exit_date = as.Date(c("2016-05-01", "2016-06-01", "2017-01-01", "2010-01-01")),
    exit_type = c("failure_candidate", "demotion", "failure_candidate", "no_bars"),
    has_bars = c(TRUE, TRUE, TRUE, FALSE),
    failure_candidate = c(TRUE, FALSE, TRUE, NA)
  )
  cov <- hd_alpaca_exit_coverage(px)
  expect_equal(cov$exit_year, c(2010L, 2016L, 2017L))
  expect_equal(cov$n_exits, c(1L, 2L, 1L))
  expect_equal(cov$n_with_bars, c(0L, 2L, 1L))
  expect_equal(cov$n_failure_candidates, c(0L, 1L, 1L))
  expect_equal(cov$n_demotion, c(0L, 1L, 0L))
  expect_equal(cov$n_failure_candidate, c(0L, 1L, 1L))
  expect_equal(cov$n_no_bars, c(1L, 0L, 0L))
  expect_equal(cov$n_takeover, c(0L, 0L, 0L))
  expect_true(all(c("n_ticker_change", "n_ticker_change_ambiguous", "n_too_recent") %in% names(cov)))
})

# ── positive control ─────────────────────────────────────────────────────────

.ep_truth <- function() {
  tibble::tibble(
    ticker = c("SIVB", "FRC", "SBNY", "TWTR", "ATVI", "CELG", "NBL", "JNPR",
               "XEC", "ARNC", "M", "AIV", "LUMN", "FI"),
    exit_type = c(rep("failure_candidate", 3), rep("takeover", 5),
                  rep("demotion", 5), "ticker_change"),
    new_ticker = c(rep(NA_character_, 13), "FISV")
  )
}

test_that("hd_alpaca_exit_controls passes when every named case has its known type", {
  res <- hd_alpaca_exit_controls(.ep_truth())
  expect_equal(nrow(res), 14L)
  expect_true(all(res$status == "PASS"))
})

test_that("hd_alpaca_exit_controls aborts, listing every mismatch (it can go red)", {
  bad <- .ep_truth()
  bad$exit_type[bad$ticker == "NBL"] <- "failure_candidate"   # the old gap-rule error
  bad$new_ticker[bad$ticker == "FI"] <- "FI2"
  expect_error(hd_alpaca_exit_controls(bad), "2 named real cases")
  err <- tryCatch(hd_alpaca_exit_controls(bad), error = function(e) conditionMessage(e))
  expect_match(err, "NBL")
  expect_match(err, "FI: expected ticker_change -> FISV")
  expect_no_match(err, "SIVB")
})

test_that("hd_alpaca_exit_controls reports absent tickers and is INDETERMINATE below 10 present", {
  few <- .ep_truth()[1:11, ]            # 3 absent: 11 present -> ok but reported
  expect_message(res <- hd_alpaca_exit_controls(few), "not in the exit table")
  expect_equal(sum(res$status == "ABSENT"), 3L)
  expect_error(hd_alpaca_exit_controls(.ep_truth()[1:9, ]), "INDETERMINATE")
})
