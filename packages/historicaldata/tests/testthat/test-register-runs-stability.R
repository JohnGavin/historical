# Tests for stability-metric registration in *_register_runs helpers (#400 PR 5/6)
#
# Covers:
#   1. .mom_prepeak_register_runs() writes SSR + top5pct rows for each sibling
#   2. Idempotency: calling register_runs twice leaves 8 stability rows per run
#   3. .mom_prepeak_register_runs() with returns_list = list() skips stability rows
#   4. .cmr_register_runs() writes SSR + top5pct rows for each lookback partition
#   5. .cmr_register_runs() with portfolio_list = list() skips stability rows
#
# NOTE: These tests source R/plan_mom_prepeak.R and
# R/plan_commodities_mean_reversion.R to pull in the private helpers
# (.mom_prepeak_register_runs, .cmr_register_runs).  If the plan files cannot
# be sourced the tests are skipped gracefully — same pattern as
# test-mom-prepeak-random-peak.R.

# ── helper loaders ────────────────────────────────────────────────────────────

.load_mom_prepeak_plan <- function() {
  plan_path <- here::here("R/plan_mom_prepeak.R")
  if (!file.exists(plan_path)) return(invisible(FALSE))
  tryCatch(
    { source(plan_path, local = FALSE); invisible(TRUE) },
    error = function(e) invisible(FALSE)
  )
}

.load_cmr_plan <- function() {
  plan_path <- here::here("R/plan_commodities_mean_reversion.R")
  if (!file.exists(plan_path)) return(invisible(FALSE))
  tryCatch(
    { source(plan_path, local = FALSE); invisible(TRUE) },
    error = function(e) invisible(FALSE)
  )
}

# ── shared registry fixture ───────────────────────────────────────────────────

.init_registry_tmp <- function() {
  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  con <- hd_registry_open(tmp, read_only = FALSE)
  list(tmp = tmp, con = con)
}

# ── shared strategy_names fixture ────────────────────────────────────────────
# Minimal tibble: only the columns referenced by .mom_prepeak_register_runs()
# and .cmr_register_runs() via dplyr::transmute().

.make_strategy_names_mom <- function() {
  code_names <- c("mom_prepeak", "mom_postpeak", "mom_combined")
  tibble::tibble(
    code_name               = code_names,
    short_name              = c("Mom Pre", "Mom Post", "Mom 12-2"),
    long_name               = c("Pre-Peak Momentum", "Post-Peak Momentum",
                                "Standard 12-2 Momentum"),
    asset_class             = rep("equity", 3L),
    frequency               = rep("monthly", 3L),
    ann_factor              = rep(12L, 3L),
    directionality          = factor(rep("long_short", 3L),
                               levels = c("long_only", "long_short",
                                          "market_neutral", "overlay")),
    liquidity_tier          = factor(rep("med", 3L),
                               levels = c("high", "med", "low")),
    time_horizon_days_avg   = rep(21L, 3L),
    trades_per_year_avg     = rep(12, 3L),
    turnover_pct_per_period_avg = rep(100, 3L),
    tags                    = rep('["momentum"]', 3L),
    research_paper_doi      = rep("10.2139/ssrn.4298538", 3L)
  )
}

.make_strategy_names_cmr <- function() {
  tibble::tibble(
    code_name               = "cmr",
    short_name              = "CMR",
    long_name               = "Commodities Mean Reversion",
    asset_class             = "commodities",
    frequency               = "daily",  # #717: matches R/plan_strategy_names.R
    ann_factor              = 252L,
    directionality          = factor("long_short",
                               levels = c("long_only", "long_short",
                                          "market_neutral", "overlay")),
    liquidity_tier          = factor("med",
                               levels = c("high", "med", "low")),
    time_horizon_days_avg   = 21L,
    trades_per_year_avg     = 12,
    turnover_pct_per_period_avg = 100,
    tags                    = '["mean_reversion","commodities"]',
    research_paper_doi      = NA_character_
  )
}

# ── synthetic returns and summaries ──────────────────────────────────────────

.make_mom_prepeak_summary <- function() {
  code_names <- c("mom_prepeak", "mom_postpeak", "mom_combined")
  tibble::tibble(
    strategy   = code_names,
    sharpe     = c(0.42, 0.31, 0.38),
    cagr       = c(4.1,  2.8,  3.5),
    vol        = c(10.0, 9.5,  9.8),
    max_dd     = c(-22,  -20,  -21),
    n_months   = rep(120L, 3L)
  )
}

.make_mom_returns_vec <- function(n = 120L) {
  set.seed(42L)
  rnorm(n, mean = 0.003, sd = 0.04)
}

