# Tests for #442 Tier 1 register_runs helpers
# (drif, fac_max, ltr, avoid_worst, rsc)
#
# Each test:
#   1. Builds minimal synthetic inputs matching the real target shapes.
#   2. Calls the helper against a tempfile() DuckDB (isolated, no shared state).
#   3. Reads back bt.strategy / bt.run / bt.metric rows.
#   4. Snapshots the tibble STRUCTURE (column names + types + row counts),
#      not the run_uuid (which is regenerated each invocation).
#
# Per snapshot-test-policy.md: snapshot schema/counts, not run_uuid.
testthat::local_edition(3)

# Load the historicaldata package (provides hd_registry_* helpers).
pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

# Source all five plan files so the .* helpers are accessible.
source(here::here("R/plan_strategy_names.R"))
source(here::here("R/plan_drif.R"))
source(here::here("R/plan_factormax.R"))
source(here::here("R/plan_ltr_momentum.R"))
source(here::here("R/plan_avoid_worst.R"))
source(here::here("R/plan_risk_state.R"))

# ── Shared: build a minimal strategy_names tibble ─────────────────────────────
# Pulls the exact same structure as the real target — avoids hardcoding
# any field that may drift.  We call plan_strategy_names() and extract the
# one tar_target body; but the safer approach in tests is to call the real
# target builder once via eval(body) — instead, we call the helper inline so
# the test is self-contained.

.make_strategy_names <- function() {
  tibble::tibble(
    code_name = c(
      "avoid_worst", "drif", "fac_max", "rsc", "ltr", "tom",
      "stk_max", "stk_drif", "xgb_drif", "pso_optimal",
      "cmr", "mom_prepeak", "mom_postpeak", "mom_combined"
    ),
    short_name = c(
      "Avoid Worst", "Factor DRIF", "Factor MAX", "Risk State", "LTR", "TOM",
      "Stock MAX", "Stock DRIF", "XGB DRIF", "PSO Optimal",
      "CMR", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2"
    ),
    long_name = c(
      "Avoid Worst Days (VIX Protection)",
      "Factor DRIF (Factor Rotation)",
      "Factor MAX (Factor Momentum)",
      "Risk State (VIX Overlay)",
      "LTR (Cross-Sectional Momentum)",
      "Turn-of-the-Month (TOM Overlay)",
      "Stock MAX (Daily Return Sorting)",
      "Stock DRIF (Elastic Net Stock Selection)",
      "XGB DRIF (XGBoost Stock Selection)",
      "PSO Optimal (Portfolio Optimisation)",
      "Commodities Mean Reversion",
      "Pre-Peak 12-2 Momentum (Büsing 2022)",
      "Post-Peak 12-2 Momentum (Büsing 2022)",
      "Standard 12-2 Momentum (Büsing baseline)"
    ),
    asset_class = c(
      "overlay", "factor", "factor", "overlay", "equity", "overlay",
      "equity", "equity", "equity", "combined",
      "commodities", "equity", "equity", "equity"
    ),
    frequency = c(
      "daily", "monthly", "monthly", "daily", "monthly", "daily",
      "monthly", "monthly", "monthly", "monthly",
      "monthly", "monthly", "monthly", "monthly"
    ),
    ann_factor = c(252L, 12L, 12L, 252L, 12L, 252L, 12L, 12L, 12L, 12L,
                   12L, 12L, 12L, 12L),
    vignette_url = c(
      "avoid-worst-days.html", "drif.html", "factor-max.html",
      "leaderboard.html", "leaderboard.html", "turn-of-month.html",
      "stock-backtest.html", "stock-backtest.html",
      "stock-backtest.html", "leaderboard.html",
      "commodities-mean-reversion.html",
      "momentum-prepeak.html", "momentum-prepeak.html", "momentum-prepeak.html"
    ),
    time_horizon_days_avg = c(
      1L,  21L, 21L, 1L,  252L, 1L,
      21L, 21L, 21L, 90L,
      21L, 21L, 21L, 21L
    ),
    trades_per_year_avg = c(
      12, 12, 12, 12, 12, 12,
      12, 12, 12,  4,
      12, 12, 12, 12
    ),
    liquidity_tier = factor(
      c("high", "high", "high", "high", "med", "high",
        "med",  "med",  "med",  "high",
        "med",  "med",  "med",  "med"),
      levels = c("high", "med", "low")
    ),
    turnover_pct_per_period_avg = c(
      50, 30, 30, 50, 20, 10,
      100, 100, 100, 10,
      100, 100, 100, 100
    ),
    directionality = factor(
      c("overlay",    "long_only",  "long_only",  "overlay",    "long_short", "overlay",
        "long_short", "long_short", "long_short", "long_only",
        "long_short", "long_short", "long_short", "long_short"),
      levels = c("long_only", "long_short", "market_neutral", "overlay")
    ),
    tags = c(
      '["vix","market_timing","overlay"]',
      '["factor_rotation","elastic_net","monthly"]',
      '["factor_rotation","monthly"]',
      '["vix","market_timing","overlay"]',
      '["momentum","cross_sectional","monthly"]',
      '["calendar","seasonal","overlay"]',
      '["momentum","cross_sectional","stock_level"]',
      '["elastic_net","ml","stock_level"]',
      '["xgboost","ml","stock_level","monotonic"]',
      '["portfolio","pso","optimisation","combined"]',
      '["mean_reversion","commodities"]',
      '["momentum","cross_sectional","decomposition","prepeak"]',
      '["momentum","cross_sectional","decomposition","postpeak"]',
      '["momentum","cross_sectional","baseline"]'
    ),
    research_paper_doi = c(
      NA_character_,
      "10.2139/ssrn.5520615",
      "10.2139/ssrn.5520615",
      NA_character_,
      "10.1016/0304-405X(93)90023-5",
      NA_character_,
      "10.2139/ssrn.5520615",
      "10.2139/ssrn.5520615",
      NA_character_,
      NA_character_,
      NA_character_,
      "10.2139/ssrn.4298538",
      "10.2139/ssrn.4298538",
      "10.2139/ssrn.4298538"
    )
  )
}

