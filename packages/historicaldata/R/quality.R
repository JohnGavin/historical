#' Detect price jumps across all tickers in a dataset
#'
#' Finds dates where the absolute log return exceeds a threshold.
#' Large jumps may indicate: missing split adjustments, share consolidations,
#' currency redenominations, or genuine market events.
#'
#' @param dataset Dataset name (default "equity_daily")
#' @param threshold Minimum absolute log return to flag (default 0.4 = ~50%)
#' @param n Maximum number of jumps to return (default 100)
#' @return Tibble with: ticker, date, prev_close, close, log_ret, pct_change
#' @export
#' @examples
#' \donttest{
#' hd_jumps("equity_daily", threshold = 0.5, n = 20)
#' }
hd_jumps <- function(dataset = "equity_daily", threshold = 0.4, n = 100) {
  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  ds <- hd_datasets()[[dataset]]
  if (is.null(ds)) cli::cli_abort("Unknown dataset: {dataset}")

  price_col <- if ("adjusted" %in% ds$schema) "adjusted" else "close"

  sql <- sprintf("
    WITH returns AS (
      SELECT ticker, date, %s AS close,
        LAG(%s) OVER (PARTITION BY ticker ORDER BY date) AS prev_close,
        LN(%s / NULLIF(LAG(%s) OVER (PARTITION BY ticker ORDER BY date), 0)) AS log_ret
      FROM read_parquet('%s')
    )
    SELECT ticker, date::DATE AS date, prev_close, close,
      ROUND(log_ret, 4) AS log_ret,
      ROUND((close / prev_close - 1) * 100, 1) AS pct_change
    FROM returns
    WHERE ABS(log_ret) > %f
    ORDER BY ABS(log_ret) DESC
    LIMIT %d",
    price_col, price_col, price_col, price_col, ds$url,
    threshold, as.integer(n)
  )

  DBI::dbGetQuery(con, sql) |> dplyr::as_tibble()
}

#' Summary of data quality per ticker
#'
#' Returns per-ticker stats: row count, date range, number of jumps,
#' max absolute jump, number of gaps > 5 days.
#'
#' @param dataset Dataset name (default "equity_daily")
#' @param jump_threshold Log return threshold for counting jumps (default 0.4)
#' @return Tibble with quality metrics per ticker
#' @family quality-audit
#' @export
hd_quality <- function(dataset = "equity_daily", jump_threshold = 0.4) {
  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  ds <- hd_datasets()[[dataset]]
  if (is.null(ds)) cli::cli_abort("Unknown dataset: {dataset}")

  price_col <- if ("adjusted" %in% ds$schema) "adjusted" else "close"

  sql <- sprintf("
    WITH data AS (
      SELECT ticker, date, %s AS close,
        LAG(%s) OVER (PARTITION BY ticker ORDER BY date) AS prev_close,
        LAG(date) OVER (PARTITION BY ticker ORDER BY date) AS prev_date
      FROM read_parquet('%s')
    ),
    metrics AS (
      SELECT ticker, date, close, prev_close, prev_date,
        LN(close / NULLIF(prev_close, 0)) AS log_ret,
        DATEDIFF('day', prev_date, date) AS gap_days
      FROM data
      WHERE prev_close IS NOT NULL
    )
    SELECT ticker,
      COUNT(*) AS n_obs,
      MIN(date)::VARCHAR AS first_date,
      MAX(date)::VARCHAR AS last_date,
      SUM(CASE WHEN ABS(log_ret) > %f THEN 1 ELSE 0 END) AS n_jumps,
      ROUND(MAX(ABS(log_ret)), 3) AS max_abs_log_ret,
      SUM(CASE WHEN gap_days > 5 THEN 1 ELSE 0 END) AS n_gaps_5d
    FROM metrics
    GROUP BY ticker
    ORDER BY n_jumps DESC, max_abs_log_ret DESC",
    price_col, price_col, ds$url, jump_threshold
  )

  DBI::dbGetQuery(con, sql) |> dplyr::as_tibble()
}
