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
        cost_per_trade           = 0.0010, # 10bps per trade (matches ltr_params)
        # MANUAL: no source -- general-collateral (GC) borrow estimate, not a
        # measured series (#665). ltr_universe is 529 tickers approximating
        # S&P 500 constituents + liquid ETFs (SPY/QQQ/IWM/TLT/GLD/EEM/EFA...);
        # the short leg here is the loser DECILE of that universe (~53 US
        # large caps), which is general-collateral borrow in practice
        # (0.25-0.50%/yr), not the hard-to-borrow population the original
        # #665 argued for a flat 3%. 0.005 (0.50%) is the conservative end
        # of GC. A real borrow-cost series (e.g. from a securities-lending
        # data vendor) is still needed to replace this estimate -- see PR
        # body for the measured CAGR/Sharpe impact at 0%, 0.5%, and 3%.
        borrow_rate_annual       = 0.005
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

    # Borrow charge (#665) applied ONLY on these three published targets --
    # see .mom_prepeak_compute_returns() roxygen for why every other caller
    # (FIP screen, gauntlet) keeps the zero default.
    targets::tar_target(mom_prepeak_returns, {
      .mom_prepeak_compute_returns(
        portfolio_tbl       = mom_prepeak_portfolio,
        universe_tbl        = ltr_universe,
        cost_per_trade      = mom_prepeak_params$cost_per_trade,
        borrow_rate_annual  = mom_prepeak_params$borrow_rate_annual
      )
    }),

    targets::tar_target(mom_postpeak_returns, {
      .mom_prepeak_compute_returns(
        portfolio_tbl       = mom_postpeak_portfolio,
        universe_tbl        = ltr_universe,
        cost_per_trade      = mom_prepeak_params$cost_per_trade,
        borrow_rate_annual  = mom_prepeak_params$borrow_rate_annual
      )
    }),

    targets::tar_target(mom_combined_returns, {
      .mom_prepeak_compute_returns(
        portfolio_tbl       = mom_combined_portfolio,
        universe_tbl        = ltr_universe,
        cost_per_trade      = mom_prepeak_params$cost_per_trade,
        borrow_rate_annual  = mom_prepeak_params$borrow_rate_annual
      )
    }),


    # ── Performance metrics (one row per sibling) ────────────────────────────

    targets::tar_target(mom_prepeak_metrics, {
      rets <- .mom_prepeak_join_rf(mom_prepeak_returns, stk_rf)
      m <- .mom_prepeak_compute_metrics(rets, strategy = "mom_prepeak")
      m$sharpe <- round(.mom_prepeak_sharpe(rets, m), 3)
      # ann_rf published alongside sharpe (#677 slice 4), same PERCENT
      # convention as cagr/vol (.mom_prepeak_compute_metrics(), packages/
      # historicaldata/R/utils_mom_prepeak_metrics.R stores them as
      # round(x * 100, 1)).
      m$ann_rf <- round(.mom_prepeak_ann_rf(rets, m) * 100, 2)
      m
    }),

    targets::tar_target(mom_postpeak_metrics, {
      rets <- .mom_prepeak_join_rf(mom_postpeak_returns, stk_rf)
      m <- .mom_prepeak_compute_metrics(rets, strategy = "mom_postpeak")
      m$sharpe <- round(.mom_prepeak_sharpe(rets, m), 3)
      m$ann_rf <- round(.mom_prepeak_ann_rf(rets, m) * 100, 2)
      m
    }),

    targets::tar_target(mom_combined_metrics, {
      rets <- .mom_prepeak_join_rf(mom_combined_returns, stk_rf)
      m <- .mom_prepeak_compute_metrics(rets, strategy = "mom_combined")
      m$sharpe <- round(.mom_prepeak_sharpe(rets, m), 3)
      m$ann_rf <- round(.mom_prepeak_ann_rf(rets, m) * 100, 2)
      m
    }),


    # ── Summary: all 3 siblings in one tibble (feeds registry sentinel) ──────

    targets::tar_target(mom_prepeak_summary, {
      dplyr::bind_rows(
        mom_prepeak_metrics,
        mom_postpeak_metrics,
        mom_combined_metrics
      )
    }),


    # ── Registry sentinel (#365 PR 2/4; stability metrics #400 PR 5/6) ──────
    # Mirrors .cmr_register_runs() from plan_commodities_mean_reversion.R.
    # Upserts 3 strategy rows + records one bt.run + bt.metric row each.
    # Also records SSR + top5pct stability metrics via hd_record_stability_metrics().
    # Guard: returns empty tibble if DBI / duckdb are unavailable.

    targets::tar_target(mom_prepeak_register_runs, {
      .mom_prepeak_register_runs(
        strategy_names      = strategy_names,
        mom_prepeak_summary = mom_prepeak_summary,
        returns_list        = list(
          mom_prepeak  = mom_prepeak_returns$ret_ls,
          mom_postpeak = mom_postpeak_returns$ret_ls,
          mom_combined = mom_combined_returns$ret_ls
        )
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
#' @param borrow_rate_annual Numeric. Annualised borrow-cost rate charged on
#'   the short leg's notional, default 0 (unchanged behaviour for existing
#'   callers -- FIP screen, walk-forward gauntlet, random-peak falsification).
#'   The short leg is 100% of NAV under this portfolio's construction
#'   (equal-weight `-1/n_short` per short position, summing to -1 in
#'   absolute value -- see `.mom_prepeak_form_portfolio()`), matching the
#'   convention already used by `portfolio_longshort()`
#'   (R/plan_stock_backtest.R: `borrow_cost <- borrow_rate_annual / 12`) and
#'   by `packages/historicaldata/R/commodities_mean_reversion.R`. Only the
#'   three published targets (`mom_prepeak_returns`, `mom_postpeak_returns`,
#'   `mom_combined_returns`) pass a non-zero rate (#665); every other caller
#'   keeps the zero default so this fix does not silently change FIP or the
#'   gauntlet's cost basis (fail-loud-not-null.md: an unstated behaviour
#'   change is exactly the defect class this rule targets).
#'
#' @return Tibble with: as_of_date, exec_date, ret_long, ret_short, ret_ls.
#'
#' @details
#' **Short-leg return cap convention:** Each per-position short return is
#' capped at +100% (i.e. `fwd_ret <= 1`) before aggregation. This reflects
#' the financial reality that a short position can lose at most 100% of
#' its notional in a single period (price doubles). Without this cap, an
#' extreme single-name short squeeze (price triples, fwd_ret = +2) would
#' produce `ret_ls < -1`, implying losing more than 100% of capital in one
#' month — unrealistic for an equity L/S portfolio. The cap is applied per
#' position, not on the aggregate `ret_short`, so the cap can attenuate
#' some short positions while others retain their unscaled returns.
#'
#' Cost convention is unchanged: 2 × cost_per_trade ≈ full turnover round-trip.
#' Borrow convention (#665): `borrow_rate_annual / 12` charged monthly against
#' 100% short notional, additive to the transaction-cost deduction.
#' @noRd
.mom_prepeak_compute_returns <- function(portfolio_tbl,
                                          universe_tbl,
                                          cost_per_trade = 0.001,
                                          borrow_rate_annual = 0) {
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

  # Cap per-position short returns at +100%: a short loses at most 100% of
  # notional (price doubles, fwd_ret = 1). Without this, a short squeeze
  # (price triples, fwd_ret = 2) would produce ret_ls < -1, which is
  # unrealistic for an equity L/S portfolio. Cap is per position, not aggregate.
  port_with_ret <- port_with_ret |>
    dplyr::mutate(
      fwd_ret_short_capped = dplyr::if_else(
        .data$weight < 0 & .data$fwd_ret > 1,
        1,
        .data$fwd_ret
      )
    )

  # Aggregate to monthly long-short return
  port_with_ret |>
    dplyr::group_by(.data$as_of_date, .data$exec_date) |>
    dplyr::summarise(
      ret_long  = sum(.data$weight[.data$weight > 0] *
                        .data$fwd_ret[.data$weight > 0]),
      ret_short = sum(abs(.data$weight[.data$weight < 0]) *
                        .data$fwd_ret_short_capped[.data$weight < 0]),
      .groups   = "drop"
    ) |>
    dplyr::mutate(
      # Net L/S return minus round-trip transaction cost (full turnover assumed)
      # minus monthly borrow charge on 100% short notional (#665; 0 for
      # callers that don't pass borrow_rate_annual -- see roxygen above).
      ret_ls = .data$ret_long - .data$ret_short - 2 * cost_per_trade -
        borrow_rate_annual / 12
    ) |>
    dplyr::arrange(.data$as_of_date)
}


#' Join a monthly risk-free series onto mom_prepeak returns (#677)
#'
#' Mirrors \code{.ltr_join_rf()} in R/plan_ltr_momentum.R: joins on
#' \code{ym} derived from \code{exec_date}. As of #677 slice 3b the
#' coverage policy itself lives in the shared \code{.join_rf_series()}
#' (R/utils_metrics.R), which distinguishes THREE cases (leading /
#' trailing / interior) -- see that function's roxygen for the full
#' policy. A missing risk-free series must never be treated as zero --
#' see fail-loud-not-null.md.
#'
#' @param returns_tbl Tibble with an `exec_date` column (mom_prepeak_returns
#'   / mom_postpeak_returns / mom_combined_returns).
#' @param stk_rf Tibble with columns `ym`, `rf_ret` (R/plan_stock_backtest.R).
#' @return `returns_tbl` with `rf_ret` joined, trailing uncovered months removed.
#' @noRd
.mom_prepeak_join_rf <- function(returns_tbl, stk_rf) {
  if (!"exec_date" %in% names(returns_tbl)) {
    cli::cli_abort(c("x" = ".mom_prepeak_join_rf(): returns_tbl has no {.field exec_date} column to join on."))
  }

  returns_tbl <- dplyr::mutate(returns_tbl, ym = format(as.Date(.data$exec_date), "%Y-%m"))

  .join_rf_series(
    df = returns_tbl, rf = stk_rf, key = "ym",
    label = ".mom_prepeak_join_rf", rf_label = "stk_rf",
    rf_source = "R/plan_stock_backtest.R",
    df_label = "mom_prepeak returns", strategy_label = "mom_prepeak",
    period_noun = "month", check_key_col = FALSE
  )
}


#' Canonical rf-adjusted geometric Sharpe for a mom_prepeak sibling (#677)
#'
#' \code{.mom_prepeak_compute_metrics()} (packages/historicaldata) cannot
#' call \code{sharpe_ratio_rf()} -- that helper lives at the pipeline layer
#' (R/utils_metrics.R), not inside the historicaldata package -- so it
#' returns \code{sharpe = NA_real_} as a placeholder. This function computes
#' the real value: it reconstructs the SAME pre-bankruptcy slice from
#' \code{blown_up}/\code{bankrupt_month} (already computed by
#' \code{.mom_prepeak_compute_metrics()}) and calls the canonical
#' \code{sharpe_ratio_rf()} on it, so the Sharpe FORMULA stays single-sourced
#' even though the two halves of the calculation live on either side of the
#' package/pipeline boundary. Post-bankruptcy: geometric annualised return
#' is undefined once cumulative equity crosses zero (a negative base raised
#' to a fractional power is NaN in R) -- exactly why cagr is NA there too --
#' so using the pre-bankruptcy slice keeps Sharpe finite, matching the
#' pre-#677 arithmetic formula's "Sharpe survives bankruptcy" behaviour.
#'
#' @param returns_tbl Tibble with `ret_ls` and `rf_ret` columns (output of
#'   \code{.mom_prepeak_join_rf()}).
#' @param metrics_row One-row tibble from \code{.mom_prepeak_compute_metrics()}
#'   (needs `blown_up`, `bankrupt_month`).
#' @param ann_factor Integer. Annualisation factor (12 for monthly).
#' @return A list with `sharpe` and `ann_rf` (either may be NA_real_).
#' @noRd
.mom_prepeak_sr <- function(returns_tbl, metrics_row, ann_factor = 12L) {
  if (!"rf_ret" %in% names(returns_tbl)) {
    cli::cli_abort(c(
      "x" = ".mom_prepeak_sharpe(): {.arg returns_tbl} has no {.field rf_ret} column.",
      "i" = "Join a risk-free series onto returns_tbl first -- see {.fn .mom_prepeak_join_rf}."
    ))
  }

  keep <- !is.na(returns_tbl$ret_ls)
  r    <- returns_tbl$ret_ls[keep]
  rf   <- returns_tbl$rf_ret[keep]
  n    <- length(r)
  if (n < 12L) return(list(sharpe = NA_real_, ann_rf = NA_real_))

  blown_up       <- isTRUE(metrics_row$blown_up[[1L]])
  bankrupt_month <- metrics_row$bankrupt_month[[1L]]

  if (blown_up) {
    if (is.na(bankrupt_month) || bankrupt_month <= 1L) return(list(sharpe = NA_real_, ann_rf = NA_real_))
    r  <- r[seq_len(bankrupt_month - 1L)]
    rf <- rf[seq_len(bankrupt_month - 1L)]
  }

  sr <- sharpe_ratio_rf(r, rf, periods_per_year = ann_factor)
  list(sharpe = sr$sharpe, ann_rf = sr$ann_rf)
}

#' Thin wrapper over .mom_prepeak_sr() returning just the Sharpe ratio
#' @return Numeric scalar Sharpe (may be NA_real_).
#' @noRd
.mom_prepeak_sharpe <- function(returns_tbl, metrics_row, ann_factor = 12L) {
  .mom_prepeak_sr(returns_tbl, metrics_row, ann_factor)$sharpe
}

#' Companion accessor to \code{.mom_prepeak_sharpe()}: the annualised
#' risk-free rate used in the same Sharpe computation (#677 slice 4)
#'
#' Published alongside `sharpe` in `mom_prepeak_metrics` /
#' `mom_postpeak_metrics` / `mom_combined_metrics` so QA gate S17
#' (\code{check_leaderboard_sharpe_coherence()}, R/plan_qa_gates.R) can
#' assert \code{sharpe == (cagr - ann_rf) / vol} for every leaderboard row.
#'
#' @return Numeric scalar annualised risk-free rate (may be NA_real_).
#' @noRd
.mom_prepeak_ann_rf <- function(returns_tbl, metrics_row, ann_factor = 12L) {
  .mom_prepeak_sr(returns_tbl, metrics_row, ann_factor)$ann_rf
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
#' Also records SSR + top-5pct stability metrics via
#' [historicaldata::hd_record_stability_metrics()] for each sibling.
#' Returns empty tibble if DBI / duckdb are unavailable.
#'
#' @param strategy_names Tibble from the strategy_names target.
#' @param mom_prepeak_summary Tibble from the mom_prepeak_summary target.
#' @param returns_list Named list of numeric vectors keyed by strategy
#'   code_name (`mom_prepeak`, `mom_postpeak`, `mom_combined`). Each
#'   vector should be the `ret_ls` column from the corresponding
#'   `*_returns` target. May be `NULL` or missing entries — stability
#'   metrics are skipped for that strategy.
#'
#' @return Tibble with columns: strategy_id, run_uuid.
#' @noRd
.mom_prepeak_register_runs <- function(strategy_names, mom_prepeak_summary,
                                       returns_list = list()) {
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

    uu <- historicaldata::hd_run_upsert(
      con,
      strategy_id      = cn,
      partition        = "phase1",
      pipeline_version = "phase1"
    )

    metrics_row <- mom_prepeak_summary[mom_prepeak_summary$strategy == cn, , drop = FALSE]
    if (nrow(metrics_row) == 1L) {
      metric_cols <- setdiff(names(metrics_row), "strategy")
      wide <- metrics_row[, metric_cols, drop = FALSE]
      # Units (#640): see .mom_prepeak_compute_metrics() in
      # packages/historicaldata/R/utils_mom_prepeak_metrics.R — cagr/vol/
      # max_dd are decimal fractions, sharpe is a scale-free ratio,
      # n_months/max_cons_losses/bankrupt_month are counts, avg_dd_days/
      # max_dd_days are day-durations. blown_up/loss_clustered are logical
      # and are auto-skipped by .normalise_metric_long (no unit needed).
      mom_prepeak_units <- c(
        n_months = "count", sharpe = "ratio", cagr = "fraction",
        vol = "fraction", max_dd = "fraction",
        bankrupt_month = "count", avg_dd_days = "days",
        max_dd_days = "days", max_cons_losses = "count"
      )
      historicaldata::hd_metric_record(con, uu, wide, units = mom_prepeak_units)
    }

    # Record SSR + top5pct stability metrics (#400 PR 5/6).
    # Monthly series: w = 36 rolling windows, ann_factor = 12.
    rets <- returns_list[[cn]]
    if (!is.null(rets) && length(rets) > 0L) {
      historicaldata::hd_record_stability_metrics(
        con        = con,
        run_uuid   = uu,
        returns    = rets,
        w          = 36L,
        ann_factor = 12L
      )
    }

    strategy_ids[[i]] <- cn
    run_uuids[[i]]    <- uu
  }

  tibble::tibble(strategy_id = strategy_ids, run_uuid = run_uuids)
}