# ── Helper: open a fresh temp registry and return (tmp_path, con) ────────────
.tmp_registry <- function() {
  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  list(
    path = tmp,
    con  = hd_registry_open(tmp, read_only = FALSE)
  )
}

# ── Helper: query bt.strategy + bt.run + bt.metric for one strategy_id ──────
.query_registry <- function(con, sid) {
  strat <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT strategy_id, short_name, asset_class, frequency, lifecycle
       FROM bt.strategy WHERE strategy_id = '%s'",
      sid
    )
  )
  runs <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT strategy_id, partition, pipeline_version FROM bt.run
       WHERE strategy_id = '%s'",
      sid
    )
  )
  metrics <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT COUNT(*) AS n_rows FROM bt.metric m
       INNER JOIN bt.run r ON m.run_uuid = r.run_uuid
       WHERE r.strategy_id = '%s'",
      sid
    )
  )
  list(strat = strat, runs = runs, n_metric_rows = metrics$n_rows)
}

# ── Helper: build a mock strategy override (patches hd_registry_path) ────────
# Each test uses withr::local_envvar to redirect hd_registry_path() to tmp.
# hd_registry_path() uses Sys.getenv("HD_REGISTRY_PATH", here::here(...)).
# We override via HD_REGISTRY_PATH env var.


# ══════════════════════════════════════════════════════════════════════════════
# 1. drif_register_runs
# ══════════════════════════════════════════════════════════════════════════════

