# Tests for S42 -- leaderboard strategy source traceability (Refs #813)
#
# #813 fixed the bt.* registry writer (.avoid_worst_register_runs()) to
# source Avoid Worst's cagr/sharpe from aw_practical_backtest$ret_strategy
# (the VIX-triggered protection strategy's OWN returns), never from
# aw_metrics' "Full Period"/"All Days" row (plain SPY buy-and-hold). The
# LEADERBOARD assembly (R/plan_leaderboard.R) was not touched by #813 and
# kept reading aw_metrics' "Remove 10 Worst" scenario -- this is exactly
# the defect S42 exists to catch, and to prevent from silently recurring.
testthat::local_edition(3)

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_avoid_worst.R"))
source(here::here("R/plan_qa_gates.R"))

make_dates <- function(n, start = "2015-01-02") {
  seq.Date(as.Date(start), by = "day", length.out = n)
}

# ── Fixture builder ─────────────────────────────────────────────────────────
# Builds aw_practical_backtest / aw_daily_rf / aw_metrics with DELIBERATELY
# divergent series (the VIX-timed strategy vs. plain SPY buy-and-hold), so a
# wrong-wiring bug cannot pass by coincidental numerical closeness. Also
# builds a `leaderboard` tibble whose Avoid Worst Full Period row can be
# pointed at EITHER series, so both the correct wiring (PASS) and the #813
# bug's wiring (FAIL) can be exercised against the SAME underlying data.
.make_s42_fixture <- function(seed = 813, n = 1260L) {
  set.seed(seed)
  dts <- make_dates(n)

  # The VIX-timed protection strategy's own returns.
  ret_strategy <- rnorm(n, mean = -0.0006, sd = 0.006)
  # Plain SPY buy-and-hold -- deliberately divergent mean/vol.
  ret_market   <- rnorm(n, mean =  0.0012, sd = 0.010)

  aw_practical_backtest <- tibble::tibble(
    date         = dts,
    ret_market   = ret_market,
    ret_strategy = ret_strategy,
    in_market    = TRUE,
    vix          = runif(n, 12, 40),
    cum_market   = cumprod(1 + ret_market),
    cum_strategy = cumprod(1 + ret_strategy)
  )
  aw_daily_rf <- tibble::tibble(date = dts, rf_ret = rep(0, n))

  # aw_metrics: minimal "Remove 10 Worst" / Full Period decoy row, built
  # from the buy-and-hold series the same way R/plan_avoid_worst.R's
  # aw_metrics target's calc()/metrics_for() does (10-worst-day removal,
  # scenario x period columns, PERCENT convention).
  ord <- order(ret_market)
  worst_10 <- ord[seq_len(10)]
  r_decoy  <- ret_market[-worst_10]
  years_decoy <- length(r_decoy) / 252
  cum_decoy   <- cumprod(1 + r_decoy)
  sr_decoy    <- .aw_sharpe_rf_full(dts[-worst_10], r_decoy, aw_daily_rf, ann_factor = 252L)

  aw_metrics <- tibble::tibble(
    strategy = "SPY",
    period   = "Full Period",
    scenario = "Remove 10 Worst",
    years    = round(years_decoy, 1),
    n_days   = length(r_decoy),
    cagr     = round((cum_decoy[length(cum_decoy)]^(1 / years_decoy) - 1) * 100, 1),
    vol      = round(sd(r_decoy) * sqrt(252) * 100, 1),
    max_dd   = round(min((cum_decoy - cummax(cum_decoy)) / cummax(cum_decoy)) * 100, 1),
    sharpe   = round(sr_decoy$sharpe, 2),
    ann_rf   = round(sr_decoy$ann_rf * 100, 2)
  )

  # The correct, canonical recomputation from the strategy's own series --
  # what a correctly-wired leaderboard row must match.
  correct <- .aw_strategy_period_metrics(dts, ret_strategy, aw_daily_rf, "Full Period")

  list(
    aw_practical_backtest = aw_practical_backtest,
    aw_daily_rf            = aw_daily_rf,
    aw_metrics             = aw_metrics,
    correct                = correct
  )
}

.make_leaderboard_row <- function(sharpe, cagr) {
  tibble::tibble(strategy = "Avoid Worst", period = "Full Period",
                 sharpe = sharpe, cagr = cagr)
}

