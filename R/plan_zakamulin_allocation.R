# Targets Plan: Zakamulin Continuous Regime Allocation
# Issue #123 follow-up: Implement Zakamulin's continuous allocation method
#
# Context: Issue #123 found baseline momentum in VIX calm regime (VIX <20) has
# Sharpe 0.63 vs always-invested 0.05. This plan implements continuous allocation
# to dynamically adjust exposure based on VIX regime.
#
# Reference: Zakamulin (2014) "Market Timing with a Robust Megatrend-Filter"

plan_zakamulin_allocation <- function() {
  list(
    # === REGIME SIGNAL VARIANTS ===

    # 1. Raw VIX signal
    tar_target(
      zak_signal_raw,
      {
        source(here::here("R/zakamulin_allocation.R"))
        calculate_regime_signal(vix_daily, signal_type = "raw")
      }
    ),

    # 2. Relative VIX signal (VIX / VIX_MA)
    tar_target(
      zak_signal_relative,
      {
        source(here::here("R/zakamulin_allocation.R"))
        calculate_regime_signal(vix_daily, signal_type = "relative", window_days = 63)
      }
    ),

    # 3. Percentile rank signal
    tar_target(
      zak_signal_percentile,
      {
        source(here::here("R/zakamulin_allocation.R"))
        calculate_regime_signal(vix_daily, signal_type = "percentile", window_days = 252)
      }
    ),


    # === ALLOCATION FUNCTIONS (RAW VIX SIGNAL) ===

    # 4. Linear allocation (15-40 range)
    tar_target(
      zak_alloc_linear,
      {
        source(here::here("R/zakamulin_allocation.R"))
        compute_continuous_allocation(
          zak_signal_raw,
          allocation_fn = "linear",
          params = list(low = 15, high = 40)
        )
      }
    ),

    # 5. Sigmoid allocation (smooth transition)
    tar_target(
      zak_alloc_sigmoid,
      {
        source(here::here("R/zakamulin_allocation.R"))
        compute_continuous_allocation(
          zak_signal_raw,
          allocation_fn = "sigmoid",
          params = list(center = 25, steepness = 5)
        )
      }
    ),

    # 6. Step allocation (binary at VIX=20, baseline from #123)
    tar_target(
      zak_alloc_step,
      {
        source(here::here("R/zakamulin_allocation.R"))
        compute_continuous_allocation(
          zak_signal_raw,
          allocation_fn = "step",
          params = list(threshold = 20)
        )
      }
    ),

    # 7. Piecewise allocation (multiple breakpoints)
    tar_target(
      zak_alloc_piecewise,
      {
        source(here::here("R/zakamulin_allocation.R"))
        compute_continuous_allocation(
          zak_signal_raw,
          allocation_fn = "piecewise",
          params = list(
            breakpoints = c(15, 20, 30, 40),
            allocations = c(1.0, 0.8, 0.3, 0.0)
          )
        )
      }
    ),


    # === BACKTEST: BASELINE MOMENTUM WITH REGIME ALLOCATION ===
    # Focus on baseline (total 12m) since it has best performance in calm regime

    # 8. Extract baseline signals only
    tar_target(
      zak_baseline_signals,
      {
        optimized_signals |>
          filter(scheme == "baseline")
      }
    ),

    # 9. Backtest with linear allocation
    tar_target(
      zak_backtest_linear,
      {
        source(here::here("R/zakamulin_allocation.R"))
        backtest_regime_momentum(
          signals = zak_baseline_signals,
          stock_returns = stock_returns_monthly,
          vix_daily = vix_daily,
          signal_type = "raw",
          allocation_fn = "linear",
          allocation_params = list(low = 15, high = 40),
          n_long = 50,
          n_short = 50,
          cost_per_trade = 0.00153
        )
      }
    ),

    # 10. Backtest with sigmoid allocation
    tar_target(
      zak_backtest_sigmoid,
      {
        source(here::here("R/zakamulin_allocation.R"))
        backtest_regime_momentum(
          signals = zak_baseline_signals,
          stock_returns = stock_returns_monthly,
          vix_daily = vix_daily,
          signal_type = "raw",
          allocation_fn = "sigmoid",
          allocation_params = list(center = 25, steepness = 5),
          n_long = 50,
          n_short = 50,
          cost_per_trade = 0.00153
        )
      }
    ),

    # 11. Backtest with step allocation (baseline from #123)
    tar_target(
      zak_backtest_step,
      {
        source(here::here("R/zakamulin_allocation.R"))
        backtest_regime_momentum(
          signals = zak_baseline_signals,
          stock_returns = stock_returns_monthly,
          vix_daily = vix_daily,
          signal_type = "raw",
          allocation_fn = "step",
          allocation_params = list(threshold = 20),
          n_long = 50,
          n_short = 50,
          cost_per_trade = 0.00153
        )
      }
    ),

    # 12. Backtest with piecewise allocation
    tar_target(
      zak_backtest_piecewise,
      {
        source(here::here("R/zakamulin_allocation.R"))
        backtest_regime_momentum(
          signals = zak_baseline_signals,
          stock_returns = stock_returns_monthly,
          vix_daily = vix_daily,
          signal_type = "raw",
          allocation_fn = "piecewise",
          allocation_params = list(
            breakpoints = c(15, 20, 30, 40),
            allocations = c(1.0, 0.8, 0.3, 0.0)
          ),
          n_long = 50,
          n_short = 50,
          cost_per_trade = 0.00153
        )
      }
    ),


    # === PERFORMANCE COMPARISON ===

    # 13. Combine all backtest results
    tar_target(
      zak_all_backtests,
      {
        bind_rows(
          zak_backtest_linear,
          zak_backtest_sigmoid,
          zak_backtest_step,
          zak_backtest_piecewise
        )
      }
    ),

    # 14. Performance summary table
    tar_target(
      zak_performance_table,
      {
        source(here::here("R/zakamulin_allocation.R"))

        summarize_regime_allocation(zak_all_backtests) |>
          mutate(
            allocation_label = recode(
              allocation_fn,
              linear = "Linear (15-40)",
              sigmoid = "Sigmoid (center=25)",
              step = "Step (VIX<20)",
              piecewise = "Piecewise (4 levels)"
            )
          ) |>
          select(
            `Allocation Method` = allocation_label,
            `Mean Exposure` = mean_allocation,
            `% Time Invested` = pct_invested,
            `Sharpe (No Regime)` = sharpe,
            `Sharpe (Regime-Aware)` = sharpe_allocated,
            `Annual Ret (Regime)` = annual_ret_allocated,
            `Max DD (Regime)` = max_dd_allocated,
            `N Months` = n_months
          ) |>
          mutate(
            `Mean Exposure` = round(`Mean Exposure`, 2),
            `% Time Invested` = round(`% Time Invested`, 1),
            `Sharpe (No Regime)` = round(`Sharpe (No Regime)`, 2),
            `Sharpe (Regime-Aware)` = round(`Sharpe (Regime-Aware)`, 2),
            `Annual Ret (Regime)` = round(`Annual Ret (Regime)` * 100, 1),
            `Max DD (Regime)` = round(`Max DD (Regime)` * 100, 1)
          ) |>
          arrange(desc(`Sharpe (Regime-Aware)`))
      }
    ),

    # 15. Regime transition analysis
    tar_target(
      zak_transition_analysis,
      {
        # How often does allocation change, and by how much?
        zak_all_backtests |>
          group_by(allocation_fn) |>
          arrange(date) |>
          mutate(
            allocation_change = abs(allocation - lag(allocation, default = first(allocation))),
            large_change = allocation_change > 0.2  # >20% allocation change
          ) |>
          summarise(
            n_months = n(),
            mean_change = mean(allocation_change, na.rm = TRUE),
            median_change = median(allocation_change, na.rm = TRUE),
            pct_large_changes = mean(large_change, na.rm = TRUE) * 100,
            n_large_changes = sum(large_change, na.rm = TRUE),
            .groups = "drop"
          ) |>
          mutate(
            allocation_label = recode(
              allocation_fn,
              linear = "Linear (15-40)",
              sigmoid = "Sigmoid (center=25)",
              step = "Step (VIX<20)",
              piecewise = "Piecewise (4 levels)"
            )
          ) |>
          select(
            `Allocation Method` = allocation_label,
            `N Months` = n_months,
            `Mean Change` = mean_change,
            `Median Change` = median_change,
            `% Large Changes` = pct_large_changes,
            `N Large Changes` = n_large_changes
          ) |>
          mutate(
            across(c(`Mean Change`, `Median Change`), ~round(.x, 3)),
            `% Large Changes` = round(`% Large Changes`, 1)
          )
      }
    ),

    # 16. Cumulative returns plot with regime shading
    tar_target(
      zak_cumulative_plot,
      {
        library(ggplot2)
        library(dplyr)

        # Compute cumulative returns
        cumulative <- zak_all_backtests |>
          group_by(allocation_fn) |>
          arrange(date) |>
          mutate(
            cumulative_allocated = cumprod(1 + allocated_ret),
            allocation_label = recode(
              allocation_fn,
              linear = "Linear (15-40)",
              sigmoid = "Sigmoid (center=25)",
              step = "Step (VIX<20)",
              piecewise = "Piecewise (4 levels)"
            )
          ) |>
          ungroup()

        # VIX regime bands for shading
        vix_regimes <- classify_vix_regimes(vix_daily)
        regime_bands <- vix_regimes |>
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
          filter(regime %in% c("elevated", "spike"))

        ggplot() +
          # Regime shading
          geom_rect(
            data = regime_bands,
            aes(xmin = xmin, xmax = xmax, ymin = 0, ymax = Inf, fill = regime),
            alpha = 0.15
          ) +
          scale_fill_manual(
            values = c(elevated = "orange", spike = "red"),
            guide = guide_legend(title = "VIX Regime", order = 2)
          ) +
          # Cumulative returns
          geom_line(
            data = cumulative,
            aes(x = date, y = cumulative_allocated, color = allocation_label),
            linewidth = 0.9
          ) +
          scale_y_log10(labels = scales::dollar) +
          scale_color_viridis_d(option = "plasma", begin = 0.2, end = 0.9) +
          labs(
            title = "Zakamulin Regime Allocation: Cumulative Returns",
            subtitle = "Baseline momentum (total 12m) with continuous VIX-based allocation. Shading: orange=elevated VIX (20-30), red=spike (>30)",
            x = NULL,
            y = "Growth of $1 (Log Scale)",
            color = "Allocation Method"
          ) +
          theme_minimal() +
          theme(
            legend.position = "bottom",
            legend.box = "vertical",
            legend.title = element_text(face = "bold", size = 9)
          ) +
          guides(
            color = guide_legend(order = 1, nrow = 2),
            fill = guide_legend(order = 2)
          )
      }
    ),

    # 17. Allocation time series plot
    tar_target(
      zak_allocation_plot,
      {
        library(ggplot2)
        library(dplyr)

        # Extract allocation over time
        allocation_ts <- zak_all_backtests |>
          select(date, allocation_fn, allocation, signal) |>
          distinct() |>
          mutate(
            allocation_label = recode(
              allocation_fn,
              linear = "Linear (15-40)",
              sigmoid = "Sigmoid (center=25)",
              step = "Step (VIX<20)",
              piecewise = "Piecewise (4 levels)"
            )
          )

        ggplot(allocation_ts, aes(x = date, y = allocation, color = allocation_label)) +
          geom_line(linewidth = 0.8, alpha = 0.8) +
          geom_hline(yintercept = c(0, 0.5, 1), linetype = "dashed", color = "gray50", linewidth = 0.3) +
          scale_y_continuous(
            labels = scales::percent_format(),
            limits = c(0, 1),
            breaks = seq(0, 1, 0.25)
          ) +
          scale_color_viridis_d(option = "plasma", begin = 0.2, end = 0.9) +
          labs(
            title = "Zakamulin Allocation Methods: Portfolio Exposure Over Time",
            subtitle = "100% = full investment, 0% = all cash",
            x = NULL,
            y = "Portfolio Allocation",
            color = "Method"
          ) +
          theme_minimal() +
          theme(
            legend.position = "bottom",
            legend.title = element_blank()
          )
      }
    ),

    # 18. VIX vs Allocation scatter (show allocation function shapes)
    tar_target(
      zak_vix_allocation_scatter,
      {
        library(ggplot2)
        library(dplyr)

        # Sample every 21 days to reduce overplotting
        scatter_data <- zak_all_backtests |>
          select(date, allocation_fn, allocation, signal) |>
          distinct() |>
          group_by(allocation_fn) |>
          filter(row_number() %% 21 == 1) |>
          ungroup() |>
          mutate(
            allocation_label = recode(
              allocation_fn,
              linear = "Linear (15-40)",
              sigmoid = "Sigmoid (center=25)",
              step = "Step (VIX<20)",
              piecewise = "Piecewise (4 levels)"
            )
          )

        ggplot(scatter_data, aes(x = signal, y = allocation, color = allocation_label)) +
          geom_point(alpha = 0.4, size = 1.5) +
          geom_smooth(method = "loess", se = FALSE, linewidth = 1.2, span = 0.3) +
          scale_y_continuous(
            labels = scales::percent_format(),
            limits = c(0, 1)
          ) +
          scale_color_viridis_d(option = "plasma", begin = 0.2, end = 0.9) +
          labs(
            title = "Allocation Function Shapes: VIX → Portfolio Exposure",
            subtitle = "Each point = one month (sampled). Smooth line shows function shape.",
            x = "VIX Level",
            y = "Portfolio Allocation",
            color = "Method"
          ) +
          theme_minimal() +
          theme(
            legend.position = "bottom",
            legend.title = element_blank()
          )
      }
    ),

    # 19. Key finding summary
    tar_target(
      zak_summary,
      {
        library(dplyr)

        perf <- summarize_regime_allocation(zak_all_backtests)

        best <- perf |>
          arrange(desc(sharpe_allocated)) |>
          slice(1)

        baseline_sharpe <- perf |>
          pull(sharpe) |>
          first() |>
          round(2)

        list(
          baseline_sharpe_no_regime = baseline_sharpe,
          best_method = best$allocation_fn,
          best_sharpe = round(best$sharpe_allocated, 2),
          improvement = round(best$sharpe_allocated - baseline_sharpe, 2),
          pct_improvement = round((best$sharpe_allocated / baseline_sharpe - 1) * 100, 1),
          mean_exposure = round(best$mean_allocation, 2),
          pct_invested = round(best$pct_invested, 1),
          recommendation = if (best$sharpe_allocated > 0.3) {
            paste0(
              "ACTIONABLE: ", best$allocation_fn, " allocation improves Sharpe from ",
              baseline_sharpe, " to ", round(best$sharpe_allocated, 2),
              " (+", round(best$sharpe_allocated - baseline_sharpe, 2), "). ",
              "Deploy for live trading."
            )
          } else if (best$sharpe_allocated > 0.1) {
            paste0(
              "MARGINAL: ", best$allocation_fn, " allocation improves Sharpe to ",
              round(best$sharpe_allocated, 2), " but may not justify complexity. ",
              "Consider combining with other signals."
            )
          } else {
            paste0(
              "FAILED: Best Sharpe is ", round(best$sharpe_allocated, 2),
              ". Even regime-aware allocation doesn't rescue baseline momentum. ",
              "Pivot to other factors."
            )
          }
        )
      }
    ),

    # 20. Summary caption for display
    tar_target(
      zak_caption,
      {
        paste0(
          "Zakamulin continuous regime allocation (Issue #123 follow-up). ",
          "Baseline momentum Sharpe without regime: ", zak_summary$baseline_sharpe_no_regime, ". ",
          "Best method: ", zak_summary$best_method, " (Sharpe = ", zak_summary$best_sharpe, ", ",
          zak_summary$pct_improvement, "% improvement). ",
          "Mean exposure: ", zak_summary$mean_exposure * 100, "% (invested ",
          zak_summary$pct_invested, "% of time). ",
          zak_summary$recommendation
        )
      }
    )
  )
}