test_that(".drif_register_runs schema and row counts are stable", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp  <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  con  <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer({
    DBI::dbDisconnect(con, shutdown = TRUE)
    unlink(tmp)
  })

  strategy_names <- .make_strategy_names()

  drif_metrics <- tibble::tibble(
    period       = c("Training", "Testing", "Validation", "Full Period"),
    months       = c(60L, 24L, 12L, 96L),
    cagr         = c(0.08, 0.06, 0.07, 0.074),
    vol          = c(0.12, 0.11, 0.10, 0.115),
    sharpe       = c(0.65, 0.53, 0.70, 0.63),
    max_dd       = c(-0.15, -0.12, -0.10, -0.17),
    hit_rate     = c(0.54, 0.52, 0.55, 0.53),
    bench_cagr   = c(0.10, 0.09, 0.08, 0.095),
    bench_vol    = c(0.16, 0.15, 0.14, 0.155),
    bench_sharpe = c(0.60, 0.58, 0.56, 0.59)
  )

  drif_portfolio <- tibble::tibble(
    ym            = paste0("2020-", sprintf("%02d", 1:24)),
    date          = seq.Date(as.Date("2020-01-31"), by = "month", length.out = 24),
    portfolio_ret = rnorm(24, 0.005, 0.03),
    benchmark_ret = rnorm(24, 0.007, 0.04),
    rf_ret        = rep(0.001, 24)
  )

  # Override HD_REGISTRY_PATH so hd_registry_path() uses our temp DB
  withr::local_envvar(HD_REGISTRY_PATH = tmp)

  result <- .drif_register_runs(
    strategy_names = strategy_names,
    drif_metrics   = drif_metrics,
    drif_portfolio = drif_portfolio
  )

  # Snapshot the result tibble structure (cols + nrow)
  expect_snapshot({
    cat("result columns:", paste(names(result), collapse = ", "), "\n")
    cat("result nrow:   ", nrow(result), "\n")
    cat("strategy_id:   ", result$strategy_id, "\n")
  })

  q <- .query_registry(con, "drif")

  # bt.strategy: exactly 1 row
  expect_equal(nrow(q$strat), 1L)
  expect_equal(q$strat$strategy_id, "drif")
  expect_equal(q$strat$asset_class, "factor")
  expect_equal(q$strat$frequency, "monthly")
  expect_equal(q$strat$lifecycle, "stable")

  # bt.run: exactly 1 row
  expect_equal(nrow(q$runs), 1L)
  expect_equal(q$runs$partition, "phase1")

  # bt.metric: at least 1 row (full-period metrics + stability metrics)
  expect_gte(q$n_metric_rows, 1L)

  # Idempotency: second call should not duplicate bt.strategy
  .drif_register_runs(
    strategy_names = strategy_names,
    drif_metrics   = drif_metrics,
    drif_portfolio = drif_portfolio
  )
  n_strat <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) AS n FROM bt.strategy WHERE strategy_id = 'drif'"
  )$n
  expect_equal(n_strat, 1L)

  expect_snapshot({
    cat("bt.strategy cols:", paste(names(q$strat), collapse = ", "), "\n")
    cat("bt.run cols:     ", paste(names(q$runs), collapse = ", "), "\n")
    cat("n_metric_rows:   ", q$n_metric_rows, "\n")
  })
})


# ══════════════════════════════════════════════════════════════════════════════
# 2. fm_register_runs (fac_max)
# ══════════════════════════════════════════════════════════════════════════════

