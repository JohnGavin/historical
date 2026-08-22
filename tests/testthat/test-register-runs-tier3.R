# Tests for #442 Tier 3 register_runs helpers
# (cmr — existing/verified, tom — new, pso_optimal — new)
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

# Source all three plan files so the .* helpers are accessible.
source(here::here("R/plan_strategy_names.R"))
source(here::here("R/plan_commodities_mean_reversion.R"))
source(here::here("R/plan_turn_of_month.R"))
source(here::here("R/plan_portfolio_opt.R"))

# ── Shared helpers ────────────────────────────────────────────────────────────
# Re-use the same .make_strategy_names() shape from test-register-runs-tier1.R.

.make_strategy_names_t3 <- function() {
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
      # #717: cmr (position 11) is daily, not monthly -- matches
      # R/plan_strategy_names.R's corrected declaration.
      "daily", "monthly", "monthly", "monthly"
    ),
    ann_factor = c(252L, 12L, 12L, 252L, 12L, 252L, 12L, 12L, 12L, 12L,
                   252L, 12L, 12L, 12L),
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

# ── Helper: query bt.strategy + bt.run + bt.metric for one strategy_id ──────
.query_registry_t3 <- function(con, sid) {
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


# ══════════════════════════════════════════════════════════════════════════════
# 1. cmr_register_runs — verify existing implementation
# ══════════════════════════════════════════════════════════════════════════════
# CMR was the first strategy registered (reference implementation from #347).
# This test verifies the existing .cmr_register_runs() still works correctly
# with the current pattern (three partitions: 1m, 3m, 6m; stability metrics #400).

test_that(".cmr_register_runs schema and row counts are stable", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer({
    DBI::dbDisconnect(con, shutdown = TRUE)
    unlink(tmp)
  })

  strategy_names <- .make_strategy_names_t3()

  # cmr_summary shape: lookback + metrics columns (decimal fractions per #336)
  # Column is n_days, not n_months (#717: CMR's underlying data is daily,
  # not monthly -- .compute_cmr_metrics() renamed the column at source).
  cmr_summary <- tibble::tibble(
    lookback        = c("1m", "3m", "6m"),
    n_days          = c(48L, 48L, 48L),
    sharpe          = c(-0.42, -0.31, -0.25),
    cagr            = c(-0.04, -0.03, -0.02),
    vol             = c(0.18, 0.17, 0.16),
    max_dd          = c(-0.28, -0.25, -0.22),
    avg_dd_duration = c(3.2, 2.8, 2.5),
    max_dd_duration = c(12L, 10L, 9L)
  )

  # portfolio_list: one tibble per lookback with net_ret column.
  # #717: n = 300 daily obs (not 48 monthly) -- .cmr_register_runs() now
  # calls hd_record_stability_metrics(w = 252L, ann_factor = 252L), so the
  # fixture needs >= 252 rows for a complete rolling window; a shorter
  # series produces 0 windows, which drops the NA-valued ssr/ssr_mean_sharpe/
  # ssr_se/ssr_lag_nw rows in hd_metric_record() and desyncs the
  # n_metric_rows snapshot below (< 8 stability rows instead of 8).
  n_days <- 300L
  make_port <- function() {
    tibble::tibble(
      date    = seq.Date(as.Date("2018-01-02"), by = "day", length.out = n_days),
      net_ret = rnorm(n_days, -0.0002, 0.01)
    )
  }

  withr::local_envvar(HD_REGISTRY_PATH = tmp)

  result <- .cmr_register_runs(
    strategy_names = strategy_names,
    cmr_summary    = cmr_summary,
    portfolio_list = list(
      `1m` = make_port(),
      `3m` = make_port(),
      `6m` = make_port()
    )
  )

  expect_snapshot({
    cat("result columns:", paste(names(result), collapse = ", "), "\n")
    cat("result nrow:   ", nrow(result), "\n")
    cat("partitions:    ", paste(sort(result$partition), collapse = ", "), "\n")
  })

  q <- .query_registry_t3(con, "cmr")

  # bt.strategy: exactly 1 row
  expect_equal(nrow(q$strat), 1L)
  expect_equal(q$strat$strategy_id, "cmr")
  expect_equal(q$strat$asset_class, "commodities")
  expect_equal(q$strat$frequency, "daily")  # #717
  expect_equal(q$strat$lifecycle, "stable")

  # bt.run: one row per partition (1m, 3m, 6m)
  expect_equal(nrow(q$runs), 3L)
  expect_setequal(q$runs$partition, c("1m", "3m", "6m"))

  # bt.metric: at least 3 rows (at least one per partition)
  expect_gte(q$n_metric_rows, 3L)

  # Idempotency: second call should not duplicate bt.strategy
  .cmr_register_runs(
    strategy_names = strategy_names,
    cmr_summary    = cmr_summary,
    portfolio_list = list(
      `1m` = make_port(),
      `3m` = make_port(),
      `6m` = make_port()
    )
  )
  n_strat <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) AS n FROM bt.strategy WHERE strategy_id = 'cmr'"
  )$n
  expect_equal(n_strat, 1L)

  expect_snapshot({
    cat("bt.strategy cols:", paste(names(q$strat), collapse = ", "), "\n")
    cat("bt.run cols:     ", paste(names(q$runs), collapse = ", "), "\n")
    cat("n_metric_rows:   ", q$n_metric_rows, "\n")
  })
})


