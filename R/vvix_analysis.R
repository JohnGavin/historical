# VVIX (Volatility-of-Volatility) Analysis
# Gap from #105: Volatility coverage 70% → 90% (add vol-of-vol regimes)
# VVIX measures the volatility of VIX itself — high VVIX = unstable vol regime

#' Classify Vol-of-Vol Regimes
#'
#' @param vix_data Tibble with columns: date, vix
#' @param vvix_data Tibble with columns: date, vvix
#' @param vvix_threshold VVIX threshold for unstable regime (default 100)
#' @return Tibble with date, vix, vvix, vol_regime, vvix_regime
#' @export
classify_vvix_regimes <- function(vix_data, vvix_data, vvix_threshold = 100) {
  # Join VIX and VVIX
  combined <- vix_data |>
    dplyr::left_join(vvix_data, by = "date", suffix = c("", "_vvix"))

  # Classify regimes
  combined |>
    dplyr::mutate(
      # VIX regime (same as existing classification)
      vol_regime = dplyr::case_when(
        vix < 20 ~ "low_vol",
        vix >= 20 & vix < 30 ~ "medium_vol",
        vix >= 30 ~ "high_vol",
        TRUE ~ NA_character_
      ),
      # VVIX regime (vol-of-vol)
      vvix_regime = dplyr::case_when(
        vvix < vvix_threshold ~ "stable_vol",
        vvix >= vvix_threshold ~ "unstable_vol",
        TRUE ~ NA_character_
      ),
      # Combined regime (9 states: 3 VIX × 3 VVIX)
      combined_regime = paste0(vol_regime, "_", vvix_regime)
    )
}

#' Calculate VIX Stability Metrics
#'
#' High VVIX indicates VIX is itself volatile — uncertainty about uncertainty.
#' Useful for position sizing: in unstable regimes, VIX moves are less predictable.
#'
#' @param regime_data Output from classify_vvix_regimes()
#' @return Tibble with regime-conditional VIX stability metrics
#' @export
vix_stability_metrics <- function(regime_data) {
  regime_data |>
    dplyr::group_by(vvix_regime) |>
    dplyr::summarise(
      n_days = dplyr::n(),
      mean_vix = mean(vix, na.rm = TRUE),
      sd_vix = sd(vix, na.rm = TRUE),
      cv_vix = sd_vix / mean_vix,  # Coefficient of variation
      vix_range_90pct = diff(quantile(vix, c(0.05, 0.95), na.rm = TRUE)),
      mean_vvix = mean(vvix, na.rm = TRUE),
      .groups = "drop"
    )
}

#' Detect Vol Regime Transitions
#'
#' Identifies dates when vol regime changed — useful for event studies.
#'
#' @param regime_data Output from classify_vvix_regimes()
#' @return Tibble with transition dates and from/to regimes
#' @export
detect_vol_transitions <- function(regime_data) {
  regime_data |>
    dplyr::arrange(date) |>
    dplyr::mutate(
      prev_vol_regime = dplyr::lag(vol_regime),
      prev_vvix_regime = dplyr::lag(vvix_regime),
      vol_transition = vol_regime != prev_vol_regime,
      vvix_transition = vvix_regime != prev_vvix_regime
    ) |>
    dplyr::filter(vol_transition | vvix_transition) |>
    dplyr::select(
      date,
      from_vol = prev_vol_regime,
      to_vol = vol_regime,
      from_vvix = prev_vvix_regime,
      to_vvix = vvix_regime,
      vix,
      vvix
    )
}

#' Enhanced Crisis Detection with VVIX
#'
#' Crisis = high VIX + unstable VVIX. More refined than VIX alone.
#'
#' @param regime_data Output from classify_vvix_regimes()
#' @param vix_crisis_threshold VIX level for crisis (default 30)
#' @param vvix_crisis_threshold VVIX level for crisis (default 120)
#' @return Tibble with crisis flags and severity
#' @export
enhanced_crisis_detection <- function(regime_data,
                                     vix_crisis_threshold = 30,
                                     vvix_crisis_threshold = 120) {
  regime_data |>
    dplyr::mutate(
      vix_crisis = vix >= vix_crisis_threshold,
      vvix_crisis = vvix >= vvix_crisis_threshold,
      crisis_severity = dplyr::case_when(
        vix_crisis & vvix_crisis ~ "severe",  # High vol + unstable
        vix_crisis & !vvix_crisis ~ "moderate",  # High vol but stable
        !vix_crisis & vvix_crisis ~ "brewing",  # Low vol but unstable (warning)
        TRUE ~ "calm"
      )
    ) |>
    dplyr::select(date, vix, vvix, vol_regime, vvix_regime, crisis_severity)
}