test_that(".fm_register_runs schema and row counts are stable", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer({
    DBI::dbDisconnect(con, shutdown = TRUE)
    unlink(tmp)
  })

  strategy_names <- .make_strategy_names()

  fm_metrics <- tibble::tibble(
    period       = c("Training", "Testing", "Validation", "Full Period"),
    months       = c(60L, 24L, 12L, 96L),
    cagr         = c(0.09, 0.07, 0.08, 0.082),
    vol          = c(0.13, 0.12, 0.11, 0.125),
    sharpe       = c(0.68, 0.57, 0.72, 0.64),
    max_dd       = c(-0.18, -0.14, -0.12, -0.20),
    hit_rate     = c(0.55, 0.53, 0.57, 0.54),
    bench_cagr   = c(0.10, 0.09, 0.08, 0.095),
    bench_vol    = c(0.16, 0.15, 0.14, 0.155),
    bench_sharpe = c(0.60, 0.58, 0.56, 0.59)
  )

  fm_portfolio <- tibble::tibble(
    ym            = paste0("2020-", sprintf("%02d", 1:24)),
    date          = seq.Date(as.Date("2020-01-31"), by = "month", length.out = 24),
    portfolio_ret = rnorm(24, 0.006, 0.035),
    benchmark_ret = rnorm(24, 0.007, 0.04),
    rf_ret        = rep(0.001, 24)
  )

  withr::local_envvar(HD_REGISTRY_PATH = tmp)

  result <- .fm_register_runs(
    strategy_names = strategy_names,
    fm_metrics     = fm_metrics,
    fm_portfolio   = fm_portfolio
  )

  expect_snapshot({
    cat("result columns:", paste(names(result), collapse = ", "), "\n")
    cat("result nrow:   ", nrow(result), "\n")
    cat("strategy_id:   ", result$strategy_id, "\n")
  })

  q <- .query_registry(con, "fac_max")

  expect_equal(nrow(q$strat), 1L)
  expect_equal(q$strat$strategy_id, "fac_max")
  expect_equal(q$strat$asset_class, "factor")
  expect_equal(q$strat$frequency, "monthly")
  expect_equal(q$strat$lifecycle, "stable")
  expect_equal(nrow(q$runs), 1L)
  expect_gte(q$n_metric_rows, 1L)

  expect_snapshot({
    cat("bt.strategy cols:", paste(names(q$strat), collapse = ", "), "\n")
    cat("bt.run cols:     ", paste(names(q$runs), collapse = ", "), "\n")
    cat("n_metric_rows:   ", q$n_metric_rows, "\n")
  })
})


# ══════════════════════════════════════════════════════════════════════════════
# 3. ltr_register_runs
# ══════════════════════════════════════════════════════════════════════════════

test_that(".ltr_register_runs schema and row counts are stable", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer({
    DBI::dbDisconnect(con, shutdown = TRUE)
    unlink(tmp)
  })

  strategy_names <- .make_strategy_names()

  ltr_metrics <- tibble::tibble(
    period     = c("Training", "Testing", "Validation", "Full Period"),
    months     = c(60L, 24L, 12L, 96L),
    cagr       = c(12.1, 9.5, 11.0, 11.3),
    vol        = c(14.2, 13.1, 12.5, 13.8),
    max_dd     = c(-18.5, -15.0, -12.0, -20.1),
    hac_sharpe = c(0.82, 0.71, 0.86, 0.79),
    hac_tstat  = c(3.2, 2.8, 3.4, 3.0),
    avg_long   = c(50L, 48L, 52L, 50L),
    avg_short  = c(50L, 48L, 52L, 50L)
  )

  ltr_portfolio <- tibble::tibble(
    date    = seq.Date(as.Date("2016-01-31"), by = "month", length.out = 96),
    port_ret = rnorm(96, 0.008, 0.04),
    n_long  = sample(45:55, 96, replace = TRUE),
    n_short = sample(45:55, 96, replace = TRUE),
    ls_ret_net = rnorm(96, 0.008, 0.04)
  )

  withr::local_envvar(HD_REGISTRY_PATH = tmp)

  result <- .ltr_register_runs(
    strategy_names = strategy_names,
    ltr_metrics    = ltr_metrics,
    ltr_portfolio  = ltr_portfolio
  )

  expect_snapshot({
    cat("result columns:", paste(names(result), collapse = ", "), "\n")
    cat("result nrow:   ", nrow(result), "\n")
    cat("strategy_id:   ", result$strategy_id, "\n")
  })

  q <- .query_registry(con, "ltr")

  expect_equal(nrow(q$strat), 1L)
  expect_equal(q$strat$strategy_id, "ltr")
  expect_equal(q$strat$asset_class, "equity")
  expect_equal(q$strat$frequency, "monthly")
  expect_equal(q$strat$lifecycle, "stable")
  expect_equal(nrow(q$runs), 1L)
  expect_gte(q$n_metric_rows, 1L)

  expect_snapshot({
    cat("bt.strategy cols:", paste(names(q$strat), collapse = ", "), "\n")
    cat("bt.run cols:     ", paste(names(q$runs), collapse = ", "), "\n")
    cat("n_metric_rows:   ", q$n_metric_rows, "\n")
  })
})


