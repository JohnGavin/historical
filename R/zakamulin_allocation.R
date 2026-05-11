# Zakamulin Continuous Regime Allocation
# Issue #123 follow-up: Implement Zakamulin's continuous allocation method
#
# Reference: Zakamulin (2014) "Market Timing with a Robust Megatrend-Filter"
#
# Context: Issue #123 found baseline momentum in VIX calm regime (VIX <20) has
# Sharpe 0.63 vs always-invested 0.05. Calm regime occurs 65% of time.
# This module implements continuous allocation to exploit regime information.

#' Calculate Regime Signal from VIX
#'
#' Transform raw VIX level into a regime confidence signal.
#'
#' @param vix_daily Tibble with columns: date, vix
#' @param signal_type Character. Type of signal:
#'   - "raw": Use VIX level directly
#'   - "relative": VIX / VIX_MA(63)
#'   - "percentile": VIX percentile rank over rolling window
#' @param window_days Integer. Window for moving average or percentile (default 252 = 1 year)
#'
#' @return Tibble with columns:
#'   - date
#'   - vix
#'   - signal: Regime signal (higher = more volatile)
#'
#' @details
#' Raw signal uses VIX level directly. This is simple and interpretable.
#' Relative signal divides VIX by its moving average, capturing deviations from trend.
#' Percentile signal converts VIX to its rank over a rolling window, making it adaptive.
#'
#' @export
calculate_regime_signal <- function(vix_daily,
                                   signal_type = c("raw", "relative", "percentile"),
                                   window_days = 252) {
  library(dplyr)
  library(RcppRoll)

  signal_type <- match.arg(signal_type)

  vix_with_signal <- vix_daily |>
    arrange(date)

  if (signal_type == "raw") {
    # Simple: use VIX level directly
    vix_with_signal <- vix_with_signal |>
      mutate(signal = vix)

  } else if (signal_type == "relative") {
    # VIX relative to its moving average
    vix_with_signal <- vix_with_signal |>
      mutate(
        vix_ma = roll_mean(vix, n = window_days, align = "right", fill = NA),
        signal = vix / vix_ma
      )

  } else if (signal_type == "percentile") {
    # VIX percentile rank over rolling window
    vix_with_signal <- vix_with_signal |>
      mutate(
        signal = slider::slide_dbl(
          vix,
          ~{
            if (all(is.na(.x)) || length(.x) < 2) return(NA_real_)
            rank(.x[length(.x)]) / length(.x)
          },
          .before = window_days - 1,
          .after = 0,
          .complete = FALSE
        )
      )
  }

  vix_with_signal |>
    select(date, vix, signal)
}


#' Compute Continuous Allocation from Regime Signal
#'
#' Map regime signal to portfolio allocation (0-100%).
#'
#' @param regime_signal Tibble with columns: date, signal
#' @param allocation_fn Character. Allocation function:
#'   - "linear": Linear scaling between thresholds
#'   - "sigmoid": Smooth sigmoid transition
#'   - "step": Binary step function
#'   - "piecewise": Piecewise linear with multiple breakpoints
#' @param params List. Parameters for allocation function (function-specific)
#'
#' @return Tibble with columns:
#'   - date
#'   - signal
#'   - allocation: Portfolio exposure (0 = all cash, 1 = full investment)
#'
#' @details
#' Linear: params = list(low = 15, high = 40) → 100% at VIX=15, 0% at VIX=40
#' Sigmoid: params = list(center = 25, steepness = 0.2) → smooth S-curve
#' Step: params = list(threshold = 20) → 100% if VIX < 20, else 0%
#' Piecewise: params = list(breakpoints = c(15, 20, 30, 40), allocations = c(1.0, 0.8, 0.3, 0.0))
#'
#' @export
compute_continuous_allocation <- function(regime_signal,
                                         allocation_fn = c("linear", "sigmoid", "step", "piecewise"),
                                         params = list()) {
  library(dplyr)

  allocation_fn <- match.arg(allocation_fn)

  if (allocation_fn == "linear") {
    # Default: 100% at VIX=15, 0% at VIX=40
    low <- params$low %||% 15
    high <- params$high %||% 40

    regime_signal |>
      mutate(
        allocation = pmax(0, pmin(1, (high - signal) / (high - low)))
      )

  } else if (allocation_fn == "sigmoid") {
    # Smooth sigmoid: allocation = 1 / (1 + exp((signal - center) / steepness))
    center <- params$center %||% 25
    steepness <- params$steepness %||% 5

    regime_signal |>
      mutate(
        allocation = 1 / (1 + exp((signal - center) / steepness))
      )

  } else if (allocation_fn == "step") {
    # Binary step function
    threshold <- params$threshold %||% 20

    regime_signal |>
      mutate(
        allocation = if_else(signal < threshold, 1.0, 0.0)
      )

  } else if (allocation_fn == "piecewise") {
    # Piecewise linear with multiple breakpoints
    breakpoints <- params$breakpoints %||% c(15, 20, 30, 40)
    allocations <- params$allocations %||% c(1.0, 0.8, 0.3, 0.0)

    if (length(breakpoints) != length(allocations)) {
      stop("Breakpoints and allocations must have same length")
    }

    regime_signal |>
      mutate(
        allocation = approx(
          x = breakpoints,
          y = allocations,
          xout = signal,
          method = "linear",
          rule = 2  # Extend endpoints
        )$y
      )
  }
}


