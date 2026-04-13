#' Dataset registry
#'
#' Maps dataset names to HF URLs, schemas, and metadata.
#' Adding a new asset class = adding an entry here.
#'
#' @return Named list of dataset metadata
#' @family discovery
#' @export
hd_datasets <- function() {
  list(
    equity_daily = list(
      url = hd_base_url("equity_daily.parquet"),
      schema = c("date", "open", "high", "low", "close", "adjusted",
                 "volume", "ticker", "source", "asset_class"),
      frequency = "daily",
      description = "US equities daily OHLCV (Yahoo Finance)"
    ),
    crypto_daily = list(
      url = hd_base_url("crypto_daily.parquet"),
      schema = c("date", "close", "volume", "market_cap",
                 "ticker", "source", "asset_class"),
      frequency = "daily",
      description = "Cryptocurrency daily prices (CoinGecko)"
    ),
    macro_daily = list(
      url = hd_base_url("macro_daily.parquet"),
      schema = c("date", "value", "series_id", "source"),
      frequency = "mixed",
      description = "FRED macro series (SP500, VIX, rates, GDP, CPI, etc.)"
    ),
    factors = list(
      url = hd_base_url("factors.parquet"),
      schema = c("date", "factor_name", "value", "dataset", "frequency", "source"),
      frequency = "daily+monthly",
      description = "Fama-French factors (FF3, FF5, Momentum, 1926+)"
    ),
    metadata = list(
      url = hd_base_url("metadata.parquet"),
      schema = c("ticker", "dataset", "long_name", "exchange", "currency",
                 "instrument_type", "sector", "industry", "country",
                 "market_cap", "volume_avg", "fifty_two_week_high", "fifty_two_week_low",
                 "expense_ratio", "yield_pct", "category", "fund_family",
                 "nav_price", "beta_3yr", "ytd_return", "three_yr_return",
                 "start_date", "end_date", "total_obs", "missing_pct"),
      frequency = "static",
      description = "Per-ticker metadata: exchange, sector, market cap, ETF fees/yield/returns, coverage stats"
    ),
    metadata_amendments = list(
      url = hd_base_url("metadata_amendments.parquet"),
      schema = c("ticker", "field", "old_value", "new_value",
                 "source", "method", "amended_at", "amended_by", "reversible"),
      frequency = "append-only",
      description = "PIT log of all metadata changes: computed fields, enrichments, corrections"
    )
  )
}

#' List available tickers in a dataset
#'
#' Queries the remote Parquet file for distinct tickers.
#' Uses DuckDB httpfs — only fetches the ticker column.
#'
#' @param dataset Name of dataset (from `hd_datasets()`)
#' @return Character vector of tickers
#' @family discovery
#' @export
hd_tickers <- function(dataset = "equity_daily") {
  ds <- hd_datasets()[[dataset]]
  if (is.null(ds)) {
    cli::cli_abort("Unknown dataset: {dataset}. See {.fn hd_datasets}.")
  }

  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT ticker FROM read_parquet('%s') ORDER BY ticker",
    ds$url
  ))$ticker
}

#' Construct HF dataset URL using DuckDB's native `hf://` protocol
#'
#' DuckDB 0.10+ supports `hf://datasets/...` natively — no httpfs extension
#' needed, 34% faster than `resolve/main/` URLs.
#'
#' @param filename Parquet filename
#' @return `hf://datasets/{repo}/{filename}` URL
#' @noRd
hd_base_url <- function(filename) {
  repo <- Sys.getenv("HD_HF_REPO", unset = "dsfefvx/finance-historical-data")
  sprintf("hf://datasets/%s/%s", repo, filename)
}
