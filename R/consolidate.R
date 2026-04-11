# Consolidation: write clean data as single Parquet per asset class

#' Consolidate cleaned data into a single Parquet-ready tibble
#'
#' In the full pipeline this writes Hive-partitioned Parquet locally
#' and a single consolidated Parquet for HF distribution.
#' For the prototype, we just return the cleaned tibble with standard schema.
#'
#' @param clean_data Cleaned tibble from clean_equity() or clean_crypto()
#' @param asset_class "equity" or "crypto"
#' @return Tibble with standardised schema ready for Parquet serialisation
consolidate_parquet <- function(clean_data, asset_class) {
  # Enforce the unified output schema
  out <- clean_data |>
    dplyr::mutate(
      asset_class = asset_class,
      updated_at = Sys.time()
    )

  # Sort for optimal Parquet row group compression
  out <- out |>
    dplyr::arrange(ticker, date)

  n_tickers <- dplyr::n_distinct(out$ticker)
  n_rows <- nrow(out)
  date_range <- range(out$date, na.rm = TRUE)

  cli::cli_inform(c(
    "v" = "Consolidated {asset_class}: {n_tickers} ticker{?s}, {n_rows} rows",
    "i" = "Date range: {date_range[1]} to {date_range[2]}"
  ))

  out
}
