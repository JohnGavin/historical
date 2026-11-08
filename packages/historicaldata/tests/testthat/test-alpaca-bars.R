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


test_that("adjusted-bars and corporate-actions path helpers abort naming the fetch script when absent", {
  tmp <- withr::local_tempdir()
  expect_snapshot(
    error = TRUE,
    hd_alpaca_exit_bars_adj_path(tmp),
    transform = function(x) gsub(tmp, "<TMP>", x, fixed = TRUE)
  )
  expect_snapshot(
    error = TRUE,
    hd_alpaca_exit_corp_actions_path(tmp),
    transform = function(x) gsub(tmp, "<TMP>", x, fixed = TRUE)
  )
  file.create(file.path(tmp, "alpaca_exit_bars_adj.parquet"))
  file.create(file.path(tmp, "alpaca_exit_corp_actions.parquet"))
  expect_equal(hd_alpaca_exit_bars_adj_path(tmp), file.path(tmp, "alpaca_exit_bars_adj.parquet"))
  expect_equal(hd_alpaca_exit_corp_actions_path(tmp), file.path(tmp, "alpaca_exit_corp_actions.parquet"))
})

# ── hd_alpaca_corporate_actions: pagination, flattening, errors ─────────────

.ca_resp <- function(cas, token = NULL, status = 200L) {
  httr2::response(
    status_code = status,
    headers = list(`Content-Type` = "application/json"),
    body = charToRaw(jsonlite::toJSON(
      list(corporate_actions = cas, next_page_token = token),
      auto_unbox = TRUE, null = "null"
    ))
  )
}

test_that("hd_alpaca_corporate_actions joins two pages and flattens every record type", {
  seen <- list()
  fake <- function(req) {
    seen[[length(seen) + 1L]] <<- req
    q <- .ab_query(req)
    if (is.null(q$page_token)) {
      .ca_resp(list(
        name_changes = list(list(old_symbol = "FI", new_symbol = "FISV", process_date = "2025-11-11")),
        cash_mergers = list(list(acquiree_symbol = "TWT", effective_date = "2022-10-28", rate = 54.2))
      ), token = "tok1")
    } else {
      expect_equal(q$page_token, "tok1")
      .ca_resp(list(
        stock_mergers = list(list(acquiree_symbol = "NBL", acquirer_symbol = "CVX",
                                  acquirer_rate = 0.1191, acquiree_rate = 1,
                                  effective_date = "2020-10-05")),
        stock_and_cash_mergers = list(list(acquiree_symbol = "CEL", acquirer_symbol = "BMY",
                                           acquirer_rate = 1, acquiree_rate = 1, cash_rate = 50,
                                           effective_date = "2019-11-20")),
        spin_offs = list(list(source_symbol = "DWD", new_symbol = "DOW", process_date = "2019-04-01"))
      ))
    }
  }
  out <- httr2::with_mocked_responses(
    fake,
    hd_alpaca_corporate_actions(c("FI", "TWT", "NBL"), "2016-01-01", "2026-11-08",
                                key = "KEYX", secret = "SECX")
  )
  expect_length(seen, 2L)
  expect_s3_class(out, "tbl_df")
  expect_named(out, c("type", "symbol", "new_symbol", "acquirer_symbol", "rate",
                      "cash_rate", "acquirer_rate", "acquiree_rate",
                      "effective_date", "process_date"))
  expect_equal(nrow(out), 5L)
  expect_s3_class(out$effective_date, "Date")
  expect_s3_class(out$process_date, "Date")
  g <- function(sym) out[out$symbol == sym, ]
  expect_equal(g("FI")$type, "name_change")
  expect_equal(g("FI")$new_symbol, "FISV")
  expect_equal(g("FI")$process_date, as.Date("2025-11-11"))
  expect_true(is.na(g("FI")$effective_date))
  expect_equal(g("TWT")$type, "cash_merger")
  expect_equal(g("TWT")$rate, 54.2)
  expect_equal(g("TWT")$effective_date, as.Date("2022-10-28"))
  expect_equal(g("NBL")$type, "stock_merger")
  expect_equal(g("NBL")$acquirer_symbol, "CVX")
  expect_equal(g("NBL")$acquirer_rate, 0.1191)
  expect_equal(g("NBL")$acquiree_rate, 1)
  expect_equal(g("CEL")$type, "stock_and_cash_merger")
  expect_equal(g("CEL")$cash_rate, 50)
  expect_equal(g("DWD")$type, "spin_off")
  # Request shape: path, credentials, types and whole range.
  q <- .ab_query(seen[[1L]])
  expect_match(seen[[1L]]$url, "/v1/corporate-actions")
  expect_equal(seen[[1L]]$headers[["APCA-API-KEY-ID"]], "KEYX")
  expect_equal(q$symbols, "FI,TWT,NBL")
  expect_equal(q$types, "name_change,cash_merger,stock_merger,stock_and_cash_merger,spin_off")
  expect_equal(q$start, "2016-01-01")
  expect_equal(q$end, "2026-11-08")
})

