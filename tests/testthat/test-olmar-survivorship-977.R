testthat::local_edition(3)
source(here::here("scripts", "olmar_survivorship_977.R"))

# Tests for scripts/olmar_survivorship_977.R (#977). The script only RUNS when it
# is the Rscript entry point (sys.nframe() == 0), so source() loads the .osv_*
# functions without touching any data.
#
# Every fixture below is SYNTHETIC test input written by this file (invented
# symbols, invented prices). No real market data or real membership is typed in;
# the real membership comes from the downloaded CSV via .osv_parse_membership().

.write_membership <- function(dir, rows) {
  p <- file.path(dir, "m.csv")
  utils::write.csv(rows, p, row.names = FALSE)
  p
}

.toy_membership <- data.frame(
  date = c("2009-06-01", "2009-12-30", "2010-03-01"),
  tickers = c("AAA,BBB,CCC",
              "AAA,BBB,CCC-201002,BF.B,AZA.A-200106",
              "AAA,BBB,DDD"),
  stringsAsFactors = FALSE
)

test_that("parse_membership reads a valid file and sorts by date", {
  d <- withr::local_tempdir()
  m <- .osv_parse_membership(.write_membership(d, .toy_membership[3:1, ]))
  expect_s3_class(m$date, "Date")
  expect_equal(m$date, as.Date(c("2009-06-01", "2009-12-30", "2010-03-01")))
})

test_that("parse_membership rejects a missing file, wrong header, bad dates", {
  d <- withr::local_tempdir()
  expect_error(.osv_parse_membership(file.path(d, "nope.csv")), "not found")
  bad_hdr <- .write_membership(d, data.frame(day = "2009-01-01", syms = "A"))
  expect_error(.osv_parse_membership(bad_hdr), "columns date,tickers")
  bad_date <- .write_membership(d, data.frame(date = "not-a-date", tickers = "A"))
  expect_error(.osv_parse_membership(bad_date), "unparseable")
})

test_that("members_asof takes the last snapshot on or before the date", {
  d <- withr::local_tempdir()
  m <- .osv_parse_membership(.write_membership(d, .toy_membership))
  s <- .osv_members_asof(m, "2010-01-04")
  expect_equal(s$snapshot_date, as.Date("2009-12-30"))
  expect_equal(s$tokens,
               c("AAA", "BBB", "CCC-201002", "BF.B", "AZA.A-200106"))
  # exact-date boundary is inclusive
  expect_equal(.osv_members_asof(m, "2010-03-01")$snapshot_date, as.Date("2010-03-01"))
  expect_error(.osv_members_asof(m, "2000-01-01"), "no membership snapshot")
})

test_that("split_tokens strips only a trailing -YYYYMM and keeps dotted symbols", {
  x <- .osv_split_tokens(c("AAA", "CCC-201002", "BF.B", "AZA.A-200106"))
  expect_equal(x$symbol, c("AAA", "CCC", "BF.B", "AZA.A"))
  expect_equal(x$suffixed, c(FALSE, TRUE, FALSE, TRUE))
})

test_that("all_symbols covers every date and drops suffixes", {
  d <- withr::local_tempdir()
  m <- .osv_parse_membership(.write_membership(d, .toy_membership))
  expect_setequal(.osv_all_symbols(m),
                  c("AAA", "BBB", "CCC", "BF.B", "AZA.A", "DDD"))
})

test_that("classify separates the four outcomes and flags symbol reuse", {
  tok <- .osv_split_tokens(c("OK", "LATE", "GONE", "DEAD-201002", "REUSED-201505"))
  eqs <- data.frame(
    ticker = c("OK", "LATE", "REUSED"),
    first_date = as.Date(c("1990-01-01", "2012-05-18", "2001-01-01")),
    last_date = as.Date("2026-04-10"))
  c1 <- .osv_classify(tok, eqs, as.Date("2010-01-04"), 7L)
  expect_equal(c1$class, c("usable", "no_history_at_start",
                           "absent_from_equity_daily",
                           "delisted_per_source", "delisted_per_source"))
  expect_equal(c1$base_symbol_reused, c(FALSE, FALSE, FALSE, FALSE, TRUE))
})

