#' Search tickers by pattern across all datasets
#'
#' Searches ticker symbols and long names using regex or glob patterns.
#'
#' @param pattern Regex pattern (default) or glob (if contains `*` or `?`)
#' @param dataset Filter to one dataset (e.g. "equity_daily"). NULL = all.
#' @return Tibble of matching tickers with metadata
#' @export
#' @examples
#' hd_search("^APP")     # regex: tickers starting with APP
#' hd_search("*coin*")   # glob: names containing "coin"
hd_search <- function(pattern, dataset = NULL) {

  # Convert glob to regex if pattern contains unescaped * or ?
  # (but NOT inside character classes like [.])
  is_glob <- grepl("\\*|(?<!\\[)\\?", pattern, perl = TRUE) &&
    !grepl("\\[.*\\]", pattern)
  if (is_glob) {
    pattern <- utils::glob2rx(pattern, trim.head = TRUE, trim.tail = TRUE)
  }

  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  ds <- hd_datasets()[["metadata"]]

  # DuckDB parameterised binding doesn't work with regexp_matches
  # Use direct interpolation (pattern is a regex, not user SQL)
  escaped_pattern <- gsub("'", "''", pattern)
  where <- sprintf(
    "regexp_matches(ticker, '%s') OR regexp_matches(LOWER(long_name), LOWER('%s'))",
    escaped_pattern, escaped_pattern
  )

  if (!is.null(dataset)) {
    where <- paste0("(", where, ") AND dataset = '", gsub("'", "''", dataset), "'")
  }

  sql <- sprintf(
    "SELECT * FROM read_parquet('%s') WHERE %s ORDER BY dataset, ticker",
    ds$url, where
  )

  DBI::dbGetQuery(con, sql) |>
    dplyr::as_tibble()
}

#' Summary of all datasets
#'
#' Returns one row per dataset with ticker count, row count, and date range.
#'
#' @return Tibble with dataset, n_tickers, total_obs, min_date, max_date, description
#' @export
hd_summary <- function() {
  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  ds <- hd_datasets()[["metadata"]]
  DBI::dbGetQuery(con, sprintf(
    "SELECT dataset, COUNT(*) as n_tickers,
            SUM(total_obs) as total_obs,
            MIN(start_date) as min_date,
            MAX(end_date) as max_date
     FROM read_parquet('%s')
     GROUP BY dataset ORDER BY dataset", ds$url
  )) |>
    dplyr::as_tibble() |>
    dplyr::left_join(
      dplyr::tibble(
        dataset = names(hd_datasets()),
        description = vapply(hd_datasets(), \(x) x$description, character(1))
      ),
      by = "dataset"
    )
}

#' List all exchanges
#'
#' @param dataset Filter to one dataset. NULL = all.
#' @return Tibble with exchange, full_exchange, n_tickers
#' @export
hd_exchanges <- function(dataset = NULL) {
  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  ds <- hd_datasets()[["metadata"]]
  where <- if (!is.null(dataset)) sprintf("WHERE dataset = '%s'", dataset) else ""
  DBI::dbGetQuery(con, sprintf(
    "SELECT exchange, full_exchange, COUNT(*) as n_tickers,
            STRING_AGG(DISTINCT dataset, ', ') as datasets
     FROM read_parquet('%s') %s
     GROUP BY exchange, full_exchange ORDER BY n_tickers DESC",
    ds$url, where
  )) |> dplyr::as_tibble()
}

#' Compact metadata table for a vector of tickers
#'
#' Returns key metadata columns for display below plots. Accepts single or
#' multiple tickers. Uses batch `IN (...)` query.
#'
#' @param tickers Character vector of ticker symbols
#' @return Tibble with: ticker, long_name, currency, exchange, market_cap,
#'   volume_avg, yield_pct, beta_3yr
#' @export
#' @examples
#' hd_ticker_meta(c("AAPL", "MSFT"))
#' hd_ticker_meta(hd_group("FAANG"))
hd_ticker_meta <- function(tickers) {
  tickers <- as.character(tickers)
  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  ds <- hd_datasets()[["metadata"]]
  placeholders <- paste(rep("?", length(tickers)), collapse = ", ")
  sql <- sprintf(
    "SELECT ticker, long_name, currency, exchange, market_cap, volume_avg,
            yield_pct, beta_3yr, start_date, end_date, total_obs
     FROM read_parquet('%s') WHERE ticker IN (%s)
     ORDER BY ticker",
    ds$url, placeholders
  )

  DBI::dbGetQuery(con, sql, params = as.list(tickers)) |>
    dplyr::as_tibble()
}

#' Full metadata for one ticker
#'
#' @param ticker Ticker symbol (e.g. "AAPL", "BTC")
#' @return One-row tibble with all metadata columns
#' @export
hd_ticker_info <- function(ticker) {
  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  ds <- hd_datasets()[["metadata"]]
  DBI::dbGetQuery(con, sprintf(
    "SELECT * FROM read_parquet('%s') WHERE ticker = ?", ds$url
  ), params = list(ticker)) |>
    dplyr::as_tibble()
}
