#' Query OHLCV data for a ticker
#'
#' Fetches data from HF-hosted Parquet via DuckDB httpfs.
#' Only the matching rows are transferred (predicate pushdown).
#'
#' @param ticker Ticker symbol (e.g. "AAPL", "BTC")
#' @param from Start date (character or Date). Default: no filter.
#' @param to End date (character or Date). Default: no filter.
#' @param dataset Dataset name from registry. If NULL, auto-detected from ticker.
#' @param local If TRUE, query local cache instead of remote.
#' @return Tibble of OHLCV data
#' @export
hd_ohlcv <- function(ticker, from = NULL, to = NULL,
                     dataset = NULL, local = FALSE) {
  if (is.null(dataset)) {
    dataset <- detect_dataset(ticker)
  }

  ds <- hd_datasets()[[dataset]]
  if (is.null(ds)) {
    cli::cli_abort("Unknown dataset: {dataset}. See {.fn hd_datasets}.")
  }

  if (local) {
    source_path <- file.path(hd_cache_path(), paste0(dataset, ".parquet"))
    if (!file.exists(source_path)) {
      cli::cli_abort(c(
        "Local cache not found for {dataset}",
        "i" = "Run {.fn hd_download} first, or use {.code local = FALSE}."
      ))
    }
  } else {
    source_path <- ds$url
  }

  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  # Build parameterised query
  where_clauses <- "ticker = ?"
  params <- list(ticker)


  if (!is.null(from)) {
    where_clauses <- c(where_clauses, "date >= ?")
    params <- c(params, list(as.character(from)))
  }
  if (!is.null(to)) {
    where_clauses <- c(where_clauses, "date <= ?")
    params <- c(params, list(as.character(to)))
  }

  sql <- sprintf(
    "SELECT * FROM read_parquet('%s') WHERE %s ORDER BY date",
    source_path,
    paste(where_clauses, collapse = " AND ")
  )

  DBI::dbGetQuery(con, sql, params = params) |>
    dplyr::as_tibble()
}

#' Lazy duckplyr query over a dataset
#'
#' Returns an unevaluated duckplyr lazy frame. Chain dplyr verbs
#' then call `collect()` to execute.
#'
#' @param dataset Dataset name from registry
#' @param local If TRUE, use local cache
#' @return Lazy duckplyr frame
#' @export
hd_lazy <- function(dataset = "equity_daily", local = FALSE) {
  rlang::check_installed("duckplyr", reason = "for lazy queries")

  ds <- hd_datasets()[[dataset]]
  if (is.null(ds)) {
    cli::cli_abort("Unknown dataset: {dataset}. See {.fn hd_datasets}.")
  }

  if (local) {
    path <- file.path(hd_cache_path(), paste0(dataset, ".parquet"))
  } else {
    path <- ds$url
  }

  duckplyr::read_parquet_duckdb(path)
}

#' Query FRED macro series
#'
#' @param series_id FRED series ID (e.g. "SP500", "VIXCLS", "DGS10")
#' @param from Start date (character or Date). Default: no filter.
#' @param to End date (character or Date). Default: no filter.
#' @param local If TRUE, query local cache instead of remote.
#' @return Tibble with date, value, series_id columns
#' @export
hd_macro <- function(series_id, from = NULL, to = NULL, local = FALSE) {
  ds <- hd_datasets()[["macro_daily"]]

  if (local) {
    source_path <- file.path(hd_cache_path(), "macro_daily.parquet")
    if (!file.exists(source_path)) {
      cli::cli_abort("Local cache not found. Run {.fn hd_download} first.")
    }
  } else {
    source_path <- ds$url
  }

  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  where_clauses <- "series_id = ?"
  params <- list(series_id)

  if (!is.null(from)) {
    where_clauses <- c(where_clauses, "date >= ?")
    params <- c(params, list(as.character(from)))
  }
  if (!is.null(to)) {
    where_clauses <- c(where_clauses, "date <= ?")
    params <- c(params, list(as.character(to)))
  }

  sql <- sprintf(
    "SELECT * FROM read_parquet('%s') WHERE %s ORDER BY date",
    source_path,
    paste(where_clauses, collapse = " AND ")
  )

  DBI::dbGetQuery(con, sql, params = params) |>
    dplyr::as_tibble()
}

#' List available macro series
#'
#' @param local If TRUE, query local cache
#' @return Character vector of series IDs
#' @export
hd_macro_series <- function(local = FALSE) {
  ds <- hd_datasets()[["macro_daily"]]
  source_path <- if (local) {
    file.path(hd_cache_path(), "macro_daily.parquet")
  } else {
    ds$url
  }

  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT series_id FROM read_parquet('%s') ORDER BY series_id",
    source_path
  ))$series_id
}

#' Auto-detect dataset from ticker symbol
#' @noRd
detect_dataset <- function(ticker) {
  crypto_tickers <- c("BTC", "ETH", "SOL", "USDC", "USDT", "BNB",
                       "XRP", "ADA", "DOGE", "DOT")
  if (toupper(ticker) %in% crypto_tickers) {
    "crypto_daily"
  } else {
    "equity_daily"
  }
}
