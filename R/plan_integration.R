# Integration plan: Wire Tier 1 gap implementations to actual data
#
# Connects:
# - Liquidity analysis → consolidated_equity
# - Tracking error/IR → strategy returns + SPY benchmark
# - Regime correlations → multi-asset returns + VIX
# - Tail K_eff_acf → strategy returns + VIX

plan_integration <- function() {
  list(
    # === VIX monthly (from existing aw_vix_daily) ===
    targets::tar_target(
      vix_monthly,
      {
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

    # === Unified strategy returns (long format) ===
    # Combines all strategy portfolios into single tibble
    targets::tar_target(
      strategy_returns,
      {
        # Bind all strategies - extract and rename columns inline
        dplyr::bind_rows(
          # Factor strategies
          fm_portfolio |>
            dplyr::mutate(strategy = "Factor MAX") |>
            dplyr::select(date, strategy, return = portfolio_ret),
          drif_portfolio |>
            dplyr::mutate(strategy = "Factor DRIF") |>
            dplyr::select(date, strategy, return = portfolio_ret),

          # Stock strategies
          stk_max_portfolio |>
            dplyr::mutate(strategy = "Stock MAX") |>
            dplyr::select(date, strategy, return = port_ret),
          stk_drif_portfolio |>
            dplyr::mutate(strategy = "Stock DRIF") |>
            dplyr::select(date, strategy, return = port_ret),
          xgb_drif_portfolio |>
            dplyr::mutate(strategy = "XGB DRIF") |>
            dplyr::select(date, strategy, return = port_ret)
        ) |>
          dplyr::arrange(strategy, date)
      }
    ),

    # === SPY returns (benchmark for TE/IR) ===
    targets::tar_target(
      spy_returns,
      {
        hd_ohlcv("SPY") |>
          dplyr::arrange(date) |>
          dplyr::mutate(
            return = (adjusted_close / dplyr::lag(adjusted_close)) - 1
          ) |>
          dplyr::select(date, return) |>
          dplyr::filter(!is.na(return))
      }
    ),

    # === Multi-asset returns (strategies + benchmarks for correlations) ===
    # Wide format needed for correlation matrices
    targets::tar_target(
      multi_asset_returns,
      {
        # Convert strategy returns to wide format
        strategy_returns_wide <- strategy_returns |>
          tidyr::pivot_wider(
            names_from = strategy,
            values_from = return,
            id_cols = date
          )

        # Get benchmark asset returns (SPY, TLT, GLD, DBC)
        benchmark_assets <- hd_ohlcv(c("SPY", "TLT", "GLD", "DBC")) |>
          dplyr::select(date, ticker, adjusted_close) |>
          dplyr::arrange(ticker, date) |>
          dplyr::group_by(ticker) |>
          dplyr::mutate(
            return = (adjusted_close / dplyr::lag(adjusted_close)) - 1
          ) |>
          dplyr::filter(!is.na(return)) |>
          dplyr::select(date, ticker, return) |>
          tidyr::pivot_wider(
            names_from = ticker,
            values_from = return,
            id_cols = date
          )

        # Join strategies with benchmarks
        strategy_returns_wide |>
          dplyr::left_join(benchmark_assets, by = "date") |>
          dplyr::arrange(date)
      }
    ),

    # LIQUIDITY targets deliberately removed here (#625, proposed-work item 6):
    # this file's equity_with_adv/equity_liquidity_filtered/liquidity_summary_table
    # trio (a) duplicated target NAMES already defined by plan_liquidity()
    # (R/plan_liquidity.R), which would collide if this file were ever sourced
    # alongside it, and (b) liquidity_summary_table's DT::formatCurrency() call
    # referenced p25_adv_usd/p75_adv_usd columns that liquidity_summary()
    # (R/liquidity.R) does not return, so it would have errored on first build.
    # plan_integration() is not sourced by any _targets.R (root or docs/) --
    # see the commented-out `source(here::here("R/plan_integration.R"))` and
    # `# plan_integration(),` lines in docs/_targets.R -- so removing this
    # dead code changes no currently-running pipeline.

    # === TRACKING ERROR / IR: calculate for all strategies ===
    targets::tar_target(
      te_ir_metrics,
      {
        calculate_te_ir(
          returns_df = strategy_returns,
          benchmark_df = spy_returns,
          benchmark_name = "SPY",
          frequency = "monthly"
        )
      }
    ),

    # === TRACKING ERROR / IR: summary table ===
    targets::tar_target(
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
    ),

    # === REGIME CORRELATIONS: calculate 9 regime matrices ===
    targets::tar_target(
      regime_corr_matrices,
      {
        regime_correlations(
          returns_wide = multi_asset_returns,
          vix_data = vix_monthly
        )
      }
    ),

    # === REGIME CORRELATIONS: contagion detection ===
    targets::tar_target(
      contagion_pairs,
      {
        detect_contagion(
          regime_corr_list = regime_corr_matrices,
          threshold = 0.2  # Correlation increase > 0.2 = contagion
        )
      }
    ),

    # === REGIME CORRELATIONS: heatmaps ===
    targets::tar_target(
      corr_heatmap_crisis,
      plot_regime_correlation_heatmap(
        regime_corr_matrices$crisis,
        "Crisis (VIX ≥ 30)"
      )
    ),

    targets::tar_target(
      corr_heatmap_calm,
      plot_regime_correlation_heatmap(
        regime_corr_matrices$calm,
        "Calm (VIX < 30)"
      )
    ),

    # === REGIME CORRELATIONS: SPY-TLT regime comparison ===
    targets::tar_target(
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

    # === TAIL K_EFF: by strategy and regime ===
    targets::tar_target(
      keff_crisis_calm_by_strategy,
      {
        tail_keff_by_strategy(
          returns_df = strategy_returns,
          vix_data = vix_monthly,
          crisis_threshold = 30
        )
      }
    ),

    # === TAIL K_EFF: efficiency plot ===
    targets::tar_target(
      keff_efficiency_plot,
      {
        plot_keff_efficiency(keff_crisis_calm_by_strategy)
      }
    ),

    # === TAIL K_EFF: summary table ===
    targets::tar_target(
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
    )
  )
}
