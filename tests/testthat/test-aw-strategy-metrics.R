# Tests for .aw_strategy_period_metrics() and the aw_strategy_metrics
# target's period-slicing logic (R/plan_avoid_worst.R, #813 follow-up).
#
# #813 fixed .avoid_worst_register_runs() (the bt.* registry writer) to
# source cagr/sharpe from aw_practical_backtest's ret_strategy column (the
# VIX-triggered protection strategy's OWN returns) instead of aw_metrics'
# "Full Period" / "All Days" row (plain SPY buy-and-hold). This follow-up
# fixes the LEADERBOARD assembly (R/plan_leaderboard.R's .norm_aw()), which
# #813 itself did not touch -- the leaderboard's Avoid Worst rows still
# matched aw_metrics' "Remove 10 Worst" scenario. .aw_strategy_period_
# metrics() is the shared helper both surfaces now call, so they can never
# independently drift apart again.
testthat::local_edition(3)

pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_avoid_worst.R"))

make_dates <- function(n, start = "2015-01-02") {
  seq.Date(as.Date(start), by = "day", length.out = n)
}

make_daily_rf <- function(dts, rf_ret = 0.00005) {
  tibble::tibble(date = dts, rf_ret = rep(rf_ret, length(dts)))
}

test_that(".aw_strategy_period_metrics returns NULL below the 20-observation floor", {
  dts <- make_dates(10)
  ret <- rep(0.001, 10)
  rf  <- make_daily_rf(dts)

  expect_null(.aw_strategy_period_metrics(dts, ret, rf, "Full Period"))
})

test_that(".aw_strategy_period_metrics computes cagr/vol/sharpe from the return series it is given, not any other series", {
  set.seed(813)
  n   <- 1260L  # 5 years
  dts <- make_dates(n)
  ret <- rnorm(n, mean = 0.0003, sd = 0.009)
  rf  <- make_daily_rf(dts)

  result <- .aw_strategy_period_metrics(dts, ret, rf, "Full Period")

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 1L)
  expect_equal(result$period, "Full Period")
  expect_equal(result$n_days, n)

  years <- n / 252
  cum <- cumprod(1 + ret)
  expect_equal(result$cagr, round((cum[n]^(1 / years) - 1) * 100, 1))
  expect_equal(result$vol, round(sd(ret) * sqrt(252) * 100, 1))
  expect_equal(result$window_start, min(dts))
  expect_equal(result$window_end, max(dts))

  sr <- .aw_sharpe_rf_full(dts, ret, rf, ann_factor = 252L)
  expect_equal(result$sharpe, round(sr$sharpe, 2))
  expect_equal(result$ann_rf, round(sr$ann_rf * 100, 2))

  # Schema/value snapshot (snapshot-test-policy.md): catches column-order,
  # column-name, or rounding drift that the targeted expect_equal()s above
  # would not necessarily flag if they drifted together.
  expect_snapshot_value(as.list(result), style = "deparse")
})

test_that(".aw_strategy_period_metrics on ret_strategy differs from the same calculation on a divergent ret_market series (#813 regression)", {
  # Mirrors test-register-runs-tier1.R's #813 regression test: deliberately
  # divergent means so a wrong-series bug is impossible to miss by chance.
  set.seed(8130)
  n   <- 1260L
  dts <- make_dates(n)
  ret_strategy <- rnorm(n, mean = -0.0006, sd = 0.006)
  ret_market   <- rnorm(n, mean =  0.0012, sd = 0.010)
  rf <- make_daily_rf(dts, rf_ret = 0)

  strategy_row <- .aw_strategy_period_metrics(dts, ret_strategy, rf, "Full Period")
  market_row   <- .aw_strategy_period_metrics(dts, ret_market, rf, "Full Period")

  expect_gt(abs(strategy_row$cagr - market_row$cagr), 10)
  expect_false(isTRUE(all.equal(strategy_row$sharpe, market_row$sharpe)))

  expect_snapshot({
    cat("strategy_row: cagr=", strategy_row$cagr, " sharpe=", strategy_row$sharpe, "\n")
    cat("market_row:   cagr=", market_row$cagr,   " sharpe=", market_row$sharpe,   "\n")
  })
})

test_that(".avoid_worst_register_runs' Full Period row matches .aw_strategy_period_metrics() called directly (shared-helper, no duplication)", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  source(here::here("R/plan_strategy_names.R"))

  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer({
    DBI::dbDisconnect(con, shutdown = TRUE)
    unlink(tmp)
  })

  strategy_names <- hd_strategy_names_tbl()

  set.seed(9001)
  n_days <- 2000L
  dates  <- make_dates(n_days, start = "2010-01-04")
  aw_practical_backtest <- tibble::tibble(
    date         = dates,
    ret_market   = rnorm(n_days, 0.0004, 0.01),
    ret_strategy = rnorm(n_days, 0.0003, 0.009),
    in_market    = TRUE,
    vix          = runif(n_days, 12, 40),
    cum_market   = cumprod(1 + rnorm(n_days, 0.0004, 0.01)),
    cum_strategy = cumprod(1 + rnorm(n_days, 0.0003, 0.009))
  )
  aw_daily_rf <- make_daily_rf(dates)

  withr::local_envvar(HD_REGISTRY_PATH = tmp)

  .avoid_worst_register_runs(
    strategy_names        = strategy_names,
    aw_practical_backtest = aw_practical_backtest,
    aw_daily_rf           = aw_daily_rf
  )

  registered_cagr   <- DBI::dbGetQuery(
    con,
    "SELECT m.metric_value FROM bt.metric m
     INNER JOIN bt.run r ON m.run_uuid = r.run_uuid
     WHERE r.strategy_id = 'avoid_worst' AND m.metric_name = 'cagr'"
  )$metric_value
  registered_sharpe <- DBI::dbGetQuery(
    con,
    "SELECT m.metric_value FROM bt.metric m
     INNER JOIN bt.run r ON m.run_uuid = r.run_uuid
     WHERE r.strategy_id = 'avoid_worst' AND m.metric_name = 'sharpe'"
  )$metric_value

  # Recompute independently via the shared helper -- same inputs, same
  # function the registry writer now delegates to internally.
  keep <- !is.na(aw_practical_backtest$ret_strategy)
  expected <- .aw_strategy_period_metrics(
    as.Date(aw_practical_backtest$date[keep]),
    aw_practical_backtest$ret_strategy[keep],
    aw_daily_rf, "Full Period"
  )

  expect_equal(registered_cagr, expected$cagr)
  expect_equal(registered_sharpe, expected$sharpe)
})
