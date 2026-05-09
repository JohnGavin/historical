# Targets plan for VVIX (volatility-of-volatility) analysis
# Gap from #105: Volatility coverage 70% → 90%

plan_vvix <- function() {
  list(
    # === VVIX DATA PREPARATION ===
    targets::tar_target(
      vvix_daily,
      {
        # VVIX comes from CBOE CDN via fetch_cboe_vol.R
        # Once cboe_vol.parquet is available, extract VVIX series
        cboe_vol_path <- here::here("data/raw/cboe_vol.parquet")

        if (!file.exists(cboe_vol_path)) {
          cli::cli_warn("cboe_vol.parquet not yet available — run fetch_cboe_vol.R first")
          return(tibble::tibble(date = as.Date(character(0)), vvix = numeric(0)))
        }

        arrow::read_parquet(cboe_vol_path) |>
          dplyr::filter(series_id == "VVIX") |>
          dplyr::select(date, vvix = value) |>
          dplyr::arrange(date)
      }
    ),

    # === VOL-OF-VOL REGIME CLASSIFICATION ===
    targets::tar_target(
      vvix_regimes,
      {
        # Requires aw_vix_daily from plan_vix_macro_overlay.R
        classify_vvix_regimes(
          vix_data = aw_vix_daily |> dplyr::select(date, vix),
          vvix_data = vvix_daily,
          vvix_threshold = 100
        )
      }
    ),

    # === VIX STABILITY METRICS ===
    targets::tar_target(
      vix_stability,
      {
        vix_stability_metrics(vvix_regimes)
      }
    ),

    # === VOL REGIME TRANSITIONS ===
    targets::tar_target(
      vol_transitions,
      {
        detect_vol_transitions(vvix_regimes)
      }
    ),

    # === ENHANCED CRISIS DETECTION ===
    targets::tar_target(
      enhanced_crisis,
      {
        enhanced_crisis_detection(
          vvix_regimes,
          vix_crisis_threshold = 30,
          vvix_crisis_threshold = 120
        )
      }
    ),

    # === DISPLAY: VIX STABILITY TABLE ===
    targets::tar_target(
      vix_stability_table,
      {
        vix_stability |>
          dplyr::mutate(
            vvix_regime = dplyr::case_when(
              vvix_regime == "stable_vol" ~ "Stable Vol (VVIX < 100)",
              vvix_regime == "unstable_vol" ~ "Unstable Vol (VVIX ≥ 100)",
              TRUE ~ vvix_regime
            ),
            across(where(is.numeric), ~round(., 2))
          ) |>
          DT::datatable(
            options = list(pageLength = 10, dom = 't'),
            caption = "VIX Stability by VVIX Regime — Unstable regimes show higher VIX coefficient of variation"
          )
      }
    ),

    # === DISPLAY: CRISIS SEVERITY TIME SERIES ===
    targets::tar_target(
      crisis_severity_plot,
      {
        # Plot crisis severity over time with VIX and VVIX overlays
        enhanced_crisis |>
          dplyr::filter(date >= as.POSIXct("2020-01-01")) |>  # Last 5 years for visibility
          ggplot2::ggplot(ggplot2::aes(x = date)) +
          ggplot2::geom_line(ggplot2::aes(y = vix, color = "VIX"), linewidth = 0.5) +
          ggplot2::geom_line(ggplot2::aes(y = vvix, color = "VVIX"), linewidth = 0.5, alpha = 0.7) +
          ggplot2::geom_point(
            data = ~dplyr::filter(., crisis_severity %in% c("severe", "brewing")),
            ggplot2::aes(y = vix, shape = crisis_severity, color = crisis_severity),
            size = 2
          ) +
          ggplot2::scale_color_manual(
            values = c(
              "VIX" = "#2E86AB",
              "VVIX" = "#A23B72",
              "severe" = "#E63946",
              "brewing" = "#F77F00"
            )
          ) +
          ggplot2::scale_shape_manual(
            values = c("severe" = 17, "brewing" = 16)
          ) +
          ggplot2::labs(
            title = "Enhanced Crisis Detection with VVIX",
            subtitle = "Severe = High VIX + Unstable VVIX | Brewing = Low VIX but Unstable VVIX (warning)",
            x = NULL,
            y = "Level",
            color = NULL,
            shape = "Crisis Severity"
          ) +
          ggplot2::theme_minimal() +
          ggplot2::theme(legend.position = "bottom")
      }
    ),

    # === DISPLAY: REGIME TRANSITION SUMMARY ===
    targets::tar_target(
      regime_transitions_table,
      {
        vol_transitions |>
          dplyr::slice_tail(n = 20) |>  # Last 20 transitions
          dplyr::mutate(
            across(where(is.numeric), ~round(., 1)),
            date = format(date, "%Y-%m-%d")
          ) |>
          DT::datatable(
            options = list(pageLength = 10, dom = 't'),
            caption = "Recent Vol Regime Transitions — VIX and VVIX regime changes"
          )
      }
    )
  )
}