# ══════════════════════════════════════════════════════════════════════════════
# 4. avoid_worst_register_runs
# ══════════════════════════════════════════════════════════════════════════════

test_that(".avoid_worst_register_runs schema and row counts are stable", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer({
    DBI::dbDisconnect(con, shutdown = TRUE)
    unlink(tmp)
  })

  strategy_names <- .make_strategy_names()

  # aw_metrics has period + scenario columns
  aw_metrics <- tibble::tibble(
    period   = rep(c("Training", "Testing", "Full Period"), each = 3),
    scenario = rep(c("All Days", "Remove 10 Worst", "Remove 10 Best"), 3),
    years    = rep(c(5.0, 2.0, 7.0), each = 3),
    n_days   = as.integer(rep(c(1260, 504, 1764), each = 3)),
    cagr     = c(10.2, 12.0, 9.8, 8.5, 11.0, 8.0, 9.5, 11.5, 9.0),
    vol      = c(14.5, 12.1, 16.2, 13.0, 11.0, 14.5, 14.0, 11.8, 15.5),
    max_dd   = c(-22.0, -18.0, -25.0, -18.0, -15.0, -22.0, -20.0, -16.5, -23.0),
    sharpe   = c(0.68, 0.97, 0.58, 0.63, 0.97, 0.53, 0.66, 0.96, 0.56)
  )

  # aw_practical_backtest has ret_strategy column (daily)
  n_days <- 2520L
  aw_practical_backtest <- tibble::tibble(
    date         = seq.Date(as.Date("2010-01-04"), by = "day", length.out = n_days),
    ret_market   = rnorm(n_days, 0.0004, 0.01),
    ret_strategy = rnorm(n_days, 0.0003, 0.009),
    in_market    = sample(c(TRUE, FALSE), n_days, replace = TRUE, prob = c(0.85, 0.15)),
    vix          = runif(n_days, 12, 40),
    cum_market   = cumprod(1 + rnorm(n_days, 0.0004, 0.01)),
    cum_strategy = cumprod(1 + rnorm(n_days, 0.0003, 0.009))
  )

  withr::local_envvar(HD_REGISTRY_PATH = tmp)

  result <- .avoid_worst_register_runs(
    strategy_names        = strategy_names,
    aw_metrics            = aw_metrics,
    aw_practical_backtest = aw_practical_backtest
  )

  expect_snapshot({
    cat("result columns:", paste(names(result), collapse = ", "), "\n")
    cat("result nrow:   ", nrow(result), "\n")
    cat("strategy_id:   ", result$strategy_id, "\n")
  })

  q <- .query_registry(con, "avoid_worst")

  expect_equal(nrow(q$strat), 1L)
  expect_equal(q$strat$strategy_id, "avoid_worst")
  expect_equal(q$strat$asset_class, "overlay")
  expect_equal(q$strat$frequency, "daily")
  expect_equal(q$strat$lifecycle, "stable")
  expect_equal(nrow(q$runs), 1L)
  expect_gte(q$n_metric_rows, 1L)

  expect_snapshot({
    cat("bt.strategy cols:", paste(names(q$strat), collapse = ", "), "\n")
    cat("bt.run cols:     ", paste(names(q$runs), collapse = ", "), "\n")
    cat("n_metric_rows:   ", q$n_metric_rows, "\n")
  })
})