test_that("dollar_volume is the median of close*volume and NA below min_days", {
  px <- data.frame(
    ticker = rep(c("A", "B"), c(5, 2)),
    date = as.Date("2009-08-01") + c(0:4, 0:1),
    close = c(10, 10, 10, 10, 10, 100, 100),
    volume = c(1, 2, 3, 4, 1000, 1, 1))
  out <- .osv_dollar_volume(px, "2009-07-01", "2009-12-31", min_days = 3L)
  a <- out[out$ticker == "A", ]
  expect_equal(a$dollar_volume, 30)        # median(10,20,30,40,10000)
  expect_equal(a$n_days, 5L)
  expect_true(is.na(out$dollar_volume[out$ticker == "B"]))
  # rows outside the window are ignored (no look-ahead into the test window)
  px2 <- rbind(px, data.frame(ticker = "A", date = as.Date("2010-02-01"),
                              close = 10, volume = 1e9))
  expect_equal(
    .osv_dollar_volume(px2, "2009-07-01", "2009-12-31", 3L)$dollar_volume[1], 30)
})

test_that("select_top orders by dollar volume, breaks ties alphabetically, skips NA and excluded", {
  dv <- data.frame(ticker = c("D", "C", "B", "A", "E"),
                   dollar_volume = c(5, 9, 9, NA, 1), n_days = 100L)
  top <- .osv_select_top(dv, 3L, exclude = "D")
  expect_equal(top$ticker, c("B", "C", "E"))
  expect_equal(top$rank, 1:3)
})

test_that("target_command reads a tar_target body without evaluating the file", {
  d <- withr::local_tempdir()
  f <- file.path(d, "plan.R")
  writeLines(c(
    "stop('must not run')",
    "plan_x <- function() list(",
    "  targets::tar_target(other, { 1 }),",
    "  targets::tar_target(wanted, { list(a = 2L, b = bt$v) })",
    ")"), f)
  cmd <- .osv_target_command(f, "wanted")
  expect_equal(eval(cmd, list(bt = list(v = 7))), list(a = 2L, b = 7))
  expect_error(.osv_target_command(f, "missing"), "no tar_target")
})

test_that("load_params evaluates the real plan files and exposes what the run needs", {
  p <- .osv_load_params(here::here())
  expect_true(all(c("window", "epsilon", "leverage", "cost_bps", "start_date",
                    "test_start", "test_end", "tickers") %in% names(p)))
  expect_s3_class(p$start_date, "Date")
  expect_type(p$tickers, "character")
})

test_that("args parser accepts key=value and flags anything else", {
  a <- .osv_args(c("--equity=/x.parquet", "--draws=5"))
  expect_equal(a$equity, "/x.parquet")
  expect_equal(a$draws, "5")
  expect_match(.osv_args("equity")$error, "bad argument")
  expect_match(.osv_args("--bogus=1")$error, "unknown argument")
})

# --- backtest wrapper -------------------------------------------------------

.toy_prices <- function(n_days = 200L, n_assets = 4L, seed = 1L) {
  set.seed(seed)
  dates <- as.Date("2010-01-04") + seq_len(n_days) - 1L
  m <- sapply(seq_len(n_assets), function(i) 100 * cumprod(1 + rnorm(n_days, 3e-4, 0.01)))
  colnames(m) <- paste0("T", seq_len(n_assets))
  data.frame(date = dates, m)
}
.toy_params <- list(window = 25L, epsilon = 10, leverage = 0.2, cost_bps = 10,
                    test_start = as.Date("2010-04-01"), test_end = as.Date("2010-06-30"))

