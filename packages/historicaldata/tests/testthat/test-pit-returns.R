# Tests for hd_pit_monthly_returns() / hd_pit_price_series() (#1041).
#
# Hermetic: every bar, member and exit row is SYNTHETIC (invented tickers and
# prices). Month-end bars sit on 2020-01-31, 2020-02-28, 2020-03-31 so a return
# is easy to check by hand. AAA trades throughout and fixes the month calendar.
# testthat edition 3.

testthat::local_edition(3)

.pr_bars <- function(sym, dates, closes, volume = 1000) {
  tibble::tibble(symbol = sym, date = as.Date(dates), close = closes,
                 volume = volume)
}

.pr_members <- function(...) {
  # ... : snapshot = c(tickers); names are the snapshot dates
  snaps <- list(...)
  do.call(rbind, lapply(names(snaps), function(d) {
    tibble::tibble(ticker = snaps[[d]], date = as.Date(d))
  }))
}

.pr_exit <- function(ticker = character(), index_exit_date = as.Date(character()),
                     exit_type = character(), new_ticker = NA_character_,
                     last_trade_date = as.Date(NA), last_close = NA_real_,
                     exit_price_upper = NA_real_, exit_price_lower = NA_real_,
                     has_bars = TRUE) {
  n <- length(ticker)
  tibble::tibble(
    ticker = ticker,
    index_exit_date = as.Date(index_exit_date),
    exit_type = exit_type,
    new_ticker = rep_len(new_ticker, n),
    last_trade_date = rep_len(as.Date(last_trade_date), n),
    last_close = rep_len(last_close, n),
    exit_price_upper = rep_len(exit_price_upper, n),
    exit_price_lower = rep_len(exit_price_lower, n),
    has_bars = rep_len(has_bars, n)
  )
}

# AAA: the always-present member that defines the calendar.
.pr_aaa <- function() {
  .pr_bars("AAA", c("2020-01-31", "2020-02-28", "2020-03-31"), c(100, 110, 99))
}

test_that("normal month: return is month-end to month-end, upper equals lower", {
  out <- hd_pit_monthly_returns(
    .pr_aaa(),
    .pr_members("2019-12-31" = "AAA"),
    .pr_exit()
  )
  expect_s3_class(out, "tbl_df")
  expect_named(out, c("ticker", "signal_ym", "ym", "signal_date", "date",
                      "ret_upper", "ret_lower", "exit_type"))
  expect_equal(out$ym, c("2020-02", "2020-03"))
  expect_equal(out$ret_upper, c(110 / 100 - 1, 99 / 110 - 1))
  expect_equal(out$ret_lower, out$ret_upper)
  expect_true(all(is.na(out$exit_type)))
})

test_that("signal month is the month BEFORE the held month (the signal lag)", {
  out <- hd_pit_monthly_returns(
    .pr_aaa(), .pr_members("2019-12-31" = "AAA"), .pr_exit()
  )
  expect_equal(out$signal_ym, c("2020-01", "2020-02"))
  expect_equal(out$ym, c("2020-02", "2020-03"))
  expect_equal(out$signal_date, as.Date(c("2020-01-31", "2020-02-28")))
  expect_equal(out$date, as.Date(c("2020-02-28", "2020-03-31")))
  expect_s3_class(out$date, "Date")
})

test_that("membership is read at the signal month-end, not the held month-end", {
  # BBB is a member at Jan-end only (removed 2020-02-10, keeps trading):
  # held in Feb, but not in the universe at Feb-end so no March row.
  bars <- rbind(.pr_aaa(),
                .pr_bars("BBB", c("2020-01-31", "2020-02-28", "2020-03-31"), c(10, 12, 15)))
  out <- hd_pit_monthly_returns(
    bars,
    .pr_members("2019-12-31" = c("AAA", "BBB"), "2020-02-10" = "AAA"),
    .pr_exit("BBB", "2020-02-10", "demotion", last_trade_date = "2020-03-31",
             last_close = 15, exit_price_upper = 12, exit_price_lower = 12)
  )
  b <- out[out$ticker == "BBB", ]
  expect_equal(b$ym, "2020-02")
  expect_equal(b$ret_upper, 12 / 10 - 1)
})

