# Targets plan for Volatility Spike Analysis
# Issue #119 Phase 1: Replicate Alpha Architect finding that 2014-2024 had
# ~3x more VIX spikes (>= 1.5x 3-month MA) than 2004-2013

plan_volatility_spikes <- function() {
  list(
    # === VIX DATA PREPARATION ===
    targets::tar_target(
      vix_daily,
      {
        # VIX comes from FRED via historicaldata package (series VIXCLS)

        hd_macro("VIXCLS") |>
          dplyr::select(date, vix = value) |>
          dplyr::arrange(date)
      }
    ),

    # === 3-MONTH ROLLING MA ===
    targets::tar_target(
      vix_ma_3m,
      {
        vix_daily |>
          dplyr::arrange(date) |>
          dplyr::mutate(
            vix_ma_3m = roll_mean_safe(vix, n = 63)
          )
      }
    ),

    # === DETECT VOLATILITY SPIKES ===
    targets::tar_target(
      vol_spikes,
      {
        detect_volatility_spikes(
          vix_daily = vix_daily,
          threshold = 1.5,
          window_days = 63
        )
      }
    ),

    # === SPIKE DURATION STATS ===
    targets::tar_target(
      spike_durations,
      {
        calculate_spike_duration(vol_spikes)
      }
    ),

    # === PERIOD COMPARISON (2004-2013 vs 2014-2024) ===
    targets::tar_target(
      spike_comparison,
      {
        periods <- list(
          "2004-2013" = c("2004-01-01", "2013-12-31"),
          "2014-2024" = c("2014-01-01", "2024-12-31")
        )
        compare_spike_frequency(vol_spikes, periods)
      }
    ),

    # === REVERSAL SPEED STATISTICS ===
    targets::tar_target(
      reversal_speed_stats,
      {
        reversal_data <- calculate_reversal_speed(vol_spikes)

        # Overall stats
        overall <- tibble::tibble(
          period = "All",
          n_spikes = sum(!is.na(reversal_data$reversal_days)),
          median_reversal_days = median(reversal_data$reversal_days, na.rm = TRUE),
          mean_reversal_days = mean(reversal_data$reversal_days, na.rm = TRUE),
          sd_reversal_days = sd(reversal_data$reversal_days, na.rm = TRUE)
        )

        # By period (2004-2013 vs 2014-2024)
        by_period <- reversal_data |>
          dplyr::mutate(
            period = dplyr::case_when(
              peak_date >= as.Date("2004-01-01") & peak_date <= as.Date("2013-12-31") ~ "2004-2013",
              peak_date >= as.Date("2014-01-01") & peak_date <= as.Date("2024-12-31") ~ "2014-2024",
              TRUE ~ "Other"
            )
          ) |>
          dplyr::filter(period != "Other") |>
          dplyr::group_by(period) |>
          dplyr::summarise(
            n_spikes = sum(!is.na(reversal_days)),
            median_reversal_days = median(reversal_days, na.rm = TRUE),
            mean_reversal_days = mean(reversal_days, na.rm = TRUE),
            sd_reversal_days = sd(reversal_days, na.rm = TRUE),
            .groups = "drop"
          )

        dplyr::bind_rows(overall, by_period)
      }
    ),

    # === VISUALIZATION: SPIKE TIMELINE ===
    targets::tar_target(
      spike_timeline_plot,
      {
        # Similar to JST crisis timeline — show VIX with spikes highlighted
        # Focus on 2000-2024 for readability
        plot_data <- vol_spikes |>
          dplyr::filter(date >= as.Date("2000-01-01"))

        # Identify spike regions for shading
        spike_periods <- spike_durations |>
          dplyr::filter(start_date >= as.Date("2000-01-01"))

        ggplot2::ggplot() +
          # Shade spike periods
          ggplot2::geom_rect(
            data = spike_periods,
            ggplot2::aes(xmin = start_date, xmax = end_date, ymin = 0, ymax = Inf),
            fill = "#E63946", alpha = 0.15
          ) +
          # VIX line
          ggplot2::geom_line(
            data = plot_data,
            ggplot2::aes(x = date, y = vix),
            color = "#2E86AB", linewidth = 0.5
          ) +
          # 3-month MA
          ggplot2::geom_line(
            data = plot_data,
            ggplot2::aes(x = date, y = vix_ma),
            color = "#06A77D", linewidth = 0.6, linetype = "dashed"
          ) +
          # Spike threshold (1.5x MA)
          ggplot2::geom_line(
            data = plot_data,
            ggplot2::aes(x = date, y = spike_threshold),
            color = "#F77F00", linewidth = 0.4, linetype = "dotted"
          ) +
          ggplot2::labs(
            title = "VIX Volatility Spikes (2000-2024)",
            subtitle = "Red shading = VIX ≥ 1.5× 3-month MA. Spikes more frequent 2014-2024 vs 2004-2013",
            x = NULL,
            y = "VIX Level",
            caption = "Source: CBOE VIX Index. Spike threshold = 1.5× rolling 63-day MA."
          ) +
          ggplot2::scale_y_continuous(limits = c(0, NA)) +
          ggplot2::theme_minimal() +
          ggplot2::theme(
            plot.subtitle = ggplot2::element_text(size = 9, color = "gray30"),
            plot.caption = ggplot2::element_text(size = 7, color = "gray50", hjust = 0)
          )
      }
    ),

    # === DISPLAY: COMPARISON TABLE ===
    targets::tar_target(
      spike_comparison_table,
      {
        spike_comparison |>
          dplyr::mutate(
            across(where(is.numeric), ~round(., 2))
          ) |>
          dplyr::select(
            Period = period,
            `Start Date` = start,
            `End Date` = end,
            `N Spikes` = n_spikes,
            `Spikes/Year` = spikes_per_year,
            `Mean Duration (days)` = mean_duration,
            `% Days in Spike` = pct_days_in_spike
          ) |>
          DT::datatable(
            options = list(pageLength = 10, dom = 't'),
            caption = "Volatility Spike Frequency: 2004-2013 vs 2014-2024 — More frequent spikes in recent decade"
          )
      }
    )
  )
}
