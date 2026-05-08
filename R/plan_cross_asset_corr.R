# Cross-asset correlation targets with regime conditioning
# Addresses gap from #105: no cross-asset correlations, correlations not regime-conditional
# Implements contagion analysis from #102 findings

library(targets)
library(dplyr)

list(
  # === Multi-asset returns (strategies + benchmark assets) ===
  tar_target(
    multi_asset_returns,
    {
      # Combine strategy returns with benchmark assets (SPY, TLT, GLD, DBC)
      # Placeholder - integrate with actual targets
      strategy_returns_wide |>  # Assumes this exists from multi-strategy
        dplyr::left_join(
          consolidated_equity |>
            dplyr::filter(ticker %in% c("SPY", "TLT", "GLD", "DBC")) |>
            dplyr::select(date, ticker, close) |>
            tidyr::pivot_wider(names_from = ticker, values_from = close) |>
            dplyr::mutate(
              dplyr::across(c(SPY, TLT, GLD, DBC), ~(.x / dplyr::lag(.x)) - 1)
            ) |>
            dplyr::filter(!is.na(SPY)),  # Remove first row with NA
          by = "date"
        )
    }
  ),

  # === VIX data for regime classification ===
  tar_target(
    vix_monthly,
    {
      # Placeholder - integrate with actual VIX source
      # Could come from aw_vix_daily or consolidated_macro
      aw_vix_daily |>
        dplyr::mutate(year_month = format(date, "%Y-%m")) |>
        dplyr::group_by(year_month) |>
        dplyr::summarise(
          date = max(date),  # End of month
          vix = mean(vix, na.rm = TRUE),  # Monthly average VIX
          .groups = "drop"
        )
    }
  ),

  # === Regime-conditional correlation matrices ===
  tar_target(
    regime_corr_matrices,
    {
      regime_correlations(
        returns_wide = multi_asset_returns,
        vix_data = vix_monthly
      )
    }
  ),

  # === Contagion detection ===
  tar_target(
    contagion_pairs,
    {
      detect_contagion(
        regime_corr_list = regime_corr_matrices,
        threshold = 0.2  # Correlation increase > 0.2 = contagion
      )
    }
  ),

  # === Correlation heatmaps by regime ===
  tar_target(
    corr_heatmap_unconditional,
    plot_regime_correlation_heatmap(
      regime_corr_matrices$unconditional,
      "Unconditional (Full Sample)"
    )
  ),

  tar_target(
    corr_heatmap_crisis,
    plot_regime_correlation_heatmap(
      regime_corr_matrices$crisis,
      "Crisis (VIX ≥ 30)"
    )
  ),

  tar_target(
    corr_heatmap_calm,
    plot_regime_correlation_heatmap(
      regime_corr_matrices$calm,
      "Calm (VIX < 30)"
    )
  ),

  tar_target(
    corr_heatmap_vix_high,
    plot_regime_correlation_heatmap(
      regime_corr_matrices$vix_high,
      "VIX High (≥ 30)"
    )
  ),

  # === Regime comparison tables ===
  # Example: SPY-TLT correlation across regimes
  tar_target(
    spy_tlt_regime_comparison,
    {
      regime_correlation_comparison(
        regime_corr_matrices,
        asset1 = "SPY",
        asset2 = "TLT"
      ) |>
        DT::datatable(
          caption = "SPY-TLT Correlation Across Regimes",
          options = list(pageLength = 10),
          rownames = FALSE
        ) |>
        DT::formatRound(columns = "correlation", digits = 3)
    }
  ),

  # === Contagion summary table ===
  tar_target(
    contagion_table,
    {
      if (nrow(contagion_pairs) == 0) {
        tibble::tibble(message = "No contagion pairs detected (threshold = 0.2)")
      } else {
        contagion_pairs |>
          DT::datatable(
            caption = "Contagion Pairs: Correlations That Increase in Crisis",
            options = list(pageLength = 20),
            rownames = FALSE
          ) |>
          DT::formatRound(columns = c("corr_calm", "corr_crisis", "corr_change"), digits = 3)
      }
    }
  ),

  # === Summary statistics: regime correlation differences ===
  tar_target(
    regime_corr_summary,
    {
      # Create summary showing how correlations change across regimes
      tibble::tibble(
        regime = names(regime_corr_matrices$n_obs),
        n_observations = unlist(regime_corr_matrices$n_obs)
      ) |>
        dplyr::mutate(
          mean_correlation = purrr::map_dbl(
            names(regime_corr_matrices$n_obs),
            ~{
              mat <- regime_corr_matrices[[.x]]
              if (is.null(mat)) return(NA_real_)
              mean(mat[upper.tri(mat)], na.rm = TRUE)
            }
          )
        )
    }
  )
)
