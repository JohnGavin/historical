#' Search tickers by pattern across all datasets
#'
#' Searches ticker symbols and long names using regex or glob patterns.
#'
#' @param pattern Regex pattern (default) or glob (if contains `*` or `?`)
#' @param dataset Filter to one dataset (e.g. "equity_daily"). NULL = all.
#' @param collect If TRUE (default), materialise. If FALSE, return lazy frame.
#' @return Tibble or lazy duckplyr frame of matching tickers with metadata
#' @export
#' @examplesIf interactive()
#' hd_search("^APP")     # regex: tickers starting with APP
#' hd_search("*coin*")   # glob: names containing "coin"
hd_search <- function(pattern, dataset = NULL, collect = TRUE) {
  is_glob <- grepl("\\*|(?<!\\[)\\?", pattern, perl = TRUE) &&
    !grepl("\\[.*\\]", pattern)
  if (is_glob) {
    pattern <- utils::glob2rx(pattern, trim.head = TRUE, trim.tail = TRUE)
  }

  # hd_search needs regexp_matches which duckplyr doesn't support natively.
  # Use DBI for this one function (legitimate exception: regex predicate pushdown).
  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  ds <- hd_datasets()[["metadata"]]
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

  result <- DBI::dbGetQuery(con, sql) |> dplyr::as_tibble()

  chr_cols <- names(result)[vapply(result, is.character, logical(1))]
  for (col in chr_cols) {
    result[[col]] <- iconv(result[[col]], to = "UTF-8", sub = "")
  }

  result
}

#' Summary of all datasets
#'
#' @param collect If TRUE (default), materialise.
#' @return Tibble with dataset, n_tickers, total_obs, min_date, max_date, description
#' @family discovery
#' @export
hd_summary <- function(collect = TRUE) {
  ds <- hd_datasets()[["metadata"]]

  lf <- duckplyr::read_parquet_duckdb(ds$url) |>
    dplyr::summarise(
      n_tickers = dplyr::n(),
      total_obs = sum(total_obs, na.rm = TRUE),
      min_date = min(start_date, na.rm = TRUE),
      max_date = max(end_date, na.rm = TRUE),
      .by = dataset
    ) |>
    dplyr::arrange(dataset)

  result <- dplyr::collect(lf) |>
    dplyr::mutate(
      min_date = as.character(min_date),
      max_date = as.character(max_date)
    ) |>
    dplyr::left_join(
      dplyr::tibble(
        dataset = names(hd_datasets()),
        description = vapply(hd_datasets(), \(x) x$description, character(1))
      ),
      by = "dataset"
    )

  result
}

#' List all exchanges
#'
#' @param dataset Filter to one dataset. NULL = all.
#' @return Tibble with exchange, n_tickers
#' @family discovery
#' @export
hd_exchanges <- function(dataset = NULL) {
  ds <- hd_datasets()[["metadata"]]

  # STRING_AGG not available in duckplyr — use DBI for this one
  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

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
#' @param tickers Character vector of ticker symbols
#' @param collect If TRUE (default), materialise.
#' @return Tibble or lazy frame with key metadata columns
#' @export
#' @examplesIf interactive()
#' hd_ticker_meta(c("AAPL", "MSFT"))
hd_ticker_meta <- function(tickers, collect = TRUE) {
  tickers <- as.character(tickers)
  ds <- hd_datasets()[["metadata"]]

  lf <- duckplyr::read_parquet_duckdb(ds$url) |>
    dplyr::filter(ticker %in% !!tickers) |>
    dplyr::select(ticker, long_name, currency, exchange, market_cap, volume_avg,
                  yield_pct, beta_3yr, start_date, end_date, total_obs) |>
    dplyr::arrange(ticker)

  if (collect) {
    result <- dplyr::collect(lf)
    chr_cols <- names(result)[vapply(result, is.character, logical(1))]
    for (col in chr_cols) {
      result[[col]] <- iconv(result[[col]], to = "UTF-8", sub = "")
    }
    result
  } else lf
}

#' Full metadata for one ticker
#'
#' @param ticker Ticker symbol (e.g. "AAPL", "BTC")
#' @param collect If TRUE (default), materialise.
#' @return One-row tibble with all metadata columns
#' @export
hd_ticker_info <- function(ticker, collect = TRUE) {
  ds <- hd_datasets()[["metadata"]]

  lf <- duckplyr::read_parquet_duckdb(ds$url) |>
    dplyr::filter(ticker == !!ticker)

  if (collect) {
    result <- dplyr::collect(lf)
    chr_cols <- names(result)[vapply(result, is.character, logical(1))]
    for (col in chr_cols) {
      result[[col]] <- iconv(result[[col]], to = "UTF-8", sub = "")
    }
    result
  } else lf
}

#' FRED series metadata (frequency, units)
#'
#' Returns known metadata for FRED macro series.
#' These are hardcoded since the FRED API requires an API key.
#'
#' @return Tibble with series_id, frequency, units, title
#' @export
hd_fred_meta <- function() {
  dplyr::tribble(
    ~series_id,       ~frequency,  ~units,              ~title,
    "SP500",          "Daily",     "Index",             "S&P 500",
    "VIXCLS",         "Daily",     "Index",             "CBOE Volatility Index (VIX)",
    "DGS2",           "Daily",     "Percent",           "2-Year Treasury Constant Maturity Rate",
    "DGS10",          "Daily",     "Percent",           "10-Year Treasury Constant Maturity Rate",
    "DGS30",          "Daily",     "Percent",           "30-Year Treasury Constant Maturity Rate",
    "DFF",            "Daily",     "Percent",           "Effective Federal Funds Rate",
    "FEDFUNDS",       "Monthly",   "Percent",           "Federal Funds Effective Rate",
    "BAMLH0A0HYM2",   "Daily",     "Percent",           "ICE BofA US High Yield OAS",
    "BAMLC0A4CBBB",   "Daily",     "Percent",           "ICE BofA BBB US Corporate OAS",
    "GDP",            "Quarterly", "Billions USD",      "Gross Domestic Product",
    "UNRATE",         "Monthly",   "Percent",           "Unemployment Rate",
    "CPIAUCSL",       "Monthly",   "Index (1982=100)",  "Consumer Price Index (All Urban)",
    "PCEPI",          "Monthly",   "Index (2017=100)",  "Personal Consumption Expenditure Price Index",
    "DCOILWTICO",     "Daily",     "USD/Barrel",        "WTI Crude Oil Price",
    "DTWEXBGS",       "Daily",     "Index (2006=100)",  "Trade-Weighted USD Index (Broad)",
    "CSUSHPISA",      "Monthly",   "Index (2000=100)",  "Case-Shiller US Home Price Index",
    "M2SL",           "Monthly",   "Billions USD",      "M2 Money Supply",
    "T10Y2Y",         "Daily",     "Percent",           "10Y-2Y Treasury Spread",
    "T10YIE",         "Daily",     "Percent",           "10-Year Breakeven Inflation Rate"
  )
}