test_that("hd_alpaca_corporate_actions: an empty response is a zero-row tibble with the same columns", {
  fake <- function(req) .ca_resp(list())
  out <- httr2::with_mocked_responses(
    fake,
    hd_alpaca_corporate_actions("ZZZZ", "2016-01-01", "2026-11-08", key = "k", secret = "s")
  )
  expect_equal(nrow(out), 0L)
  expect_named(out, names(.hd_alpaca_empty_corp_actions()))
  expect_s3_class(out$effective_date, "Date")
})

test_that("hd_alpaca_corporate_actions aborts with the HTTP status and API message on non-200", {
  fake <- function(req) {
    httr2::response(
      status_code = 403L,
      headers = list(`Content-Type` = "application/json"),
      body = charToRaw('{"message":"forbidden"}')
    )
  }
  expect_snapshot(
    error = TRUE,
    httr2::with_mocked_responses(
      fake,
      hd_alpaca_corporate_actions(c("AAA", "BBB"), "2016-01-01", "2026-11-08",
                                  key = "k", secret = "s")
    )
  )
})

test_that("hd_alpaca_corporate_actions validates input", {
  expect_snapshot(error = TRUE, hd_alpaca_corporate_actions(character(), "2016-01-01", "2026-11-08", key = "k", secret = "s"))
  expect_snapshot(error = TRUE, hd_alpaca_corporate_actions("A", "2016-01-01", "2026-11-08", types = "dividend", key = "k", secret = "s"))
  withr::local_envvar(ALPACA_KEY = NA, ALPACA_SECRET = NA)
  expect_snapshot(error = TRUE, hd_alpaca_corporate_actions("A", "2016-01-01", "2026-11-08"))
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

# Flat SPY (close 100) on every weekday from 2015-12 to the end of 2023.
.ep_spy_flat <- function() {
  .ep_bars("SPY", "2023-12-29", 2200L, close = 100)
}

# Corporate-action records in the shape of hd_alpaca_corporate_actions().
.ep_ca <- function(type, symbol, effective = NA, process = NA, new_symbol = NA_character_,
                   acquirer = NA_character_, rate = NA_real_, cash_rate = NA_real_,
                   acquirer_rate = NA_real_, acquiree_rate = NA_real_) {
  tibble::tibble(
    type = type, symbol = symbol, new_symbol = new_symbol, acquirer_symbol = acquirer,
    rate = rate, cash_rate = cash_rate, acquirer_rate = acquirer_rate,
    acquiree_rate = acquiree_rate,
    effective_date = as.Date(effective), process_date = as.Date(process)
  )
}
.ep_no_ca <- function() .hd_alpaca_empty_corp_actions()

# A later bar for an unrelated symbol: the "last date in the fetched bars"
# that decides too_recent. 2023-12-29 is far past every test exit.
.ep_clock <- function() .ep_bars("CLK", "2023-12-29", 5)

# `adj` defaults to the raw bars (no corporate action in the window); `spy` to
# a flat SPY. Both get the clock/SPY rows they need.
.ep_px <- function(bars, exits, ca = .ep_no_ca(), adj = bars, spy = .ep_spy_flat(),
                   clock = TRUE, ...) {
  force(adj)
  if (clock) bars <- rbind(bars, .ep_clock())
  hd_alpaca_exit_prices(bars, rbind(adj, spy), ca, exits, ...)
}

test_that("hd_alpaca_exit_rule holds the #1041 constants", {
  r <- hd_alpaca_exit_rule()
  expect_equal(r$panel_start, as.Date("2016-01-04"))
  expect_equal(r$window_days, 30L)
  expect_equal(r$crash_drop, 0.40)
  expect_equal(r$crash_lookback, 60L)
  expect_equal(r$too_recent_weekdays, 5L)
  expect_equal(r$ca_days_before, 30L)
  expect_equal(r$ca_days_after, 10L)
  expect_null(r$max_gap_trading_days)
})

test_that("failure_candidate, SIVB shape: stops before the exit and fell 52% (SPY flat)", {
  # Last bar Thu 2023-03-09; weekdays 10,13,14,15,16,17 March = 6.
  bars <- .ep_bars("SIV", "2023-03-09", 120, close = c(rep(100, 119), 48))
  out <- .ep_px(bars, .ep_exit("SIV"))
  expect_equal(out$exit_type, "failure_candidate")
  expect_equal(out$ca_source, "rule")
  expect_equal(out$last_trade_date, as.Date("2023-03-09"))
  expect_equal(out$gap_trading_days, 6L)
  expect_equal(out$ret_60d, -0.52)
  expect_equal(out$ret_60d_spy, 0)
  expect_equal(out$ret_60d_rel, -0.52)
  expect_true(out$failure_candidate)
  expect_equal(out$exit_price_upper, 48)
  expect_equal(out$exit_price_lower, 0)
  expect_true(out$has_bars)
  expect_true(is.na(out$new_ticker))
})

test_that("failure_candidate, SBNY shape: stock -43%, SPY +3% (relative -45%), zero-volume flat tail cut", {
  real <- .ep_bars("SBN", "2023-03-14", 120, close = c(rep(100, 119), 57), volume = 5000)
  tail_dates <- .ep_weekdays("2023-03-15", 200)  # runs far past exit + 30 days
  tail <- tibble::tibble(symbol = "SBN", date = tail_dates, close = 57, volume = 0)
  spy <- .ep_bars("SPY", "2023-03-14", 120, close = c(rep(100, 119), 103))
  out <- .ep_px(rbind(real, tail), .ep_exit("SBN"), adj = rbind(real, tail), spy = spy)
  expect_equal(out$last_trade_date, as.Date("2023-03-14"))
  expect_equal(out$last_close, 57)
  expect_equal(out$ret_60d, -0.43)
  expect_equal(out$ret_60d_spy, 0.03)
  expect_equal(out$ret_60d_rel, 0.57 / 1.03 - 1)
  expect_equal(out$exit_type, "failure_candidate")
  expect_equal(out$exit_price_lower, 0)
  expect_equal(out$exit_price_upper, 57)
})

test_that("spin-off shape: raw -44% but adjusted ~0% is a takeover, not a failure", {
  raw <- .ep_bars("DWD", "2023-03-14", 120, close = c(rep(100, 119), 56))
  adj <- .ep_bars("DWD", "2023-03-14", 120, close = 100)
  out <- .ep_px(raw, .ep_exit("DWD"), adj = adj)
  expect_equal(out$ret_60d, 0)
  expect_equal(out$exit_type, "takeover")
  expect_equal(out$ca_source, "rule")
  expect_false(out$failure_candidate)
  expect_equal(out$exit_price_upper, 56)   # priced at the RAW last close
  expect_equal(out$exit_price_lower, 56)
  # The same raw shape with no adjustment (the old rule's input) IS a failure.
  expect_equal(.ep_px(raw, .ep_exit("DWD"))$exit_type, "failure_candidate")
})

test_that("market-crash shape: stock -48% while SPY -25% (relative -31%) is a takeover", {
  bars <- .ep_bars("RTN", "2023-03-14", 120, close = c(rep(100, 119), 52))
  spy <- .ep_bars("SPY", "2023-03-14", 120, close = c(rep(100, 119), 75))
  out <- .ep_px(bars, .ep_exit("RTN"), spy = spy)
  expect_equal(out$ret_60d, -0.48)
  expect_equal(out$ret_60d_spy, -0.25)
  expect_equal(out$ret_60d_rel, 0.52 / 0.75 - 1)
  expect_equal(out$exit_type, "takeover")
  expect_false(out$failure_candidate)
})

test_that("a stopped name that fell 25% is a takeover, not a failure (threshold is 40% relative)", {
  bars <- .ep_bars("DIP", "2023-03-14", 120, close = c(rep(100, 119), 75))
  out <- .ep_px(bars, .ep_exit("DIP"))
  expect_equal(out$ret_60d, -0.25)
  expect_equal(out$exit_type, "takeover")
  expect_false(out$failure_candidate)
})

test_that("takeover without a record, NBL shape: -2%, stops 6 weekdays before exit (gap does not matter)", {
  bars <- .ep_bars("NBL", "2023-03-09", 120, close = c(rep(100, 119), 98))
  out <- .ep_px(bars, .ep_exit("NBL"))
  expect_equal(out$gap_trading_days, 6L)
  expect_equal(out$exit_type, "takeover")
  expect_false(out$failure_candidate)
  expect_equal(out$exit_price_upper, 98)
  expect_equal(out$exit_price_lower, 98)
  expect_true(is.na(out$acquirer))
})

test_that("fewer than 61 trade bars: returns are NA and the name is not flagged", {
  bars <- .ep_bars("NEW", "2023-03-16", 30, close = c(100, rep(10, 29)))
  out <- .ep_px(bars, .ep_exit("NEW"))
  expect_true(is.na(out$ret_60d))
  expect_true(is.na(out$ret_60d_rel))
  expect_equal(out$exit_type, "takeover")
})

test_that("cash_merger record: takeover at the deal price, not the last close", {
  bars <- .ep_bars("TWT", "2023-03-16", 120, close = c(rep(40, 119), 52.4))
  ca <- .ep_ca("cash_merger", "TWT", effective = "2023-03-17", rate = 54.2)
  out <- .ep_px(bars, .ep_exit("TWT"), ca)
  expect_equal(out$exit_type, "takeover")
  expect_equal(out$ca_source, "corporate_action")
  expect_equal(out$exit_price_upper, 54.2)
  expect_equal(out$exit_price_lower, 54.2)
  expect_equal(out$last_close, 52.4)
  expect_equal(out$cash_rate, 54.2)
  expect_true(is.na(out$acquirer))
  # Without the record: priced at the last close.
  expect_equal(.ep_px(bars, .ep_exit("TWT"))$exit_price_upper, 52.4)
})

test_that("a record beats the fall test: a cash merger after a big drop is still a takeover", {
  bars <- .ep_bars("DRP", "2023-03-16", 120, close = c(rep(100, 119), 40))
  ca <- .ep_ca("cash_merger", "DRP", effective = "2023-03-17", rate = 41)
  expect_equal(.ep_px(bars, .ep_exit("DRP"))$exit_type, "failure_candidate")
  out <- .ep_px(bars, .ep_exit("DRP"), ca)
  expect_equal(out$exit_type, "takeover")
  expect_false(out$failure_candidate)
})

test_that("stock_merger and stock_and_cash_merger records: takeover at last close with acquirer columns", {
  bars <- .ep_bars("NBL", "2023-03-16", 120, close = c(rep(100, 119), 98))
  sm <- .ep_ca("stock_merger", "NBL", effective = "2023-03-17", acquirer = "CVX",
               acquirer_rate = 0.1191, acquiree_rate = 1)
  out <- .ep_px(bars, .ep_exit("NBL"), sm)
  expect_equal(out$exit_type, "takeover")
  expect_equal(out$ca_source, "corporate_action")
  expect_equal(out$acquirer, "CVX")
  expect_equal(out$acquirer_rate, 0.1191)
  expect_true(is.na(out$cash_rate))
  expect_equal(out$exit_price_upper, 98)
  expect_equal(out$exit_price_lower, 98)
  sc <- .ep_ca("stock_and_cash_merger", "NBL", effective = "2023-03-17", acquirer = "BMY",
               acquirer_rate = 0.5, cash_rate = 50)
  out2 <- .ep_px(bars, .ep_exit("NBL"), sc)
  expect_equal(out2$acquirer, "BMY")
  expect_equal(out2$acquirer_rate, 0.5)
  expect_equal(out2$cash_rate, 50)
  expect_equal(out2$exit_price_upper, 98)
})

test_that("name_change record: ticker_change with the new symbol and no price", {
  bars <- .ep_bars("FI", "2023-03-16", 120, close = c(rep(100, 119), 47))
  ca <- .ep_ca("name_change", "FI", process = "2023-03-17", new_symbol = "FISV")
  out <- .ep_px(bars, .ep_exit("FI"), ca)
  expect_equal(out$exit_type, "ticker_change")
  expect_equal(out$new_ticker, "FISV")
  expect_equal(out$ca_source, "corporate_action")
  expect_true(is.na(out$exit_price_upper))
  expect_true(is.na(out$exit_price_lower))
  expect_false(out$failure_candidate)
  # Without the record the same shape (-53%, SPY flat) is a failure candidate.
  expect_equal(.ep_px(bars, .ep_exit("FI"))$exit_type, "failure_candidate")
})

test_that("a name_change record wins over a merger record for the same exit", {
  bars <- .ep_bars("UTX", "2023-03-16", 120, close = 100)
  ca <- rbind(
    .ep_ca("cash_merger", "UTX", effective = "2023-03-17", rate = 99),
    .ep_ca("name_change", "UTX", process = "2023-03-17", new_symbol = "RTX")
  )
  expect_equal(.ep_px(bars, .ep_exit("UTX"), ca)$exit_type, "ticker_change")
})

test_that("records outside [exit - 30, exit + 10] days, for another symbol, or of type spin_off are ignored", {
  bars <- .ep_bars("OLD", "2023-03-16", 120, close = c(rep(100, 119), 47))
  exit <- .ep_exit("OLD")                      # 2023-03-17
  too_early <- .ep_ca("name_change", "OLD", process = "2023-02-10", new_symbol = "NEW")  # exit - 35
  too_late  <- .ep_ca("name_change", "OLD", process = "2023-03-28", new_symbol = "NEW")  # exit + 11
  other     <- .ep_ca("name_change", "XXX", process = "2023-03-17", new_symbol = "NEW")
  spin      <- .ep_ca("spin_off", "OLD", process = "2023-03-17", new_symbol = "NEW")
  for (ca in list(too_early, too_late, other, spin)) {
    out <- .ep_px(bars, exit, ca)
    expect_equal(out$exit_type, "failure_candidate")
    expect_equal(out$ca_source, "rule")
  }
  # The window edges are inclusive: exit - 30 and exit + 10 count.
  early_edge <- .ep_ca("name_change", "OLD", process = "2023-02-15", new_symbol = "NEW")
  late_edge  <- .ep_ca("name_change", "OLD", process = "2023-03-27", new_symbol = "NEW")
  expect_equal(.ep_px(bars, exit, early_edge)$exit_type, "ticker_change")
  expect_equal(.ep_px(bars, exit, late_edge)$exit_type, "ticker_change")
})

test_that("a record's effective_date is used when present, else process_date", {
  bars <- .ep_bars("OLD", "2023-03-16", 120, close = 100)
  both <- .ep_ca("name_change", "OLD", effective = "2022-01-01", process = "2023-03-17",
                 new_symbol = "NEW")
  # effective_date 2022-01-01 is far outside the window and wins over process_date.
  expect_equal(.ep_px(bars, .ep_exit("OLD"), both)$exit_type, "takeover")
})

test_that("demotion: -80% but still trading after the exit; priced at the exit date; records ignored", {
  d <- .ep_weekdays("2022-09-01", 150)           # runs to ~ 2023-03-28 (past exit)
  d <- d[d <= as.Date("2023-04-14")]
  bars <- tibble::tibble(symbol = "DEM", date = d,
                         close = ifelse(d <= as.Date("2023-03-17"), 100, 20),
                         volume = 1000)
  ca <- .ep_ca("name_change", "DEM", process = "2023-03-17", new_symbol = "NEW")
  out <- .ep_px(bars, .ep_exit("DEM"), ca)
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

test_that("too_recent: exit within 5 weekdays of the last fetched bar; 5 is too recent, 6 is not", {
  bars <- .ep_bars("REC", "2023-03-16", 120, close = 50)
  px <- function(clock_last) {
    hd_alpaca_exit_prices(rbind(bars, .ep_bars("CLK", clock_last, 5)),
                          rbind(bars, .ep_spy_flat()), .ep_no_ca(), .ep_exit("REC"))
  }
  # Latest bar anywhere is Tue 2023-03-21: 2 weekdays after the exit.
  out <- px("2023-03-21")
  expect_equal(out$exit_type, "too_recent")
  expect_true(is.na(out$failure_candidate))
  expect_true(is.na(out$exit_price_upper))
  expect_equal(px("2023-03-24")$exit_type, "too_recent")
  expect_equal(px("2023-03-27")$exit_type, "takeover")
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
  # known_delisted beats a corporate-action record.
  ca <- .ep_ca("cash_merger", "TWT", effective = "2023-03-17", rate = 54.2)
  expect_equal(.ep_px(bars, .ep_exit("TWT"), ca, known_failed = "TWT")$exit_type, "failure_candidate")
  # Without the override the same shape is a takeover.
  expect_equal(.ep_px(bars, .ep_exit("TWT"))$exit_type, "takeover")
})

test_that("no bars and not known: no_bars, failure unknown (NA), never a price", {
  bars <- .ep_bars("OTHER", "2023-03-17", 10)
  out <- .ep_px(bars, .ep_exit("MISSING"))
  expect_equal(out$exit_type, "no_bars")
  expect_false(out$has_bars)
  expect_true(is.na(out$failure_candidate))
  expect_true(is.na(out$ca_source))
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

test_that("red run guard: with a -50% relative threshold the SBNY shape would NOT be flagged", {
  # Documents why crash_drop is 0.40: SBNY's relative fall is -45%.
  bars <- .ep_bars("SBN", "2023-03-14", 120, close = c(rep(100, 119), 57))
  spy <- .ep_bars("SPY", "2023-03-14", 120, close = c(rep(100, 119), 103))
  loose <- hd_alpaca_exit_rule()
  loose$crash_drop <- 0.50
  expect_equal(.ep_px(bars, .ep_exit("SBN"), spy = spy, rule = loose)$exit_type, "takeover")
  expect_equal(.ep_px(bars, .ep_exit("SBN"), spy = spy)$exit_type, "failure_candidate")
})

test_that("hd_alpaca_exit_prices validates its inputs", {
  bars <- .ep_bars("AAA", "2023-03-17", 10)
  adj <- rbind(bars, .ep_spy_flat())
  ex <- .ep_exit("AAA")
  ca <- .ep_no_ca()
  expect_snapshot(error = TRUE, hd_alpaca_exit_prices(data.frame(x = 1), adj, ca, ex))
  bad <- bars
  bad$volume[1] <- NA
  expect_snapshot(error = TRUE, hd_alpaca_exit_prices(bad, adj, ca, ex))
  expect_snapshot(error = TRUE, hd_alpaca_exit_prices(bars, data.frame(x = 1), ca, ex))
  expect_snapshot(error = TRUE, hd_alpaca_exit_prices(bars, adj, ca, rbind(ex, ex)))
  expect_snapshot(error = TRUE, hd_alpaca_exit_prices(bars, adj, data.frame(symbol = "A"), ex))
  expect_snapshot(error = TRUE, hd_alpaca_exit_prices(bars, bars, ca, ex))   # no SPY rows
})

test_that("hd_alpaca_exit_coverage counts exits, priced exits, failures, each exit type and each ca_source by year", {
  px <- tibble::tibble(
    ticker = c("A", "B", "C", "D"),
    index_exit_date = as.Date(c("2016-05-01", "2016-06-01", "2017-01-01", "2010-01-01")),
    exit_type = c("failure_candidate", "demotion", "ticker_change", "no_bars"),
    ca_source = c("rule", "rule", "corporate_action", NA),
    has_bars = c(TRUE, TRUE, TRUE, FALSE),
    failure_candidate = c(TRUE, FALSE, FALSE, NA)
  )
  cov <- hd_alpaca_exit_coverage(px)
  expect_equal(cov$exit_year, c(2010L, 2016L, 2017L))
  expect_equal(cov$n_exits, c(1L, 2L, 1L))
  expect_equal(cov$n_with_bars, c(0L, 2L, 1L))
  expect_equal(cov$n_failure_candidates, c(0L, 1L, 0L))
  expect_equal(cov$n_demotion, c(0L, 1L, 0L))
  expect_equal(cov$n_failure_candidate, c(0L, 1L, 0L))
  expect_equal(cov$n_ticker_change, c(0L, 0L, 1L))
  expect_equal(cov$n_no_bars, c(1L, 0L, 0L))
  expect_equal(cov$n_takeover, c(0L, 0L, 0L))
  expect_equal(cov$n_ca_corporate_action, c(0L, 0L, 1L))
  expect_equal(cov$n_ca_rule, c(0L, 2L, 0L))
  expect_true(all(c("n_too_recent") %in% names(cov)))
})

# ── positive control ─────────────────────────────────────────────────────────

.ep_truth <- function() {
  t <- tibble::tibble(
    ticker = c("SIVB", "FRC", "SBNY", "TWTR", "NBL", "ATVI", "CELG", "JNPR", "RTN", "DWDP",
               "XEC", "ARNC", "M", "AIV", "LUMN", "FI", "UTX"),
    exit_type = c(rep("failure_candidate", 3), rep("takeover", 7),
                  rep("demotion", 5), rep("ticker_change", 2)),
    new_ticker = c(rep(NA_character_, 15), "FISV", "RTX"),
    acquirer = c(rep(NA_character_, 4), "CVX", rep(NA_character_, 12)),
    exit_price_upper = NA_real_
  )
  # Priced types carry a price; TWTR's is the cash deal price.
  t$exit_price_upper <- ifelse(t$exit_type == "ticker_change", NA_real_,
                               ifelse(t$ticker == "TWTR", 54.2, 10))
  t
}

test_that("hd_alpaca_exit_controls passes when every named case has its known type", {
  res <- hd_alpaca_exit_controls(.ep_truth())
  expect_equal(nrow(res), 17L)
  expect_true(all(res$status == "PASS"))
})

test_that("hd_alpaca_exit_controls aborts, listing every mismatch (it can go red)", {
  bad <- .ep_truth()
  bad$exit_type[bad$ticker == "SBNY"] <- "takeover"
  bad$new_ticker[bad$ticker == "FI"] <- "FI2"
  bad$exit_price_upper[bad$ticker == "TWTR"] <- 52.4     # last close, not the deal price
  bad$acquirer[bad$ticker == "NBL"] <- NA_character_
  expect_error(hd_alpaca_exit_controls(bad), "4 named real cases")
  err <- tryCatch(hd_alpaca_exit_controls(bad), error = function(e) conditionMessage(e))
  expect_match(err, "SBNY: expected failure_candidate, got takeover")
  expect_match(err, "FI: expected ticker_change -> FISV")
  expect_match(err, "TWTR: expected takeover \\(price 54.2\\)")
  expect_match(err, "NBL: expected takeover \\(acquirer CVX\\)")
  expect_no_match(err, "SIVB")
})

test_that("hd_alpaca_exit_controls reports absent tickers and is INDETERMINATE below 13 present", {
  few <- .ep_truth()[1:14, ]            # 3 absent: 14 present -> ok but reported
  expect_message(res <- hd_alpaca_exit_controls(few), "not in the exit table")
  expect_equal(sum(res$status == "ABSENT"), 3L)
  expect_error(hd_alpaca_exit_controls(.ep_truth()[1:12, ]), "INDETERMINATE")
})

test_that(".hd_env_flag parses explicitly and aborts on unknown values", {
  f <- historicaldata:::.hd_env_flag
  expect_false(f("X", ""))
  for (v in c("1", "true", "TRUE", "yes")) expect_true(f("X", v))
  for (v in c("0", "false", "FALSE", "no")) expect_false(f("X", v))
  expect_error(f("ALPACA_FORCE_REFETCH", "maybe"), "maybe")
})

test_that(".hd_alpaca_request_digest changes when a ticker or window changes", {
  d <- historicaldata:::.hd_alpaca_request_digest
  s <- as.Date(c("2016-01-04", "2017-02-01", "2018-03-01"))
  e <- s + 400L
  base <- d(c("AAA", "BBB", "CCC"), s, e)
  expect_match(base, "^[0-9a-f]{16}$")
  expect_equal(d(c("CCC", "AAA", "BBB"), s[c(3, 1, 2)], e[c(3, 1, 2)]), base)  # order-free
  expect_false(identical(d(c("AAA", "BBB", "ZZZ"), s, e), base))               # one ticker swapped
  expect_false(identical(d(c("AAA", "BBB", "CCC"), s, e + c(0L, 0L, 1L)), base)) # one window moved
})
