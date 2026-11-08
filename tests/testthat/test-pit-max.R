testthat::local_edition(3)
# #1041: stock MAX on point-in-time S&P 500 members, with exit-month bounds.
#
# The key property: portfolio_longshort() winsorises monthly returns at +-20%,
# which would clip a -100% failure month (the LOWER bound) to -20% and make the
# bound meaningless. Exit months are therefore exempt for the PIT portfolios.
# All data here is SYNTHETIC.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
pit_env <- new.env(parent = globalenv())
suppressWarnings(sys.source(here::here("R/utils_metrics.R"),
                            envir = pit_env, keep.source = FALSE))
suppressWarnings(sys.source(here::here("R/plan_stock_backtest.R"),
                            envir = pit_env, keep.source = FALSE))
suppressWarnings(sys.source(here::here("R/plan_pit_max.R"),
                            envir = pit_env, keep.source = FALSE))

.pm_params <- list(n_deciles = 10L, cost_per_trade = 0.005,
                   borrow_rate_annual = 0.03, max_monthly_ret = 0.20)

# One month, 10 deciles x 5 stocks = 50 stocks. Decile d has max_ret = 11 - d
# (decile 1 = highest signal). Every ordinary stock returns +1%; the single
# failing stock sits in decile 1 with ret_upper = -0.2, ret_lower = -1.
.pm_panel <- function(n_months = 1L, fail = TRUE) {
  months <- format(seq(as.Date("2020-02-01"), by = "month", length.out = n_months), "%Y-%m")
  rows <- lapply(months, function(m) {
    tibble::tibble(
      ticker = paste0("S", seq_len(50L)),
      signal_ym = format(seq(as.Date(paste0(m, "-01")), by = "-1 month", length.out = 2L)[2L], "%Y-%m"),
      ym = m,
      max_ret = rep(10:1, each = 5L) + seq_len(50L) / 1000,
      ret_upper = 0.01, ret_lower = 0.01,
      exit_type = NA_character_
    )
  })
  p <- dplyr::bind_rows(rows)
  if (fail) {
    i <- which(p$ticker == "S1" & p$ym == months[1L])   # S1 is in decile 1
    p$ret_upper[i] <- -0.2
    p$ret_lower[i] <- -1
    p$exit_type[i] <- "failure_candidate"
  }
  p$is_exit <- p$exit_type %in% c("takeover", "failure_candidate")
  p
}

.pm_rf <- function(n = 24L) {
  tibble::tibble(ym = format(seq(as.Date("2020-01-01"), by = "month", length.out = n), "%Y-%m"),
                 rf_ret = 0.001)
}

test_that("portfolio_longshort: a -1 exit-month return survives when exit months are not winsorised", {
  df <- tibble::tibble(
    ym = "2020-02", ticker = c("A", "B", "C", "D"), decile = c(1L, 1L, 10L, 10L),
    monthly_ret = c(-1, 0.1, 0.02, 0.02), is_exit = c(TRUE, FALSE, FALSE, FALSE)
  )
  keep <- pit_env$portfolio_longshort(df, winsorise_exits = FALSE)
  expect_equal(keep$long_ret, mean(c(-1, 0.1)))           # -0.45: the -1 survived
  clipped <- pit_env$portfolio_longshort(df)              # default: unchanged behaviour
  expect_equal(clipped$long_ret, mean(c(-0.2, 0.1)))
})

test_that("portfolio_longshort: only EXIT months are exempt from winsorising", {
  df <- tibble::tibble(
    ym = "2020-02", ticker = c("A", "B", "C", "D"), decile = c(1L, 1L, 10L, 10L),
    monthly_ret = c(-1, 0.9, 0.02, 0.02), is_exit = c(TRUE, FALSE, FALSE, FALSE)
  )
  out <- pit_env$portfolio_longshort(df, winsorise_exits = FALSE)
  expect_equal(out$long_ret, mean(c(-1, 0.2)))            # B is clipped at +20%, A is not
  # No is_exit column: nothing is exempt even with winsorise_exits = FALSE.
  out2 <- pit_env$portfolio_longshort(df[, setdiff(names(df), "is_exit")], winsorise_exits = FALSE)
  expect_equal(out2$long_ret, mean(c(-0.2, 0.2)))
})

