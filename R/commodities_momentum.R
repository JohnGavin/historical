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
#   1. Baseline 12-month momentum
#   2. Short-term (3m) + Long-term (9m) decomposition
#   3. Volatility-filtered momentum
#   4. Trend-strength-filtered momentum
#
# Data: Monthly spot/index prices only (no futures curve, so no roll yield).
# Universe: 37 commodity series from FRED/IMF via fred_imf source.


#' Calculate Commodity Returns
#'
#' Compute monthly returns from commodity prices in long format.
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
#' @param lookback Integer. Momentum lookback in months (default 12)
#'
#' @return Tibble with columns:
#'   - date, series_id
#'   - baseline_12m: Total 12-month return
#'   - short_term_3m: 3-month component
#'   - long_term_9m: 9-month component (months 4-12)
#'   - volatility_30d: Rolling volatility (for filtering)
#'   - trend_strength: Ratio of (12m ret / cumulative abs returns)
#'
#' @details
#' Decompositions tested:
#'   1. Baseline: ret[t-12:t] (control)
#'   2. Short + Long: ret[t-3:t] + ret[t-12:t-3] (time decomposition)
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
      # Baseline 12-month momentum
      baseline_12m = roll_prodr(1 + monthly_ret, n = lookback, fill = NA, align = "right") - 1,

      # Short-term (3m) and long-term (9m) components
      short_term_3m = roll_prodr(1 + monthly_ret, n = 3, fill = NA, align = "right") - 1,
      # Long-term: months 4-12 (9 months total)
      long_term_9m = (roll_prodr(1 + monthly_ret, n = 12, fill = NA, align = "right") /
                       roll_prodr(1 + monthly_ret, n = 3, fill = NA, align = "right")) - 1,

      # Volatility (rolling 30-month std dev of log returns)
      volatility_30m = roll_sd(log_ret, n = min(30, lookback), fill = NA, align = "right"),

      # Trend strength: ratio of net return to sum of absolute monthly moves
      # Higher = smoother trend, Lower = choppy/reversals
      # Use log returns for better properties
      cumulative_abs_ret = roll_sum(abs(log_ret), n = lookback, fill = NA, align = "right"),
      net_log_ret = roll_sum(log_ret, n = lookback, fill = NA, align = "right"),
      trend_strength = ifelse(cumulative_abs_ret > 0,
                              abs(net_log_ret) / cumulative_abs_ret,
                              0)
    ) |>
    ungroup() |>
    select(date, series_id, baseline_12m, short_term_3m, long_term_9m,
           volatility_30m, trend_strength)
}


#' Backtest Commodity Momentum Strategies
#'
#' Simulate long-short portfolio returns from commodity momentum signals with
#' transaction costs.
#'
#' @param signals Tibble with columns: date, series_id, baseline_12m, short_term_3m,
#'   long_term_9m, volatility_30m, trend_strength
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
#'   1. baseline: Raw 12-month momentum (control)
#'   2. short_long: Combine short_term_3m + long_term_9m (equal weight)
#'   3. vol_filtered: baseline_12m / volatility_30m (rank by vol-adjusted signal)
#'   4. trend_filtered: baseline_12m * trend_strength (only smooth trends)
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

  # Join signals with next month's returns
  combined <- signals |>
    inner_join(
      returns |>
        group_by(series_id) |>
        arrange(date) |>
        mutate(date_lag = lag(date),
               next_ret = lead(monthly_ret)) |>
        filter(!is.na(date_lag), !is.na(next_ret)) |>
        select(series_id, date = date_lag, next_ret),
      by = c("series_id", "date")
    )

  # Define strategies: each has a signal column
  strategies <- list(
    baseline = "baseline_12m",
    short_long = NULL,  # Will compute as combination
    vol_filtered = NULL,  # Will compute as ratio
    trend_filtered = NULL  # Will compute as product
  )

  # Add computed signal columns
  combined <- combined |>
    mutate(
      # Short-term + long-term decomposition (equal weight)
      short_long_signal = 0.5 * short_term_3m + 0.5 * long_term_9m,

      # Volatility-filtered: divide by volatility (lower vol = higher rank)
      vol_filtered_signal = ifelse(!is.na(volatility_30m) & volatility_30m > 0,
                                   baseline_12m / volatility_30m,
                                   NA_real_),

      # Trend-filtered: multiply by trend strength (smoother trends only)
      trend_filtered_signal = baseline_12m * trend_strength
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
    monthly_returns <- portfolio |>
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
    result <- monthly_returns |>
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
#' @param annual_rf Numeric. Annual risk-free rate (default 0.02)
#'
#' @return Tibble with columns:
#'   - strategy
#'   - n_months, mean_ret, sd_ret, sharpe, annual_ret, cumulative_ret
#'   - max_dd, mean_turnover, mean_cost
#'   - gross_sharpe (before costs)
#'
#' @export
summarize_commodity_performance <- function(backtest_results, annual_rf = 0.02) {
  library(dplyr)
  library(purrr)

  monthly_rf <- (1 + annual_rf)^(1/12) - 1

  backtest_results |>
    group_by(strategy) |>
    summarise(
      n_months = n(),
      mean_ret = mean(net_ret, na.rm = TRUE),
      sd_ret = sd(net_ret, na.rm = TRUE),
      sharpe = (mean(net_ret, na.rm = TRUE) - monthly_rf) / sd(net_ret, na.rm = TRUE) * sqrt(12),
      cumulative_ret = prod(1 + net_ret, na.rm = TRUE) - 1,
      annual_ret = (1 + mean(net_ret, na.rm = TRUE))^12 - 1,
      mean_turnover = mean(turnover, na.rm = TRUE),
      mean_cost = mean(cost, na.rm = TRUE),
      gross_sharpe = (mean(portfolio_ret, na.rm = TRUE) - monthly_rf) /
                     sd(portfolio_ret, na.rm = TRUE) * sqrt(12),
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