test_that("run returns OLMAR-1 and EqualWeight for the three periods and EW == leverage 0", {
  suppressPackageStartupMessages(
    pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE))
  px <- .toy_prices()
  rf <- data.frame(date = px$date, rf_ret = 0.00005)
  r <- .osv_run(px, rf, .toy_params)
  expect_setequal(unique(r$strategy), c("OLMAR-1", "EqualWeight"))
  expect_setequal(unique(r$period), c("Training", "Testing", "Full Period"))
  # EW must be the same function with leverage 0 -- compare to a direct call
  direct <- olmar_backtest(px, window = 25L, epsilon = 10, leverage = 0, cost_bps = 10)
  ew_full <- r[r$strategy == "EqualWeight" & r$period == "Full Period", ]
  d <- direct[!is.na(direct$net_ret), ]
  expect_equal(ew_full$days, nrow(d))
  eq <- cumprod(1 + d$net_ret)
  expect_equal(ew_full$max_dd, min((eq - cummax(eq)) / cummax(eq)) * 100)
  # and OLMAR-1 must differ from EW (leverage 0.2 changes weights)
  ol <- r[r$strategy == "OLMAR-1" & r$period == "Full Period", ]
  expect_false(isTRUE(all.equal(ol$sharpe, ew_full$sharpe)))
})

test_that("run aborts instead of treating a missing risk-free series as zero", {
  suppressPackageStartupMessages(
    pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE))
  px <- .toy_prices()
  rf_thin <- data.frame(date = px$date[1:20], rf_ret = 0.00005)
  expect_error(.osv_run(px, rf_thin, .toy_params), "risk-free series missing")
})

test_that("an empty window yields NA metrics rather than a fabricated row", {
  d <- data.frame(net_ret = c(0.01, NA), rf_ret = 0)
  m <- .osv_metrics_one(d, "Testing")
  expect_equal(m$days, 1L)
  expect_true(is.na(m$sharpe))
})

test_that("wide builds one column per ticker, honours the start date, drops NA", {
  px <- data.frame(
    ticker = c("A", "A", "B", "B"),
    date = as.Date(c("2009-12-31", "2010-01-04", "2010-01-04", "2010-01-05")),
    adjusted = c(1, 2, 3, NA))
  w <- .osv_wide(px, c("A", "B"), "2010-01-01")
  expect_equal(names(w), c("date", "A", "B"))
  expect_equal(nrow(w), 1L)
  expect_null(.osv_wide(px, "Z", "2010-01-01"))
})

# --- main(): the three-outcome contract ------------------------------------

test_that("main returns 2 on a usage error", {
  expect_equal(suppressMessages(.osv_main("not-an-arg")), 2L)
  expect_equal(suppressMessages(.osv_main("--bogus=1")), 2L)
})

test_that("main returns 3 (INDETERMINATE) when an input is missing", {
  d <- withr::local_tempdir()
  expect_equal(suppressMessages(capture.output(
    st <- .osv_main(c("--equity=/no/such.parquet", "--factors=/no/such.parquet")))
    ), "RESULT: INDETERMINATE -- --equity parquet missing or not found")
  expect_equal(st, 3L)
  # equity present, factors missing
  eqf <- file.path(d, "eq.parquet"); file.create(eqf)
  capture.output(st2 <- suppressMessages(
    .osv_main(c(paste0("--equity=", eqf), "--factors=/no/such.parquet"))))
  expect_equal(st2, 3L)
})

