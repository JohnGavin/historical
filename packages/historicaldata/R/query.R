#' Query OHLCV data for one or more tickers
#'
#' Fetches data from HF-hosted Parquet via DuckDB httpfs.
#' Only the matching rows are transferred (predicate pushdown).
#' Accepts a single ticker or a character vector for batch queries.
#'
#' @param ticker Ticker symbol(s). Character scalar or vector.
#'   Single: `"AAPL"`. Batch: `c("AAPL", "MSFT", "GOOGL")`.
#' @param from Start date (character or Date). Default: no filter.
#' @param to End date (character or Date). Default: no filter.
#' @param dataset Dataset name from registry. If NULL, auto-detected from first ticker.
#' @param local If TRUE, query local cache instead of remote.
#' @return Tibble of OHLCV data (multiple tickers stacked by ticker + date)
#' @export
#' @examples
#' hd_ohlcv("AAPL", from = "2024-01-01")
#' hd_ohlcv(c("AAPL", "MSFT", "GOOGL"), from = "2024-01-01")
#' hd_ohlcv(hd_group("FAANG"), from = "2024-01-01")
hd_ohlcv <- function(ticker, from = NULL, to = NULL,
                     dataset = NULL, local = FALSE) {
  ticker <- as.character(ticker)
  if (is.null(dataset)) {
    dataset <- detect_dataset(ticker[1])
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

  # Build parameterised query — single ticker or batch

  if (length(ticker) == 1L) {
    where_clauses <- "ticker = ?"
    params <- list(ticker)
  } else {
    placeholders <- paste(rep("?", length(ticker)), collapse = ", ")
    where_clauses <- paste0("ticker IN (", placeholders, ")")
    params <- as.list(ticker)
  }

  if (!is.null(from)) {
    where_clauses <- c(where_clauses, "date >= ?")
    params <- c(params, list(as.character(from)))
  }
  if (!is.null(to)) {
    where_clauses <- c(where_clauses, "date <= ?")
    params <- c(params, list(as.character(to)))
  }

  sql <- sprintf(
    "SELECT * FROM read_parquet('%s') WHERE %s ORDER BY ticker, date",
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
#' @family data-access
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
#' Accepts a single series ID or a character vector for batch queries.
#'
#' @param series_id FRED series ID(s). Scalar or vector.
#'   Single: `"SP500"`. Batch: `c("SP500", "VIXCLS", "DGS10")`.
#' @param from Start date (character or Date). Default: no filter.
#' @param to End date (character or Date). Default: no filter.
#' @param local If TRUE, query local cache instead of remote.
#' @return Tibble with date, value, series_id columns
#' @export
#' @examples
#' hd_macro("SP500", from = "2024-01-01")
#' hd_macro(c("SP500", "VIXCLS", "DGS10"), from = "2024-01-01")
hd_macro <- function(series_id, from = NULL, to = NULL, local = FALSE) {
  series_id <- as.character(series_id)
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

  if (length(series_id) == 1L) {
    where_clauses <- "series_id = ?"
    params <- list(series_id)
  } else {
    placeholders <- paste(rep("?", length(series_id)), collapse = ", ")
    where_clauses <- paste0("series_id IN (", placeholders, ")")
    params <- as.list(series_id)
  }

  if (!is.null(from)) {
    where_clauses <- c(where_clauses, "date >= ?")
    params <- c(params, list(as.character(from)))
  }
  if (!is.null(to)) {
    where_clauses <- c(where_clauses, "date <= ?")
    params <- c(params, list(as.character(to)))
  }

  sql <- sprintf(
    "SELECT * FROM read_parquet('%s') WHERE %s ORDER BY series_id, date",
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
#' @family data-access
#' @family discovery
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

#' Query Fama-French factor returns
#'
#' @param dataset Factor dataset: "FF3", "FF5", or "Mom"
#' @param frequency "daily" or "monthly"
#' @param from Start date. Default: no filter.
#' @param to End date. Default: no filter.
#' @param local If TRUE, query local cache.
#' @return Tibble with date, factor_name, value columns
#' @export
hd_factors <- function(dataset = "FF3", frequency = "daily",
                       from = NULL, to = NULL, local = FALSE) {
  ds <- hd_datasets()[["factors"]]

  if (local) {
    source_path <- file.path(hd_cache_path(), "factors.parquet")
  } else {
    source_path <- ds$url
  }

  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  where_clauses <- c("dataset = ?", "frequency = ?")
  params <- list(dataset, frequency)

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
