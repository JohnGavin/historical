#' Top N tickers by a metadata metric
#'
#' Queries the metadata Parquet for tickers ranked by the specified metric.
#'
#' @param dataset Dataset name (e.g. "equity_daily", "crypto_daily")
#' @param metric Column name to rank by: "market_cap", "volume_avg", "total_obs", "missing_pct"
#' @param n Number of tickers to return (default 10)
#' @param desc Sort descending? (default TRUE = largest first)
#' @return Tibble with ticker + metadata columns, sorted by metric
#' @export
#' @examples
#' hd_top_by("equity_daily", "market_cap", 5)
#' hd_top_by("crypto_daily", "volume_avg", 3)
hd_top_by <- function(dataset, metric, n = 10, desc = TRUE) {
  valid_metrics <- c("market_cap", "volume_avg", "total_obs", "missing_pct",
                     "fifty_two_week_high", "fifty_two_week_low", "expense_ratio",
                     "yield_pct", "beta_3yr", "ytd_return", "three_yr_return")
  if (!metric %in% valid_metrics) {
    cli::cli_abort("Invalid metric: {metric}. Valid: {paste(valid_metrics, collapse = ', ')}")
  }


  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  ds <- hd_datasets()[["metadata"]]
  direction <- if (desc) "DESC" else "ASC"
  sql <- sprintf(
    "SELECT * FROM read_parquet('%s') WHERE dataset = ? AND %s IS NOT NULL ORDER BY %s %s LIMIT %d",
    ds$url, metric, metric, direction, as.integer(n)
  )

  DBI::dbGetQuery(con, sql, params = list(dataset)) |>
    dplyr::as_tibble()
}

#' Most volatile tickers by recent realised volatility
#'
#' Computes 21-day rolling annualised volatility for all tickers in a dataset
#' and returns the top N. Uses a single DuckDB window query over the full Parquet.
#'
#' @param dataset Dataset name (default "equity_daily")
#' @param n Number of tickers to return (default 5)
#' @param window_days Rolling window in trading days (default 21)
#' @return Tibble with ticker, vol_21d, sorted by vol descending
#' @export
#' @examples
#' hd_most_volatile("equity_daily", 3)
hd_most_volatile <- function(dataset = "equity_daily", n = 5, window_days = 21) {
  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  ds <- hd_datasets()[[dataset]]
  if (is.null(ds)) cli::cli_abort("Unknown dataset: {dataset}")

  # Use adjusted if available (equity), else close
  price_col <- if ("adjusted" %in% ds$schema) "adjusted" else "close"

  sql <- sprintf("
    WITH returns AS (
      SELECT ticker, date, %s as price,
        LN(%s / LAG(%s) OVER (PARTITION BY ticker ORDER BY date)) AS log_ret
      FROM read_parquet('%s')
    ),
    vol AS (
      SELECT ticker, date, log_ret,
        STDDEV(log_ret) OVER (PARTITION BY ticker ORDER BY date
          ROWS BETWEEN %d PRECEDING AND CURRENT ROW) * SQRT(252) AS vol
      FROM returns
      WHERE log_ret IS NOT NULL
    ),
    latest_vol AS (
      SELECT ticker,
        LAST(vol) AS vol_21d,
        LAST(date) AS as_of
      FROM vol
      GROUP BY ticker
    )
    SELECT ticker, ROUND(vol_21d, 4) as vol_21d, as_of
    FROM latest_vol
    WHERE vol_21d IS NOT NULL
    ORDER BY vol_21d DESC
    LIMIT %d",
    price_col, price_col, price_col, ds$url,
    as.integer(window_days) - 1L, as.integer(n)
  )

  DBI::dbGetQuery(con, sql) |> dplyr::as_tibble()
}
