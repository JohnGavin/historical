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
    macro_vintages = list(
      url = hd_base_url("macro_vintages.parquet"),
      schema = c("series_id", "date", "pub_date", "value"),
      frequency = "vintage",
      description = "FRED macro revision history: value as known at each publication date (ALFRED API)"
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

#' Macro series metadata registry
#'
#' Returns a tibble with metadata for every FRED macro series in the dataset.
#' Useful for filtering by category, frequency, or forward-looking status before
#' pulling data with [hd_fred()].
#'
#' @return A tibble with columns:
#'   \describe{
#'     \item{series_id}{FRED series identifier (character)}
#'     \item{description}{Human-readable series name (character)}
#'     \item{category}{One of "equity_index", "implied_vol", "interest_rate",
#'       "credit_spread", "inflation", "yield_curve", "commodity", "currency",
#'       "employment", "money_supply", "housing", "output" (character)}
#'     \item{frequency}{One of "daily", "monthly", "quarterly" (character)}
#'     \item{forward_looking}{TRUE if the series reflects market expectations (logical)}
#'     \item{market_implied}{TRUE if derived from market prices (logical)}
#'     \item{start_year}{Approximate start year on FRED (integer)}
#'     \item{source_detail}{Data provider detail, e.g. "CBOE", "ICE BofA" (character)}
#'   }
#' @family discovery
#' @export
hd_macro_registry <- function() {
  tibble::tribble(
    ~series_id,              ~description,                              ~category,       ~frequency,  ~forward_looking, ~market_implied, ~start_year, ~source_detail,
    "SP500",                 "S&P 500 Index",                           "equity_index",  "daily",     FALSE,            FALSE,           1957L,       "Standard & Poor's",
    "VIXCLS",                "CBOE VIX (30-day implied vol)",           "implied_vol",   "daily",     TRUE,             TRUE,            1990L,       "CBOE",
    "VXVCLS",                "CBOE VXV (93-day implied vol)",           "implied_vol",   "daily",     TRUE,             TRUE,            2007L,       "CBOE",
    "OVXCLS",                "CBOE OVX (crude oil implied vol)",        "implied_vol",   "daily",     TRUE,             TRUE,            2007L,       "CBOE",
    "GVZCLS",                "CBOE GVZ (gold implied vol)",             "implied_vol",   "daily",     TRUE,             TRUE,            2008L,       "CBOE",
    "EVZCLS",                "CBOE EVZ (EUR/USD implied vol)",          "implied_vol",   "daily",     TRUE,             TRUE,            2007L,       "CBOE",
    "DGS2",                  "2-Year Treasury Yield",                   "interest_rate", "daily",     FALSE,            FALSE,           1976L,       "US Treasury",
    "DGS10",                 "10-Year Treasury Yield",                  "interest_rate", "daily",     FALSE,            FALSE,           1962L,       "US Treasury",
    "DGS30",                 "30-Year Treasury Yield",                  "interest_rate", "daily",     FALSE,            FALSE,           1977L,       "US Treasury",
    "DFF",                   "Federal Funds Rate (daily)",              "interest_rate", "daily",     FALSE,            FALSE,           1954L,       "Federal Reserve",
    "FEDFUNDS",              "Effective Federal Funds Rate",            "interest_rate", "monthly",   FALSE,            FALSE,           1954L,       "Federal Reserve",
    "BAMLH0A0HYM2",          "ICE BofA US High Yield OAS",             "credit_spread", "daily",     TRUE,             TRUE,            1996L,       "ICE BofA",
    "BAMLC0A4CBBB",          "ICE BofA BBB Corporate OAS",             "credit_spread", "daily",     TRUE,             TRUE,            1996L,       "ICE BofA",
    "BAMLH0A2HYB",           "ICE BofA BB High Yield OAS",             "credit_spread", "daily",     TRUE,             TRUE,            1996L,       "ICE BofA",
    "T10Y2Y",                "10Y-2Y Treasury Spread",                  "yield_curve",   "daily",     TRUE,             TRUE,            1976L,       "US Treasury",
    "T10Y3M",                "10Y-3M Treasury Spread",                  "yield_curve",   "daily",     TRUE,             TRUE,            1982L,       "US Treasury",
    "T10YIE",                "10-Year Breakeven Inflation",             "inflation",     "daily",     TRUE,             TRUE,            2003L,       "TIPS-nominal spread",
    "T5YIE",                 "5-Year Breakeven Inflation",              "inflation",     "daily",     TRUE,             TRUE,            2003L,       "TIPS-nominal spread",
    "T5YIFR",                "5Y-5Y Forward Inflation Expectation",     "inflation",     "daily",     TRUE,             TRUE,            2003L,       "TIPS-nominal spread",
    "GDP",                   "Gross Domestic Product",                  "output",        "quarterly", FALSE,            FALSE,           1947L,       "BEA",
    "UNRATE",                "Unemployment Rate",                       "employment",    "monthly",   FALSE,            FALSE,           1948L,       "BLS",
    "CPIAUCSL",              "Consumer Price Index",                    "inflation",     "monthly",   FALSE,            FALSE,           1947L,       "BLS",
    "PCEPI",                 "PCE Price Index",                         "inflation",     "monthly",   FALSE,            FALSE,           1959L,       "BEA",
    "DCOILWTICO",            "WTI Crude Oil Spot",                      "commodity",     "daily",     FALSE,            FALSE,           1986L,       "EIA",
    "GOLDAMGBD228NLBM",      "Gold Price London Fix",                   "commodity",     "daily",     FALSE,            FALSE,           1968L,       "ICE Benchmark",
    "DTWEXBGS",              "Trade-Weighted USD Index",                "currency",      "daily",     FALSE,            FALSE,           2006L,       "Federal Reserve",
    "CSUSHPISA",             "Case-Shiller Home Price Index",           "housing",       "monthly",   FALSE,            FALSE,           1987L,       "S&P/Case-Shiller",
    "M2SL",                  "M2 Money Supply",                         "money_supply",  "monthly",   FALSE,            FALSE,           1959L,       "Federal Reserve"
  )
}

#' List forward-looking macro series
#'
#' Returns the subset of `hd_macro_registry()` where `forward_looking == TRUE`.
#'
#' @return Tibble of forward-looking macro series metadata
#' @family discovery
#' @export
hd_macro_forward <- function() {
  hd_macro_registry() |> dplyr::filter(forward_looking)
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
