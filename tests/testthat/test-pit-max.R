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
  biased <- up
  biased$port_ret <- biased$port_ret + 0.001
  biased_n <- tibble::tibble(ym = up$ym, n_stocks = 60L)
  cmp <- pit_env$pit_max_comparison(biased, up, lo, panel, biased_n, min_months = 12L)
  expect_equal(cmp$variant, c("biased", "pit_upper", "pit_lower"))
  expect_equal(cmp$n_months, rep(14L, 3L))
  ref <- pit_env$calc_backtest_metrics(up, "Full Period", strategy = "Stock MAX")
  expect_equal(cmp$sharpe[2L], ref$sharpe)
  expect_equal(cmp$ann_return[2L], ref$cagr)
  expect_equal(cmp$mean_n_stocks, c(60, 50, 50))
  expect_equal(cmp$n_failure_candidate, c(NA, 1L, 1L))
  expect_equal(cmp$n_takeover, c(NA, 0L, 0L))
  expect_lt(cmp$ann_return[3L], cmp$ann_return[2L])   # lower bound is worse
})

test_that("pit_max_comparison: every variant uses the common non-NA-rf months only", {
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
  cmp <- pit_env$pit_max_comparison(biased, up, lo, panel, biased_n)
  common <- setdiff(biased$ym, "2020-10")
  expect_length(common, 25L)
  expect_equal(cmp$n_months, rep(25L, 3L))
  expect_equal(cmp$first_ym, rep(min(common), 3L))
  expect_equal(cmp$last_ym, rep(max(common), 3L))
  ref <- pit_env$calc_backtest_metrics(up[up$ym %in% common, ], "Full Period",
                                       strategy = "Stock MAX")
  expect_equal(cmp$sharpe[2L], ref$sharpe)
  expect_equal(cmp$ann_return[2L], ref$cagr)
  ub <- up[up$ym %in% common, ]
  expect_equal(cmp$long_ann[2L], mean(ub$long_ret) * 12)
  expect_equal(cmp$short_ann[2L], mean(ub$short_ret) * 12)
  # Leaver-months are counted in the common window only: the failure sits in
  # 2020-02, which is before the biased start, so it drops out.
  expect_equal(cmp$n_failure_candidate, c(NA, 0L, 0L))
})

test_that("pit_max_comparison aborts when fewer than 24 common non-NA-rf months remain", {
  panel <- .pm_panel(n_months = 3L)
  up <- pit_env$pit_max_portfolio(panel, "upper", .pm_params, .pm_rf())
  lo <- pit_env$pit_max_portfolio(panel, "lower", .pm_params, .pm_rf())
  expect_error(
    pit_env$pit_max_comparison(up, up, lo, panel, tibble::tibble(ym = up$ym, n_stocks = 50L)),
    "at least 24"
  )
  # 26 months, but 3 NA rf months leave 23 common: still an abort.
  panel <- .pm_panel(n_months = 26L)
  rf <- .pm_rf(30L)
  rf$rf_ret[c(5L, 6L, 7L)] <- NA_real_
  up <- pit_env$pit_max_portfolio(panel, "upper", .pm_params, rf)
  lo <- pit_env$pit_max_portfolio(panel, "lower", .pm_params, rf)
  expect_error(
    pit_env$pit_max_comparison(up, up, lo, panel, tibble::tibble(ym = up$ym, n_stocks = 50L)),
    "Only 23 months"
  )
})

test_that("pit_excluded_summary counts in-window securities and keeps the full count", {
  ex <- tibble::tibble(ticker = c("A", "B", "C", "D", "E"),
                       reason = c("no_bars", "no_bars", "no_bars", "failure_no_bars", "failure_no_bars"))
  out <- pit_env$pit_excluded_summary(ex, member_ids = c("A", "D", "Z"))
  expect_equal(out$reason, c("no_bars", "failure_no_bars"))   # tie: larger n_all first
  expect_equal(out$n_securities, c(1L, 1L))
  expect_equal(out$n_all, c(3L, 2L))
})

test_that("plan_pit_max defines the report targets and none feeds the leaderboard", {
  tg <- pit_env$plan_pit_max()
  nm <- vapply(tg, function(t) t$settings$name, character(1))
  expect_true(all(c("stk_member_bars_adj_file", "stk_member_bars_adj", "stk_pit_monthly",
                    "stk_pit_max_portfolio_upper", "stk_pit_max_portfolio_lower",
                    "stk_max_portfolio_biased_2016", "stk_pit_max_comparison") %in% nm))
  src <- paste(readLines(here::here("R/plan_pit_max.R")), collapse = "\n")
  code <- gsub("#[^\n]*", "", src)
  expect_false(grepl("register_runs|leaderboard", code))
  expect_equal(tg[[which(nm == "stk_member_bars_adj_file")]]$settings$format, "file")
})