.make_synthetic_world <- function(dir) {
  skip_if_not_installed("duckdb")
  set.seed(7)
  p <- .osv_load_params(here::here())
  dates <- seq(as.Date("2009-06-01"), as.Date("2011-12-30"), by = "day")
  dates <- dates[!format(dates, "%u") %in% c("6", "7")]
  etfs <- c("SPY", "QQQ", "IWM", "DIA")
  # synthetic series are generated for every current-list ticker, so the real
  # olmar_params$tickers can be matched; sector ETFs are absent on purpose.
  cur_stocks <- setdiff(p$tickers, c(etfs, grep("^XL", p$tickers, value = TRUE)))
  members <- sprintf("M%02d", 1:30)
  all_t <- c(etfs, cur_stocks, members)
  rows <- do.call(rbind, lapply(all_t, function(tk) {
    n <- length(dates)
    px <- 50 * cumprod(1 + rnorm(n, 3e-4, 0.01))
    data.frame(date = as.POSIXct(dates, tz = "UTC"), open = px, high = px, low = px,
               close = px, adjusted = px,
               volume = runif(n, 1e5, 1e6) * (1 + match(tk, all_t)),
               ticker = tk, source = "synthetic", asset_class = "equity",
               updated_at = Sys.time())
  }))
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbWriteTable(con, "eq", rows)
  eqp <- file.path(dir, "equity.parquet")
  DBI::dbExecute(con, sprintf("COPY eq TO '%s' (FORMAT PARQUET)", eqp))
  fa <- data.frame(date = dates, factor_name = "RF", value = 0.01,
                   dataset = "FF3", frequency = "daily", source = "synthetic",
                   updated_at = Sys.time())
  DBI::dbWriteTable(con, "fa", fa)
  fap <- file.path(dir, "factors.parquet")
  DBI::dbExecute(con, sprintf("COPY fa TO '%s' (FORMAT PARQUET)", fap))
  mem <- data.frame(
    date = "2009-12-30",
    tickers = paste(c(members, cur_stocks, "GONE-201002"), collapse = ","))
  list(equity = eqp, factors = fap, membership = .write_membership(dir, mem),
       cur_stocks = cur_stocks)
}

test_that("main end to end on a synthetic world returns 0 and writes the outputs", {
  d <- withr::local_tempdir()
  w <- .make_synthetic_world(d)
  out <- file.path(d, "out")
  txt <- capture.output(st <- suppressMessages(.osv_main(
    c(paste0("--equity=", w$equity), paste0("--factors=", w$factors),
      paste0("--membership=", w$membership), "--draws=3", "--to=2011-12-30",
      paste0("--out=", out)),
    cfg = list(min_equity_tickers = 10L, min_snapshot_tokens = 10L))))
  expect_equal(st, 0L)
  expect_true(any(grepl("^RESULT: ESTIMATE", txt)))
  expect_true(all(file.exists(file.path(out, c(
    "results.csv", "deltas.csv", "membership_classes.csv", "alt_stocks.csv", "draws.csv")))))
  cls <- utils::read.csv(file.path(out, "membership_classes.csv"))
  expect_equal(cls$n[cls$class == "delisted_per_source"], 1L)
  res <- utils::read.csv(file.path(out, "results.csv"))
  expect_setequal(unique(res$universe),
                  c("current", "alt_top_by_2009H2_dollar_volume"))
})

test_that("main returns 3 on thin inputs (falsification of the thin-input guards)", {
  d <- withr::local_tempdir()
  w <- .make_synthetic_world(d)
  args <- c(paste0("--equity=", w$equity), paste0("--factors=", w$factors),
            paste0("--membership=", w$membership), "--draws=0")
  # default guard (500 tickers / 400 tokens) must refuse the small synthetic world
  txt <- capture.output(st <- suppressMessages(.osv_main(args)))
  expect_equal(st, 3L)
  expect_match(txt, "too thin")
  # thin membership only
  txt2 <- capture.output(st2 <- suppressMessages(.osv_main(
    args, cfg = list(min_equity_tickers = 10L))))
  expect_equal(st2, 3L)
  expect_match(txt2, "tokens")
})

test_that("main returns 1 (none) when too few members are eligible to match the current list", {
  d <- withr::local_tempdir()
  w <- .make_synthetic_world(d)
  half <- seq_len(length(w$cur_stocks) %/% 2L)
  toks <- c(w$cur_stocks[half], paste0(w$cur_stocks[-half], "-201002"))
  mpath <- .write_membership(d, data.frame(date = "2009-12-30",
                                           tickers = paste(toks, collapse = ",")))
  txt <- capture.output(st <- suppressMessages(.osv_main(
    c(paste0("--equity=", w$equity), paste0("--factors=", w$factors),
      paste0("--membership=", mpath), "--draws=0", "--to=2011-12-30"),
    cfg = list(min_equity_tickers = 10L, min_snapshot_tokens = 1L))))
  expect_equal(st, 1L)
  expect_true(any(grepl("^RESULT: NONE", txt)))
})
