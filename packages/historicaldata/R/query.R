#' Query OHLCV data for one or more tickers
#'
#' Returns a duckplyr lazy frame by default. Call `collect()` to materialise,
#' or chain additional dplyr verbs for server-side computation.
#'
#' @param ticker Ticker symbol(s). Character scalar or vector.
#'   Single: `"AAPL"`. Batch: `c("AAPL", "MSFT", "GOOGL")`.
#' @param from Start date (character or Date). Default: no filter.
#' @param to End date (character or Date). Default: no filter.
#' @param dataset Dataset name from registry. If `NULL` (default), each ticker
#'   is routed to its dataset via [detect_dataset()] and results are bound
#'   together. Pass an explicit dataset name to force single-dataset routing.
#' @param local If TRUE, query local cache instead of remote.
#' @param collect If TRUE, materialise immediately (backward compatible).
#'   If FALSE (default), return a lazy duckplyr frame.
#' @details
#' Mixed-dataset batches (e.g. `c("AAPL", "BTC")`) are split by detected
#' dataset, queried separately, and `bind_rows`'d. Columns that exist in
#' only one dataset (e.g. `adjusted` in equities, `market_cap` in crypto)
#' are filled with `NA` for rows from the other dataset. When the batch
#' spans multiple datasets, the result is always materialised — `collect
#' = FALSE` cannot be honoured because lazy frames from distinct parquet
#' sources cannot be bound.
#' @return Lazy duckplyr frame (collect=FALSE) or tibble (collect=TRUE)
#' @family data-access
#' @export
#' @examplesIf interactive()
#' hd_ohlcv("AAPL", from = "2024-01-01") |> collect()
#' hd_ohlcv(c("AAPL", "MSFT"), from = "2024-01-01", collect = TRUE)
#' hd_ohlcv(c("AAPL", "BTC"), from = "2024-01-01")  # mixed equity + crypto
hd_ohlcv <- function(ticker, from = NULL, to = NULL,
                     dataset = NULL, local = FALSE, collect = TRUE) {
  ticker <- as.character(ticker)
  if (length(ticker) == 0L) {
    cli::cli_abort("{.arg ticker} must be a non-empty character vector.")
  }

  # Explicit dataset: skip auto-detection, single-dataset query (unchanged behaviour).
  if (!is.null(dataset)) {
    return(hd_ohlcv_single(ticker, dataset, from, to, local, collect))
  }

  # Auto-detect per ticker, then group.
  detected <- vapply(ticker, detect_dataset, character(1L), USE.NAMES = FALSE)
  ds_groups <- split(ticker, detected)

  # Fast path: all tickers belong to one dataset — single query, identical to old behaviour.
  if (length(ds_groups) == 1L) {
    return(hd_ohlcv_single(ticker, names(ds_groups), from, to, local, collect))
  }

  # Mixed-dataset batch: query each, bind, return materialised.
  # Lazy mode cannot survive bind_rows across distinct parquet sources — inform user.
  if (!collect) {
    cli::cli_inform(c(
      "Mixed-dataset batch detected: {.val {names(ds_groups)}}.",
      "i" = "Returning materialised tibble; {.code collect = FALSE} cannot be honoured when binding across datasets."
    ))
  }

  results <- lapply(names(ds_groups), function(ds_name) {
    hd_ohlcv_single(ds_groups[[ds_name]], ds_name, from, to, local, collect = TRUE)
  })
  dplyr::bind_rows(results) |> dplyr::arrange(ticker, date)
}

#' @noRd
# Internal: single-dataset OHLCV query. See hd_ohlcv for split-and-bind public wrapper.
hd_ohlcv_single <- function(ticker, dataset, from, to, local, collect) {
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
#' @family data-access
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
#' @family data-access
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
                       "XRP", "ADA", "DOGE", "DOT", "HNT", "RAY",
                       "BONK", "PYTH")
  if (toupper(ticker) %in% crypto_tickers) {
    "crypto_daily"
  } else {
    "equity_daily"
  }
}
