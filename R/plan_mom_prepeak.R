# Plan: Pre-Peak / Post-Peak 12-2 Momentum Decomposition (#365 PR 2/4)
#
# Wires historicaldata::hd_mom_prepeak_signal() into the targets pipeline.
# Operates on ltr_universe (~51 US non-ETF equities; methodology-demo scope).
#
# Three sibling strategies from one shared signal computation:
#   mom_prepeak  — ranks on pre_peak_return  (84% of paper's alpha)
#   mom_postpeak — ranks on post_peak_return (standard 52-week-high mechanism)
#   mom_combined — ranks on total_return     (baseline 12-2 momentum control)
#
# Reference: Büsing, Mohrschladt & Siedhoff (2022), DOI 10.2139/ssrn.4298538.
#
# Look-ahead safety: signal at t uses prices through formation_end = t - 2 months.
# Execution: trade at t+1 month-end closing prices (identical to CMR pilot).
# Transaction cost: cost_per_trade applied on full turnover per leg.
#
# Precedent: R/plan_commodities_mean_reversion.R — registry sentinel structure.

plan_mom_prepeak <- function() {
  list(

    # ── Parameters ──────────────────────────────────────────────────────────────

    targets::tar_target(mom_prepeak_params, {
      list(
        lookback_months_start    = 12L,   # "12" in 12-2 momentum
        lookback_months_end      = 2L,    # "2" in 12-2 (skip recent reversal month)
        min_obs_days             = 100L,  # minimum trading days in formation window
        n_quantiles              = 10L,   # deciles
        min_stocks_per_month     = 30L,   # matches ltr_params$min_stocks_per_month
        cost_per_trade           = 0.0010 # 10bps per trade (matches ltr_params)
      )
    }),


    # ── Monthly rebalance dates from ltr_universe ────────────────────────────
    # Last actual trading day per calendar month appearing in ltr_universe$date.
    # Returns Date (NOT POSIXct) — consistent with #147 month-end convention.

    targets::tar_target(mom_prepeak_as_of_dates, {
      library(dplyr)

      ltr_universe |>
        dplyr::mutate(ym = format(as.Date(.data$date), "%Y-%m")) |>
        dplyr::group_by(.data$ym) |>
        dplyr::summarise(as_of_date = max(as.Date(.data$date)), .groups = "drop") |>
        dplyr::arrange(.data$as_of_date) |>
        dplyr::pull(.data$as_of_date)
    }),


    # ── Shared signal: one call feeds all 3 sibling strategies ──────────────
    # Returns one row per (ticker, as_of_date) with 10 columns including
    # pre_peak_return, post_peak_return, total_return.

    targets::tar_target(mom_prepeak_signal_raw, {
      historicaldata::hd_mom_prepeak_signal(
        daily_prices          = ltr_universe,
        as_of_dates           = mom_prepeak_as_of_dates,
        lookback_months_start = mom_prepeak_params$lookback_months_start,
        lookback_months_end   = mom_prepeak_params$lookback_months_end,
        min_obs_days          = mom_prepeak_params$min_obs_days
      )
    }),


    # ── Portfolios: cross-sectional decile sort, long top / short bottom ─────
    # One target per sibling — each calls the shared helper with a different
    # signal column. Long top decile, short bottom decile, equal-weighted.
    # Dates with fewer than min_stocks_per_month are dropped.

    targets::tar_target(mom_prepeak_portfolio, {
      .mom_prepeak_form_portfolio(
        signal_tbl  = mom_prepeak_signal_raw,
        signal_col  = "pre_peak_return",
        n_quantiles = mom_prepeak_params$n_quantiles,
        min_stocks  = mom_prepeak_params$min_stocks_per_month
      )
    }),

    targets::tar_target(mom_postpeak_portfolio, {
      .mom_prepeak_form_portfolio(
        signal_tbl  = mom_prepeak_signal_raw,
        signal_col  = "post_peak_return",
        n_quantiles = mom_prepeak_params$n_quantiles,
        min_stocks  = mom_prepeak_params$min_stocks_per_month
      )
    }),

    targets::tar_target(mom_combined_portfolio, {
      .mom_prepeak_form_portfolio(
        signal_tbl  = mom_prepeak_signal_raw,
        signal_col  = "total_return",
        n_quantiles = mom_prepeak_params$n_quantiles,
        min_stocks  = mom_prepeak_params$min_stocks_per_month
      )
    }),


    # ── Realised monthly returns (look-ahead-safe, t+1 execution) ───────────
    # Signal at as_of_date t -> trade executes at t+1 month-end.
    # Returns: as_of_date (signal date), exec_date (t+1 month-end),
    #          ret_long, ret_short, ret_ls (net of cost on full turnover).

    targets::tar_target(mom_prepeak_returns, {
      .mom_prepeak_compute_returns(
        portfolio_tbl   = mom_prepeak_portfolio,
        universe_tbl    = ltr_universe,
        cost_per_trade  = mom_prepeak_params$cost_per_trade
      )
    }),

    targets::tar_target(mom_postpeak_returns, {
      .mom_prepeak_compute_returns(
        portfolio_tbl   = mom_postpeak_portfolio,
        universe_tbl    = ltr_universe,
        cost_per_trade  = mom_prepeak_params$cost_per_trade
      )
    }),

    targets::tar_target(mom_combined_returns, {
      .mom_prepeak_compute_returns(
        portfolio_tbl   = mom_combined_portfolio,
        universe_tbl    = ltr_universe,
        cost_per_trade  = mom_prepeak_params$cost_per_trade
      )
    }),


    # ── Performance metrics (one row per sibling) ────────────────────────────

    targets::tar_target(mom_prepeak_metrics, {
      .mom_prepeak_compute_metrics(mom_prepeak_returns, strategy = "mom_prepeak")
    }),

    targets::tar_target(mom_postpeak_metrics, {
      .mom_prepeak_compute_metrics(mom_postpeak_returns, strategy = "mom_postpeak")
    }),

    targets::tar_target(mom_combined_metrics, {
      .mom_prepeak_compute_metrics(mom_combined_returns, strategy = "mom_combined")
    }),


    # ── Summary: all 3 siblings in one tibble (feeds registry sentinel) ──────

    targets::tar_target(mom_prepeak_summary, {
      dplyr::bind_rows(
        mom_prepeak_metrics,
        mom_postpeak_metrics,
        mom_combined_metrics
      )
    }),


    # ── Registry sentinel (#365 PR 2/4) ─────────────────────────────────────
    # Mirrors .cmr_register_runs() from plan_commodities_mean_reversion.R.
    # Upserts 3 strategy rows + records one bt.run + bt.metric row each.
    # Guard: returns empty tibble if DBI / duckdb are unavailable.

    targets::tar_target(mom_prepeak_register_runs, {
      .mom_prepeak_register_runs(
        strategy_names    = strategy_names,
        mom_prepeak_summary = mom_prepeak_summary
      )
    })

  )
}