test_that("the lower-bound PIT portfolio carries the -1 failure month, the upper one -20%", {
  panel <- .pm_panel()
  lo <- pit_env$pit_max_portfolio(panel, "lower", .pm_params, .pm_rf())
  up <- pit_env$pit_max_portfolio(panel, "upper", .pm_params, .pm_rf())
  expect_equal(lo$long_ret, mean(c(-1, rep(0.01, 4L))))
  expect_equal(up$long_ret, mean(c(-0.2, rep(0.01, 4L))))
  expect_lt(lo$port_ret, up$port_ret)
  # The two bounds differ ONLY in that month: remove the failure and they agree.
  ok <- .pm_panel(fail = FALSE)
  expect_equal(pit_env$pit_max_portfolio(ok, "lower", .pm_params, .pm_rf())$port_ret,
               pit_env$pit_max_portfolio(ok, "upper", .pm_params, .pm_rf())$port_ret)
})

test_that("pit_max_portfolio rejects an unknown variant", {
  expect_error(pit_env$pit_max_portfolio(.pm_panel(), "middle", .pm_params, .pm_rf()),
               "should be one of")
})

test_that("pit_max_signal: max daily return of the month, at least 10 daily returns", {
  d <- seq(as.Date("2020-01-01"), by = "day", length.out = 60L)
  d <- d[!(format(d, "%u") %in% c("6", "7"))]
  px <- cumprod(c(100, rep(1.01, length(d) - 1L)))
  px[15L] <- px[14L] * 1.10   # a +10% day in January (the 15th weekday)
  series <- tibble::tibble(ticker = "AAA", date = d, adj_close = px)
  sig <- pit_env$pit_max_signal(series)
  jan <- sig[sig$ym == "2020-01", ]
  expect_equal(jan$max_ret, 0.10, tolerance = 1e-9)
  # A month with fewer than 10 daily returns is dropped.
  short <- series[series$date < as.Date("2020-01-10"), ]
  expect_equal(nrow(pit_env$pit_max_signal(short)), 0L)
})

test_that("pit_max_panel keeps only months with at least n_deciles * 5 stocks and flags exits", {
  p <- .pm_panel(n_months = 2L)
  sig <- p |> dplyr::transmute(ticker, ym = signal_ym, max_ret)
  pm <- p |> dplyr::select(ticker, signal_ym, ym, ret_upper, ret_lower, exit_type)
  out <- pit_env$pit_max_panel(pm, sig, 10L)
  expect_setequal(unique(out$ym), unique(p$ym))
  expect_true(out$is_exit[out$ticker == "S1" & out$ym == "2020-02"])
  # Drop some stocks from month 2 so it has fewer than 50: the month goes.
  pm2 <- pm[!(pm$ym == "2020-03" & pm$ticker %in% paste0("S", 1:10)), ]
  out2 <- pit_env$pit_max_panel(pm2, sig, 10L)
  expect_equal(unique(out2$ym), "2020-02")
})

# A current-members portfolio for the tests: same months, no exits, a slightly
# different return level so the variants are distinguishable.
.pm_current <- function(panel, rf, shift = 0.003) {
  ok <- panel
  ok$ret_upper <- ok$ret_upper + shift
  ok$ret_lower <- ok$ret_upper
  ok$exit_type <- NA_character_
  ok$is_exit <- FALSE
  list(panel = ok, port = pit_env$pit_max_portfolio(ok, "upper", .pm_params, rf))
}

test_that("pit_max_comparison: one row per variant, same metric code, leaver-months counted", {
  panel <- .pm_panel(n_months = 14L)
  # Month-varying returns so the volatility is not zero.
  set.seed(1)
  panel$ret_upper <- panel$ret_upper + rnorm(nrow(panel), 0, 0.01)
  panel$ret_lower <- panel$ret_upper
  panel$ret_lower[panel$is_exit] <- -1
  rf <- .pm_rf()
  up <- pit_env$pit_max_portfolio(panel, "upper", .pm_params, rf)
  lo <- pit_env$pit_max_portfolio(panel, "lower", .pm_params, rf)
  cur <- .pm_current(panel, rf)
  biased <- up
  biased$port_ret <- biased$port_ret + 0.001
  biased_n <- tibble::tibble(ym = up$ym, n_stocks = 60L)
  cmp <- pit_env$pit_max_comparison(biased, cur$port, up, lo, panel, cur$panel,
                                    biased_n, min_months = 12L)
  expect_equal(cmp$variant, c("biased", "current_members", "pit_upper", "pit_lower"))
  expect_equal(cmp$n_months, rep(14L, 4L))
  ref <- pit_env$calc_backtest_metrics(up, "Full Period", strategy = "Stock MAX")
  expect_equal(cmp$sharpe[3L], ref$sharpe)
  expect_equal(cmp$ann_return[3L], ref$cagr)
  ref_cur <- pit_env$calc_backtest_metrics(cur$port, "Full Period", strategy = "Stock MAX")
  expect_equal(cmp$ann_return[2L], ref_cur$cagr)
  expect_equal(cmp$mean_n_stocks, c(60, 50, 50, 50))
  expect_equal(cmp$n_failure_candidate, c(NA, NA, 1L, 1L))
  expect_equal(cmp$n_takeover, c(NA, NA, 0L, 0L))
  expect_lt(cmp$ann_return[4L], cmp$ann_return[3L])   # lower bound is worse
})

