# Volatility Spike Analysis
# Issue #119 Phase 1: Replicate Alpha Architect VIX spike findings
# Finding: 2014-2024 had ~3x more volatility spikes than 2004-2013

#' Detect Volatility Spikes
#'
#' A spike is defined as VIX >= threshold × rolling window MA.
#' Default: VIX >= 1.5x its 3-month (63-trading-day) moving average.
#'
#' @param vix_daily Tibble with columns: date, vix (or value if from raw data)
#' @param threshold Spike threshold multiplier (default 1.5)
#' @param window_days Rolling MA window in days (default 63 = ~3 months)
#' @return Tibble with date, vix, vix_ma, spike_threshold, is_spike, spike_id
#' @export
detect_volatility_spikes <- function(vix_daily, threshold = 1.5, window_days = 63) {
  # Ensure we have the right column name
  if ("value" %in% names(vix_daily) && !"vix" %in% names(vix_daily)) {
    vix_daily <- vix_daily |> dplyr::rename(vix = value)
  }

  # Calculate rolling MA and spike threshold
  vix_with_ma <- vix_daily |>
    dplyr::arrange(date) |>
    dplyr::mutate(
      vix_ma = roll_mean_safe(vix, n = window_days),
      spike_threshold = vix_ma * threshold,
      is_spike = !is.na(vix_ma) & vix >= spike_threshold
    )

  # Assign spike_id to consecutive spike periods
  vix_with_ma |>
    dplyr::mutate(
      spike_group = cumsum(is_spike & (dplyr::lag(is_spike, default = FALSE) == FALSE)),
      spike_id = ifelse(is_spike, spike_group, NA_integer_)
    ) |>
    dplyr::select(-spike_group)
}

#' Calculate Spike Duration
#'
#' Compute the duration (in days) of each volatility spike event.
#'
#' @param spike_data Output from detect_volatility_spikes()
#' @return Tibble with spike_id, start_date, end_date, duration_days, peak_vix, peak_date
#' @export
calculate_spike_duration <- function(spike_data) {
  spike_data |>
    dplyr::filter(is_spike) |>
    dplyr::group_by(spike_id) |>
    dplyr::summarise(
      start_date = min(date),
      end_date = max(date),
      duration_days = as.numeric(end_date - start_date) + 1,
      peak_vix = max(vix, na.rm = TRUE),
      peak_date = date[which.max(vix)],
      .groups = "drop"
    )
}

#' Calculate Reversal Speed
#'
#' Measure how many days it takes for VIX to revert from peak back to 1.0x MA
#' (i.e., cross back below the moving average after a spike).
#'
#' @param spike_data Output from detect_volatility_spikes()
#' @return Tibble with spike_id, peak_date, reversal_date, reversal_days
#' @export
calculate_reversal_speed <- function(spike_data) {
  spike_durations <- calculate_spike_duration(spike_data)

  # For each spike, find when VIX drops back to MA level (or below)
  reversal_stats <- spike_durations |>
    dplyr::rowwise() |>
    dplyr::mutate(
      reversal_date = {
        # Get data from peak to 90 days after
        post_peak <- spike_data |>
          dplyr::filter(date >= peak_date, date <= peak_date + 90)

        # Find first date where VIX <= vix_ma after peak
        reversal_rows <- post_peak |>
          dplyr::filter(date > peak_date, vix <= vix_ma)

        if (nrow(reversal_rows) > 0) {
          min(reversal_rows$date)
        } else {
          as.Date(NA)
        }
      },
      reversal_days = as.numeric(reversal_date - peak_date)
    ) |>
    dplyr::ungroup() |>
    dplyr::select(spike_id, peak_date, reversal_date, reversal_days)

  reversal_stats
}

#' Compare Spike Frequency Across Periods
#'
#' Count spikes per period and compute spike frequency metrics.
#'
#' @param spike_data Output from detect_volatility_spikes()
#' @param periods Named list of period definitions, e.g.,
#'   list("2004-2013" = c("2004-01-01", "2013-12-31"),
#'        "2014-2024" = c("2014-01-01", "2024-12-31"))
#' @return Tibble with period, n_spikes, n_days, spikes_per_year, mean_duration
#' @export
compare_spike_frequency <- function(spike_data, periods) {
  spike_durations <- calculate_spike_duration(spike_data)

  # For each period, count spikes and compute metrics
  period_stats <- purrr::map_dfr(names(periods), function(period_name) {
    period_range <- periods[[period_name]]
    start_date <- as.Date(period_range[1])
    end_date <- as.Date(period_range[2])

    # Filter spikes that started in this period
    period_spikes <- spike_durations |>
      dplyr::filter(start_date >= !!start_date, start_date <= !!end_date)

    # Count total days in period
    n_days <- as.numeric(end_date - start_date) + 1
    n_years <- n_days / 365.25

    tibble::tibble(
      period = period_name,
      start = start_date,
      end = end_date,
      n_spikes = nrow(period_spikes),
      n_days = n_days,
      spikes_per_year = n_spikes / n_years,
      mean_duration = mean(period_spikes$duration_days, na.rm = TRUE),
      median_duration = median(period_spikes$duration_days, na.rm = TRUE),
      total_spike_days = sum(period_spikes$duration_days, na.rm = TRUE),
      pct_days_in_spike = 100 * total_spike_days / n_days
    )
  })

  period_stats
}
