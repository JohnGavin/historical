# ── Point-in-time hard-error guard ────────────────────────────────────────────

#' Abort if a requested end-date is in the future
#'
#' Raises a classed error (`"hd_future_date"`) when `to` is strictly after
#' `Sys.Date()`. This prevents accidental look-ahead in backtesting and
#' strategy research: requesting data "to" a future date implies knowledge
#' of prices that do not yet exist, silently corrupting any analysis that
#' depends on point-in-time correctness.
#'
#' @param to Date or character. The upper bound passed to a data-access
#'   function. `NULL` is silently allowed (no upper filter).
#' @param arg_name Character scalar used in the error message.
#' @return Invisibly `NULL` when `to <= Sys.Date()` or `to` is `NULL`.
#' @noRd
.hd_check_pit <- function(to, arg_name = "to") {
  if (is.null(to)) return(invisible(NULL))
  to_date <- tryCatch(as.Date(to), error = function(e) NULL)
  if (is.null(to_date) || is.na(to_date)) return(invisible(NULL))
  if (to_date > Sys.Date()) {
    cli::cli_abort(
      c(
        "Future-dated request: {.arg {arg_name}} = {.val {as.character(to_date)}} is after today ({.val {as.character(Sys.Date())}}).",
        "x" = "Requesting data beyond today is a look-ahead risk: prices for {.val {as.character(to_date)}} do not exist yet.",
        "i" = "Use {.code to = Sys.Date()} or an earlier date."
      ),
      class = "hd_future_date",
      call = rlang::caller_env()
    )
  }
  invisible(NULL)
}

# ── Survivorship-bias guard ───────────────────────────────────────────────────

