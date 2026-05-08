# Integration test pipeline: validates Tier 1 gap implementations
#
# Minimal dependencies, runs in <5 minutes
# Tests: vix_monthly, spy_returns, liquidity, strategy_returns,
#        multi_asset_returns, te_ir, regime_correlations, keff

library(targets)

tar_option_set(
  packages = c("dplyr", "duckplyr", "ggplot2", "tidyr", "scales", "DT", "rlang", "cli"),
  memory = "transient",
  garbage_collection = TRUE,
  error = "stop",  # Fail fast on errors
  format = "rds"
)

# Source integration functions (skip liquidity - already validated)
source(here::here("R/tracking_error.R"))
source(here::here("R/regime_correlations.R"))
source(here::here("R/tail_keff.R"))

list(
  # === VIX data (from existing avoid_worst plan) ===
  targets::tar_target(
    aw_vix_daily,
    {
      library(dplyr)
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      spy <- hd_ohlcv("SPY") |>
        dplyr::filter(date >= as.POSIXct("2010-01-01")) |>  # 2010+ for TLT availability
        dplyr::select(date, ticker, ret = adjusted) |>
        dplyr::arrange(date) |>
        dplyr::mutate(ret = (ret / dplyr::lag(ret)) - 1) |>
        dplyr::filter(!is.na(ret))

      vix <- hd_macro("VIXCLS") |>
        dplyr::select(date, vix = value) |>
        dplyr::arrange(date)

      spy |> dplyr::left_join(vix, by = "date")
    }
  ),

  # === VIX monthly ===
  targets::tar_target(
    vix_monthly,
    {
      aw_vix_daily |>
        dplyr::mutate(year_month = format(date, "%Y-%m")) |>
        dplyr::group_by(year_month) |>
        dplyr::summarise(
          date = max(date),
          vix = mean(vix, na.rm = TRUE),
          .groups = "drop"
        )
    }
  ),

  # === SPY returns ===
  targets::tar_target(
    spy_returns,
    {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_ohlcv("SPY") |>
        dplyr::filter(date >= as.POSIXct("2010-01-01")) |>
        dplyr::arrange(date) |>
        dplyr::mutate(
          return = (adjusted / dplyr::lag(adjusted)) - 1
        ) |>
        dplyr::select(date, return) |>
        dplyr::filter(!is.na(return))
    }
  ),

  # === Mock strategy returns (for testing) ===
  # In real pipeline these come from strategy portfolios
  targets::tar_target(
    strategy_returns,
    {
      # Create 3 mock strategies with different characteristics
      dates <- spy_returns$date
      n <- length(dates)

      set.seed(42)
      dplyr::bind_rows(
        tibble::tibble(
          date = dates,
          strategy = "Strategy A",
          return = spy_returns$return + rnorm(n, 0, 0.01)  # SPY + noise
        ),
        tibble::tibble(
          date = dates,
          strategy = "Strategy B",
          return = -0.5 * spy_returns$return + rnorm(n, 0, 0.01)  # Inverse
        ),
        tibble::tibble(
          date = dates,
          strategy = "Strategy C",
          return = 1.5 * spy_returns$return + rnorm(n, 0, 0.015)  # Levered
        )
      )
    }
  ),

  # === Multi-asset returns ===
  targets::tar_target(
    multi_asset_returns,
    {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      # Strategy returns wide
      strategy_returns_wide <- strategy_returns |>
        tidyr::pivot_wider(
          names_from = strategy,
          values_from = return,
          id_cols = date
        )

      # Benchmark assets (SPY, TLT only for speed)
      benchmark_assets <- hd_ohlcv(c("SPY", "TLT")) |>
        dplyr::filter(date >= as.POSIXct("2010-01-01")) |>
        dplyr::select(date, ticker, adjusted) |>
        dplyr::arrange(ticker, date) |>
        dplyr::group_by(ticker) |>
        dplyr::mutate(
          return = (adjusted / dplyr::lag(adjusted)) - 1
        ) |>
        dplyr::filter(!is.na(return)) |>
        dplyr::select(date, ticker, return) |>
        tidyr::pivot_wider(
          names_from = ticker,
          values_from = return,
          id_cols = date
        )

      strategy_returns_wide |>
        dplyr::left_join(benchmark_assets, by = "date") |>
        dplyr::arrange(date)
    }
  ),

  # === Tracking Error / IR ===
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

  # === TE/IR table ===
  targets::tar_target(
    te_ir_table,
    {
      te_ir_metrics |>
        dplyr::select(strategy, tracking_error, information_ratio, active_return, correlation_to_benchmark) |>
        DT::datatable(
          caption = "TE/IR Metrics (Integration Test)",
          options = list(pageLength = 10),
          rownames = FALSE
        ) |>
        DT::formatRound(columns = c("tracking_error", "information_ratio", "active_return"), digits = 3) |>
        DT::formatRound(columns = "correlation_to_benchmark", digits = 2)
    }
  ),

  # === Regime correlations ===
  targets::tar_target(
    regime_corr_matrices,
    {
      regime_correlations(
        returns_wide = multi_asset_returns,
        vix_data = vix_monthly
      )
    }
  ),

  # === Contagion detection ===
  targets::tar_target(
    contagion_pairs,
    {
      detect_contagion(
        regime_corr_list = regime_corr_matrices,
        threshold = 0.2
      )
    }
  ),

  # === Regime correlation heatmaps ===
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

  # === Tail K_eff ===
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

  # === K_eff plot ===
  targets::tar_target(
    keff_efficiency_plot,
    {
      plot_keff_efficiency(keff_crisis_calm_by_strategy)
    }
  ),

  # === K_eff table ===
  targets::tar_target(
    keff_summary_table,
    {
      keff_crisis_calm_by_strategy |>
        DT::datatable(
          caption = "K_eff by Strategy and Regime (Integration Test)",
          options = list(pageLength = 10),
          rownames = FALSE
        ) |>
        DT::formatRound(columns = c("K_eff", "acf_sum"), digits = 2) |>
        DT::formatPercentage(columns = "efficiency", digits = 1) |>
        DT::formatRound(columns = "N", digits = 0)
    }
  )
)