# ══════════════════════════════════════════════════════════════════════════════
# 2. tom_register_runs — new in Tier 3
# ══════════════════════════════════════════════════════════════════════════════
# TOM is daily (ann_factor=252). tom_metrics stores cagr/vol/max_dd in
# percentage units (× 100) per plan_turn_of_month.R's internal convention.
# Stability metrics use w=252L, ann_factor=252L.

test_that(".tom_register_runs schema and row counts are stable", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer({
    DBI::dbDisconnect(con, shutdown = TRUE)
    unlink(tmp)
  })

  strategy_names <- .make_strategy_names_t3()

  # tom_metrics shape: percentage units for cagr/vol/max_dd (matching real target)
  tom_metrics <- tibble::tibble(
    period       = c("Training", "Testing", "Full Period"),
    n_days       = c(3024L, 1512L, 7560L),
    years        = c(12.0, 6.0, 30.0),
    cagr_tom     = c(10.2, 8.5, 9.8),    # percentage
    vol_tom      = c(9.1, 8.8, 9.0),     # percentage
    sharpe_tom   = c(1.12, 0.96, 1.08),
    max_dd_tom   = c(-18.5, -15.2, -22.0),  # percentage (negative)
    cagr_bh      = c(9.1, 7.2, 8.6),     # percentage
    vol_bh       = c(17.2, 16.0, 17.0),  # percentage
    sharpe_bh    = c(0.52, 0.44, 0.49),
    max_dd_bh    = c(-55.2, -34.0, -55.2),  # percentage (negative)
    n_tom_days   = c(1134L, 567L, 2835L),
    pct_in_tom   = c(37.5, 37.5, 37.5)
  )

  # tom_portfolio shape: ret_net column (daily returns)
  n_days <- 7560L
  tom_portfolio <- tibble::tibble(
    date         = seq.Date(as.Date("1994-01-03"), by = "day", length.out = n_days),
    ret          = rnorm(n_days, 0.0004, 0.01),
    yr_mon       = format(seq.Date(as.Date("1994-01-03"), by = "day", length.out = n_days), "%Y-%m"),
    rank_start   = 1L,
    rank_end     = 1L,
    in_tail      = FALSE,
    in_head      = FALSE,
    in_tom       = sample(c(TRUE, FALSE), n_days, replace = TRUE, prob = c(0.38, 0.62)),
    prev_in_tom  = FALSE,
    is_switch    = FALSE,
    ret_gross    = rnorm(n_days, 0.0004, 0.01),
    cost_daily   = 0,
    ret_net      = rnorm(n_days, 0.0003, 0.009),
    cum_bh       = cumprod(1 + rnorm(n_days, 0.0004, 0.01)),
    cum_strategy = cumprod(1 + rnorm(n_days, 0.0003, 0.009))
  )

  withr::local_envvar(HD_REGISTRY_PATH = tmp)

  result <- .tom_register_runs(
    strategy_names = strategy_names,
    tom_metrics    = tom_metrics,
    tom_portfolio  = tom_portfolio
  )

  expect_snapshot({
    cat("result columns:", paste(names(result), collapse = ", "), "\n")
    cat("result nrow:   ", nrow(result), "\n")
    cat("strategy_id:   ", result$strategy_id, "\n")
  })

  q <- .query_registry_t3(con, "tom")

  # bt.strategy: exactly 1 row
  expect_equal(nrow(q$strat), 1L)
  expect_equal(q$strat$strategy_id, "tom")
  expect_equal(q$strat$asset_class, "overlay")
  expect_equal(q$strat$frequency, "daily")
  expect_equal(q$strat$lifecycle, "stable")

  # bt.run: exactly 1 row (single "phase1" partition)
  expect_equal(nrow(q$runs), 1L)
  expect_equal(q$runs$partition, "phase1")

  # bt.metric: at least 1 row (full-period metrics + stability metrics)
  expect_gte(q$n_metric_rows, 1L)

  # Idempotency: second call should not duplicate bt.strategy
  .tom_register_runs(
    strategy_names = strategy_names,
    tom_metrics    = tom_metrics,
    tom_portfolio  = tom_portfolio
  )
  n_strat <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) AS n FROM bt.strategy WHERE strategy_id = 'tom'"
  )$n
  expect_equal(n_strat, 1L)

  expect_snapshot({
    cat("bt.strategy cols:", paste(names(q$strat), collapse = ", "), "\n")
    cat("bt.run cols:     ", paste(names(q$runs), collapse = ", "), "\n")
    cat("n_metric_rows:   ", q$n_metric_rows, "\n")
  })
})