.make_cmr_summary <- function() {
  # Column is n_days, not n_months (#717: CMR's underlying data is daily,
  # not monthly -- .compute_cmr_metrics() renamed the column at source).
  tibble::tibble(
    lookback        = c("1m", "3m", "6m"),
    n_days          = c(100L, 98L, 95L),
    sharpe          = c(-0.21, -0.18, -0.15),
    cagr            = c(-2.1, -1.8, -1.5),
    vol             = c(12.0, 11.5, 11.0),
    max_dd          = c(-30, -28, -26),
    avg_dd_duration = c(6L, 5L, 5L),
    max_dd_duration = c(18L, 16L, 15L)
  )
}

.make_cmr_portfolio <- function(n = 300L) {
  # #717: CMR's real return series is daily (~252 obs/year), not monthly --
  # .cmr_register_runs() now calls hd_record_stability_metrics(w = 252L,
  # ann_factor = 252L) to match. n = 300 gives 300 - 252 + 1 = 49 complete
  # rolling windows, enough for hd_sharpe_stability_ratio() to return
  # non-NA ssr/ssr_mean_sharpe/ssr_se -- the previous n = 100L (monthly-
  # dated fixture, w = 36L pre-#717) is too short for a w = 252L window and
  # produces < 8 stability rows (NA metric_value rows are dropped by
  # hd_metric_record(), not written).
  set.seed(7L)
  gross <- rnorm(n, 0, 0.01)
  cost  <- rep(0.0002, n)
  tibble::tibble(
    date      = seq.Date(as.Date("2015-01-02"), by = "day", length.out = n),
    gross_ret = gross,
    cost      = cost,
    net_ret   = gross - cost,
    n_long    = rep(10L, n),
    n_short   = rep(10L, n),
    turnover  = rep(0.5, n)
  )
}

# ── query helpers ─────────────────────────────────────────────────────────────

.stability_metric_names <- c(
  "ssr", "ssr_mean_sharpe", "ssr_se", "ssr_n_windows", "ssr_lag_nw",
  "top_share", "top_n_top", "top_n_total"
)

.count_stability_rows <- function(con, run_uuid) {
  DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT COUNT(*) AS n FROM bt.metric
       WHERE run_uuid = ? AND metric_name IN (%s)",
      paste(rep("?", length(.stability_metric_names)), collapse = ", ")
    ),
    params = c(list(run_uuid), as.list(.stability_metric_names))
  )$n
}

# ─────────────────────────────────────────────────────────────────────────────
# Tests 1–3: .mom_prepeak_register_runs()
# ─────────────────────────────────────────────────────────────────────────────

test_that("mom_prepeak_register_runs writes 8 stability rows per sibling strategy", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  skip_if_not(
    .load_mom_prepeak_plan(),
    "R/plan_mom_prepeak.R not loadable — skipping"
  )
  skip_if_not(
    exists(".mom_prepeak_register_runs"),
    ".mom_prepeak_register_runs not found after source()"
  )

  s <- .init_registry_tmp()
  withr::defer({
    DBI::dbDisconnect(s$con, shutdown = TRUE)
    unlink(s$tmp)
  })

  withr::with_envvar(c(HD_REGISTRY_PATH = s$tmp), {
    rvec  <- .make_mom_returns_vec()
    out   <- .mom_prepeak_register_runs(
      strategy_names      = .make_strategy_names_mom(),
      mom_prepeak_summary = .make_mom_prepeak_summary(),
      returns_list        = list(
        mom_prepeak  = rvec,
        mom_postpeak = rvec,
        mom_combined = rvec
      )
    )
  })

  expect_equal(nrow(out), 3L)
  expect_setequal(out$strategy_id, c("mom_prepeak", "mom_postpeak", "mom_combined"))

  for (uuid in out$run_uuid) {
    n <- .count_stability_rows(s$con, uuid)
    expect_equal(n, 8L,
      info = paste("strategy run_uuid:", uuid,
                   "expected 8 stability rows, got", n))
  }
})


