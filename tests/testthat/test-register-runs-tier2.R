# Tests for #442 Tier 2 register_runs helpers
# (stk_max, stk_drif, xgb_drif)
#
# Each test:
#   1. Builds minimal synthetic inputs matching the real target shapes.
#   2. Calls the helper against a tempfile() DuckDB (isolated, no shared state).
#   3. Reads back bt.strategy / bt.run / bt.metric / bt.diagnostic rows.
#   4. Snapshots the tibble STRUCTURE (column names + types + row counts),
#      not the run_uuid (which is regenerated each invocation).
#
# Per snapshot-test-policy.md: snapshot schema/counts, not run_uuid.
testthat::local_edition(3)

# Load the historicaldata package (provides hd_registry_* helpers).
pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

# Source the required plan files so the .* helpers are accessible.
source(here::here("R/plan_strategy_names.R"))
source(here::here("R/plan_stock_backtest.R"))
source(here::here("R/plan_xgb_signal.R"))

# ── Shared: build a minimal strategy_names tibble ─────────────────────────────
# Reuses .make_strategy_names() from tier1 test if sourced; else define inline.
# We define it here to be self-contained.
if (!exists(".make_strategy_names")) {
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
}

# ── Helper: build synthetic stock metrics tibble ─────────────────────────────
# Matches calc_backtest_metrics() shape + survivorship_biased (logical) added
# via mutate in the real targets.
.make_stk_metrics <- function() {
  tibble::tibble(
    period             = c("Training", "Testing", "Validation", "Full Period"),
    months             = c(60L, 24L, 12L, 96L),
    cagr               = c(-0.05, -0.08, -0.03, -0.06),
    vol                = c(0.18, 0.17, 0.16, 0.175),
    sharpe             = c(-0.28, -0.47, -0.19, -0.34),
    max_dd             = c(-0.45, -0.52, -0.38, -0.55),
    avg_long           = c(13.0, 12.5, 13.2, 12.9),
    avg_short          = c(13.0, 12.5, 13.2, 12.9),
    survivorship_biased = TRUE   # logical; silently skipped by hd_metric_record
  )
}

# ── Helper: build synthetic stock portfolio tibble ───────────────────────────
# Matches the shape produced by portfolio_longshort() + left_join(stk_rf) +
# mutate(date, port_cum, long_cum).
.make_stk_portfolio <- function(n = 24L) {
  tibble::tibble(
    ym       = paste0("2020-", sprintf("%02d", seq_len(n))),
    date     = seq.Date(as.Date("2020-01-15"), by = "month", length.out = n),
    port_ret = rnorm(n, -0.004, 0.05),
    long_ret = rnorm(n,  0.003, 0.04),
    short_ret = rnorm(n, 0.007, 0.04),
    n_long   = sample(10L:16L, n, replace = TRUE),
    n_short  = sample(10L:16L, n, replace = TRUE),
    rf_ret   = rep(0.001, n),
    port_cum = cumprod(1 + rnorm(n, -0.004, 0.05)),
    long_cum = cumprod(1 + rnorm(n,  0.003, 0.04))
  )
}

# ── Helper: query bt.strategy + bt.run + bt.metric + bt.diagnostic ───────────
.query_registry_t2 <- function(con, sid) {
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
  diagnostics <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT d.diagnostic_name, d.value_num FROM bt.diagnostic d
       INNER JOIN bt.run r ON d.run_uuid = r.run_uuid
       WHERE r.strategy_id = '%s' AND d.diagnostic_name = 'survivorship_biased'",
      sid
    )
  )
  list(
    strat        = strat,
    runs         = runs,
    n_metric_rows = metrics$n_rows,
    diagnostics  = diagnostics
  )
}


# ══════════════════════════════════════════════════════════════════════════════
# 1. stk_max_register_runs
# ══════════════════════════════════════════════════════════════════════════════

test_that(".stk_register_runs (stk_max) schema and row counts are stable", {
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
  stk_max_metrics   <- .make_stk_metrics()
  stk_max_portfolio <- .make_stk_portfolio()

  withr::local_envvar(HD_REGISTRY_PATH = tmp)

  result <- .stk_register_runs(
    strategy_names = strategy_names,
    code_name      = "stk_max",
    metrics        = stk_max_metrics,
    portfolio      = stk_max_portfolio
  )

  # Snapshot the result tibble structure (cols + nrow)
  expect_snapshot({
    cat("result columns:", paste(names(result), collapse = ", "), "\n")
    cat("result nrow:   ", nrow(result), "\n")
    cat("strategy_id:   ", result$strategy_id, "\n")
  })

  q <- .query_registry_t2(con, "stk_max")

  # bt.strategy: exactly 1 row with correct metadata
  expect_equal(nrow(q$strat), 1L)
  expect_equal(q$strat$strategy_id, "stk_max")
  expect_equal(q$strat$asset_class, "equity")
  expect_equal(q$strat$frequency, "monthly")
  expect_equal(q$strat$lifecycle, "stable")

  # bt.run: exactly 1 row
  expect_equal(nrow(q$runs), 1L)
  expect_equal(q$runs$partition, "phase1")

  # bt.metric: at least 1 row (full-period metrics + stability metrics)
  expect_gte(q$n_metric_rows, 1L)

  # bt.diagnostic: survivorship_biased row present with value_num = 1
  expect_equal(nrow(q$diagnostics), 1L)
  expect_equal(q$diagnostics$diagnostic_name, "survivorship_biased")
  expect_equal(q$diagnostics$value_num, 1)

  # Idempotency: second call should not duplicate bt.strategy
  .stk_register_runs(
    strategy_names = strategy_names,
    code_name      = "stk_max",
    metrics        = stk_max_metrics,
    portfolio      = stk_max_portfolio
  )
  n_strat <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) AS n FROM bt.strategy WHERE strategy_id = 'stk_max'"
  )$n
  expect_equal(n_strat, 1L)

  expect_snapshot({
    cat("bt.strategy cols:", paste(names(q$strat), collapse = ", "), "\n")
    cat("bt.run cols:     ", paste(names(q$runs), collapse = ", "), "\n")
    cat("n_metric_rows:   ", q$n_metric_rows, "\n")
    cat("n_diagnostic_rows:", nrow(q$diagnostics), "\n")
  })
})


