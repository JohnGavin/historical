# Commodities Momentum Decomposition Functions
# Test if momentum decomposition works in commodities (Issue #134)
#
# Context: Equity momentum decomposition FAILED (issue #121, #123):
#   - All decomposed variants had Sharpe < 0
#   - Turnover 3.3x higher than baseline
#   - Failure persisted across ALL VIX regimes
#
# Question: Is failure universal, or equity-specific?
#
# Approach: Test simpler decompositions on commodities (37 series, 1992-2026):
#   1. Baseline 12-bar momentum
#   2. Short-term (3-bar) + Long-term (9-bar) decomposition
#   3. Volatility-filtered momentum
#   4. Trend-strength-filtered momentum
#
# Data (#1048 follow-up): the merged universe is DAILY-dominated, not monthly.
#   Measured 2026-11-09 on commodities_raw: 24 Yahoo futures/ETF series print
#   daily (median gap 1 day), 13 FRED/IMF series print monthly (median gap 31
#   days); the backtest date axis has a median gap of 1 day. Every lookback
#   below (12/3/9/30) is therefore a count of OBSERVATIONS (bars, i.e. trading
#   days for the daily series), NOT calendar months, and the performance
#   summary annualises with periods_per_year = 252 (not 12). The strategy
#   itself is unchanged; only the labels and the annualisation were wrong.
#   The `monthly_ret` column name is kept: it is the shared per-observation
#   return contract with hd_commodity_mr_*() (see packages/historicaldata/R/
#   commodities_mean_reversion.R header, #720) and is NOT a monthly return.
# No futures curve is used, so there is no roll yield.


#' Calculate Commodity Returns
#'
#' Compute per-observation returns from commodity prices in long format.
#'
#' The return is value / previous value - 1 on each series' own rows, so it is
#' a DAILY return for the Yahoo series and a monthly one for FRED/IMF series.
#' The column keeps the historical name \code{monthly_ret} (shared with
#' \code{hd_commodity_mr_*()}); it is not a monthly return.
#'
#' @param commodities_data Tibble with columns: date, value, series_id
#'
#' @return Tibble with columns: date, series_id, monthly_ret, log_ret
#'
#' @export
calculate_commodity_returns <- function(commodities_data) {
  library(dplyr)

  commodities_data |>
    arrange(series_id, date) |>
    group_by(series_id) |>
    mutate(
      monthly_ret = value / lag(value) - 1,
      log_ret = log(value / lag(value))
    ) |>
    ungroup() |>
    filter(!is.na(monthly_ret))
}


#' Build Commodity Momentum Signals
#'
#' Create baseline and decomposed momentum signals for commodities.
#'
#' @param returns Tibble with columns: date, series_id, monthly_ret
#' @param lookback Integer. Momentum lookback in observations, i.e. bars
#'   (trading days for daily series; default 12)
#'
#' @return Tibble with columns:
#'   - date, series_id
#'   - mom_12d: Total return over the last \code{lookback} (12) bars
#'   - mom_3d: Return over the last 3 bars
#'   - mom_9d: Return over bars 4-12 back (9 bars)
#'   - volatility_roll: Rolling sd of log returns over min(30, lookback) bars
#'     (for filtering; 12 bars at the default lookback)
#'   - trend_strength: Ratio of (net log return / cumulative abs log returns)
#'
#' @details
#' Decompositions tested:
#'   1. Baseline: ret[t-12:t] bars (control)
#'   2. Short + Long: ret[t-3:t] + ret[t-12:t-3] bars (time decomposition)
#'   3. Vol-filtered: baseline * (1 / volatility) (low-vol preference)
#'   4. Trend-filtered: baseline * trend_strength (smooth trends only)
#'
#' @export
build_commodity_signals <- function(returns, lookback = 12) {
  library(dplyr)
  library(RcppRoll)

  returns |>
    arrange(series_id, date) |>
    group_by(series_id) |>
    mutate(
      # Baseline 12-bar momentum
      mom_12d = roll_prodr(1 + monthly_ret, n = lookback, fill = NA, align = "right") - 1,

      # Short-term (3-bar) and long-term (9-bar) components
      mom_3d = roll_prodr(1 + monthly_ret, n = 3, fill = NA, align = "right") - 1,
      # Long-term: bars 4-12 (9 bars total)
      mom_9d = (roll_prodr(1 + monthly_ret, n = 12, fill = NA, align = "right") /
                       roll_prodr(1 + monthly_ret, n = 3, fill = NA, align = "right")) - 1,

      # Volatility (rolling std dev of log returns over min(30, lookback) bars)
      volatility_roll = roll_sd(log_ret, n = min(30, lookback), fill = NA, align = "right"),

      # Trend strength: ratio of net return to sum of absolute per-bar moves
      # Higher = smoother trend, Lower = choppy/reversals
      # Use log returns for better properties
      cumulative_abs_ret = roll_sum(abs(log_ret), n = lookback, fill = NA, align = "right"),
      net_log_ret = roll_sum(log_ret, n = lookback, fill = NA, align = "right"),
      trend_strength = ifelse(cumulative_abs_ret > 0,
                              abs(net_log_ret) / cumulative_abs_ret,
                              0)
    ) |>
    ungroup() |>
    select(date, series_id, mom_12d, mom_3d, mom_9d,
           volatility_roll, trend_strength)
}


