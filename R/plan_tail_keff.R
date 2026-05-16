# Tail effective sample size (K_eff_acf) targets
# Addresses gap from #105: tail K_eff_acf mentioned in #55 but not computed
# Measures effective independent observations in crisis vs calm regimes

library(targets)
library(dplyr)

list(
  # === K_eff_acf by strategy and regime (crisis vs calm) ===
  tar_target(
    keff_crisis_calm_by_strategy,
    {
      # Placeholder - integrate with actual strategy_returns target
      tail_keff_by_strategy(
        returns_df = strategy_returns,  # Assumes this exists
        vix_data = vix_monthly,         # From plan_cross_asset_corr.R
        crisis_threshold = 30
      )
    }
  ),

  # === K_eff_acf visualization ===
  tar_target(
    keff_efficiency_plot,
    {
      plot_keff_efficiency(keff_crisis_calm_by_strategy)
    }
  ),

  # === K_eff_acf summary table ===
  tar_target(
    keff_summary_table,
    {
      keff_crisis_calm_by_strategy |>
        DT::datatable(
          caption = "Effective Sample Size (K_eff_acf) by Strategy and Regime",
          options = list(pageLength = 20),
          rownames = FALSE
        ) |>
        DT::formatRound(columns = c("K_eff_acf", "acf_sum"), digits = 2) |>
        DT::formatPercentage(columns = "efficiency", digits = 1) |>
        DT::formatRound(columns = "N", digits = 0)
    }
  ),

  # === Tail partition K_eff_acf (5%/90%/5%) ===
  # Example for a single strategy
  tar_target(
    keff_tail_partitions_example,
    {
      # Example: calculate for first strategy
      first_strategy_returns <- strategy_returns |>
        dplyr::filter(strategy == strategy[1]) |>
        dplyr::pull(return)

      tail_keff_partitions(first_strategy_returns)
    }
  ),

  # === Crisis vs calm efficiency comparison ===
  tar_target(
    keff_crisis_calm_summary,
    {
      keff_crisis_calm_by_strategy |>
        dplyr::select(strategy, regime, K_eff_acf, efficiency) |>
        tidyr::pivot_wider(
          names_from = regime,
          values_from = c(K_eff_acf, efficiency)
        ) |>
        dplyr::mutate(
          # Crisis efficiency as % of calm efficiency
          crisis_penalty = `efficiency_Crisis (VIX ≥ 30)` / `efficiency_Calm (VIX < 30)`,
          # How much more data needed in crisis to match calm power
          data_multiplier = 1 / crisis_penalty
        )
    }
  ),

  # === Interpretation notes ===
  tar_target(
    keff_interpretation,
    {
      tibble::tibble(
        metric = c(
          "K_eff_acf",
          "Efficiency (K_eff_acf/N)",
          "Crisis penalty",
          "Data multiplier"
        ),
        interpretation = c(
          "Effective number of independent observations (accounts for autocorrelation)",
          "Proportion of observations that are effectively independent (0-1)",
          "Crisis efficiency / Calm efficiency (typically <1, meaning crisis is less efficient)",
          "How many times more data needed in crisis to match calm statistical power"
        )
      )
    }
  )
)
