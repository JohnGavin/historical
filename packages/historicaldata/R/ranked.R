#' Top N tickers by a metadata metric
#'
#' Queries the metadata Parquet for tickers ranked by the specified metric.
#' The Parquet is filtered by dataset in DuckDB, then collected into R memory
#' before the dynamic-column filter and sort (`.data[[metric]]` is not
#' translatable by duckplyr in a lazy frame).
#'
#' @param dataset Dataset name (e.g. "equity_daily", "crypto_daily")
#' @param metric Column name to rank by: "market_cap", "volume_avg", "total_obs", "missing_pct"
#' @param n Number of tickers to return (default 10)
#' @param desc Sort descending? (default TRUE = largest first)
#' @return Tibble with ticker + metadata columns, sorted by metric
#' @family curated-groups
#' @export
#' @examplesIf interactive()
#' hd_top_by("equity_daily", "market_cap", 5)
#' hd_top_by("crypto_daily", "volume_avg", 3)
hd_top_by <- function(dataset, metric, n = 10, desc = TRUE) {
  valid_metrics <- c("market_cap", "volume_avg", "total_obs", "missing_pct",
                     "fifty_two_week_high", "fifty_two_week_low", "expense_ratio",
                     "yield_pct", "beta_3yr", "ytd_return", "three_yr_return")
  if (!metric %in% valid_metrics) {
    cli::cli_abort("Invalid metric: {metric}. Valid: {paste(valid_metrics, collapse = ', ')}")
  }

  df <- duckplyr::read_parquet_duckdb(hd_dataset_source("metadata")) |>
    dplyr::filter(dataset == !!dataset) |>
    dplyr::collect()
  df <- df |> dplyr::filter(!is.na(.data[[metric]]))
  df <- if (desc) {
    df |> dplyr::arrange(dplyr::desc(.data[[metric]]))
  } else {
    df |> dplyr::arrange(.data[[metric]])
  }
  df |> dplyr::slice_head(n = n)
}

# Pick the best available adjusted-price column from an actual column list.
# Priority: adjusted_close (canonical post-#397) > adjusted (legacy) > close.
# Internal helper — not exported.
.pick_price_col <- function(actual_cols) {
  if ("adjusted_close" %in% actual_cols) "adjusted_close"
  else if ("adjusted" %in% actual_cols) "adjusted"
  else "close"
}

# Compute rolling annualised volatility for each ticker and return the top N.
#
# `raw`        — collected data frame with ticker, date, and `price_col` column.
# `price_col`  — name of the price column (output of .pick_price_col).
# `window_days`— rolling window in trading days.
# `n`          — number of top-vol tickers to return.
#
# Returns a tibble with columns: ticker, vol_21d, as_of.
# Annualisation factor: sqrt(252) for daily returns.
# Internal helper — not exported. Extracted for testability.
.rolling_vol_rank <- function(raw, price_col, window_days, n) {
  raw |>
    dplyr::filter(.data[[price_col]] > 0) |>
    dplyr::group_by(ticker) |>
    dplyr::arrange(date, .by_group = TRUE) |>
    dplyr::mutate(log_ret = log(.data[[price_col]] / dplyr::lag(.data[[price_col]]))) |>
    dplyr::filter(!is.na(log_ret)) |>
    dplyr::mutate(
      vol_21d = slider::slide_dbl(log_ret, stats::sd,
        .before = as.integer(window_days) - 1L, .complete = TRUE) * sqrt(252)
    ) |>
    dplyr::slice_tail(n = 1) |>
    dplyr::ungroup() |>
    dplyr::filter(!is.na(vol_21d)) |>
    dplyr::arrange(dplyr::desc(vol_21d)) |>
    dplyr::slice_head(n = n) |>
    dplyr::transmute(ticker, vol_21d = round(vol_21d, 4), as_of = date)
}

#' Most volatile tickers by recent realised volatility
#'
#' Computes 21-day rolling annualised volatility for all tickers in a dataset
#' and returns the top N. The full Parquet is collected into R memory and
#' rolling volatility is computed with `slider::slide_dbl()` — no raw SQL
#' window functions are used.
#'
#' The adjusted-price column is detected at runtime from the actual Parquet
#' columns (priority: `adjusted_close` > `adjusted` > `close`), so the
#' function tolerates parquets written both before and after the #397 rename.
#'
#' @param dataset Dataset name (default "equity_daily")
#' @param n Number of tickers to return (default 5)
#' @param window_days Rolling window in trading days (default 21)
#' @return Tibble with columns ticker, vol_21d, as_of; sorted by vol descending
#' @family curated-groups
#' @export
#' @examplesIf interactive()
#' hd_most_volatile("equity_daily", 3)
hd_most_volatile <- function(dataset = "equity_daily", n = 5, window_days = 21) {
  ds <- hd_datasets()[[dataset]]
  if (is.null(ds)) cli::cli_abort("Unknown dataset: {dataset}")
  raw <- duckplyr::read_parquet_duckdb(hd_dataset_source(dataset)) |> dplyr::collect()
  price_col <- .pick_price_col(names(raw))
  .rolling_vol_rank(raw, price_col, window_days, n)
}