#' Backtest Commodity Momentum Strategies
#'
#' Simulate long-short portfolio returns from commodity momentum signals with
#' transaction costs.
#'
#' @param signals Tibble with columns: date, series_id, mom_12d, mom_3d,
#'   mom_9d, volatility_roll, trend_strength
#' @param returns Tibble with columns: date, series_id, monthly_ret
#' @param cost_bps Numeric. Transaction cost in basis points (default 20 = 0.2%)
#' @param n_long Integer. Number of commodities to long (default 10)
#' @param n_short Integer. Number of commodities to short (default 10)
#'
#' @return Tibble with columns:
#'   - date, strategy
#'   - portfolio_ret, turnover, cost, net_ret
#'
#' @details
#' Strategies tested:
#'   1. baseline: Raw 12-bar momentum (control)
#'   2. short_long: Combine mom_3d + mom_9d (equal weight)
#'   3. vol_filtered: mom_12d / volatility_roll (rank by vol-adjusted signal)
#'   4. trend_filtered: mom_12d * trend_strength (only smooth trends)
#'
#' Transaction costs: 20 bps per trade (commodities are liquid).
#' Portfolio: Long top N, short bottom N by signal, equal-weight within leg.
#'
#' @export
backtest_commodity_momentum <- function(signals,
                                       returns,
                                       cost_bps = 20,
                                       n_long = 10,
                                       n_short = 10) {
  library(dplyr)

  cost_per_trade <- cost_bps / 10000

  # Join signals with the next bar's return (#1048). monthly_ret on the row
  # dated t is the return over bar t, and the signal at t uses data through
  # t, so the signal at t pairs with lead(monthly_ret) on the SAME date t.
  # (Relabelling the row to lag(date) too paired it with the t+2 return.)
  combined <- signals |>
    inner_join(
      returns |>
        group_by(series_id) |>
        arrange(date) |>
        mutate(next_ret = lead(monthly_ret)) |>
        filter(!is.na(next_ret)) |>
        select(series_id, date, next_ret),
      by = c("series_id", "date")
    )

  # Define strategies: each has a signal column
  strategies <- list(
    baseline = "mom_12d",
    short_long = NULL,  # Will compute as combination
    vol_filtered = NULL,  # Will compute as ratio
    trend_filtered = NULL  # Will compute as product
  )

  # Add computed signal columns
  combined <- combined |>
    mutate(
      # Short-term + long-term decomposition (equal weight)
      short_long_signal = 0.5 * mom_3d + 0.5 * mom_9d,

      # Volatility-filtered: divide by volatility (lower vol = higher rank)
      vol_filtered_signal = ifelse(!is.na(volatility_roll) & volatility_roll > 0,
                                   mom_12d / volatility_roll,
                                   NA_real_),

      # Trend-filtered: multiply by trend strength (smoother trends only)
      trend_filtered_signal = mom_12d * trend_strength
    )

  # Backtest each strategy
  results_list <- list()

  for (strat_name in names(strategies)) {
    signal_col <- if (is.null(strategies[[strat_name]])) {
      paste0(strat_name, "_signal")
    } else {
      strategies[[strat_name]]
    }

    # Rank by signal, select top/bottom
    portfolio <- combined |>
      select(date, series_id, signal = !!rlang::sym(signal_col), next_ret) |>
      filter(!is.na(signal)) |>
      group_by(date) |>
      mutate(
        rank = rank(-signal, na.last = "keep", ties.method = "first"),
        n_commodities = n()
      ) |>
      filter(rank <= n_long | rank > (n_commodities - n_short)) |>
      mutate(
        weight = case_when(
          rank <= n_long ~ 1 / (2 * n_long),
          TRUE ~ -1 / (2 * n_short)
        ),
        position = ifelse(rank <= n_long, "long", "short")
      ) |>
      ungroup()

    # Compute returns
    period_returns <- portfolio |>
      group_by(date) |>
      summarise(
        portfolio_ret = sum(weight * next_ret, na.rm = TRUE),
        n_positions = n(),
        .groups = "drop"
      )

    # Compute turnover
    turnover <- portfolio |>
      arrange(series_id, date) |>
      group_by(series_id) |>
      mutate(
        prev_weight = lag(weight, default = 0),
        weight_change = abs(weight - prev_weight)
      ) |>
      group_by(date) |>
      summarise(
        turnover = sum(weight_change, na.rm = TRUE) / 2,
        .groups = "drop"
      )

    # Join and compute costs
    result <- period_returns |>
      left_join(turnover, by = "date") |>
      mutate(
        strategy = strat_name,
        turnover = ifelse(is.na(turnover), 0, turnover),
        cost = turnover * cost_per_trade,
        net_ret = portfolio_ret - cost
      ) |>
      select(date, strategy, portfolio_ret, turnover, cost, net_ret, n_positions)

    results_list[[strat_name]] <- result
  }

  bind_rows(results_list)
}


