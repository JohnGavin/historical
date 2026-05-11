# Regime-Dependent Momentum Functions
# Issue #123: Test if momentum decomposition works conditionally by VIX regime
#
# Context: Issue #121 showed ALL decomposed momentum strategies have negative
# Sharpe ratios (-0.34 to -0.39) vs baseline 0.05. This module tests if
# decomposed components work better in specific volatility regimes.

#' Classify VIX Regimes
#'
#' Classify days into calm (VIX<20), elevated (20-30), and spike (>30) regimes.
#'
#' @param vix_daily Tibble with columns: date, vix (VIX level)
#'
#' @return Tibble with columns:
#'   - date
#'   - vix
#'   - regime: "calm", "elevated", or "spike"
#'
#' @details
#' Thresholds based on historical VIX behavior:
#' - Calm: VIX < 20 (normal market conditions)
#' - Elevated: VIX 20-30 (heightened uncertainty)
#' - Spike: VIX > 30 (crisis/panic)
#'
#' @export
classify_vix_regimes <- function(vix_daily) {
  library(dplyr)

  vix_daily |>
    mutate(
      regime = case_when(
        is.na(vix) ~ NA_character_,
        vix < 20 ~ "calm",
        vix <= 30 ~ "elevated",
        TRUE ~ "spike"
      ),
      regime = factor(regime, levels = c("calm", "elevated", "spike"))
    )
}


#' Partition Returns by VIX Regime
#'
#' Split monthly returns into regime-specific subsets based on VIX classification.
#'
#' @param returns Tibble with columns: date, scheme, net_ret, portfolio_ret, ...
#' @param vix_regimes Tibble with columns: date, regime (daily classification)
#'
#' @return Tibble with same columns as returns, plus:
#'   - regime: "calm", "elevated", or "spike"
#'
#' @details
#' Matches monthly returns to regimes by taking the regime that was most
#' prevalent during that month. This avoids look-ahead bias — we use only
#' the VIX regime that was observable during the month.
#'
#' @export
partition_returns_by_regime <- function(returns, vix_regimes) {
  library(dplyr)

  # Convert returns to daily if monthly (join on month)
  returns_with_ym <- returns |>
    mutate(ym = format(date, "%Y-%m"))

  # Convert VIX regimes to monthly (most frequent regime in month)
  vix_monthly <- vix_regimes |>
    filter(!is.na(regime)) |>
    mutate(ym = format(date, "%Y-%m")) |>
    group_by(ym) |>
    # Use modal regime (most common) for the month
    summarise(
      regime = names(sort(table(regime), decreasing = TRUE))[1],
      mean_vix = mean(vix, na.rm = TRUE),
      max_vix = max(vix, na.rm = TRUE),
      n_days = n(),
      .groups = "drop"
    ) |>
    mutate(regime = factor(regime, levels = c("calm", "elevated", "spike")))

  # Join returns with regime
  returns_with_ym |>
    left_join(vix_monthly, by = "ym") |>
    select(-ym)
}


