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
#' @param df Tibble with adv_usd column
#' @param min_adv_usd Minimum average daily volume in USD (default $1M)
#' @param filter_mode "warn" (default) or "remove"
#' @return Filtered tibble with liquidity_flag column
#' @export
filter_liquidity <- function(df, min_adv_usd = 1e6, filter_mode = "warn") {
  if (!"adv_usd" %in% names(df)) {
    cli::cli_abort("adv_usd column missing. Run calculate_adv() first.")
  }

  df <- df |>
    dplyr::mutate(
      liquidity_flag = dplyr::case_when(
        is.na(adv_usd) ~ "insufficient_data",
        adv_usd < min_adv_usd ~ "illiquid",
        TRUE ~ "liquid"
      )
    )

  n_illiquid <- sum(df$liquidity_flag == "illiquid", na.rm = TRUE)
  n_total <- nrow(df)
  pct_illiquid <- round(100 * n_illiquid / n_total, 1)

  if (n_illiquid > 0) {
    cli::cli_warn(c(
      "!" = "{n_illiquid} / {n_total} ({pct_illiquid}%) observations flagged as illiquid (ADV < ${scales::comma(min_adv_usd)})",
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
#' Compares actual position changes to assumed 80% monthly turnover
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