test_that("build_leaderboard_traceability_table: PASS when the leaderboard row matches the strategy's own return series", {
  fx <- .make_s42_fixture()
  leaderboard <- .make_leaderboard_row(
    sharpe = fx$correct$sharpe,
    cagr   = fx$correct$cagr / 100  # leaderboard stores cagr as a FRACTION
  )

  tbl <- build_leaderboard_traceability_table(
    leaderboard, fx$aw_practical_backtest, fx$aw_daily_rf, fx$aw_metrics
  )

  expect_true(all(tbl$verdict == "PASS"))
  expect_true(all(!tbl$matches_decoy))
})

test_that("build_leaderboard_traceability_table: FAIL when the leaderboard row matches the aw_metrics decoy instead (#813 regression)", {
  fx <- .make_s42_fixture()
  # This is the #813 bug: the leaderboard row equals aw_metrics' "Remove 10
  # Worst" scenario, not aw_practical_backtest's own strategy metrics.
  leaderboard <- .make_leaderboard_row(
    sharpe = fx$aw_metrics$sharpe,
    cagr   = fx$aw_metrics$cagr / 100
  )

  tbl <- build_leaderboard_traceability_table(
    leaderboard, fx$aw_practical_backtest, fx$aw_daily_rf, fx$aw_metrics
  )

  expect_true(all(tbl$verdict == "FAIL"))
  expect_true(all(tbl$matches_decoy))
})

test_that("check_leaderboard_strategy_traceability: passes silently on a PASS verdict table", {
  fx <- .make_s42_fixture()
  leaderboard <- .make_leaderboard_row(
    sharpe = fx$correct$sharpe,
    cagr   = fx$correct$cagr / 100
  )
  tbl <- build_leaderboard_traceability_table(
    leaderboard, fx$aw_practical_backtest, fx$aw_daily_rf, fx$aw_metrics
  )

  expect_silent(check_leaderboard_strategy_traceability(tbl))
})

test_that("check_leaderboard_strategy_traceability: aborts, naming the decoy match, on the #813 wiring", {
  fx <- .make_s42_fixture()
  leaderboard <- .make_leaderboard_row(
    sharpe = fx$aw_metrics$sharpe,
    cagr   = fx$aw_metrics$cagr / 100
  )
  tbl <- build_leaderboard_traceability_table(
    leaderboard, fx$aw_practical_backtest, fx$aw_daily_rf, fx$aw_metrics
  )

  expect_snapshot(error = TRUE, check_leaderboard_strategy_traceability(tbl))
})

test_that("check_leaderboard_strategy_traceability: aborts on a table missing required columns", {
  expect_snapshot(error = TRUE,
    check_leaderboard_strategy_traceability(tibble::tibble(strategy = "x"))
  )
})

test_that("build_leaderboard_traceability_table: aborts when the leaderboard has no matching Avoid Worst / Full Period row", {
  fx <- .make_s42_fixture()
  leaderboard <- tibble::tibble(strategy = "Avoid Worst", period = "Training",
                                 sharpe = 0.3, cagr = 0.05)

  expect_snapshot(error = TRUE,
    build_leaderboard_traceability_table(
      leaderboard, fx$aw_practical_backtest, fx$aw_daily_rf, fx$aw_metrics
    )
  )
})

# ── Regression: literal curly braces in a strategy/metric label must not
# break cli formatting (same defect class as S41's #910/#917 CMR fix). ──

test_that("check_leaderboard_strategy_traceability: a strategy label containing literal curly braces does not break the abort message", {
  tbl <- tibble::tibble(
    strategy = "Avoid Worst {x,y}", metric = "sharpe",
    published = 0.5, recomputed = 0.9, decoy = 0.5, verdict = "FAIL"
  )
  err <- testthat::capture_error(check_leaderboard_strategy_traceability(tbl))
  expect_match(conditionMessage(err), "Avoid Worst {x,y}", fixed = TRUE)
})

test_that("build_leaderboard_traceability_table: aborts when aw_metrics has no matching decoy row", {
  fx <- .make_s42_fixture()
  leaderboard <- .make_leaderboard_row(sharpe = fx$correct$sharpe, cagr = fx$correct$cagr / 100)
  bad_aw_metrics <- fx$aw_metrics[fx$aw_metrics$scenario != "Remove 10 Worst", , drop = FALSE]

  expect_snapshot(error = TRUE,
    build_leaderboard_traceability_table(
      leaderboard, fx$aw_practical_backtest, fx$aw_daily_rf, bad_aw_metrics
    )
  )
})