#' Compute Regime-Conditional Performance
#'
#' Calculate performance metrics (Sharpe, return, vol) within each regime.
#'
#' @param strategy_returns Tibble with columns: date, scheme, net_ret, regime
#' @param regime_filter Character. Which regime to analyze: "calm", "elevated", "spike", or "all"
#' @param annual_rf Numeric. Annual risk-free rate (default 0.02)
#'
#' @return Tibble with one row per strategy and regime:
#'   - scheme: Strategy name
#'   - regime: VIX regime
#'   - n_months: Number of months in regime
#'   - mean_ret: Mean monthly return
#'   - sd_ret: Standard deviation
#'   - sharpe: Annualized Sharpe ratio
#'   - annual_ret: Annualized return
#'   - max_dd: Maximum drawdown
#'   - mean_vix: Average VIX level
#'
#' @export
regime_conditional_performance <- function(strategy_returns,
                                          regime_filter = "all",
                                          annual_rf = 0.02) {
  library(dplyr)

  monthly_rf <- (1 + annual_rf)^(1/12) - 1

  # Filter to regime if specified
  if (regime_filter != "all") {
    strategy_returns <- strategy_returns |>
      filter(regime == regime_filter)
  }

  # Compute metrics per strategy and regime
  strategy_returns |>
    filter(!is.na(regime), !is.na(net_ret)) |>
    group_by(scheme, regime) |>
    summarise(
      n_months = n(),
      mean_ret = mean(net_ret, na.rm = TRUE),
      sd_ret = sd(net_ret, na.rm = TRUE),
      sharpe = if (sd_ret > 1e-8) (mean_ret - monthly_rf) / sd_ret * sqrt(12) else NA_real_,
      annual_ret = (1 + mean_ret)^12 - 1,
      cumulative_ret = prod(1 + net_ret, na.rm = TRUE) - 1,
      mean_turnover = mean(turnover, na.rm = TRUE),
      mean_cost = mean(cost, na.rm = TRUE),
      mean_vix = mean(mean_vix, na.rm = TRUE),
      max_vix = max(max_vix, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(
      # Compute max drawdown per strategy-regime
      max_dd = purrr::map2_dbl(scheme, regime, ~{
        rets <- strategy_returns |>
          filter(scheme == .x, regime == .y, !is.na(net_ret)) |>
          arrange(date) |>
          pull(net_ret)
        if (length(rets) < 2) return(NA_real_)
        cumrets <- cumprod(1 + rets)
        cummax_vals <- cummax(cumrets)
        dd <- (cumrets - cummax_vals) / cummax_vals
        min(dd, na.rm = TRUE)
      })
    )
}


#' Compare Binary vs Continuous Regime Allocation
#'
#' Test two allocation approaches:
#' - Binary: 100% exposure in calm, 0% in elevated/spike
#' - Continuous: Scale exposure linearly with VIX (e.g., 100% at VIX=15, 0% at VIX=40)
#'
#' @param returns Tibble with columns: date, scheme, net_ret, regime, mean_vix
#' @param regimes Character vector. Which regimes to use for binary (default: "calm")
#' @param vix_min Numeric. VIX level for 100% exposure (continuous)
#' @param vix_max Numeric. VIX level for 0% exposure (continuous)
#'
#' @return Tibble with columns:
#'   - scheme: Strategy name
#'   - allocation_type: "binary" or "continuous"
#'   - n_months_invested: Months with >0 exposure
#'   - pct_time_invested: Percentage of months invested
#'   - sharpe: Net Sharpe ratio
#'   - annual_ret: Annualized return
#'   - max_dd: Maximum drawdown
#'
#' @export
compare_regime_allocation <- function(returns,
                                     regimes = c("calm"),
                                     vix_min = 15,
                                     vix_max = 40) {
  library(dplyr)

  # Binary allocation: 100% in specified regimes, 0% otherwise
  binary <- returns |>
    group_by(scheme) |>
    arrange(date) |>
    mutate(
      exposure = if_else(regime %in% regimes, 1.0, 0.0),
      allocated_ret = exposure * net_ret,
      allocation_type = "binary"
    ) |>
    ungroup()

  # Continuous allocation: linear scaling based on VIX
  continuous <- returns |>
    group_by(scheme) |>
    arrange(date) |>
    mutate(
      # Linear scaling: 1.0 at vix_min, 0.0 at vix_max
      exposure = pmax(0, pmin(1, (vix_max - mean_vix) / (vix_max - vix_min))),
      allocated_ret = exposure * net_ret,
      allocation_type = "continuous"
    ) |>
    ungroup()

  # Compute metrics for both
  calc_metrics <- function(df) {
    monthly_rf <- (1.02)^(1/12) - 1

    df |>
      group_by(scheme, allocation_type) |>
      summarise(
        n_months = n(),
        n_months_invested = sum(exposure > 0.01, na.rm = TRUE),
        pct_time_invested = mean(exposure > 0.01, na.rm = TRUE) * 100,
        mean_exposure = mean(exposure, na.rm = TRUE),
        mean_ret = mean(allocated_ret, na.rm = TRUE),
        sd_ret = sd(allocated_ret, na.rm = TRUE),
        sharpe = if (sd_ret > 1e-8) (mean_ret - monthly_rf * mean_exposure) / sd_ret * sqrt(12) else NA_real_,
        annual_ret = (1 + mean_ret)^12 - 1,
        cumulative_ret = prod(1 + allocated_ret, na.rm = TRUE) - 1,
        .groups = "drop"
      ) |>
      mutate(
        max_dd = purrr::map2_dbl(scheme, allocation_type, ~{
          rets <- df |>
            filter(scheme == .x, allocation_type == .y) |>
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

  bind_rows(
    calc_metrics(binary),
    calc_metrics(continuous)
  )
}


#' Plot Regime-Conditional Sharpe Ratios
#'
#' Visualize how each strategy performs in different VIX regimes.
#'
#' @param regime_performance Tibble from regime_conditional_performance()
#' @param title Character. Plot title
#'
#' @return A ggplot2 object
#'
#' @export
plot_regime_sharpe <- function(regime_performance,
                               title = "Momentum Strategy Performance by VIX Regime") {
  library(ggplot2)
  library(dplyr)

  # Clean scheme names for display
  plot_data <- regime_performance |>
    mutate(
      scheme_label = recode(
        scheme,
        baseline = "Baseline (Total 12m)",
        paper = "Paper (Style + Industry)",
        data_driven = "Data-Driven (Industry + Stock)",
        conservative = "Conservative (Industry Only)"
      )
    )

  ggplot(plot_data, aes(x = regime, y = sharpe, fill = scheme_label)) +
    geom_col(position = "dodge", width = 0.7) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    geom_text(
      aes(label = ifelse(!is.na(sharpe), sprintf("%.2f", sharpe), "")),
      position = position_dodge(width = 0.7),
      vjust = ifelse(plot_data$sharpe >= 0, -0.5, 1.5),
      size = 3
    ) +
    labs(
      title = title,
      subtitle = "Net-of-cost Sharpe ratio by volatility regime",
      x = "VIX Regime",
      y = "Sharpe Ratio",
      fill = "Strategy"
    ) +
    scale_fill_viridis_d(option = "plasma", begin = 0.2, end = 0.9) +
    theme_minimal() +
    theme(
      legend.position = "bottom",
      legend.title = element_blank(),
      panel.grid.major.x = element_blank()
    )
}


#' Plot Cumulative Returns by Regime Period
#'
#' Show cumulative returns with shading for different VIX regimes.
#'
#' @param strategy_returns Tibble with columns: date, scheme, net_ret, regime
#' @param highlight_scheme Character. Which strategy to highlight (default: "paper")
#'
#' @return A ggplot2 object
#'
#' @export
plot_regime_cumulative <- function(strategy_returns,
                                  highlight_scheme = "paper") {
  library(ggplot2)
  library(dplyr)
  library(tidyr)

  # Compute cumulative returns per strategy
  cumulative_data <- strategy_returns |>
    filter(!is.na(net_ret)) |>
    group_by(scheme) |>
    arrange(date) |>
    mutate(cumulative = cumprod(1 + net_ret)) |>
    ungroup() |>
    mutate(
      scheme_label = recode(
        scheme,
        baseline = "Baseline",
        paper = "Paper",
        data_driven = "Data-Driven",
        conservative = "Conservative"
      )
    )

  # Create regime shading bands
  regime_bands <- strategy_returns |>
    filter(!is.na(regime)) |>
    arrange(date) |>
    mutate(
      regime_change = regime != lag(regime, default = first(regime)),
      regime_block = cumsum(regime_change)
    ) |>
    group_by(regime_block, regime) |>
    summarise(
      xmin = min(date),
      xmax = max(date),
      .groups = "drop"
    ) |>
    filter(regime != "calm")  # Only shade elevated and spike

  ggplot(cumulative_data, aes(x = date, y = cumulative, color = scheme_label)) +
    # Regime shading
    geom_rect(
      data = regime_bands,
      inherit.aes = FALSE,
      aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf, fill = regime),
      alpha = 0.15
    ) +
    scale_fill_manual(
      values = c(elevated = "orange", spike = "red"),
      guide = guide_legend(title = "VIX Regime")
    ) +
    # Cumulative returns
    geom_line(linewidth = 0.8, alpha = 0.7) +
    scale_y_log10(labels = scales::dollar) +
    scale_color_viridis_d(option = "plasma", begin = 0.2, end = 0.9) +
    labs(
      title = "Cumulative Returns: Momentum Decomposition by VIX Regime",
      subtitle = "Shaded areas: orange = elevated VIX (20-30), red = spike (>30)",
      x = NULL,
      y = "Growth of $1 (Log Scale)",
      color = "Strategy"
    ) +
    theme_minimal() +
    theme(
      legend.position = "bottom",
      legend.box = "vertical"
    )
}
