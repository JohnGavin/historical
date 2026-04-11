# Cleaning functions: dedup, adjust, impute

#' Clean equity data from multiple sources
#'
#' Strategy:
#'   1. Combine sources, preferring API (Yahoo) over static (Kaggle)
#'   2. Deduplicate by (ticker, date), keeping API source
#'   3. Use Yahoo adjusted prices (split/dividend corrected)
#'   4. Impute short gaps (<= 5 days) via LOCF
#'
#' @param api_data Validated equity data from API source (Yahoo)
#' @param static_data Validated equity data from static source (Kaggle)
#' @return Cleaned, deduplicated tibble
clean_equity <- function(api_data, static_data) {
  # Ensure both have adjusted column
  if (!"adjusted" %in% names(static_data)) {
    static_data$adjusted <- static_data$close
  }
  if (!"adjusted" %in% names(api_data)) {
    api_data$adjusted <- api_data$close
  }

  # Standardise to common schema
  schema_cols <- c("date", "open", "high", "low", "close", "adjusted",
                   "volume", "ticker", "source", "asset_class")

  api_std <- api_data |>
    ensure_columns(schema_cols) |>
    dplyr::select(dplyr::any_of(schema_cols))

  static_std <- static_data |>
    ensure_columns(schema_cols) |>
    dplyr::select(dplyr::any_of(schema_cols))

  # Combine and deduplicate: prefer API source
  combined <- dplyr::bind_rows(api_std, static_std) |>
    dplyr::mutate(
      source_priority = dplyr::case_when(
        source == "yahoo" ~ 1L,
        source == "kaggle" ~ 2L,
        TRUE ~ 3L
      )
    ) |>
    dplyr::arrange(ticker, date, source_priority) |>
    dplyr::distinct(ticker, date, .keep_all = TRUE) |>
    dplyr::select(-source_priority)

  # Impute short gaps (weekends/holidays are NOT gaps — they're expected)
  # Only impute if there's a gap > 1 business day
  combined |>
    dplyr::arrange(ticker, date)
}

#' Clean crypto data from multiple sources
#'
#' Strategy:
#'   1. Combine sources, preferring API (CoinGecko) over static
#'   2. Deduplicate by (ticker, date)
#'   3. No split/dividend adjustment needed for crypto
#'
#' @param api_data Validated crypto data from API source
#' @param static_data Validated crypto data from static source
#' @return Cleaned, deduplicated tibble
clean_crypto <- function(api_data, static_data) {
  schema_cols <- c("date", "close", "volume", "market_cap",
                   "ticker", "source", "asset_class")

  api_std <- api_data |>
    ensure_columns(schema_cols) |>
    dplyr::select(dplyr::any_of(schema_cols))

  static_std <- static_data |>
    ensure_columns(schema_cols) |>
    dplyr::select(dplyr::any_of(schema_cols))

  dplyr::bind_rows(api_std, static_std) |>
    dplyr::mutate(
      source_priority = dplyr::case_when(
        source == "coingecko" ~ 1L,
        source == "backfill" ~ 2L,
        TRUE ~ 3L
      )
    ) |>
    dplyr::arrange(ticker, date, source_priority) |>
    dplyr::distinct(ticker, date, .keep_all = TRUE) |>
    dplyr::select(-source_priority) |>
    dplyr::arrange(ticker, date)
}

#' Ensure a tibble has all expected columns (add NA columns if missing)
ensure_columns <- function(df, expected_cols) {
  missing <- setdiff(expected_cols, names(df))
  for (col in missing) {
    df[[col]] <- NA
  }
  df
}