# ── Internal helpers ───────────────────────────────────────────────────────────
# Prefixed .mom_prepeak_* (private; not exported from the package).
# These plan-level helpers live here rather than in packages/historicaldata/R/
# because they are wiring code, not reusable library code.


#' Form a long-short decile portfolio from pre/post-peak signals
#'
#' @param signal_tbl Tibble from hd_mom_prepeak_signal().
#' @param signal_col Character. Column name to rank on.
#' @param n_quantiles Integer. Number of quantile buckets (default 10 = deciles).
#' @param min_stocks Integer. Drop as_of_dates with fewer stocks than this.
#'
#' @return Tibble with columns: as_of_date, ticker, signal_value, decile,
#'   weight (positive = long leg, negative = short leg).
#' @noRd
.mom_prepeak_form_portfolio <- function(signal_tbl,
                                        signal_col,
                                        n_quantiles = 10L,
                                        min_stocks  = 30L) {
  library(dplyr)

  stopifnot(
    is.data.frame(signal_tbl),
    is.character(signal_col),
    length(signal_col) == 1L,
    signal_col %in% names(signal_tbl)
  )

  result <- signal_tbl |>
    dplyr::select(
      "as_of_date",
      "ticker",
      signal_value = dplyr::all_of(signal_col)
    ) |>
    dplyr::filter(!is.na(.data$signal_value)) |>
    dplyr::group_by(.data$as_of_date) |>
    dplyr::filter(dplyr::n() >= min_stocks) |>
    dplyr::mutate(
      decile = dplyr::ntile(.data$signal_value, n_quantiles)
    ) |>
    dplyr::filter(.data$decile == 1L | .data$decile == n_quantiles) |>
    dplyr::mutate(
      # Equal weight within each leg
      n_long  = sum(.data$decile == n_quantiles),
      n_short = sum(.data$decile == 1L),
      weight  = dplyr::case_when(
        .data$decile == n_quantiles ~  1 / .data$n_long,
        .data$decile == 1L         ~ -1 / .data$n_short,
        TRUE                       ~  NA_real_
      )
    ) |>
    dplyr::ungroup() |>
    dplyr::select("as_of_date", "ticker", "signal_value", "decile", "weight")

  result
}


