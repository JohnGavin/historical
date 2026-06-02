# Plan: Commodities Mean Reversion (Issue #138)
#
# Counterpart to plan_commodities_momentum.R (#134).
# #134 found commodity momentum is broken (Sharpe -0.85 baseline,
# -0.89 to -0.91 decomposed). This plan tests the counter-hypothesis:
# if momentum doesn't work, mean reversion might — commodities have
# backwardation/contango cycles, supply/demand seasonality, and supply
# shocks that reverse.
#
# A clear negative result is fine and valuable.
#
# Data: re-uses commodities_raw + commodities_returns from
#       plan_commodities_momentum.R (DO NOT re-define those targets here).
# Frequency: monthly (ann_factor = 12).
# Look-ahead safety: signal at t uses returns through t-1 only.
# Execution: signal at t -> trade at t+1 close.
# Transaction cost: 0.2% per trade (same as commodity momentum, #134).

plan_commodities_mean_reversion <- function() {
  list(

    # ── Signals: three lookback windows ──────────────────────────────────
    # Re-uses commodities_returns from plan_commodities_momentum.R.
    # Each signal: mr_signal = -(cumulative return over prior L months).
    # Higher signal -> bigger recent loser -> long candidate.

    targets::tar_target(cmr_signals_1m, {
      hd_commodity_mr_signal(commodities_returns, lookback_months = 1L)
    }),

    targets::tar_target(cmr_signals_3m, {
      hd_commodity_mr_signal(commodities_returns, lookback_months = 3L)
    }),

    targets::tar_target(cmr_signals_6m, {
      hd_commodity_mr_signal(commodities_returns, lookback_months = 6L)
    }),


    # ── Portfolios: long-losers / short-winners ───────────────────────────
    # t+1 execution: signal at t -> trade executes at t+1 closing prices.
    # 10 long + 10 short, equal weight within each leg.
    # 0.2% one-way transaction cost.

    targets::tar_target(cmr_portfolio_1m, {
      hd_commodity_mr_portfolio(
        signal_tbl  = cmr_signals_1m,
        returns_tbl = commodities_returns,
        n_long      = 10L,
        n_short     = 10L,
        cost_bps    = 20
      )
    }),

    targets::tar_target(cmr_portfolio_3m, {
      hd_commodity_mr_portfolio(
        signal_tbl  = cmr_signals_3m,
        returns_tbl = commodities_returns,
        n_long      = 10L,
        n_short     = 10L,
        cost_bps    = 20
      )
    }),

    targets::tar_target(cmr_portfolio_6m, {
      hd_commodity_mr_portfolio(
        signal_tbl  = cmr_signals_6m,
        returns_tbl = commodities_returns,
        n_long      = 10L,
        n_short     = 10L,
        cost_bps    = 20
      )
    }),


    # ── Monthly net returns (thin wrappers for falsification bridge) ──────

    targets::tar_target(cmr_returns_1m, {
      cmr_portfolio_1m |>
        dplyr::select(date, strategy_ret = net_ret)
    }),

    targets::tar_target(cmr_returns_3m, {
      cmr_portfolio_3m |>
        dplyr::select(date, strategy_ret = net_ret)
    }),

    targets::tar_target(cmr_returns_6m, {
      cmr_portfolio_6m |>
        dplyr::select(date, strategy_ret = net_ret)
    }),


    # ── Performance metrics per lookback ──────────────────────────────────
    # Sharpe, MDD, max DD duration (hd_dd_duration from risk_metrics.R).

    targets::tar_target(cmr_metrics_1m, {
      .compute_cmr_metrics(cmr_portfolio_1m, lookback = "1m", ann_factor = 12L)
    }),

    targets::tar_target(cmr_metrics_3m, {
      .compute_cmr_metrics(cmr_portfolio_3m, lookback = "3m", ann_factor = 12L)
    }),

    targets::tar_target(cmr_metrics_6m, {
      .compute_cmr_metrics(cmr_portfolio_6m, lookback = "6m", ann_factor = 12L)
    }),


    # ── Summary: comparison across lookbacks ─────────────────────────────

    targets::tar_target(cmr_summary, {
      dplyr::bind_rows(cmr_metrics_1m, cmr_metrics_3m, cmr_metrics_6m) |>
        dplyr::arrange(lookback)
    }),


    # ── Head-to-head: mean reversion vs momentum (Part C) ─────────────────
    # Joins commodity-momentum metrics (from plan_commodities_momentum.R)
    # with MR metrics. Lightweight: no new data fetch.
    # Momentum baseline = 12m lookback (Sharpe -0.85 per #134).

    targets::tar_target(cmr_vs_mom_compare, {
      library(dplyr)

      mom_metrics <- commodities_perf_summary |>
        dplyr::filter(strategy == "baseline") |>
        dplyr::transmute(
          lookback     = "12m (momentum)",
          mom_sharpe   = round(sharpe, 3),
          mom_mdd      = round(max_dd, 3)
        )

      mr_metrics <- cmr_summary |>
        dplyr::transmute(
          lookback   = paste0(lookback, " (MR)"),
          mr_sharpe  = round(sharpe, 3),
          mr_mdd     = round(max_dd, 3)
        )

      # One row per configuration; NA where comparison doesn't apply.
      tibble::tibble(
        lookback    = c(mr_metrics$lookback, mom_metrics$lookback),
        type        = c(rep("mean_reversion", nrow(mr_metrics)), "momentum"),
        sharpe      = c(mr_metrics$mr_sharpe, mom_metrics$mom_sharpe),
        max_dd      = c(mr_metrics$mr_mdd,    mom_metrics$mom_mdd)
      ) |>
        dplyr::arrange(type, lookback)
    }),


    # ── Registry sentinel (#347 PR 2/4; stability metrics #400 PR 5/6) ──────
    # First strategy to write into the bt.* registry. One bt.strategy row
    # + three bt.run rows (one per lookback partition: 1m, 3m, 6m). The
    # registry path is overridable via HD_REGISTRY_PATH so CI / tests can
    # point it at a tempfile. Returns a tibble of the run_uuids for
    # inspection via tar_read(cmr_registry_run).
    # Also records SSR + top5pct stability metrics via hd_record_stability_metrics().

    targets::tar_target(cmr_registry_run, {
      .cmr_register_runs(
        strategy_names = strategy_names,
        cmr_summary    = cmr_summary,
        portfolio_list = list(
          `1m` = cmr_portfolio_1m,
          `3m` = cmr_portfolio_3m,
          `6m` = cmr_portfolio_6m
        )
      )
    })

  )
}


