#' Top N tickers by a metadata metric
#'
#' Queries the metadata Parquet for tickers ranked by the specified metric.
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

  ds <- hd_datasets()[["metadata"]]
  lf <- duckplyr::read_parquet_duckdb(ds$url) |>
    dplyr::filter(dataset == !!dataset, !is.na(.data[[metric]]))

  if (desc) {
    lf <- lf |> dplyr::arrange(dplyr::desc(.data[[metric]]))
  } else {
    lf <- lf |> dplyr::arrange(.data[[metric]])
  }

  lf |> dplyr::collect() |> dplyr::slice_head(n = n)
}

# Pick the best available adjusted-price column from an actual column list.
# Priority: adjusted_close (canonical post-#397) > adjusted (legacy) > close.
# Internal helper — not exported.
.pick_price_col <- function(actual_cols) {
  if ("adjusted_close" %in% actual_cols) "adjusted_close"
  else if ("adjusted" %in% actual_cols) "adjusted"
  else "close"
}

#' Most volatile tickers by recent realised volatility
#'
#' Computes 21-day rolling annualised volatility for all tickers in a dataset
#' and returns the top N. Uses a single DuckDB window query over the full Parquet.
#'
#' The adjusted-price column is detected at runtime from the actual Parquet
#' columns (priority: `adjusted_close` > `adjusted` > `close`), so the
#' function tolerates parquets written both before and after the #397 rename.
#'
#' @param dataset Dataset name (default "equity_daily")
#' @param n Number of tickers to return (default 5)
#' @param window_days Rolling window in trading days (default 21)
#' @return Tibble with ticker, vol_21d, sorted by vol descending
#' @family curated-groups
#' @export
#' @examplesIf interactive()
#' hd_most_volatile("equity_daily", 3)
hd_most_volatile <- function(dataset = "equity_daily", n = 5, window_days = 21) {
  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  ds <- hd_datasets()[[dataset]]
  if (is.null(ds)) cli::cli_abort("Unknown dataset: {dataset}")

  # Detect price column from the actual parquet columns at runtime.
  # The registry schema declares adjusted_close, but parquets written before
  # issue #397 still use the old name `adjusted`. Checking ds$schema would
  # always resolve to adjusted_close (absent from old parquets) → Binder Error.
  src <- hd_read_parquet_sql(con, ds$url)
  actual_cols <- names(DBI::dbGetQuery(con, sprintf("SELECT * FROM %s LIMIT 0", src)))
  price_col <- .pick_price_col(actual_cols)

  sql <- sprintf("
    WITH returns AS (
      SELECT ticker, date, %s as price,
        TRY(LN(%s / NULLIF(LAG(%s) OVER (PARTITION BY ticker ORDER BY date), 0))) AS log_ret
      FROM %s
      WHERE %s > 0
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
        LAST(vol ORDER BY date) AS vol_21d,
        MAX(date) AS as_of
      FROM vol
      GROUP BY ticker
    )
    SELECT ticker, ROUND(vol_21d, 4) as vol_21d, as_of
    FROM latest_vol
    WHERE vol_21d IS NOT NULL
    ORDER BY vol_21d DESC
    LIMIT %d",
    price_col, price_col, price_col, src, price_col,
    as.integer(window_days) - 1L, as.integer(n)
  )

  DBI::dbGetQuery(con, sql) |> dplyr::as_tibble()
}