test_that("failure: upper ends at the last close, lower is -1", {
  bars <- rbind(
    .pr_aaa(),
    .pr_bars("FFF", c("2020-01-31", "2020-02-14"), c(50, 40))
  )
  out <- hd_pit_monthly_returns(
    bars,
    .pr_members("2019-12-31" = c("AAA", "FFF"), "2020-02-17" = "AAA"),
    .pr_exit("FFF", "2020-02-17", "failure_candidate",
             last_trade_date = "2020-02-14", last_close = 40,
             exit_price_upper = 40, exit_price_lower = 0)
  )
  f <- out[out$ticker == "FFF", ]
  expect_equal(nrow(f), 1L)
  expect_equal(f$signal_ym, "2020-01")
  expect_equal(f$ym, "2020-02")
  expect_equal(f$date, as.Date("2020-02-14"))
  expect_equal(f$ret_upper, 40 / 50 - 1)
  expect_equal(f$ret_lower, -1)
  expect_equal(f$exit_type, "failure_candidate")
})

test_that("cash takeover above the last close: the deal price, applied to the adjusted path", {
  # Adjusted closes (20 -> 25) differ in LEVEL from raw ones in real data; the
  # ratio exit_price / last_close is raw, the path is adjusted. Here the raw
  # last close is 50 while the adjusted one is 25 (a later 2:1 split).
  bars <- rbind(
    .pr_aaa(),
    .pr_bars("TTT", c("2020-01-31", "2020-02-20"), c(20, 25))
  )
  out <- hd_pit_monthly_returns(
    bars,
    .pr_members("2019-12-31" = c("AAA", "TTT"), "2020-02-24" = "AAA"),
    .pr_exit("TTT", "2020-02-24", "takeover",
             last_trade_date = "2020-02-20", last_close = 50,
             exit_price_upper = 60, exit_price_lower = 60)
  )
  t1 <- out[out$ticker == "TTT", ]
  expect_equal(nrow(t1), 1L)
  expect_equal(t1$ret_upper, (25 / 20) * (60 / 50) - 1)
  expect_equal(t1$ret_lower, t1$ret_upper)
  expect_equal(t1$exit_type, "takeover")
})

test_that("demotion: real return in the held month, tagged, then out of the universe", {
  bars <- rbind(
    .pr_aaa(),
    .pr_bars("DDD", c("2020-01-31", "2020-02-28", "2020-03-31"), c(10, 8, 7))
  )
  out <- hd_pit_monthly_returns(
    bars,
    .pr_members("2019-12-31" = c("AAA", "DDD"), "2020-02-17" = "AAA"),
    .pr_exit("DDD", "2020-02-17", "demotion",
             last_trade_date = "2020-03-31", last_close = 7,
             exit_price_upper = 8, exit_price_lower = 8)
  )
  d <- out[out$ticker == "DDD", ]
  expect_equal(d$ym, "2020-02")
  expect_equal(d$ret_upper, 8 / 10 - 1)   # the actual month return, no special case
  expect_equal(d$ret_lower, d$ret_upper)
  expect_equal(d$exit_type, "demotion")
})