test_that("pit_max_comparison: every variant uses the common non-NA-rf months of ALL FOUR", {
  set.seed(2)
  panel <- .pm_panel(n_months = 32L)         # months 2020-02 .. 2022-09
  panel$ret_upper <- panel$ret_upper + rnorm(nrow(panel), 0, 0.01)
  panel$ret_lower <- panel$ret_upper
  panel$ret_lower[panel$is_exit] <- -1
  rf <- .pm_rf(30L)                          # 2020-01 .. 2022-06: last 3 panel months NA
  rf$rf_ret[10L] <- NA_real_                 # 2020-10 NA as well
  up <- pit_env$pit_max_portfolio(panel, "upper", .pm_params, rf)
  lo <- pit_env$pit_max_portfolio(panel, "lower", .pm_params, rf)
  biased <- up[4:29, ]                       # the biased universe starts later, ends earlier
  biased$port_ret <- biased$port_ret + 0.002
  biased_n <- tibble::tibble(ym = biased$ym, n_stocks = 60L)
  cur <- .pm_current(panel, rf)
  # The current-members portfolio starts even later and ends earlier still.
  cur_port <- cur$port[6:27, ]
  cmp <- pit_env$pit_max_comparison(biased, cur_port, up, lo, panel, cur$panel,
                                    biased_n, min_months = 12L)
  common <- setdiff(intersect(biased$ym, cur_port$ym), "2020-10")
  expect_length(common, 21L)
  expect_equal(cmp$n_months, rep(21L, 4L))
  expect_equal(cmp$first_ym, rep(min(common), 4L))
  expect_equal(cmp$last_ym, rep(max(common), 4L))
  ref <- pit_env$calc_backtest_metrics(up[up$ym %in% common, ], "Full Period",
                                       strategy = "Stock MAX")
  expect_equal(cmp$sharpe[3L], ref$sharpe)
  expect_equal(cmp$ann_return[3L], ref$cagr)
  ub <- up[up$ym %in% common, ]
  expect_equal(cmp$long_ann[3L], mean(ub$long_ret) * 12)
  expect_equal(cmp$short_ann[3L], mean(ub$short_ret) * 12)
  cb <- cur_port[cur_port$ym %in% common, ]
  expect_equal(cmp$long_ann[2L], mean(cb$long_ret) * 12)
  # Leaver-months are counted in the common window only: the failure sits in
  # 2020-02, which is before the biased start, so it drops out.
  expect_equal(cmp$n_failure_candidate, c(NA, NA, 0L, 0L))
})

test_that("pit_max_comparison aborts when fewer than 24 common non-NA-rf months remain", {
  panel <- .pm_panel(n_months = 3L)
  rf <- .pm_rf()
  up <- pit_env$pit_max_portfolio(panel, "upper", .pm_params, rf)
  lo <- pit_env$pit_max_portfolio(panel, "lower", .pm_params, rf)
  bn <- tibble::tibble(ym = up$ym, n_stocks = 50L)
  expect_error(pit_env$pit_max_comparison(up, up, up, lo, panel, panel, bn), "at least 24")
  # 26 months, but 3 NA rf months leave 23 common: still an abort.
  panel <- .pm_panel(n_months = 26L)
  rf <- .pm_rf(30L)
  rf$rf_ret[c(5L, 6L, 7L)] <- NA_real_
  up <- pit_env$pit_max_portfolio(panel, "upper", .pm_params, rf)
  lo <- pit_env$pit_max_portfolio(panel, "lower", .pm_params, rf)
  bn <- tibble::tibble(ym = up$ym, n_stocks = 50L)
  expect_error(pit_env$pit_max_comparison(up, up, up, lo, panel, panel, bn), "Only 23 months")
  # ONE short variant is enough to abort the four-way comparison.
  expect_error(pit_env$pit_max_comparison(up, up[1:10, ], up, lo, panel, panel, bn),
               "Only 7 months")
})

