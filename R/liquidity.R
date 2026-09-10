# Liquidity analysis functions
# Gap from #105: volume data ingested but not used for liquidity metrics

#' Calculate average daily volume (ADV) in dollar terms
#'
#' @param df Tibble with columns: date, ticker, close, volume
#' @param window_days Rolling window for ADV calculation (default 20 trading days)
#' @return Tibble with additional column: adv_usd (average daily volume in USD)
#' @export
calculate_adv <- function(df, window_days = 20) {
  df |>
    dplyr::arrange(ticker, date) |>
    dplyr::group_by(ticker) |>
    dplyr::mutate(
      dollar_volume = close * volume,
      adv_usd = slider::slide_dbl(
        dollar_volume,
        mean,
        .before = window_days - 1,
        .complete = TRUE,
        na.rm = TRUE
      )
    ) |>
    dplyr::ungroup() |>
    dplyr::select(-dollar_volume)
}

#' Apply liquidity filter based on minimum ADV
#'
#' Two threshold modes are supported (#625):
#'
#' - `"nominal"` (default) flags rows below a fixed dollar `min_adv_usd`.
#'   This is a fixed cut that drifts in liquidity-percentile terms as
#'   market-wide ADV grows over a multi-decade sample -- see the issue's
#'   "A real modelling concern" section.
#' - `"percentile"` flags the bottom `min_adv_percentile` fraction of the
#'   cross-section defined by `by` (default `"date"`) each period, so the
#'   threshold is recomputed from current data and is regime-invariant
#'   against ADV growth/inflation over the sample -- the "principled fix"
#'   option in #625.
#'
#' @param df Tibble with adv_usd column (and, for `threshold_mode =
#'   "percentile"`, the column named by `by`)
#' @param min_adv_usd Minimum average daily volume in USD (default $1M).
#'   Used when `threshold_mode = "nominal"`.
#' @param filter_mode "warn" (default) or "remove"
#' @param threshold_mode "nominal" (default, fixed dollar cut) or
#'   "percentile" (cross-sectional percentile cut, recomputed per `by`
#'   group)
#' @param min_adv_percentile Minimum ADV percentile rank within each `by`
#'   group (default 0.30, i.e. the bottom 30% by ADV are flagged illiquid).
#'   Used when `threshold_mode = "percentile"`.
#' @param by Column defining the cross-section percentile is computed
#'   within (default `"date"`). Used when `threshold_mode = "percentile"`.
#' @return Filtered tibble with liquidity_flag column
#' @export
filter_liquidity <- function(df,
                              min_adv_usd = 1e6,
                              filter_mode = "warn",
                              threshold_mode = c("nominal", "percentile"),
                              min_adv_percentile = 0.30,
                              by = "date") {
  threshold_mode <- match.arg(threshold_mode)

  if (!"adv_usd" %in% names(df)) {
    cli::cli_abort("adv_usd column missing. Run calculate_adv() first.")
  }

  if (threshold_mode == "percentile") {
    if (!by %in% names(df)) {
      cli::cli_abort(
        "Column {.val {by}} (threshold_mode = 'percentile' cross-section key, `by`) not found in df."
      )
    }
    df <- df |>
      dplyr::mutate(.pctile_grp = .data[[by]]) |>
      dplyr::group_by(.pctile_grp) |>
      dplyr::mutate(
        .adv_pctile = dplyr::if_else(
          is.na(adv_usd),
          NA_real_,
          dplyr::percent_rank(adv_usd)
        ),
        liquidity_flag = dplyr::case_when(
          is.na(adv_usd) ~ "insufficient_data",
          .adv_pctile < min_adv_percentile ~ "illiquid",
          TRUE ~ "liquid"
        )
      ) |>
      dplyr::ungroup() |>
      dplyr::select(-.pctile_grp, -.adv_pctile)
  } else {
    df <- df |>
      dplyr::mutate(
        liquidity_flag = dplyr::case_when(
          is.na(adv_usd) ~ "insufficient_data",
          adv_usd < min_adv_usd ~ "illiquid",
          TRUE ~ "liquid"
        )
      )
  }

  n_illiquid <- sum(df$liquidity_flag == "illiquid", na.rm = TRUE)
  n_total <- nrow(df)
  pct_illiquid <- round(100 * n_illiquid / n_total, 1)

  if (n_illiquid > 0) {
    threshold_desc <- if (threshold_mode == "percentile") {
      "ADV percentile rank < {min_adv_percentile} within each '{by}' cross-section"
    } else {
      "ADV < ${scales::comma(min_adv_usd)}"
    }
    cli::cli_warn(c(
      "!" = paste0(
        "{n_illiquid} / {n_total} ({pct_illiquid}%) observations flagged as illiquid (",
        threshold_desc, ")"
      ),
      "i" = "Set filter_mode='remove' to exclude them"
    ))
  }

  if (filter_mode == "remove") {
    df <- df |>
      dplyr::filter(liquidity_flag == "liquid")
    cli::cli_inform(c("v" = "Removed {n_illiquid} illiquid observations"))
  }

  df
}

#' Compute liquidity summary statistics by ticker
#'
#' @param df Tibble with volume, close, adv_usd columns
#' @return Summary tibble with liquidity metrics per ticker
#' @export
liquidity_summary <- function(df) {
  df |>
    dplyr::group_by(ticker) |>
    dplyr::summarise(
      n_obs = dplyr::n(),
      median_volume = stats::median(volume, na.rm = TRUE),
      median_price = stats::median(close, na.rm = TRUE),
      median_adv_usd = stats::median(adv_usd, na.rm = TRUE),
      pct_illiquid = 100 * mean(liquidity_flag == "illiquid", na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(median_adv_usd))
}

#' Calculate realized turnover for a strategy
#'
#' Compares actual position changes to assumed 80% monthly turnover.
#'
#' NOT wired into any targets pipeline (#569). The `assumed_turnover = 0.80`
#' constant below is itself under review in #567 — do not wire this function
#' in until that issue resolves the constant, to avoid a collision.
#'
#' @param positions Tibble with columns: date, ticker, weight (target weights)
#' @return Monthly turnover summary
#' @export
calculate_turnover <- function(positions) {
  positions |>
    dplyr::arrange(ticker, date) |>
    dplyr::group_by(ticker) |>
    dplyr::mutate(
      weight_change = abs(weight - dplyr::lag(weight, default = 0))
    ) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      year_month = format(date, "%Y-%m")
    ) |>
    dplyr::group_by(year_month) |>
    dplyr::summarise(
      monthly_turnover = sum(weight_change, na.rm = TRUE) / 2,  # Divide by 2 (buy + sell)
      .groups = "drop"
    ) |>
    dplyr::summarise(
      mean_monthly_turnover = mean(monthly_turnover, na.rm = TRUE),
      median_monthly_turnover = stats::median(monthly_turnover, na.rm = TRUE),
      sd_monthly_turnover = stats::sd(monthly_turnover, na.rm = TRUE),
      assumed_turnover = 0.80,
      difference = mean_monthly_turnover - 0.80,
      .groups = "drop"
    )
}
