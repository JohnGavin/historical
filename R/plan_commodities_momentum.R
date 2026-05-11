# Commodities Momentum Decomposition Plan (Issue #134)
#
# Test if momentum decomposition works in commodities after equity failure.
#
# Context:
#   - Issue #121: Equity momentum decomposition FAILED (all Sharpe < 0)
#   - Issue #123: Failure persisted across ALL VIX regimes
#   - Decomposition produced 3.3x higher turnover than baseline
#
# Question: Is failure universal, or equity-specific?
#
# Test plan:
#   1. Load commodities data (37 series, monthly, 1992-2026)
#   2. Build 4 momentum variants:
#      a. Baseline 12m (control)
#      b. Short (3m) + Long (9m) decomposition
#      c. Volatility-filtered (low-vol preference)
#      d. Trend-strength-filtered (smooth trends only)
#   3. Backtest with 0.2% transaction costs
#   4. Compare Sharpe ratios
#
# Success criterion: ANY decomposed variant has net Sharpe > 0
# (Equity baseline had Sharpe ~0.5; ALL decomposed had Sharpe < 0)

plan_commodities_momentum <- function() {
  list(

    # ── Load raw commodities data ─────────────────────────────────────────
    targets::tar_target(commodities_raw, {
      library(arrow)
      library(dplyr)

      raw_path <- here::here("data", "raw", "commodities.parquet")
      if (!file.exists(raw_path)) {
        cli::cli_abort("Commodities data not found at {raw_path}")
      }

      data <- read_parquet(raw_path)

      cli::cli_inform(c(
        "v" = "Loaded {nrow(data)} obs across {n_distinct(data$series_id)} series",
        "i" = "Date range: {format(min(data$date), '%Y-%m')} to {format(max(data$date), '%Y-%m')}"
      ))

      data |>
        arrange(series_id, date)
    }),


    # ── Compute monthly returns ──────────────────────────────────────────
    targets::tar_target(commodities_returns, {
      calculate_commodity_returns(commodities_raw)
    }),


    # ── Build momentum signals ───────────────────────────────────────────
    targets::tar_target(commodities_signals, {
      build_commodity_signals(commodities_returns, lookback = 12)
    }),


    # ── Backtest all strategies ──────────────────────────────────────────
    targets::tar_target(commodities_backtest, {
      backtest_commodity_momentum(
        signals = commodities_signals,
        returns = commodities_returns,
        cost_bps = 20,  # 0.2% per trade (commodities are liquid)
        n_long = 10,
        n_short = 10
      )
    }),


    # ── Performance summary ──────────────────────────────────────────────
    targets::tar_target(commodities_perf_summary, {
      summarize_commodity_performance(
        backtest_results = commodities_backtest,
        annual_rf = 0.02
      )
    }),


    # ── Key finding: Rescue test ─────────────────────────────────────────
    # Does ANY decomposed variant have Sharpe > 0?
    # This is the critical question from issue #134.
    targets::tar_target(commodities_rescue_test, {
      library(dplyr)

      decomposed_strategies <- c("short_long", "vol_filtered", "trend_filtered")

      decomposed_perf <- commodities_perf_summary |>
        filter(strategy %in% decomposed_strategies)

      baseline_perf <- commodities_perf_summary |>
        filter(strategy == "baseline")

      result <- list(
        any_positive_sharpe = any(decomposed_perf$sharpe > 0, na.rm = TRUE),
        max_decomposed_sharpe = max(decomposed_perf$sharpe, na.rm = TRUE),
        baseline_sharpe = baseline_perf$sharpe[1],
        n_better_than_baseline = sum(decomposed_perf$sharpe > baseline_perf$sharpe[1],
                                     na.rm = TRUE),
        verdict = if (any(decomposed_perf$sharpe > 0, na.rm = TRUE)) {
          "RESCUE: Decomposition works in commodities (equity failure is asset-specific)"
        } else {
          "UNIVERSAL FAILURE: Decomposition broken across all tested asset classes"
        }
      )

      cli::cli_h2("Commodities Momentum Decomposition Test (#134)")
      cli::cli_alert_info("Baseline Sharpe: {round(result$baseline_sharpe, 3)}")
      cli::cli_alert_info("Best decomposed Sharpe: {round(result$max_decomposed_sharpe, 3)}")
      cli::cli_alert_info("{result$n_better_than_baseline}/3 decomposed > baseline")

      if (result$any_positive_sharpe) {
        cli::cli_alert_success(result$verdict)
      } else {
        cli::cli_alert_danger(result$verdict)
      }

      result
    }),


    # ── Cumulative returns plot ──────────────────────────────────────────
    targets::tar_target(commodities_cumret_plot, {
      library(ggplot2)
      library(dplyr)

      # Compute cumulative returns
      cumret_data <- commodities_backtest |>
        arrange(strategy, date) |>
        group_by(strategy) |>
        mutate(cumret = cumprod(1 + net_ret)) |>
        ungroup()

      # Strategy labels
      cumret_data <- cumret_data |>
        mutate(strategy_label = case_when(
          strategy == "baseline" ~ "Baseline (12m)",
          strategy == "short_long" ~ "Short (3m) + Long (9m)",
          strategy == "vol_filtered" ~ "Vol-Filtered",
          strategy == "trend_filtered" ~ "Trend-Filtered",
          TRUE ~ strategy
        ))

      ggplot(cumret_data, aes(x = date, y = cumret, color = strategy_label)) +
        geom_line(linewidth = 0.8) +
        scale_y_log10(labels = scales::percent_format(accuracy = 1)) +
        scale_color_brewer(palette = "Dark2") +
        labs(
          title = "Commodities Momentum: Cumulative Returns",
          subtitle = "Long-short (10/10), 0.2% transaction costs",
          x = NULL,
          y = "Cumulative Return (log scale)",
          color = "Strategy",
          caption = paste0(
            "Source: FRED/IMF commodity prices (37 series, monthly, 1992-2026)\n",
            "Issue #134: Test if momentum decomposition works in commodities after equity failure"
          )
        ) +
        theme_minimal() +
        theme(
          legend.position = "bottom",
          plot.caption = element_text(hjust = 0, size = 8, color = "gray40")
        )
    }),


    # ── Rolling Sharpe plot (36-month window) ────────────────────────────
    targets::tar_target(commodities_rolling_sharpe_plot, {
      library(ggplot2)
      library(dplyr)
      library(slider)

      # Compute 36-month rolling Sharpe
      rolling_sharpe <- commodities_backtest |>
        arrange(strategy, date) |>
        group_by(strategy) |>
        mutate(
          rolling_sharpe_36m = slide_dbl(
            net_ret,
            ~{
              if (length(.x) < 36) return(NA_real_)
              monthly_rf <- (1.02)^(1/12) - 1
              mean_ret <- mean(.x, na.rm = TRUE)
              sd_ret <- sd(.x, na.rm = TRUE)
              if (sd_ret == 0) return(NA_real_)
              (mean_ret - monthly_rf) / sd_ret * sqrt(12)
            },
            .before = 35,
            .after = 0,
            .complete = FALSE
          )
        ) |>
        ungroup()

      # Strategy labels
      rolling_sharpe <- rolling_sharpe |>
        mutate(strategy_label = case_when(
          strategy == "baseline" ~ "Baseline (12m)",
          strategy == "short_long" ~ "Short (3m) + Long (9m)",
          strategy == "vol_filtered" ~ "Vol-Filtered",
          strategy == "trend_filtered" ~ "Trend-Filtered",
          TRUE ~ strategy
        ))

      ggplot(rolling_sharpe, aes(x = date, y = rolling_sharpe_36m, color = strategy_label)) +
        geom_line(linewidth = 0.8) +
        geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
        scale_color_brewer(palette = "Dark2") +
        labs(
          title = "Commodities Momentum: Rolling 36-Month Sharpe Ratio",
          subtitle = "Net of 0.2% transaction costs",
          x = NULL,
          y = "Sharpe Ratio (36m rolling)",
          color = "Strategy",
          caption = paste0(
            "Sharpe computed on monthly net returns over trailing 36-month window\n",
            "Issue #134: Test if decomposition improves risk-adjusted returns"
          )
        ) +
        theme_minimal() +
        theme(
          legend.position = "bottom",
          plot.caption = element_text(hjust = 0, size = 8, color = "gray40")
        )
    }),


    # ── Turnover comparison ──────────────────────────────────────────────
    targets::tar_target(commodities_turnover_plot, {
      library(ggplot2)
      library(dplyr)

      # Mean turnover by strategy
      turnover_summary <- commodities_backtest |>
        group_by(strategy) |>
        summarise(
          mean_turnover = mean(turnover, na.rm = TRUE),
          .groups = "drop"
        )

      # Strategy labels
      turnover_summary <- turnover_summary |>
        mutate(strategy_label = case_when(
          strategy == "baseline" ~ "Baseline (12m)",
          strategy == "short_long" ~ "Short (3m) + Long (9m)",
          strategy == "vol_filtered" ~ "Vol-Filtered",
          strategy == "trend_filtered" ~ "Trend-Filtered",
          TRUE ~ strategy
        ))

      # Add turnover ratio vs baseline
      baseline_turnover <- turnover_summary |>
        filter(strategy == "baseline") |>
        pull(mean_turnover)

      turnover_summary <- turnover_summary |>
        mutate(
          turnover_ratio = mean_turnover / baseline_turnover,
          label_text = paste0(
            round(mean_turnover * 100, 1), "%\n",
            "(", round(turnover_ratio, 2), "x)"
          )
        )

      ggplot(turnover_summary, aes(x = reorder(strategy_label, -mean_turnover),
                                    y = mean_turnover, fill = strategy)) +
        geom_col(show.legend = FALSE) +
        geom_text(aes(label = label_text), vjust = -0.3, size = 3.5) +
        scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                          expand = expansion(mult = c(0, 0.15))) +
        scale_fill_brewer(palette = "Dark2") +
        labs(
          title = "Commodities Momentum: Turnover by Strategy",
          subtitle = "Mean monthly turnover (one-way). Labels show ratio vs baseline.",
          x = NULL,
          y = "Mean Turnover",
          caption = paste0(
            "Issue #121: Equity decomposition had 3.3x higher turnover than baseline\n",
            "Testing if commodities decomposition has similar turnover penalty"
          )
        ) +
        theme_minimal() +
        theme(
          plot.caption = element_text(hjust = 0, size = 8, color = "gray40"),
          axis.text.x = element_text(angle = 15, hjust = 1)
        )
    })

  )
}