# ══════════════════════════════════════════════════════════════════════════════
# 5. rsc_register_runs
# ══════════════════════════════════════════════════════════════════════════════

test_that(".rsc_register_runs schema and row counts are stable", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer({
    DBI::dbDisconnect(con, shutdown = TRUE)
    unlink(tmp)
  })

  strategy_names <- .make_strategy_names()

  # rsc_metrics has strategy + period columns
  rsc_metrics <- tibble::tibble(
    strategy   = c("SPY_buyhold", "SPY_overlay",
                   "SPY_buyhold", "SPY_overlay",
                   "SPY_buyhold", "SPY_overlay",
                   "DRIF_raw", "DRIF_overlay",
                   "FacMAX_raw", "FacMAX_overlay"),
    period     = c("Full Period", "Full Period",
                   "Training", "Training",
                   "Testing", "Testing",
                   "Full Period", "Full Period",
                   "Full Period", "Full Period"),
    cagr       = c(10.5, 12.1, 9.8, 11.3, 11.2, 13.0, 8.5, 10.2, 9.1, 11.0),
    vol        = c(17.2, 14.5, 16.0, 13.2, 18.1, 15.0, 13.5, 11.8, 14.0, 12.3),
    max_dd     = c(-34.0, -25.0, -30.0, -22.0, -28.0, -21.0, -20.0, -18.0, -22.0, -19.0),
    hac_tstat  = c(2.1, 2.8, 1.9, 2.5, 2.3, 3.1, 2.0, 2.7, 2.1, 2.9),
    hac_sharpe = c(0.58, 0.82, 0.59, 0.83, 0.60, 0.85, 0.61, 0.84, 0.62, 0.87)
  )

  # rsc_portfolio has ret_strategy + ret_buyhold + regime columns
  n_days <- 3024L
  rsc_portfolio <- tibble::tibble(
    date         = seq.Date(as.Date("2009-01-01"), by = "day", length.out = n_days),
    ret_strategy = rnorm(n_days, 0.0003, 0.009),
    ret_buyhold  = rnorm(n_days, 0.0004, 0.011),
    regime       = sample(c("benign", "cautious", "hostile"), n_days,
                          replace = TRUE, prob = c(0.6, 0.25, 0.15)),
    cum_strategy = cumprod(1 + rnorm(n_days, 0.0003, 0.009)),
    cum_buyhold  = cumprod(1 + rnorm(n_days, 0.0004, 0.011))
  )

  withr::local_envvar(HD_REGISTRY_PATH = tmp)

  result <- .rsc_register_runs(
    strategy_names = strategy_names,
    rsc_metrics    = rsc_metrics,
    rsc_portfolio  = rsc_portfolio
  )

  expect_snapshot({
    cat("result columns:", paste(names(result), collapse = ", "), "\n")
    cat("result nrow:   ", nrow(result), "\n")
    cat("strategy_id:   ", result$strategy_id, "\n")
  })

  q <- .query_registry(con, "rsc")

  expect_equal(nrow(q$strat), 1L)
  expect_equal(q$strat$strategy_id, "rsc")
  expect_equal(q$strat$asset_class, "overlay")
  expect_equal(q$strat$frequency, "daily")
  expect_equal(q$strat$lifecycle, "stable")
  expect_equal(nrow(q$runs), 1L)
  expect_gte(q$n_metric_rows, 1L)

  expect_snapshot({
    cat("bt.strategy cols:", paste(names(q$strat), collapse = ", "), "\n")
    cat("bt.run cols:     ", paste(names(q$runs), collapse = ", "), "\n")
    cat("n_metric_rows:   ", q$n_metric_rows, "\n")
  })
})