#' Compute realised monthly long-short returns (t+1 execution)
#'
#' Signal at as_of_date t -> trade executes at t+1 month-end.
#' Monthly return per leg = equal-weighted average of constituent returns.
#' Net return = ret_long - ret_short - 2 * cost_per_trade (full turnover both legs).
#'
#' @param portfolio_tbl Tibble from .mom_prepeak_form_portfolio().
#' @param universe_tbl Tibble with columns ticker, date, adjusted (ltr_universe).
#' @param cost_per_trade Numeric. One-way transaction cost fraction.
#'
#' @return Tibble with: as_of_date, exec_date, ret_long, ret_short, ret_ls.
#' @noRd
.mom_prepeak_compute_returns <- function(portfolio_tbl,
                                          universe_tbl,
                                          cost_per_trade = 0.001) {
  library(dplyr)

  # Build monthly return table from universe: for each ticker, compute
  # the month-over-month return using the last price in each month.
  monthly_ret <- universe_tbl |>
    dplyr::mutate(
      date = as.Date(.data$date),
      ym   = format(.data$date, "%Y-%m")
    ) |>
    dplyr::group_by(.data$ticker, .data$ym) |>
    dplyr::slice_max(.data$date, n = 1L, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::arrange(.data$ticker, .data$date) |>
    dplyr::group_by(.data$ticker) |>
    dplyr::mutate(fwd_ret = dplyr::lead(.data$adjusted) / .data$adjusted - 1) |>
    dplyr::ungroup() |>
    dplyr::select("ticker", "date", "ym", "fwd_ret")

  # Build exec_date map: as_of_date -> next month-end date in the universe
  as_of_dates <- sort(unique(portfolio_tbl$as_of_date))

  exec_map <- purrr::map_dfr(as_of_dates, function(aod) {
    aod_ym <- format(aod, "%Y-%m")
    next_dates <- monthly_ret |>
      dplyr::filter(.data$date > aod) |>
      dplyr::group_by(.data$ym) |>
      dplyr::summarise(exec_date = min(.data$date), .groups = "drop") |>
      dplyr::slice_min(.data$exec_date, n = 1L, with_ties = FALSE)

    if (nrow(next_dates) == 0L) {
      return(tibble::tibble(
        as_of_date = aod,
        exec_date  = as.Date(NA)
      ))
    }
    tibble::tibble(as_of_date = aod, exec_date = next_dates$exec_date[[1L]])
  })

  # Join portfolio weights with forward returns and exec dates
  port_with_ret <- portfolio_tbl |>
    dplyr::left_join(exec_map, by = "as_of_date") |>
    dplyr::filter(!is.na(.data$exec_date)) |>
    dplyr::left_join(
      monthly_ret |> dplyr::select("ticker", "date", "fwd_ret"),
      by = c("ticker", "exec_date" = "date")
    ) |>
    dplyr::filter(!is.na(.data$fwd_ret))

  # Aggregate to monthly long-short return
  port_with_ret |>
    dplyr::group_by(.data$as_of_date, .data$exec_date) |>
    dplyr::summarise(
      ret_long  = sum(.data$weight[.data$weight > 0] *
                        .data$fwd_ret[.data$weight > 0]),
      ret_short = sum(abs(.data$weight[.data$weight < 0]) *
                        .data$fwd_ret[.data$weight < 0]),
      .groups   = "drop"
    ) |>
    dplyr::mutate(
      # Net L/S return minus round-trip transaction cost (full turnover assumed)
      ret_ls = .data$ret_long - .data$ret_short - 2 * cost_per_trade
    ) |>
    dplyr::arrange(.data$as_of_date)
}


# .mom_prepeak_compute_metrics() is defined in
# packages/historicaldata/R/utils_mom_prepeak_metrics.R and loaded via
# pkgload::load_all() / library(historicaldata) at pipeline run time.
# The implementation was extracted there so it can be unit-tested
# independently of the plan file's tar_target library() calls.
# See also: packages/historicaldata/tests/testthat/test-mom-prepeak-metrics.R


#' Registry sentinel: upsert 3 sibling strategies + record runs + metrics
#'
#' Mirrors .cmr_register_runs() from plan_commodities_mean_reversion.R.
#' Returns empty tibble if DBI / duckdb are unavailable.
#'
#' @param strategy_names Tibble from the strategy_names target.
#' @param mom_prepeak_summary Tibble from the mom_prepeak_summary target.
#'
#' @return Tibble with columns: strategy_id, run_uuid.
#' @noRd
.mom_prepeak_register_runs <- function(strategy_names, mom_prepeak_summary) {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("duckdb", quietly = TRUE)) {
    return(tibble::tibble(
      strategy_id = character(),
      run_uuid    = character()
    ))
  }

  path <- historicaldata::hd_registry_path()
  historicaldata::hd_registry_init(path)
  con <- historicaldata::hd_registry_open(path, read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  code_names <- c("mom_prepeak", "mom_postpeak", "mom_combined")
  strategy_ids <- character(length(code_names))
  run_uuids    <- character(length(code_names))

  for (i in seq_along(code_names)) {
    cn <- code_names[[i]]

    strat_row <- strategy_names |>
      dplyr::filter(.data$code_name == cn) |>
      dplyr::transmute(
        strategy_id        = .data$code_name,
        short_name         = .data$short_name,
        long_name          = .data$long_name,
        asset_class        = .data$asset_class,
        frequency          = .data$frequency,
        ann_factor         = as.integer(.data$ann_factor),
        directionality     = as.character(.data$directionality),
        liquidity_tier     = as.character(.data$liquidity_tier),
        time_horizon_days  = as.integer(.data$time_horizon_days_avg),
        trades_per_year    = as.numeric(.data$trades_per_year_avg),
        turnover_pct       = as.numeric(.data$turnover_pct_per_period_avg),
        tags               = .data$tags,
        research_paper_doi = .data$research_paper_doi
      )

    historicaldata::hd_strategy_upsert(con, strat_row)

    uu <- historicaldata::hd_run_record(
      con,
      strategy_id      = cn,
      partition        = "phase1",
      pipeline_version = "phase1"
    )

    metrics_row <- mom_prepeak_summary[mom_prepeak_summary$strategy == cn, , drop = FALSE]
    if (nrow(metrics_row) == 1L) {
      metric_cols <- setdiff(names(metrics_row), "strategy")
      wide <- metrics_row[, metric_cols, drop = FALSE]
      historicaldata::hd_metric_record(con, uu, wide)
    }

    strategy_ids[[i]] <- cn
    run_uuids[[i]]    <- uu
  }

  tibble::tibble(strategy_id = strategy_ids, run_uuid = run_uuids)
}