test_that("rename A -> B is one continuous security with no exit across the switch", {
  # OLD trades to 2020-02-14, NEW from 2020-02-18 at a different price LEVEL
  # (adjusted series are independent). Chain-linked: the NEW series is rescaled
  # so its first close equals OLD's last.
  bars <- rbind(
    .pr_aaa(),
    .pr_bars("OLD", c("2020-01-31", "2020-02-14"), c(100, 102)),
    .pr_bars("NEW", c("2020-02-18", "2020-02-28", "2020-03-31"), c(51, 52, 53))
  )
  out <- hd_pit_monthly_returns(
    bars,
    .pr_members("2019-12-31" = c("AAA", "OLD"),
                "2020-02-18" = c("AAA", "NEW")),
    .pr_exit("OLD", "2020-02-18", "ticker_change", new_ticker = "NEW",
             last_trade_date = "2020-02-14", last_close = 102)
  )
  expect_false("OLD" %in% out$ticker)
  n <- out[out$ticker == "NEW", ]
  expect_equal(n$ym, c("2020-02", "2020-03"))
  # Jan-end 100; Feb-end = 102 * 52 / 51; Mar-end = 102 * 53 / 51
  expect_equal(n$ret_upper, c(102 * 52 / 51 / 100 - 1, 53 / 52 - 1))
  expect_true(all(is.na(n$exit_type)))
})

test_that("rename chain A -> B -> C resolves to C", {
  bars <- rbind(
    .pr_aaa(),
    .pr_bars("AA1", c("2020-01-31"), 10),
    .pr_bars("BB1", c("2020-02-03", "2020-02-14"), c(10, 11)),
    .pr_bars("CC1", c("2020-02-18", "2020-02-28"), c(11, 12))
  )
  out <- hd_pit_monthly_returns(
    bars,
    .pr_members("2019-12-31" = c("AAA", "AA1"), "2020-02-03" = c("AAA", "BB1"),
                "2020-02-18" = c("AAA", "CC1")),
    .pr_exit(c("AA1", "BB1"), c("2020-02-03", "2020-02-18"),
             c("ticker_change", "ticker_change"),
             new_ticker = c("BB1", "CC1"))
  )
  expect_equal(unique(out$ticker[out$ticker != "AAA"]), "CC1")
})

test_that("a rename cycle aborts", {
  bars <- .pr_aaa()
  ex <- .pr_exit(c("AAB", "BBA"), c("2020-02-03", "2020-02-18"),
                 c("ticker_change", "ticker_change"),
                 new_ticker = c("BBA", "AAB"))
  expect_snapshot(
    error = TRUE,
    hd_pit_monthly_returns(bars, .pr_members("2019-12-31" = "AAA"), ex)
  )
})

test_that("invalid or empty input aborts with a structured message", {
  mem <- .pr_members("2019-12-31" = "AAA")
  expect_snapshot(error = TRUE, hd_pit_monthly_returns(data.frame(x = 1), mem, .pr_exit()))
  expect_snapshot(error = TRUE, hd_pit_monthly_returns(.pr_aaa()[0, ], mem, .pr_exit()))
  expect_snapshot(error = TRUE, hd_pit_monthly_returns(.pr_aaa(), mem[0, ], .pr_exit()))
  expect_snapshot(error = TRUE, hd_pit_monthly_returns(.pr_aaa(), data.frame(ticker = "AAA"), .pr_exit()))
  expect_snapshot(error = TRUE, hd_pit_monthly_returns(.pr_aaa(), mem, data.frame(ticker = "AAA")))
  dup <- rbind(.pr_aaa(), .pr_aaa()[1, ])
  expect_snapshot(error = TRUE, hd_pit_monthly_returns(dup, mem, .pr_exit()))
  # a takeover with a missing exit price cannot be priced
  bars <- rbind(.pr_aaa(), .pr_bars("TTT", c("2020-01-31", "2020-02-20"), c(20, 25)))
  bad <- .pr_exit("TTT", "2020-02-24", "takeover", last_trade_date = "2020-02-20",
                  last_close = 25)
  expect_snapshot(error = TRUE, hd_pit_monthly_returns(
    bars, .pr_members("2019-12-31" = c("AAA", "TTT")), bad))
})