# ── Internal helper ────────────────────────────────────────────────────────────
# Not exported; called only within this plan's targets.

.compute_cmr_metrics <- function(portfolio_tbl, lookback, ann_factor = 12L) {
  library(dplyr)

  r    <- portfolio_tbl$net_ret
  r    <- r[!is.na(r)]
  n    <- length(r)

  if (n < 12L) {
    return(tibble::tibble(
      lookback = lookback, n_months = n,
      sharpe = NA_real_, cagr = NA_real_, vol = NA_real_,
      max_dd = NA_real_, avg_dd_duration = NA_real_, max_dd_duration = NA_real_
    ))
  }

  monthly_rf <- (1.02)^(1 / ann_factor) - 1
  mean_r     <- mean(r)
  sd_r       <- sd(r)
  sharpe     <- if (sd_r > 0) (mean_r - monthly_rf) / sd_r * sqrt(ann_factor) else NA_real_

  cum        <- cumprod(1 + r)
  years      <- n / ann_factor
  cagr       <- (cum[n])^(1 / years) - 1
  vol        <- sd_r * sqrt(ann_factor)

  cum_max    <- cummax(cum)
  dd         <- (cum - cum_max) / cum_max
  max_dd     <- min(dd)

  dd_stats   <- hd_dd_duration(r)

  tibble::tibble(
    lookback        = lookback,
    n_months        = n,
    sharpe          = round(sharpe, 3),
    cagr            = round(cagr * 100, 1),
    vol             = round(vol * 100, 1),
    max_dd          = round(max_dd * 100, 1),
    avg_dd_duration = dd_stats$avg_dd_duration,
    max_dd_duration = dd_stats$max_dd_duration
  )
}


# ── Registry sentinel helper (#347 PR 2/4; stability metrics #400 PR 5/6) ──
# Initialises (idempotent) + upserts CMR strategy + records one bt.run
# row per lookback partition. Also records SSR + top5pct stability metrics
# via hd_record_stability_metrics() when portfolio_list is supplied.
# Returns a tibble of (partition, run_uuid).
.cmr_register_runs <- function(strategy_names, cmr_summary,
                               portfolio_list = list()) {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("duckdb", quietly = TRUE)) {
    return(tibble::tibble(
      partition = character(),
      run_uuid  = character()
    ))
  }

  path <- historicaldata::hd_registry_path()
  historicaldata::hd_registry_init(path)
  con <- historicaldata::hd_registry_open(path, read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  cmr_row <- strategy_names |>
    dplyr::filter(.data$code_name == "cmr") |>
    dplyr::transmute(
      strategy_id       = .data$code_name,
      short_name        = .data$short_name,
      long_name         = .data$long_name,
      asset_class       = .data$asset_class,
      frequency         = .data$frequency,
      ann_factor        = as.integer(.data$ann_factor),
      directionality    = as.character(.data$directionality),
      liquidity_tier    = as.character(.data$liquidity_tier),
      time_horizon_days = as.integer(.data$time_horizon_days_avg),
      trades_per_year   = as.numeric(.data$trades_per_year_avg),
      turnover_pct      = as.numeric(.data$turnover_pct_per_period_avg),
      tags              = .data$tags,
      research_paper_doi = .data$research_paper_doi
    )
  historicaldata::hd_strategy_upsert(con, cmr_row)

  partitions <- unique(cmr_summary$lookback)
  uuids <- character(length(partitions))
  for (i in seq_along(partitions)) {
    p <- partitions[i]
    uu <- historicaldata::hd_run_upsert(
      con,
      strategy_id      = "cmr",
      partition        = p,
      pipeline_version = "phase1"
    )
    uuids[i] <- uu

    # PR 3/4 — record long-form metrics for this partition.
    row <- cmr_summary[cmr_summary$lookback == p, , drop = FALSE]
    if (nrow(row) == 1L) {
      metric_cols <- setdiff(names(row), "lookback")
      wide <- row[, metric_cols, drop = FALSE]
      historicaldata::hd_metric_record(con, uu, wide)
    }

    # Record SSR + top5pct stability metrics (#400 PR 5/6).
    # Monthly series: w = 36 rolling windows, ann_factor = 12.
    port <- portfolio_list[[p]]
    if (!is.null(port) && is.data.frame(port) && "net_ret" %in% names(port)) {
      rets <- port$net_ret
      if (length(rets) > 0L) {
        historicaldata::hd_record_stability_metrics(
          con        = con,
          run_uuid   = uu,
          returns    = rets,
          w          = 36L,
          ann_factor = 12L
        )
      }
    }
  }

  tibble::tibble(partition = partitions, run_uuid = uuids)
}