# ══════════════════════════════════════════════════════════════════════════════
# 3. pso_optimal_register_runs — new in Tier 3
# ══════════════════════════════════════════════════════════════════════════════
# PSO Optimal is monthly (ann_factor=12). port_metrics stores opt_cagr/vol/maxdd
# as decimal fractions (canonical convention). Stability metrics use w=36L,
# ann_factor=12L. Only PSO columns are registered; HRP/equal-weight are excluded.

test_that(".pso_optimal_register_runs schema and row counts are stable", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer({
    DBI::dbDisconnect(con, shutdown = TRUE)
    unlink(tmp)
  })

  strategy_names <- .make_strategy_names_t3()

  # port_metrics shape: matches plan_portfolio_opt.R calc_port_metrics() output.
  # Decimal fractions for all return/vol/dd columns.
  port_metrics <- tibble::tibble(
    period     = c("Training", "Testing", "Validation", "Full Period"),
    months     = c(60L, 24L, 12L, 96L),
    opt_cagr   = c(0.109, 0.085, 0.097, 0.102),
    opt_vol    = c(0.140, 0.128, 0.135, 0.138),
    opt_sharpe = c(0.76, 0.65, 0.71, 0.73),
    opt_maxdd  = c(-0.22, -0.18, -0.16, -0.24),
    hrp_cagr   = c(0.101, 0.078, 0.089, 0.095),
    hrp_sharpe = c(0.70, 0.59, 0.65, 0.68),
    hrp_maxdd  = c(-0.24, -0.20, -0.17, -0.26),
    eq_cagr    = c(0.098, 0.076, 0.086, 0.092),
    eq_sharpe  = c(0.68, 0.57, 0.63, 0.66),
    eq_maxdd   = c(-0.25, -0.21, -0.18, -0.27)
  )

  # port_combined shape: must have optimal_ret column (monthly returns)
  n_months <- 96L
  port_combined <- tibble::tibble(
    ym          = paste0(rep(2015:2022, each = 12), "-", sprintf("%02d", 1:12))[seq_len(n_months)],
    date        = seq.Date(as.Date("2015-01-31"), by = "month", length.out = n_months),
    stk_max     = rnorm(n_months, 0.006, 0.04),
    stk_drif    = rnorm(n_months, 0.007, 0.038),
    fac_max     = rnorm(n_months, 0.005, 0.035),
    fac_drif    = rnorm(n_months, 0.006, 0.033),
    rf_ret      = rep(0.001, n_months),
    optimal_ret = rnorm(n_months, 0.008, 0.036),
    hrp_ret     = rnorm(n_months, 0.007, 0.037),
    equalwt_ret = rnorm(n_months, 0.006, 0.038),
    optimal_cum = cumprod(1 + rnorm(n_months, 0.008, 0.036)),
    hrp_cum     = cumprod(1 + rnorm(n_months, 0.007, 0.037)),
    equalwt_cum = cumprod(1 + rnorm(n_months, 0.006, 0.038))
  )

  withr::local_envvar(HD_REGISTRY_PATH = tmp)

  result <- .pso_optimal_register_runs(
    strategy_names = strategy_names,
    port_metrics   = port_metrics,
    port_combined  = port_combined
  )

  expect_snapshot({
    cat("result columns:", paste(names(result), collapse = ", "), "\n")
    cat("result nrow:   ", nrow(result), "\n")
    cat("strategy_id:   ", result$strategy_id, "\n")
  })

  q <- .query_registry_t3(con, "pso_optimal")

  # bt.strategy: exactly 1 row
  expect_equal(nrow(q$strat), 1L)
  expect_equal(q$strat$strategy_id, "pso_optimal")
  expect_equal(q$strat$asset_class, "combined")
  expect_equal(q$strat$frequency, "monthly")
  expect_equal(q$strat$lifecycle, "stable")

  # bt.run: exactly 1 row (single "phase1" partition)
  expect_equal(nrow(q$runs), 1L)
  expect_equal(q$runs$partition, "phase1")

  # bt.metric: at least 1 row (full-period PSO metrics + stability metrics)
  expect_gte(q$n_metric_rows, 1L)

  # Idempotency: second call should not duplicate bt.strategy
  .pso_optimal_register_runs(
    strategy_names = strategy_names,
    port_metrics   = port_metrics,
    port_combined  = port_combined
  )
  n_strat <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) AS n FROM bt.strategy WHERE strategy_id = 'pso_optimal'"
  )$n
  expect_equal(n_strat, 1L)

  expect_snapshot({
    cat("bt.strategy cols:", paste(names(q$strat), collapse = ", "), "\n")
    cat("bt.run cols:     ", paste(names(q$runs), collapse = ", "), "\n")
    cat("n_metric_rows:   ", q$n_metric_rows, "\n")
  })
})