#' Summarize Commodity Momentum Performance
#'
#' Compute performance metrics for backtested commodity momentum strategies.
#'
#' @param backtest_results Tibble from backtest_commodity_momentum()
#' @param annual_rf Numeric. Annual risk-free rate (default 0.02). Deducted
#'   only when \code{strategy}'s registered basis is \code{"total"}; the
#'   long-short spread here is an excess return, so for the registered label
#'   \code{"Commodity Momentum L/S"} it is ignored (Refs #937).
#' @param periods_per_year Integer. Bars per year used to annualise Sharpe and
#'   return, and to convert \code{annual_rf} to a per-bar rate. Default 252
#'   (trading days): the backtest date axis is daily (#1048 follow-up).
#' @param strategy Single string; a label registered in
#'   \code{hd_return_basis()} (use \code{"Commodity Momentum L/S"}). REQUIRED:
#'   an omitted or unregistered label aborts rather than silently keeping an
#'   rf-deducted Sharpe (fail-loud-not-null).
#'
#' @return Tibble with columns:
#'   - strategy
#'   - n_periods (bars), mean_ret, sd_ret, sharpe (annualised with
#'     \code{periods_per_year}), annual_ret, cumulative_ret
#'   - max_dd, mean_turnover, mean_cost
#'   - gross_sharpe (before costs)
#'
#' @export
summarize_commodity_performance <- function(backtest_results, annual_rf = 0.02,
                                            strategy = NULL,
                                            periods_per_year = 252L) {
  library(dplyr)
  library(purrr)

  if (!is.numeric(periods_per_year) || length(periods_per_year) != 1L ||
      is.na(periods_per_year) || periods_per_year < 1) {
    cli::cli_abort(c(
      "x" = "{.arg periods_per_year} must be a single number >= 1.",
      "i" = "Got {.val {periods_per_year}}."
    ))
  }

  .require_basis_label(strategy, "summarize_commodity_performance")
  # #937: the top-n / bottom-n weights sum to zero, so net_ret is already an
  # excess return; the registry returns 0 for it (rf only for a "total" label).
  period_rf <- hd_rf_for_basis((1 + annual_rf)^(1 / periods_per_year) - 1, strategy)

  backtest_results |>
    group_by(strategy) |>
    summarise(
      n_periods = n(),
      mean_ret = mean(net_ret, na.rm = TRUE),
      sd_ret = sd(net_ret, na.rm = TRUE),
      sharpe = (mean(net_ret, na.rm = TRUE) - period_rf) / sd(net_ret, na.rm = TRUE) *
               sqrt(periods_per_year),
      cumulative_ret = prod(1 + net_ret, na.rm = TRUE) - 1,
      annual_ret = (1 + mean(net_ret, na.rm = TRUE))^periods_per_year - 1,
      mean_turnover = mean(turnover, na.rm = TRUE),
      mean_cost = mean(cost, na.rm = TRUE),
      gross_sharpe = (mean(portfolio_ret, na.rm = TRUE) - period_rf) /
                     sd(portfolio_ret, na.rm = TRUE) * sqrt(periods_per_year),
      .groups = "drop"
    ) |>
    mutate(
      max_dd = map_dbl(strategy, ~{
        rets <- backtest_results |>
          filter(strategy == .x) |>
          pull(net_ret)
        cumrets <- cumprod(1 + rets)
        cummax_val <- cummax(cumrets)
        dd <- (cumrets - cummax_val) / cummax_val
        min(dd, na.rm = TRUE)
      })
    ) |>
    arrange(desc(sharpe))
}
