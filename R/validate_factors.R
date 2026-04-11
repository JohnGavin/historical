# Validation for Ken French factor data

#' Validate French factor data
#' @param df Tibble with columns: date, factor_name, value, dataset, frequency, source
#' @return Validated tibble
validate_factors <- function(df) {
  agent <- pointblank::create_agent(df) |>
    pointblank::col_exists(columns = c("date", "factor_name", "value", "dataset")) |>
    pointblank::col_is_date(columns = "date") |>
    pointblank::col_is_numeric(columns = "value") |>
    pointblank::col_vals_not_null(columns = c("date", "factor_name")) |>
    pointblank::interrogate()

  n_fail <- sum(agent$validation_set$n_failed, na.rm = TRUE)
  if (n_fail > 0) {
    cli::cli_warn("Validation issues in factor data: {n_fail} failures")
  }

  n_factors <- dplyr::n_distinct(df$factor_name)
  cli::cli_inform(c("v" = "Validated {n_factors} factors, {nrow(df)} total observations"))
  df
}