test_that("mom_prepeak_register_runs idempotent: 8 stability rows after 2 calls", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  skip_if_not(
    .load_mom_prepeak_plan(),
    "R/plan_mom_prepeak.R not loadable — skipping"
  )
  skip_if_not(
    exists(".mom_prepeak_register_runs"),
    ".mom_prepeak_register_runs not found after source()"
  )

  s <- .init_registry_tmp()
  withr::defer({
    DBI::dbDisconnect(s$con, shutdown = TRUE)
    unlink(s$tmp)
  })

  rvec <- .make_mom_returns_vec()
  rl   <- list(
    mom_prepeak  = rvec,
    mom_postpeak = rvec,
    mom_combined = rvec
  )

  out1 <- NULL
  withr::with_envvar(c(HD_REGISTRY_PATH = s$tmp), {
    out1 <- .mom_prepeak_register_runs(
      strategy_names      = .make_strategy_names_mom(),
      mom_prepeak_summary = .make_mom_prepeak_summary(),
      returns_list        = rl
    )
    .mom_prepeak_register_runs(
      strategy_names      = .make_strategy_names_mom(),
      mom_prepeak_summary = .make_mom_prepeak_summary(),
      returns_list        = rl
    )
  })

  # hd_run_upsert is idempotent: same uuid on second call.
  # hd_metric_record DELETE-then-INSERTs, so still exactly 8 rows.
  for (uuid in out1$run_uuid) {
    n <- .count_stability_rows(s$con, uuid)
    expect_equal(n, 8L,
      info = paste("after 2 calls, run_uuid:", uuid, "has", n, "stability rows"))
  }
})


test_that("mom_prepeak_register_runs with empty returns_list writes 0 stability rows", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  skip_if_not(
    .load_mom_prepeak_plan(),
    "R/plan_mom_prepeak.R not loadable — skipping"
  )
  skip_if_not(
    exists(".mom_prepeak_register_runs"),
    ".mom_prepeak_register_runs not found after source()"
  )

  s <- .init_registry_tmp()
  withr::defer({
    DBI::dbDisconnect(s$con, shutdown = TRUE)
    unlink(s$tmp)
  })

  out <- NULL
  withr::with_envvar(c(HD_REGISTRY_PATH = s$tmp), {
    out <- .mom_prepeak_register_runs(
      strategy_names      = .make_strategy_names_mom(),
      mom_prepeak_summary = .make_mom_prepeak_summary(),
      returns_list        = list()
    )
  })

  for (uuid in out$run_uuid) {
    n <- .count_stability_rows(s$con, uuid)
    expect_equal(n, 0L,
      info = paste("no returns supplied; run_uuid:", uuid, "should have 0 stability rows"))
  }
})


# ─────────────────────────────────────────────────────────────────────────────
# Tests 4–5: .cmr_register_runs()
# ─────────────────────────────────────────────────────────────────────────────

test_that("cmr_register_runs writes 8 stability rows per lookback partition", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  skip_if_not(
    .load_cmr_plan(),
    "R/plan_commodities_mean_reversion.R not loadable — skipping"
  )
  skip_if_not(
    exists(".cmr_register_runs"),
    ".cmr_register_runs not found after source()"
  )

  s <- .init_registry_tmp()
  withr::defer({
    DBI::dbDisconnect(s$con, shutdown = TRUE)
    unlink(s$tmp)
  })

  port <- .make_cmr_portfolio()
  pl   <- list(`1m` = port, `3m` = port, `6m` = port)

  out <- NULL
  withr::with_envvar(c(HD_REGISTRY_PATH = s$tmp), {
    out <- .cmr_register_runs(
      strategy_names = .make_strategy_names_cmr(),
      cmr_summary    = .make_cmr_summary(),
      portfolio_list = pl
    )
  })

  expect_equal(nrow(out), 3L)
  expect_setequal(out$partition, c("1m", "3m", "6m"))

  for (uuid in out$run_uuid) {
    n <- .count_stability_rows(s$con, uuid)
    expect_equal(n, 8L,
      info = paste("cmr run_uuid:", uuid,
                   "expected 8 stability rows, got", n))
  }
})


test_that("cmr_register_runs with empty portfolio_list writes 0 stability rows", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  skip_if_not(
    .load_cmr_plan(),
    "R/plan_commodities_mean_reversion.R not loadable — skipping"
  )
  skip_if_not(
    exists(".cmr_register_runs"),
    ".cmr_register_runs not found after source()"
  )

  s <- .init_registry_tmp()
  withr::defer({
    DBI::dbDisconnect(s$con, shutdown = TRUE)
    unlink(s$tmp)
  })

  out <- NULL
  withr::with_envvar(c(HD_REGISTRY_PATH = s$tmp), {
    out <- .cmr_register_runs(
      strategy_names = .make_strategy_names_cmr(),
      cmr_summary    = .make_cmr_summary(),
      portfolio_list = list()
    )
  })

  for (uuid in out$run_uuid) {
    n <- .count_stability_rows(s$con, uuid)
    expect_equal(n, 0L,
      info = paste("no portfolio supplied; run_uuid:", uuid,
                   "should have 0 stability rows"))
  }
})