#' Apply Regime Allocation to Portfolio Returns
#'
#' Scale portfolio returns by allocation weights.
#'
#' @param portfolio_returns Tibble with columns: date, net_ret, ...
#' @param allocation Tibble with columns: date, allocation
#'
#' @return Tibble with original columns plus:
#'   - allocation: Portfolio exposure at each date
#'   - allocated_ret: net_ret * allocation (return after regime scaling)
#'
#' @details
#' When allocation = 1.0, full strategy return is realized.
#' When allocation = 0.0, return is 0 (100% cash, assuming 0% cash rate).
#' Intermediate allocations scale proportionally.
#'
#' @export
apply_regime_allocation <- function(portfolio_returns, allocation) {
  library(dplyr)

  # Join returns with allocation (by date or month)
  # Handle monthly returns (from backtest) with daily allocation (from VIX)
  returns_with_ym <- portfolio_returns |>
    mutate(ym = format(date, "%Y-%m"))

  allocation_monthly <- allocation |>
    mutate(ym = format(date, "%Y-%m")) |>
    group_by(ym) |>
    # Use month-end allocation (most recent)
    arrange(date) |>
    slice_tail(n = 1) |>
    ungroup() |>
    select(ym, allocation, signal)

  returns_with_ym |>
    left_join(allocation_monthly, by = "ym") |>
    mutate(
      allocation = coalesce(allocation, 1.0),  # Default to full allocation if missing
      allocated_ret = net_ret * allocation
    ) |>
    select(-ym)
}


#' Backtest Regime-Aware Momentum
#'
#' Full pipeline: signal → allocation → backtest.
#'
#' @param signals Tibble with momentum signals (from build_optimized_signals)
#' @param stock_returns Tibble with monthly stock returns
#' @param vix_daily Tibble with daily VIX data
#' @param signal_type Character. Regime signal type
#' @param allocation_fn Character. Allocation function
#' @param allocation_params List. Parameters for allocation function
#' @param n_long Integer. Number of long positions
#' @param n_short Integer. Number of short positions
#' @param cost_per_trade Numeric. Cost per trade (default 0.00153)
#' @param leverage Numeric. Leverage multiplier (default 1)
#'
#' @return Tibble with columns:
#'   - date
#'   - scheme: Strategy name
#'   - signal_type: Regime signal type
#'   - allocation_fn: Allocation function
#'   - net_ret: Net return after costs
#'   - allocated_ret: Return after regime allocation
#'   - allocation: Portfolio exposure
#'   - signal: Regime signal value
#'   - turnover, cost: Trading metrics
#'
#' @details
#' This is the main entry point for backtesting regime-aware momentum.
#' It chains together signal calculation, allocation computation, and
#' return scaling.
#'
#' @export
backtest_regime_momentum <- function(signals,
                                    stock_returns,
                                    vix_daily,
                                    signal_type = "raw",
                                    allocation_fn = "linear",
                                    allocation_params = list(),
                                    n_long = 50,
                                    n_short = 50,
                                    cost_per_trade = 0.00153,
                                    leverage = 1) {
  library(dplyr)
  source(here::here("R/momentum_decomposition.R"))

  # 1. Calculate regime signal
  regime_signal <- calculate_regime_signal(
    vix_daily,
    signal_type = signal_type
  )

  # 2. Compute allocation
  allocation <- compute_continuous_allocation(
    regime_signal,
    allocation_fn = allocation_fn,
    params = allocation_params
  )

  # 3. Backtest momentum (standard)
  backtest_raw <- backtest_momentum_signals(
    signals = signals,
    stock_returns = stock_returns,
    n_long = n_long,
    n_short = n_short,
    cost_per_trade = cost_per_trade,
    leverage = leverage
  )

  # 4. Apply allocation
  backtest_allocated <- apply_regime_allocation(
    backtest_raw,
    allocation
  )

  # 5. Add metadata
  backtest_allocated |>
    mutate(
      signal_type = signal_type,
      allocation_fn = allocation_fn
    )
}