# ══════════════════════════════════════════════════════════════════════════════
# 2. stk_drif_register_runs
# ══════════════════════════════════════════════════════════════════════════════

test_that(".stk_register_runs (stk_drif) schema and row counts are stable", {
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
  stk_drif_metrics   <- .make_stk_metrics()
  stk_drif_portfolio <- .make_stk_portfolio()

  withr::local_envvar(HD_REGISTRY_PATH = tmp)

  result <- .stk_register_runs(
    strategy_names = strategy_names,
    code_name      = "stk_drif",
    metrics        = stk_drif_metrics,
    portfolio      = stk_drif_portfolio
  )

  expect_snapshot({
    cat("result columns:", paste(names(result), collapse = ", "), "\n")
    cat("result nrow:   ", nrow(result), "\n")
    cat("strategy_id:   ", result$strategy_id, "\n")
  })

  q <- .query_registry_t2(con, "stk_drif")

  expect_equal(nrow(q$strat), 1L)
  expect_equal(q$strat$strategy_id, "stk_drif")
  expect_equal(q$strat$asset_class, "equity")
  expect_equal(q$strat$frequency, "monthly")
  expect_equal(q$strat$lifecycle, "stable")

  expect_equal(nrow(q$runs), 1L)
  expect_equal(q$runs$partition, "phase1")

  expect_gte(q$n_metric_rows, 1L)

  expect_equal(nrow(q$diagnostics), 1L)
  expect_equal(q$diagnostics$diagnostic_name, "survivorship_biased")
  expect_equal(q$diagnostics$value_num, 1)

  # Idempotency: second call should not duplicate bt.strategy
  .stk_register_runs(
    strategy_names = strategy_names,
    code_name      = "stk_drif",
    metrics        = stk_drif_metrics,
    portfolio      = stk_drif_portfolio
  )
  n_strat <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) AS n FROM bt.strategy WHERE strategy_id = 'stk_drif'"
  )$n
  expect_equal(n_strat, 1L)

  expect_snapshot({
    cat("bt.strategy cols:", paste(names(q$strat), collapse = ", "), "\n")
    cat("bt.run cols:     ", paste(names(q$runs), collapse = ", "), "\n")
    cat("n_metric_rows:   ", q$n_metric_rows, "\n")
    cat("n_diagnostic_rows:", nrow(q$diagnostics), "\n")
  })
})


# ══════════════════════════════════════════════════════════════════════════════
# 3. xgb_drif_register_runs
# ══════════════════════════════════════════════════════════════════════════════

test_that(".xgb_drif_register_runs schema and row counts are stable", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer({
    DBI::dbDisconnect(con, shutdown = TRUE)
    unlink(tmp)
  })

  strategy_names     <- .make_strategy_names()
  xgb_drif_metrics   <- .make_stk_metrics()
  xgb_drif_portfolio <- .make_stk_portfolio()

  withr::local_envvar(HD_REGISTRY_PATH = tmp)

  result <- .xgb_drif_register_runs(
    strategy_names     = strategy_names,
    xgb_drif_metrics   = xgb_drif_metrics,
    xgb_drif_portfolio = xgb_drif_portfolio
  )

  expect_snapshot({
    cat("result columns:", paste(names(result), collapse = ", "), "\n")
    cat("result nrow:   ", nrow(result), "\n")
    cat("strategy_id:   ", result$strategy_id, "\n")
  })

  q <- .query_registry_t2(con, "xgb_drif")

  expect_equal(nrow(q$strat), 1L)
  expect_equal(q$strat$strategy_id, "xgb_drif")
  expect_equal(q$strat$asset_class, "equity")
  expect_equal(q$strat$frequency, "monthly")
  expect_equal(q$strat$lifecycle, "stable")

  expect_equal(nrow(q$runs), 1L)
  expect_equal(q$runs$partition, "phase1")

  expect_gte(q$n_metric_rows, 1L)

  expect_equal(nrow(q$diagnostics), 1L)
  expect_equal(q$diagnostics$diagnostic_name, "survivorship_biased")
  expect_equal(q$diagnostics$value_num, 1)

  # Idempotency: second call should not duplicate bt.strategy
  .xgb_drif_register_runs(
    strategy_names     = strategy_names,
    xgb_drif_metrics   = xgb_drif_metrics,
    xgb_drif_portfolio = xgb_drif_portfolio
  )
  n_strat <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) AS n FROM bt.strategy WHERE strategy_id = 'xgb_drif'"
  )$n
  expect_equal(n_strat, 1L)

  expect_snapshot({
    cat("bt.strategy cols:", paste(names(q$strat), collapse = ", "), "\n")
    cat("bt.run cols:     ", paste(names(q$runs), collapse = ", "), "\n")
    cat("n_metric_rows:   ", q$n_metric_rows, "\n")
    cat("n_diagnostic_rows:", nrow(q$diagnostics), "\n")
  })
})