test_that("pit_diff_stats: a constant +0.01 monthly difference gives annualised mean 0.12", {
  st <- pit_env$pit_diff_stats(rep(0.01, 48L), B = 200L)
  expect_equal(st$mean_ann, 0.12)
  expect_equal(st$n_months, 48L)
  # No variation: the bootstrap interval collapses on the mean.
  expect_equal(st$ci_lo, 0.12)
  expect_equal(st$ci_hi, 0.12)
})

test_that("pit_diff_stats: an iid-noise difference has a small t and an interval around 0", {
  set.seed(7)
  d <- rnorm(240L, 0, 0.02)
  st <- pit_env$pit_diff_stats(d, B = 2000L)
  expect_lt(abs(st$t_plain), 3)
  expect_lt(abs(st$t_nw), 3)
  expect_lt(st$ci_lo, 0)
  expect_gt(st$ci_hi, 0)
  expect_equal(st$mean_ann, mean(d) * 12)
  # A real +1.5 sd drift is detected: the same noise shifted has a large t.
  big <- pit_env$pit_diff_stats(d + 0.03, B = 500L)
  expect_gt(big$t_plain, 5)
  expect_gt(big$ci_lo, 0)
})

test_that("pit_diff_stats: Newey-West t equals the plain t when lags = 0", {
  set.seed(11)
  d <- rnorm(100L, 0.002, 0.02)
  st <- pit_env$pit_diff_stats(d, lags = 0L, B = 100L)
  expect_equal(st$t_nw, st$t_plain)
  # With autocorrelated data and lags the two differ.
  ar <- as.numeric(stats::arima.sim(list(ar = 0.6), n = 200L)) * 0.01 + 0.002
  st6 <- pit_env$pit_diff_stats(ar, lags = 6L, B = 100L)
  expect_false(isTRUE(all.equal(st6$t_nw, st6$t_plain)))
  expect_lt(abs(st6$t_nw), abs(st6$t_plain))   # positive autocorrelation widens the SE
})

test_that("pit_diff_stats: the bootstrap is reproducible under a seed and validates input", {
  d <- c(0.01, -0.02, 0.03, 0.0, 0.015, -0.01, 0.02, 0.005)
  set.seed(1041L); a <- pit_env$pit_diff_stats(d, B = 500L)
  set.seed(1041L); b <- pit_env$pit_diff_stats(d, B = 500L)
  expect_equal(a, b)
  expect_error(pit_env$pit_diff_stats(c(0.1, NA, 0.2)), "without NA")
  expect_error(pit_env$pit_diff_stats(c(0.1, 0.2)), "at least 3")
})

test_that("pit_max_decomposition: three effects x three legs, differences of the right pair", {
  set.seed(3)
  panel <- .pm_panel(n_months = 30L)
  panel$ret_upper <- panel$ret_upper + rnorm(nrow(panel), 0, 0.01)
  panel$ret_lower <- panel$ret_upper
  panel$ret_lower[panel$is_exit] <- -1
  rf <- .pm_rf(40L)
  up <- pit_env$pit_max_portfolio(panel, "upper", .pm_params, rf)
  lo <- pit_env$pit_max_portfolio(panel, "lower", .pm_params, rf)
  cur <- .pm_current(panel, rf, shift = 0.003)
  biased <- up
  biased$port_ret <- biased$port_ret + 0.005
  biased$long_ret <- biased$long_ret + 0.005
  set.seed(1041L)
  dec <- pit_env$pit_max_decomposition(biased, cur$port, up, lo, lags = 6L, block = 6L, B = 300L)
  expect_equal(nrow(dec), 9L)
  expect_equal(unique(dec$comparison),
               c("biased - current_members", "current_members - pit_upper",
                 "pit_upper - pit_lower"))
  expect_equal(unique(dec$effect), c("size / concentration", "survivorship", "failure bound"))
  expect_equal(dec$leg[1:3], c("long", "short", "long_short"))
  expect_true(all(dec$n_months == 30L))
  # survivorship long leg: current - upper, annualised mean.
  row <- dec[dec$comparison == "current_members - pit_upper" & dec$leg == "long", ]
  expect_equal(row$mean_ann, mean(cur$port$long_ret - up$long_ret) * 12)
  # size long-short: (up + 0.005) - current on port_ret.
  row2 <- dec[dec$comparison == "biased - current_members" & dec$leg == "long_short", ]
  expect_equal(row2$mean_ann, mean(biased$port_ret - cur$port$port_ret) * 12)
  # failure bound: lower is worse only in the failure month, so the mean is > 0.
  row3 <- dec[dec$comparison == "pit_upper - pit_lower" & dec$leg == "long", ]
  expect_gt(row3$mean_ann, 0)
  expect_error(pit_env$pit_max_decomposition(up, cur$port[1:5, ], up, lo), "at least 24")
})