#' Summarize Regime Allocation Performance
#'
#' Compute performance metrics for regime-allocated strategies.
#'
#' @param backtest_results Tibble from backtest_regime_momentum()
#' @param annual_rf Numeric. Annual risk-free rate (default 0.02)
#'
#' @return Tibble with one row per strategy variant:
#'   - scheme: Strategy name
#'   - signal_type: Regime signal type
#'   - allocation_fn: Allocation function
#'   - n_months: Number of months
#'   - mean_allocation: Average portfolio exposure
#'   - sharpe: Net-of-cost Sharpe ratio
#'   - sharpe_allocated: Sharpe after regime allocation
#'   - annual_ret: Annualized return
#'   - annual_ret_allocated: Annualized return after allocation
#'   - max_dd: Maximum drawdown
#'   - max_dd_allocated: Max drawdown after allocation
#'
#' @export
summarize_regime_allocation <- function(backtest_results, annual_rf = 0.02) {
  library(dplyr)

  monthly_rf <- (1 + annual_rf)^(1/12) - 1

  backtest_results |>
    group_by(scheme, signal_type, allocation_fn) |>
    summarise(
      n_months = n(),
      mean_allocation = mean(allocation, na.rm = TRUE),
      pct_invested = mean(allocation > 0.01, na.rm = TRUE) * 100,

      # Unallocated (standard backtest)
      mean_ret = mean(net_ret, na.rm = TRUE),
      sd_ret = sd(net_ret, na.rm = TRUE),
      sharpe = if (sd_ret > 1e-8) (mean_ret - monthly_rf) / sd_ret * sqrt(12) else NA_real_,
      annual_ret = (1 + mean_ret)^12 - 1,

      # Allocated (regime-aware)
      mean_ret_allocated = mean(allocated_ret, na.rm = TRUE),
      sd_ret_allocated = sd(allocated_ret, na.rm = TRUE),
      sharpe_allocated = if (sd_ret_allocated > 1e-8) (mean_ret_allocated - monthly_rf * mean_allocation) / sd_ret_allocated * sqrt(12) else NA_real_,
      annual_ret_allocated = (1 + mean_ret_allocated)^12 - 1,

      .groups = "drop"
    ) |>
    mutate(
      # Compute max drawdowns
      max_dd = purrr::pmap_dbl(list(scheme, signal_type, allocation_fn), ~{
        rets <- backtest_results |>
          filter(scheme == ..1, signal_type == ..2, allocation_fn == ..3) |>
          arrange(date) |>
          pull(net_ret)
        if (length(rets) < 2) return(NA_real_)
        cumrets <- cumprod(1 + rets)
        cummax_vals <- cummax(cumrets)
        dd <- (cumrets - cummax_vals) / cummax_vals
        min(dd, na.rm = TRUE)
      }),
      max_dd_allocated = purrr::pmap_dbl(list(scheme, signal_type, allocation_fn), ~{
        rets <- backtest_results |>
          filter(scheme == ..1, signal_type == ..2, allocation_fn == ..3) |>
          arrange(date) |>
          pull(allocated_ret)
        if (length(rets) < 2) return(NA_real_)
        cumrets <- cumprod(1 + rets)
        cummax_vals <- cummax(cumrets)
        dd <- (cumrets - cummax_vals) / cummax_vals
        min(dd, na.rm = TRUE)
      })
    )
}
