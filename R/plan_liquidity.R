# Liquidity metrics targets
# Addresses gap from #105: volume data not used for liquidity analysis

library(targets)
library(dplyr)

list(
  # === Liquidity metrics for equity data ===
  tar_target(
    equity_with_adv,
    {
      # Load consolidated equity (assumes this exists from main pipeline)
      # For now, use placeholder - will integrate with actual consolidated_equity
      consolidated_equity |>
        calculate_adv(window_days = 20)
    }
  ),

  tar_target(
    equity_liquidity_filtered,
    {
      equity_with_adv |>
        filter_liquidity(min_adv_usd = 1e6, filter_mode = "warn")
    }
  ),

  tar_target(
    liquidity_summary_table,
    {
      equity_liquidity_filtered |>
        liquidity_summary() |>
        DT::datatable(
          caption = "Liquidity Summary by Ticker",
          options = list(pageLength = 20),
          rownames = FALSE
        ) |>
        DT::formatRound(columns = c("median_volume", "median_adv_usd"), digits = 0) |>
        DT::formatRound(columns = c("median_price", "pct_illiquid"), digits = 2)
    }
  ),

  # === Volume statistics for vignettes ===
  tar_target(
    volume_stats,
    {
      equity_with_adv |>
        dplyr::summarise(
          total_tickers = dplyr::n_distinct(ticker),
          total_observations = dplyr::n(),
          median_adv_all = median(adv_usd, na.rm = TRUE),
          pct_liquid = 100 * mean(liquidity_flag == "liquid", na.rm = TRUE),
          pct_illiquid = 100 * mean(liquidity_flag == "illiquid", na.rm = TRUE),
          min_adv_threshold = 1e6
        )
    }
  )
)