#' Warn when a dataset is known to be survivorship-biased
#'
#' Emits a `cli::cli_warn()` if `dataset` is flagged with
#' `survivorship_biased = TRUE` in the registry. Call this before computing
#' per-stock Sharpe / CAGR / drawdown metrics so that callers are reminded the
#' numbers overstate achievable performance.
#'
#' The `equity_daily` dataset is survivorship-biased: the 672-ticker universe
#' reflects currently-listed stocks only. Known failed firms (Enron, Lehman
#' Brothers, Bear Stearns, WorldCom, Washington Mutual) are absent. Across 56
#' years of history (1970-2026), zero delistings are recorded. Per-stock
#' performance metrics derived from this dataset overstate returns by an
#' unquantified but non-trivial amount (literature estimate: +1 to +3 pp/year
#' CAGR for long-only strategies). See GitHub issue #150 for full analysis and
#' remediation roadmap.
#'
#' @param dataset Dataset name from [hd_datasets()].
#' @return `dataset` invisibly. Called for its warning side-effect.
#' @family data-access
#' @family quality-audit
#' @export
#' @examples
#' hd_check_survivorship_bias("equity_daily")  # emits a warning
#' hd_check_survivorship_bias("factors")       # silent
hd_check_survivorship_bias <- function(dataset) {
  ds <- hd_datasets()[[dataset]]
  if (is.null(ds)) {
    cli::cli_abort("Unknown dataset: {.val {dataset}}. See {.fn hd_datasets}.")
  }
  if (isTRUE(ds[["survivorship_biased"]])) {
    n_del <- ds[["known_delistings"]]
    cli::cli_warn(c(
      "{.val {dataset}} is survivorship-biased: {n_del} delisting event{?s} recorded across full history.",
      "i" = "Universe contains only currently-listed tickers.",
      "i" = "Known failed firms (Enron, Lehman, Bear Stearns, WorldCom, WaMu) are absent.",
      "x" = "Per-stock Sharpe / CAGR / drawdown metrics OVER-ESTIMATE achievable performance.",
      ">" = "True fix requires a point-in-time universe with delisting records (CRSP/WRDS/Sharadar). See GitHub issue #150."
    ))
  }
  invisible(dataset)
}

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
#' only one dataset (e.g. `adjusted_close` in equities, `market_cap` in crypto)
#' are filled with `NA` for rows from the other dataset. When the batch
#' spans multiple datasets, the result is always materialised — `collect
#' = FALSE` cannot be honoured because lazy frames from distinct parquet
#' sources cannot be bound.
#' @return Lazy duckplyr frame (collect=FALSE) or tibble (collect=TRUE)
#' @section Point-in-time guard:
#'   Passing `to > Sys.Date()` raises a classed error (`"hd_future_date"`).
#'   Future-dated requests imply look-ahead knowledge and are forbidden to
#'   prevent silent backtest contamination.
#' @section Non-US volume nulling (issue #21):
#'   When `collect = TRUE`, the `volume` column is set to `NA` for tickers
#'   on non-US exchanges (`.L`, `.DE`, `.PA`, `.AS`, `.SW`, `.MC`, `.MI`,
#'   `.ST`, `.CO`). yfinance reports unreliable volume for these exchanges.
#'   The raw parquet is preserved unchanged (`raw-folder-readonly` rule).
#'   When `collect = FALSE`, callers should apply
#'   [hd_unreliable_volume_ticker()] to filter volume themselves.
#' @family data-access
#' @export
#' @examplesIf interactive()
#' hd_ohlcv("AAPL", from = "2024-01-01") |> collect()
#' hd_ohlcv(c("AAPL", "MSFT"), from = "2024-01-01", collect = TRUE)
#' hd_ohlcv(c("AAPL", "BTC"), from = "2024-01-01")  # mixed equity + crypto
hd_ohlcv <- function(ticker, from = NULL, to = NULL,
                     dataset = NULL, local = FALSE, collect = TRUE) {
  .hd_check_pit(to)
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

  # Emit a once-per-session survivorship-bias warning for equity_daily (#150)
  if (isTRUE(ds[["survivorship_biased"]])) {
    warn_key <- paste0("hd_survivorship_warned_", dataset)
    if (!isTRUE(getOption(warn_key))) {
      hd_check_survivorship_bias(dataset)
      options(stats::setNames(list(TRUE), warn_key))
    }
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

  # Backward-compat alias: cached parquets written before #325 use 'adjusted'.
  # New parquets use 'adjusted_close'.  Alias here so callers always see
  # 'adjusted_close'. (#325)
  schema0 <- lf |> head(0) |> dplyr::collect()
  col_names <- names(schema0)
  if ("adjusted" %in% col_names && !("adjusted_close" %in% col_names)) {
    lf <- lf |> dplyr::rename(adjusted_close = adjusted)
  }

  # Date-filter type matching for duckplyr (#453)
  # The HF equity_daily parquet stores 'date' as TIMESTAMP_NS. DuckDB throws an
  # INTERNAL exception when comparing TIMESTAMP_NS against a DATE literal
  # (injected by !!as.Date()), and against a STRING_LITERAL (injected by
  # !!as.character()). The correct injection is as.POSIXct(tz="UTC") which
  # produces a TIMESTAMP literal — the only type DuckDB can compare directly
  # with TIMESTAMP_NS in a stingy duckplyr frame.
  #
  # For datasets whose 'date' column is typed DATE (not TIMESTAMP), duckplyr
  # falls back from DuckDB to dplyr when it sees a TIMESTAMP vs DATE predicate,
  # and R's Ops.Date vs Ops.POSIXt coercion silently returns 0 rows. We
  # therefore probe the column type once (already materialised above) and
  # convert the bound values accordingly:
  #   TIMESTAMP_NS → as.POSIXct(tz="UTC")  (matches via TIMESTAMP candidate)
  #   DATE         → as.Date()              (matches via DATE candidate)
  if (!is.null(from) || !is.null(to)) {
    date_is_timestamp <- inherits(schema0[["date"]], "POSIXct")
    date_coerce <- if (date_is_timestamp) {
      function(x) as.POSIXct(x, tz = "UTC")
    } else {
      as.Date
    }
    if (!is.null(from)) lf <- lf |> dplyr::filter(date >= !!date_coerce(from))
    if (!is.null(to))   lf <- lf |> dplyr::filter(date <= !!date_coerce(to))
  }

  if (collect) {
    result <- dplyr::collect(lf)
    # #21: yfinance volume is unreliable for non-US exchanges — null on read.
    # The raw parquet is preserved (raw-folder-readonly rule). When collect = FALSE
    # the lazy frame is returned as-is; callers should apply
    # hd_unreliable_volume_ticker() themselves if they need volume filtering.
    if ("volume" %in% names(result)) {
      result[["volume"]] <- dplyr::if_else(
        hd_unreliable_volume_ticker(result[["ticker"]]),
        NA_real_,
        as.numeric(result[["volume"]])
      )
    }
    result
  } else {
    lf
  }
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

  # Emit a once-per-session survivorship-bias warning for equity_daily (#150)
  if (isTRUE(ds[["survivorship_biased"]])) {
    warn_key <- paste0("hd_survivorship_warned_", dataset)
    if (!isTRUE(getOption(warn_key))) {
      hd_check_survivorship_bias(dataset)
      options(stats::setNames(list(TRUE), warn_key))
    }
  }

  # Guard against API-only and non-HF datasets when using remote path.
  # alphavantage_daily has url=NA; jst_macrohistory has a .dta URL.
  # Both fail with cryptic errors from read_parquet_duckdb if not caught here.
  if (!local && (is.na(ds$url) || !grepl("hf://", ds$url, fixed = TRUE))) {
    cli::cli_abort(c(
      "{.val {dataset}} is not an HF parquet dataset and cannot be queried with {.fn hd_lazy}.",
      "i" = "Use the dedicated helper for this dataset (e.g. {.fn hd_alphavantage}, {.fn hd_jst})."
    ))
  }

  path <- if (local) {
    file.path(hd_cache_path(), paste0(dataset, ".parquet"))
  } else {
    ds$url
  }

  lf <- duckplyr::read_parquet_duckdb(path)

  # Backward-compat alias: cached parquets written before #325 use 'adjusted'
  # (the old yfinance column name from fetch_equity.py).  New parquets use
  # 'adjusted_close' (canonical, matching alphavantage_daily).  Callers always
  # see 'adjusted_close' regardless of the underlying parquet column name.
  # (#325)
  col_names <- lf |> head(0) |> dplyr::collect() |> names()
  if ("adjusted" %in% col_names && !("adjusted_close" %in% col_names)) {
    lf <- lf |> dplyr::rename(adjusted_close = adjusted)
  }

  lf
}

#' Query FRED macro series
#'
#' @param series_id FRED series ID(s). Scalar or vector.
#' @param from Start date (character or Date). Default: no filter.
#' @param to End date (character or Date). Default: no filter.
#' @param local If TRUE, query local cache instead of remote.
#' @param collect If TRUE (default), materialise. If FALSE, return lazy frame.
#' @return Lazy duckplyr frame or tibble
#' @section Point-in-time guard:
#'   Passing `to > Sys.Date()` raises a classed error (`"hd_future_date"`).
#'   Future-dated requests imply look-ahead knowledge and are forbidden to
#'   prevent silent backtest contamination.
#' @family data-access
#' @export
#' @examplesIf interactive()
#' hd_macro("SP500", from = "2024-01-01") |> head()
hd_macro <- function(series_id, from = NULL, to = NULL,
                     local = FALSE, collect = TRUE) {
  .hd_check_pit(to)
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

  if (!is.null(from) || !is.null(to)) {
    schema0 <- lf |> head(0) |> dplyr::collect()
    date_coerce <- if (inherits(schema0[["date"]], "POSIXct")) {
      function(x) as.POSIXct(x, tz = "UTC")
    } else {
      as.Date
    }
    if (!is.null(from)) lf <- lf |> dplyr::filter(date >= !!date_coerce(from))  # (#453)
    if (!is.null(to))   lf <- lf |> dplyr::filter(date <= !!date_coerce(to))    # (#453)
  }

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

  if (!is.null(from) || !is.null(to)) {
    schema0 <- lf |> head(0) |> dplyr::collect()
    date_coerce <- if (inherits(schema0[["date"]], "POSIXct")) {
      function(x) as.POSIXct(x, tz = "UTC")
    } else {
      as.Date
    }
    if (!is.null(from)) lf <- lf |> dplyr::filter(date >= !!date_coerce(from))  # (#453)
    if (!is.null(to))   lf <- lf |> dplyr::filter(date <= !!date_coerce(to))    # (#453)
  }

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