test_that("pit_current_members_monthly: today's list in every month, renames spliced, no exits", {
  # AAA is a current member all along; NEW (renamed from OLD) joined the index later
  # but is a current member too, so it is carried back; GONE left before the latest
  # snapshot and must NOT appear.
  bars <- function(sym, dates, closes) {
    tibble::tibble(symbol = sym, date = as.Date(dates), close = closes, volume = 1000)
  }
  b <- dplyr::bind_rows(
    bars("AAA", c("2020-01-31", "2020-02-28", "2020-03-31"), c(100, 110, 99)),
    bars("OLD", c("2020-01-31", "2020-02-28"), c(10, 12)),
    bars("NEW", c("2020-03-31"), c(6)),
    bars("GONE", c("2020-01-31", "2020-02-28", "2020-03-31"), c(5, 5, 5))
  )
  uni <- tibble::tibble(
    ticker = c("AAA", "GONE", "AAA", "NEW"),
    date = as.Date(c("2019-06-30", "2019-06-30", "2020-06-30", "2020-06-30"))
  )
  ex <- tibble::tibble(
    ticker = c("OLD", "GONE"), index_exit_date = as.Date(c("2020-03-01", "2020-06-30")),
    exit_type = c("ticker_change", "takeover"), new_ticker = c("NEW", NA_character_),
    last_trade_date = as.Date(c(NA, "2020-03-31")), last_close = c(NA, 5),
    exit_price_upper = c(NA, 6), exit_price_lower = c(NA, 0), has_bars = TRUE
  )
  out <- pit_env$pit_current_members_monthly(b, uni, ex, as.Date("2016-01-04"))
  expect_setequal(out$ticker, c("AAA", "NEW"))           # GONE is not a current member
  expect_true(all(is.na(out$exit_type)))                 # no exits by construction
  expect_equal(out$ret_upper, out$ret_lower)
  # NEW is the OLD series chain-linked: 12/10 - 1 in 2020-02 (OLD's own bars).
  new_feb <- out[out$ticker == "NEW" & out$ym == "2020-02", ]
  expect_equal(new_feb$ret_upper, 12 / 10 - 1)
  # Every month's universe is today's list, from the first month on.
  expect_equal(sort(unique(out$ticker[out$ym == "2020-02"])), c("AAA", "NEW"))
})

test_that("pit_excluded_summary counts in-window securities and keeps the full count", {
  ex <- tibble::tibble(ticker = c("A", "B", "C", "D", "E"),
                       reason = c("no_bars", "no_bars", "no_bars", "failure_no_bars", "failure_no_bars"),
                       last_member_date = as.Date(c("2020-01-01", "2015-01-01", "2014-01-01",
                                                    "2021-01-01", "2012-01-01")))
  out <- pit_env$pit_excluded_summary(ex, panel_start = as.Date("2016-01-01"))
  expect_equal(out$reason, c("no_bars", "failure_no_bars"))   # tie: larger n_all first
  expect_equal(out$n_securities, c(1L, 1L))
  expect_equal(out$n_all, c(3L, 2L))
})

test_that("plan_pit_max defines the report targets and none feeds the leaderboard", {
  tg <- pit_env$plan_pit_max()
  nm <- vapply(tg, function(t) t$settings$name, character(1))
  expect_true(all(c("stk_member_bars_adj_file", "stk_member_bars_adj", "stk_pit_monthly",
                    "stk_pit_max_portfolio_upper", "stk_pit_max_portfolio_lower",
                    "stk_max_portfolio_biased_2016", "stk_pit_max_comparison",
                    "stk_current_member_bars_adj_file", "stk_current_member_bars_adj",
                    "stk_current_member_trimmed", "stk_current_members_monthly",
                    "stk_current_members_max_portfolio",
                    "stk_pit_max_decomposition") %in% nm))
  src <- paste(readLines(here::here("R/plan_pit_max.R")), collapse = "\n")
  code <- gsub("#[^\n]*", "", src)
  expect_false(grepl("register_runs|leaderboard", code))
  expect_equal(tg[[which(nm == "stk_member_bars_adj_file")]]$settings$format, "file")
  expect_equal(tg[[which(nm == "stk_current_member_bars_adj_file")]]$settings$format, "file")
})
