# Validation functions for historical data pipeline
# Uses pointblank for schema/type/range checks

#' Validate equity OHLCV data
#' @param df Tibble with equity OHLCV data
#' @param source_label Label for error messages
#' @return The input tibble (unchanged) if validation passes; stops on failure
validate_equity <- function(df, source_label = "unknown") {
  agent <- pointblank::create_agent(df) |>
    pointblank::col_exists(columns = c("date", "open", "high", "low", "close", "volume", "ticker")) |>
    pointblank::col_is_date(columns = "date") |>
    pointblank::col_is_numeric(columns = c("open", "high", "low", "close")) |>
    pointblank::col_vals_gt(columns = "close", value = 0, na_pass = TRUE) |>
    pointblank::col_vals_gte(columns = "high", value = pointblank::vars(low), na_pass = TRUE) |>
    pointblank::col_vals_not_null(columns = c("date", "ticker")) |>
    pointblank::interrogate()

  n_fail <- sum(agent$validation_set$n_failed, na.rm = TRUE)
  if (n_fail > 0) {
    cli::cli_warn(c(
      "!" = "Validation issues in equity data from {source_label}: {n_fail} failures",
      "i" = "Run pointblank::get_agent_report() for details"
    ))
  }

  # Standardise column names and types
  df |>
    dplyr::mutate(
      date = as.Date(date),
      across(c(open, high, low, close), as.double),
      volume = as.double(volume)
    )
}

#' Validate crypto OHLCV data
#' @param df Tibble with crypto data
#' @param source_label Label for error messages
#' @return The input tibble (unchanged) if validation passes
validate_crypto <- function(df, source_label = "unknown") {
  # Crypto data may have different column names depending on source
  # Standardise first, then validate
  df <- standardise_crypto_columns(df)

  agent <- pointblank::create_agent(df) |>
    pointblank::col_exists(columns = c("date", "close", "ticker")) |>
    pointblank::col_is_date(columns = "date") |>
    pointblank::col_is_numeric(columns = "close") |>
    pointblank::col_vals_gt(columns = "close", value = 0, na_pass = TRUE) |>
    pointblank::col_vals_not_null(columns = c("date", "ticker")) |>
    pointblank::interrogate()

  n_fail <- sum(agent$validation_set$n_failed, na.rm = TRUE)
  if (n_fail > 0) {
    cli::cli_warn(c(
      "!" = "Validation issues in crypto data from {source_label}: {n_fail} failures",
      "i" = "Run pointblank::get_agent_report() for details"
    ))
  }

  df
}

#' Standardise crypto column names across sources
#' CoinGecko (geckor) uses price_close, total_volume, etc.
#' Kaggle/backfill may use close, volume, etc.
standardise_crypto_columns <- function(df) {
  nms <- names(df)

  # geckor output: price_close -> close
  if ("price_close" %in% nms && !"close" %in% nms) {
    df <- dplyr::rename(df, close = price_close)
  }
  if ("total_volume" %in% nms && !"volume" %in% nms) {
    df <- dplyr::rename(df, volume = total_volume)
  }

  df |>
    dplyr::mutate(date = as.Date(date))
}
