# Tracking error and information ratio targets
# Addresses gap from #105: no explicit TE or IR metrics

library(targets)
library(dplyr)

list(
  # === Benchmark data (SPY) ===
  # Assumes SPY is in consolidated_equity or available separately
  tar_target(
    spy_returns,
    {
      # Placeholder - will integrate with actual data pipeline
      # Extract SPY monthly returns from consolidated equity or factors
      consolidated_equity |>
        dplyr::filter(ticker == "SPY") |>
        dplyr::arrange(date) |>
        dplyr::mutate(
          return = (close / dplyr::lag(close)) - 1
        ) |>
        dplyr::select(date, return) |>
        dplyr::filter(!is.na(return))
    }
  ),

  # === TE/IR calculation for all strategies ===
  tar_target(
    te_ir_metrics,
    {
      # Assumes strategy_returns exists from leaderboard or multi-strategy pipeline
      calculate_te_ir(
        returns_df = strategy_returns,  # Placeholder - integrate with actual target
        benchmark_df = spy_returns,
        benchmark_name = "SPY",
        frequency = "monthly"
      )
    }
  ),

  # === Enhanced leaderboard with TE/IR ===
  tar_target(
    leaderboard_with_te_ir,
    {
      # Assumes leaderboard_metrics exists
      add_te_ir_to_leaderboard(
        leaderboard_df = leaderboard_metrics,  # Placeholder
        te_ir_df = te_ir_metrics
      )
    }
  ),

  # === TE/IR summary table for vignettes ===
  tar_target(
    te_ir_table,
    {
      te_ir_metrics |>
        dplyr::select(strategy, tracking_error, information_ratio, active_return, correlation_to_benchmark) |>
        DT::datatable(
          caption = "Tracking Error and Information Ratio vs SPY",
          options = list(pageLength = 20),
          rownames = FALSE
        ) |>
        DT::formatRound(columns = c("tracking_error", "information_ratio", "active_return"), digits = 3) |>
        DT::formatRound(columns = "correlation_to_benchmark", digits = 2)
    }
  )
)
