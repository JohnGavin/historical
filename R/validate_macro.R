# Validation functions for FRED macro data

#' Validate FRED macro series
#' @param df Tibble with columns: date, value, series_id, source
#' @return Validated tibble
validate_macro <- function(df) {
  agent <- pointblank::create_agent(df) |>
    pointblank::col_exists(columns = c("date", "value", "series_id", "source")) |>
    pointblank::col_is_date(columns = "date") |>
    pointblank::col_is_numeric(columns = "value") |>
    pointblank::col_vals_not_null(columns = c("date", "series_id")) |>
    pointblank::interrogate()

  n_fail <- sum(agent$validation_set$n_failed, na.rm = TRUE)
  if (n_fail > 0) {
    cli::cli_warn(c(
      "!" = "Validation issues in macro data: {n_fail} failures"
    ))
  }

  # Report per-series summary
  summary <- df |>
    dplyr::group_by(series_id) |>
    dplyr::summarise(
      n = dplyr::n(),
      n_na = sum(is.na(value)),
      from = min(date),
      to = max(date),
      .groups = "drop"
    )

  cli::cli_inform(c(
    "v" = "Validated {nrow(summary)} macro series, {nrow(df)} total observations"
  ))

  df
}
