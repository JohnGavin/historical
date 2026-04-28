#' Query OHLCV data for one or more tickers
#'
#' Returns a duckplyr lazy frame by default. Call `collect()` to materialise,
#' or chain additional dplyr verbs for server-side computation.
#'
#' @param ticker Ticker symbol(s). Character scalar or vector.
#'   Single: `"AAPL"`. Batch: `c("AAPL", "MSFT", "GOOGL")`.
#' @param from Start date (character or Date). Default: no filter.
#' @param to End date (character or Date). Default: no filter.
#' @param dataset Dataset name from registry. If NULL, auto-detected from first ticker.
#' @param local If TRUE, query local cache instead of remote.
#' @param collect If TRUE, materialise immediately (backward compatible).
#'   If FALSE (default), return a lazy duckplyr frame.
#' @return Lazy duckplyr frame (collect=FALSE) or tibble (collect=TRUE)
#' @export
#' @examplesIf interactive()
#' hd_ohlcv("AAPL", from = "2024-01-01") |> collect()
#' hd_ohlcv(c("AAPL", "MSFT"), from = "2024-01-01", collect = TRUE)
hd_ohlcv <- function(ticker, from = NULL, to = NULL,
                     dataset = NULL, local = FALSE, collect = TRUE) {
  ticker <- as.character(ticker)
  if (is.null(dataset)) {
    dataset <- detect_dataset(ticker[1])
  }

  ds <- hd_datasets()[[dataset]]
  if (is.null(ds)) {
    cli::cli_abort("Unknown dataset: {dataset}. See {.fn hd_datasets}.")
  }

  source_path <- if (local) {
    p <- file.path(hd_cache_path(), paste0(dataset, ".parquet"))
    if (!file.exists(p)) {
      cli::cli_abort(c(
        "Local cache not found for {dataset}",
        "i" = "Run {.fn hd_download} first, or use {.code local = FALSE}."
      ))
    }
    p
  } else {
    ds$url
  }

  lf <- duckplyr::read_parquet_duckdb(source_path) |>
    dplyr::filter(ticker %in% !!ticker) |>
    dplyr::arrange(ticker, date)

  if (!is.null(from)) lf <- lf |> dplyr::filter(date >= !!as.character(from))
  if (!is.null(to))   lf <- lf |> dplyr::filter(date <= !!as.character(to))

  if (collect) dplyr::collect(lf) else lf
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
  ds <- hd_datasets()[[dataset]]
  if (is.null(ds)) {
    cli::cli_abort("Unknown dataset: {dataset}. See {.fn hd_datasets}.")
  }

  path <- if (local) {
    file.path(hd_cache_path(), paste0(dataset, ".parquet"))
  } else {
    ds$url
  }

  duckplyr::read_parquet_duckdb(path)
}

#' Query FRED macro series
#'
#' @param series_id FRED series ID(s). Scalar or vector.
#' @param from Start date (character or Date). Default: no filter.
#' @param to End date (character or Date). Default: no filter.
#' @param local If TRUE, query local cache instead of remote.
#' @param collect If TRUE (default), materialise. If FALSE, return lazy frame.
#' @return Lazy duckplyr frame or tibble
#' @export
#' @examplesIf interactive()
#' hd_macro("SP500", from = "2024-01-01") |> head()
hd_macro <- function(series_id, from = NULL, to = NULL,
                     local = FALSE, collect = TRUE) {
  series_id <- as.character(series_id)
  ds <- hd_datasets()[["macro_daily"]]

  source_path <- if (local) {
    p <- file.path(hd_cache_path(), "macro_daily.parquet")
    if (!file.exists(p)) {
      cli::cli_abort("Local cache not found. Run {.fn hd_download} first.")
    }
    p
  } else {
    ds$url
  }

  lf <- duckplyr::read_parquet_duckdb(source_path) |>
    dplyr::filter(series_id %in% !!series_id) |>
    dplyr::arrange(series_id, date)

  if (!is.null(from)) lf <- lf |> dplyr::filter(date >= !!as.character(from))
  if (!is.null(to))   lf <- lf |> dplyr::filter(date <= !!as.character(to))

  if (collect) dplyr::collect(lf) else lf
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

  duckplyr::read_parquet_duckdb(source_path) |>
    dplyr::distinct(series_id) |>
    dplyr::arrange(series_id) |>
    dplyr::collect() |>
    dplyr::pull(series_id)
}

#' Query Fama-French factor returns
#'
#' @param dataset Factor dataset: "FF3", "FF5", or "Mom"
#' @param frequency "daily" or "monthly"
#' @param from Start date. Default: no filter.
#' @param to End date. Default: no filter.
#' @param local If TRUE, query local cache.
#' @param collect If TRUE (default), materialise. If FALSE, return lazy frame.
#' @return Lazy duckplyr frame or tibble
#' @export
hd_factors <- function(dataset = "FF3", frequency = "daily",
                       from = NULL, to = NULL, local = FALSE,
                       collect = TRUE) {
  ds <- hd_datasets()[["factors"]]

  source_path <- if (local) {
    file.path(hd_cache_path(), "factors.parquet")
  } else {
    ds$url
  }

  lf <- duckplyr::read_parquet_duckdb(source_path) |>
    dplyr::filter(dataset == !!dataset, frequency == !!frequency) |>
    dplyr::arrange(date)

  if (!is.null(from)) lf <- lf |> dplyr::filter(date >= !!as.character(from))
  if (!is.null(to))   lf <- lf |> dplyr::filter(date <= !!as.character(to))

  if (collect) dplyr::collect(lf) else lf
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