test_that("excluded securities are counted with a reason, never silently dropped", {
  bars <- rbind(
    .pr_aaa(),
    .pr_bars("TRC", c("2020-01-31", "2020-02-28"), c(10, 11))
  )
  mem <- .pr_members("2019-12-31" = c("AAA", "TRC", "NOB", "MNB", "FNB"))
  ex <- rbind(
    .pr_exit("TRC", "2020-03-02", "too_recent", last_trade_date = "2020-02-28",
             last_close = 11),
    .pr_exit("NOB", "2020-02-02", "no_bars", has_bars = FALSE),
    .pr_exit("FNB", "2020-02-02", "failure_candidate", has_bars = FALSE,
             exit_price_lower = 0)
  )
  out <- hd_pit_monthly_returns(bars, mem, ex)
  ex_tbl <- attr(out, "excluded")
  expect_s3_class(ex_tbl, "tbl_df")
  got <- stats::setNames(ex_tbl$reason, ex_tbl$ticker)
  expect_equal(got[["TRC"]], "too_recent")
  expect_equal(got[["NOB"]], "no_bars")
  expect_equal(got[["FNB"]], "failure_no_bars")
  expect_equal(got[["MNB"]], "member_no_bars")
  expect_false("AAA" %in% ex_tbl$ticker)
  # an excluded name contributes no rows
  expect_false(any(out$ticker %in% c("TRC", "NOB", "MNB", "FNB")))
})

test_that("hd_pit_price_series splices renamed tickers and clips at the last trade of an exit", {
  bars <- rbind(
    .pr_bars("OLD", c("2020-01-31", "2020-02-14"), c(100, 102)),
    .pr_bars("NEW", c("2020-02-18", "2020-02-28"), c(51, 52)),
    .pr_bars("TTT", c("2020-01-31", "2020-02-20", "2020-02-21"), c(20, 25, 99))
  )
  ex <- rbind(
    .pr_exit("OLD", "2020-02-18", "ticker_change", new_ticker = "NEW",
             last_trade_date = "2020-02-14", last_close = 102),
    .pr_exit("TTT", "2020-02-24", "takeover", last_trade_date = "2020-02-20",
             last_close = 25, exit_price_upper = 30, exit_price_lower = 30)
  )
  s <- hd_pit_price_series(bars, ex)
  expect_named(s, c("ticker", "date", "adj_close"))
  expect_setequal(s$ticker, c("NEW", "TTT"))
  new <- s[s$ticker == "NEW", ]
  expect_equal(new$adj_close, c(100, 102, 102, 104))   # 2 = 102/51
  expect_equal(max(s$date[s$ticker == "TTT"]), as.Date("2020-02-20"))
})

test_that("hd_alpaca_member_bars_adj_path aborts naming the fetch script when absent", {
  tmp <- withr::local_tempdir()
  expect_snapshot(
    error = TRUE,
    hd_alpaca_member_bars_adj_path(tmp),
    transform = function(x) gsub(tmp, "<TMP>", x, fixed = TRUE)
  )
  file.create(file.path(tmp, "alpaca_member_bars_adj.parquet"))
  expect_equal(hd_alpaca_member_bars_adj_path(tmp),
               file.path(tmp, "alpaca_member_bars_adj.parquet"))
})

test_that("excluded carries last_member_date: the latest snapshot a security was a member", {
  bars <- .pr_aaa()
  mem <- .pr_members(
    "2018-06-30" = c("AAA", "OLD", "NEW"),
    "2019-12-31" = c("AAA", "NEW")
  )
  ex <- rbind(
    .pr_exit("OLD", "2019-01-02", "no_bars", has_bars = FALSE),
    .pr_exit("NEW", "2020-02-02", "no_bars", has_bars = FALSE)
  )
  ex_tbl <- attr(hd_pit_monthly_returns(bars, mem, ex), "excluded")
  expect_s3_class(ex_tbl$last_member_date, "Date")
  got <- stats::setNames(ex_tbl$last_member_date, ex_tbl$ticker)
  expect_equal(got[["OLD"]], as.Date("2018-06-30"))   # pre-window leaver
  expect_equal(got[["NEW"]], as.Date("2019-12-31"))   # still a member later
})
