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

  duckplyr::read_parquet_duckdb(ds$url) |>
    dplyr::distinct(ticker) |>
    dplyr::arrange(ticker) |>
    dplyr::collect() |>
    dplyr::pull(ticker)
}

#' Macro series metadata registry
#'
#' Returns a tibble with metadata for every macro series in the dataset,
#' covering FRED series plus CBOE/ICE volatility indicators fetched directly.
#' Useful for filtering by category, frequency, source, or forward-looking
#' status before pulling data with [hd_fred()] or the CBOE fetch script.
#'
#' @return A tibble with columns:
#'   \describe{
#'     \item{series_id}{Series identifier (character)}
#'     \item{description}{Short series name (character)}
#'     \item{long_name}{Descriptive human-readable name (character)}
#'     \item{category}{One of "equity_index", "implied_vol", "interest_rate",
#'       "credit_spread", "inflation", "yield_curve", "commodity", "currency",
#'       "employment", "money_supply", "housing", "output",
#'       "implied_correlation", "implied_dispersion", "options_strategy",
#'       "variance_premium", "vol_strategy" (character)}
#'     \item{frequency}{One of "daily", "monthly", "quarterly" (character)}
#'     \item{forward_looking}{TRUE if the series reflects market expectations (logical)}
#'     \item{market_implied}{TRUE if derived from market prices (logical)}
#'     \item{start_year}{Approximate start year of the series (integer)}
#'     \item{source_detail}{Data provider detail, e.g. "CBOE", "ICE BofA" (character)}
#'     \item{source_type}{Where data is fetched from: "fred", "cboe", or "yahoo" (character)}
#'     \item{implied_from}{Underlying market the indicator is derived from, or
#'       \code{NA_character_} for non-implied series (character)}
#'     \item{liquidity}{Market liquidity of the underlying: "high", "medium",
#'       or "low" (character)}
#'   }
#' @family discovery
#' @export
hd_macro_registry <- function() {
  tibble::tribble(
    ~series_id,          ~description,                              ~long_name,                                            ~category,       ~frequency,  ~forward_looking, ~market_implied, ~start_year, ~source_detail,        ~source_type, ~implied_from,                        ~liquidity,
    # ---- Equity index ----
    "SP500",             "S&P 500 Index",                           "S&P 500 Stock Market Index",                          "equity_index",  "daily",     FALSE,            FALSE,           1957L,       "Standard & Poor's",   "fred",        NA_character_,                        "high",
    # ---- Implied vol: existing FRED series ----
    "VIXCLS",            "CBOE VIX (30-day implied vol)",           "30-Day Expected Volatility (S&P 500 Options)",        "implied_vol",   "daily",     TRUE,             TRUE,            1990L,       "CBOE",                "fred",        "S&P 500 options",                    "high",
    "VXVCLS",            "CBOE VXV (93-day implied vol)",           "93-Day Expected Volatility (S&P 500 Options)",        "implied_vol",   "daily",     TRUE,             TRUE,            2007L,       "CBOE",                "fred",        "S&P 500 options",                    "high",
    "OVXCLS",            "CBOE OVX (crude oil implied vol)",        "Crude Oil Expected Volatility (USO Options)",         "implied_vol",   "daily",     TRUE,             TRUE,            2007L,       "CBOE",                "fred",        "USO crude oil options",              "medium",
    "GVZCLS",            "CBOE GVZ (gold implied vol)",             "Gold Expected Volatility (GLD Options)",              "implied_vol",   "daily",     TRUE,             TRUE,            2008L,       "CBOE",                "fred",        "GLD gold options",                   "medium",
    "EVZCLS",            "CBOE EVZ (EUR/USD implied vol)",          "EUR/USD Expected Volatility (FXE Options)",           "implied_vol",   "daily",     TRUE,             TRUE,            2007L,       "CBOE",                "fred",        "FXE EUR/USD options",                "medium",
    # ---- Interest rates ----
    "DGS2",              "2-Year Treasury Yield",                   "2-Year US Treasury Yield",                            "interest_rate", "daily",     FALSE,            FALSE,           1976L,       "US Treasury",         "fred",        NA_character_,                        "high",
    "DGS10",             "10-Year Treasury Yield",                  "10-Year US Treasury Yield",                           "interest_rate", "daily",     FALSE,            FALSE,           1962L,       "US Treasury",         "fred",        NA_character_,                        "high",
    "DGS30",             "30-Year Treasury Yield",                  "30-Year US Treasury Yield",                           "interest_rate", "daily",     FALSE,            FALSE,           1977L,       "US Treasury",         "fred",        NA_character_,                        "high",
    "DFF",               "Federal Funds Rate (daily)",              "Federal Funds Rate (Daily)",                          "interest_rate", "daily",     FALSE,            FALSE,           1954L,       "Federal Reserve",     "fred",        NA_character_,                        "high",
    "FEDFUNDS",          "Effective Federal Funds Rate",            "Effective Federal Funds Rate (Monthly)",              "interest_rate", "monthly",   FALSE,            FALSE,           1954L,       "Federal Reserve",     "fred",        NA_character_,                        "high",
    # ---- Credit spreads ----
    "BAMLH0A0HYM2",      "ICE BofA US High Yield OAS",             "US High Yield Bond Spread (All Ratings)",             "credit_spread", "daily",     TRUE,             TRUE,            1996L,       "ICE BofA",            "fred",        "corporate bond vs Treasury spread",  "high",
    "BAMLC0A4CBBB",      "ICE BofA BBB Corporate OAS",             "US Investment Grade Bond Spread (BBB)",               "credit_spread", "daily",     TRUE,             TRUE,            1996L,       "ICE BofA",            "fred",        "corporate bond vs Treasury spread",  "medium",
    "BAMLH0A2HYB",       "ICE BofA BB High Yield OAS",             "US High Yield Bond Spread (BB Rating)",               "credit_spread", "daily",     TRUE,             TRUE,            1996L,       "ICE BofA",            "fred",        "corporate bond vs Treasury spread",  "medium",
    # ---- Yield curve ----
    "T10Y2Y",            "10Y-2Y Treasury Spread",                  "Yield Curve Slope (10Y minus 2Y Treasury)",           "yield_curve",   "daily",     TRUE,             TRUE,            1976L,       "US Treasury",         "fred",        "Treasury term structure",            "high",
    "T10Y3M",            "10Y-3M Treasury Spread",                  "Yield Curve Slope (10Y minus 3M Treasury)",           "yield_curve",   "daily",     TRUE,             TRUE,            1982L,       "US Treasury",         "fred",        "Treasury term structure",            "high",
    # ---- Inflation ----
    "T10YIE",            "10-Year Breakeven Inflation",             "10-Year Market-Implied Inflation Rate",               "inflation",     "daily",     TRUE,             TRUE,            2003L,       "TIPS-nominal spread", "fred",        "TIPS vs nominal Treasury spread",    "high",
    "T5YIE",             "5-Year Breakeven Inflation",              "5-Year Market-Implied Inflation Rate",                "inflation",     "daily",     TRUE,             TRUE,            2003L,       "TIPS-nominal spread", "fred",        "TIPS vs nominal Treasury spread",    "high",
    "T5YIFR",            "5Y-5Y Forward Inflation Expectation",     "5-to-10-Year Forward Inflation Expectation",          "inflation",     "daily",     TRUE,             TRUE,            2003L,       "TIPS-nominal spread", "fred",        "TIPS vs nominal Treasury spread",    "high",
    "GDP",               "Gross Domestic Product",                  "US Gross Domestic Product",                           "output",        "quarterly", FALSE,            FALSE,           1947L,       "BEA",                 "fred",        NA_character_,                        "low",
    "UNRATE",            "Unemployment Rate",                       "US Unemployment Rate",                                "employment",    "monthly",   FALSE,            FALSE,           1948L,       "BLS",                 "fred",        NA_character_,                        "low",
    "CPIAUCSL",          "Consumer Price Index",                    "Consumer Price Index (All Urban Consumers)",          "inflation",     "monthly",   FALSE,            FALSE,           1947L,       "BLS",                 "fred",        NA_character_,                        "low",
    "PCEPI",             "PCE Price Index",                         "Personal Consumption Expenditures Price Index",       "inflation",     "monthly",   FALSE,            FALSE,           1959L,       "BEA",                 "fred",        NA_character_,                        "low",
    # ---- Commodities ----
    "DCOILWTICO",        "WTI Crude Oil Spot",                      "WTI Crude Oil Spot Price",                            "commodity",     "daily",     FALSE,            FALSE,           1986L,       "EIA",                 "fred",        NA_character_,                        "medium",
    # ---- Currency ----
    "DTWEXBGS",          "Trade-Weighted USD Index",                "Trade-Weighted US Dollar Index",                      "currency",      "daily",     FALSE,            FALSE,           2006L,       "Federal Reserve",     "fred",        NA_character_,                        "medium",
    # ---- Housing / money ----
    "CSUSHPISA",         "Case-Shiller Home Price Index",           "S&P/Case-Shiller Home Price Index",                   "housing",       "monthly",   FALSE,            FALSE,           1987L,       "S&P/Case-Shiller",    "fred",        NA_character_,                        "low",
    "M2SL",              "M2 Money Supply",                         "M2 Money Supply",                                     "money_supply",  "monthly",   FALSE,            FALSE,           1959L,       "Federal Reserve",     "fred",        NA_character_,                        "low",
    # ---- CBOE term structure (fetched via fetch_cboe_vol.R) ----
    "VIX9D",             "CBOE VIX9D (9-day implied vol)",          "9-Day Expected Volatility (S&P 500 Options)",         "implied_vol",   "daily",     TRUE,             TRUE,            2011L,       "CBOE",                "cboe",        "S&P 500 options",                    "high",
    "VIX3M",             "CBOE VIX3M (3-month implied vol)",        "3-Month Expected Volatility (S&P 500 Options)",       "implied_vol",   "daily",     TRUE,             TRUE,            2009L,       "CBOE",                "cboe",        "S&P 500 options",                    "high",
    "VIX6M",             "CBOE VIX6M (6-month implied vol)",        "6-Month Expected Volatility (S&P 500 Options)",       "implied_vol",   "daily",     TRUE,             TRUE,            2008L,       "CBOE",                "cboe",        "S&P 500 options",                    "high",
    "VIX1Y",             "CBOE VIX1Y (1-year implied vol)",         "1-Year Expected Volatility (S&P 500 Options)",        "implied_vol",   "daily",     TRUE,             TRUE,            2007L,       "CBOE",                "cboe",        "S&P 500 options",                    "high",
    "SKEW",              "CBOE SKEW (tail risk)",                   "Tail Risk Index (S&P 500 OTM Put Skew)",              "implied_vol",   "daily",     TRUE,             TRUE,            1990L,       "CBOE",                "cboe",        "S&P 500 OTM put options",            "high",
    "MOVE",              "ICE BofA MOVE (bond vol)",                "Bond Market Volatility (Treasury Options)",           "implied_vol",          "daily",     TRUE,             TRUE,            2002L,       "ICE BofA",            "yahoo",       "Treasury options (swaptions)",                     "medium",
    # ---- CBOE VIX term structure extras (fetched via fetch_cboe_vol.R) ----
    "VIX1D",             "CBOE 1-Day VIX",                          "Overnight Expected Volatility (S&P 500 Options)",     "implied_vol",          "daily",     TRUE,             TRUE,            2022L,       "CBOE",                "cboe",        "S&P 500 options",                                  "high",
    "VVIX",              "CBOE VIX of VIX",                         "Volatility of Volatility (VIX Options)",              "implied_vol",          "daily",     TRUE,             TRUE,            2006L,       "CBOE",                "cboe",        "VIX options",                                      "high",
    # ---- CBOE equity index vol ----
    "VXN",               "CBOE Nasdaq-100 VIX",                     "Nasdaq-100 Expected Volatility (NDX Options)",        "implied_vol",          "daily",     TRUE,             TRUE,            2009L,       "CBOE",                "cboe",        "Nasdaq-100 options",                               "high",
    "VXD",               "CBOE DJIA VIX",                           "Dow Jones Expected Volatility (DJX Options)",         "implied_vol",          "daily",     TRUE,             TRUE,            2009L,       "CBOE",                "cboe",        "DJIA options",                                     "high",
    "RVX",               "CBOE Russell 2000 VIX",                   "Russell 2000 Expected Volatility (RUT Options)",      "implied_vol",          "daily",     TRUE,             TRUE,            2009L,       "CBOE",                "cboe",        "Russell 2000 options",                             "high",
    # ---- CBOE international / ETF vol ----
    "VXEEM",             "CBOE EM ETF VIX",                         "Emerging Markets Expected Volatility (EEM Options)",  "implied_vol",          "daily",     TRUE,             TRUE,            2011L,       "CBOE",                "cboe",        "EEM options",                                      "medium",
    "VXEWZ",             "CBOE Brazil ETF VIX",                     "Brazil Expected Volatility (EWZ Options)",            "implied_vol",          "daily",     TRUE,             TRUE,            2011L,       "CBOE",                "cboe",        "EWZ options",                                      "medium",
    "VXFXI",             "CBOE China ETF VIX",                      "China Expected Volatility (FXI Options)",             "implied_vol",          "daily",     TRUE,             TRUE,            2011L,       "CBOE",                "cboe",        "FXI options",                                      "medium",
    "VXEFA",             "CBOE EAFE ETF VIX",                       "Developed ex-US Expected Volatility (EFA Options)",   "implied_vol",          "daily",     TRUE,             TRUE,            2008L,       "CBOE",                "cboe",        "EFA options",                                      "medium",
    # ---- CBOE single-stock vol ----
    "VXAPL",             "CBOE Apple VIX",                          "Apple Expected Volatility (AAPL Options)",            "implied_vol",          "daily",     TRUE,             TRUE,            2011L,       "CBOE",                "cboe",        "AAPL options",                                     "high",
    "VXAZN",             "CBOE Amazon VIX",                         "Amazon Expected Volatility (AMZN Options)",           "implied_vol",          "daily",     TRUE,             TRUE,            2011L,       "CBOE",                "cboe",        "AMZN options",                                     "high",
    "VXGOG",             "CBOE Google VIX",                         "Alphabet Expected Volatility (GOOG Options)",         "implied_vol",          "daily",     TRUE,             TRUE,            2011L,       "CBOE",                "cboe",        "GOOG options",                                     "high",
    "VXGS",              "CBOE Goldman Sachs VIX",                  "Goldman Sachs Expected Volatility (GS Options)",      "implied_vol",          "daily",     TRUE,             TRUE,            2011L,       "CBOE",                "cboe",        "GS options",                                       "medium",
    "VXIBM",             "CBOE IBM VIX",                            "IBM Expected Volatility (IBM Options)",               "implied_vol",          "daily",     TRUE,             TRUE,            2011L,       "CBOE",                "cboe",        "IBM options",                                      "medium",
    # ---- CBOE commodity vol (OVX/GVZ CBOE CDN; OVXCLS/GVZCLS are FRED equivalents) ----
    "OVX",               "CBOE OVX (crude oil implied vol, CDN)",   "Crude Oil Expected Volatility (USO Options, CBOE CDN)","implied_vol",         "daily",     TRUE,             TRUE,            2007L,       "CBOE",                "cboe",        "USO crude oil options",                            "medium",
    "GVZ",               "CBOE GVZ (gold implied vol, CDN)",        "Gold Expected Volatility (GLD Options, CBOE CDN)",    "implied_vol",          "daily",     TRUE,             TRUE,            2008L,       "CBOE",                "cboe",        "GLD gold options",                                 "medium",
    "VXSLV",             "CBOE Silver ETF VIX",                     "Silver Expected Volatility (SLV Options)",            "implied_vol",          "daily",     TRUE,             TRUE,            2011L,       "CBOE",                "cboe",        "SLV options",                                      "medium",
    "VXGDX",             "CBOE Gold Miners ETF VIX",                "Gold Miners Expected Volatility (GDX Options)",       "implied_vol",          "daily",     TRUE,             TRUE,            2011L,       "CBOE",                "cboe",        "GDX options",                                      "medium",
    # ---- CBOE bond vol ----
    "VXTLT",             "CBOE Treasury Bond ETF VIX",              "Long Treasury Expected Volatility (TLT Options)",     "implied_vol",          "daily",     TRUE,             TRUE,            2004L,       "CBOE",                "cboe",        "TLT options",                                      "high",
    # ---- CBOE implied correlation ----
    "COR1M",             "CBOE 1-Month Implied Correlation",        "1-Month S&P 500 Pairwise Implied Correlation",        "implied_correlation",  "daily",     TRUE,             TRUE,            2006L,       "CBOE",                "cboe",        "S&P 500 index vs component options",               "high",
    "COR3M",             "CBOE 3-Month Implied Correlation",        "3-Month S&P 500 Pairwise Implied Correlation",        "implied_correlation",  "daily",     TRUE,             TRUE,            2006L,       "CBOE",                "cboe",        "S&P 500 index vs component options",               "high",
    "COR6M",             "CBOE 6-Month Implied Correlation",        "6-Month S&P 500 Pairwise Implied Correlation",        "implied_correlation",  "daily",     TRUE,             TRUE,            2006L,       "CBOE",                "cboe",        "S&P 500 index vs component options",               "high",
    "COR1Y",             "CBOE 1-Year Implied Correlation",         "1-Year S&P 500 Pairwise Implied Correlation",         "implied_correlation",  "daily",     TRUE,             TRUE,            2006L,       "CBOE",                "cboe",        "S&P 500 index vs component options",               "high",
    # ---- CBOE implied dispersion ----
    "DSPX",              "CBOE S&P 500 Dispersion Index",           "S&P 500 Implied Dispersion (Component vs Index Vol Gap)", "implied_dispersion", "daily",   TRUE,             TRUE,            2014L,       "CBOE",                "cboe",        "S&P 500 index vs component options",               "high",
    # ---- CBOE options strategy benchmarks (realised returns, NOT forward-looking) ----
    "BXM",               "CBOE BuyWrite Monthly: sell ATM SPX call monthly, hold underlying, roll at expiry", "S&P 500 Covered Call Strategy Return (Monthly ATM)",  "options_strategy",     "daily",     FALSE,            FALSE,           2002L,       "CBOE",                "cboe",        NA_character_,                                      "high",
    "BXY",               "CBOE 2% OTM BuyWrite: sell 2% OTM SPX call, less premium but lower cap risk", "S&P 500 Covered Call Strategy Return (2% OTM)",       "options_strategy",     "daily",     FALSE,            FALSE,           1988L,       "CBOE",                "cboe",        NA_character_,                                      "high",
    "BXMD",              "CBOE 30-Delta BuyWrite: sell 30-delta SPX call (further OTM), highest upside retention", "S&P 500 Covered Call Strategy Return (30-Delta)",     "options_strategy",     "daily",     FALSE,            FALSE,           1986L,       "CBOE",                "cboe",        NA_character_,                                      "high",
    "BXMC",              "CBOE Midpoint BuyWrite: sell SPX call at bid/ask midpoint strike", "S&P 500 Covered Call Strategy Return (Midpoint)",     "options_strategy",     "daily",     FALSE,            FALSE,           1990L,       "CBOE",                "cboe",        NA_character_,                                      "high",
    "BXMW",              "CBOE Weekly BuyWrite: sell ATM SPX call weekly, higher premium capture from faster rolls", "S&P 500 Weekly Covered Call Strategy Return",         "options_strategy",     "daily",     FALSE,            FALSE,           2012L,       "CBOE",                "cboe",        NA_character_,                                      "high",
    "PUT",               "CBOE PutWrite Monthly: sell ATM SPX put monthly, hold T-bills as collateral", "S&P 500 Cash-Secured Put Strategy Return (Monthly)",  "options_strategy",     "daily",     FALSE,            FALSE,           1991L,       "CBOE",                "cboe",        NA_character_,                                      "high",
    "WPUT",              "CBOE Weekly PutWrite: sell ATM SPX put weekly, faster premium capture", "S&P 500 Weekly Put Write Strategy Return",            "options_strategy",     "daily",     FALSE,            FALSE,           2006L,       "CBOE",                "cboe",        NA_character_,                                      "high",
    "PPUT",              "CBOE Protective Put: long SPX + buy 5% OTM put for tail protection", "S&P 500 with 5% OTM Put Protection Return",           "options_strategy",     "daily",     FALSE,            FALSE,           1986L,       "CBOE",                "cboe",        NA_character_,                                      "high",
    "CLL",               "CBOE 95-110 Collar: long SPX + buy 95% put + sell 110% call, capped upside/downside", "S&P 500 Collar Strategy Return (95% Put / 110% Call)","options_strategy",     "daily",     FALSE,            FALSE,           2008L,       "CBOE",                "cboe",        NA_character_,                                      "high",
    "CLLZ",              "CBOE Zero-Cost Collar: long SPX + collar where put premium equals call premium received", "S&P 500 Zero-Premium Collar Strategy Return",         "options_strategy",     "daily",     FALSE,            FALSE,           1986L,       "CBOE",                "cboe",        NA_character_,                                      "high",
    "BFLY",              "CBOE Iron Butterfly: short ATM straddle + long OTM strangle wings, profits from low vol", "S&P 500 Iron Butterfly Strategy Return",              "options_strategy",     "daily",     FALSE,            FALSE,           1986L,       "CBOE",                "cboe",        NA_character_,                                      "high",
    "CNDR",              "CBOE Iron Condor: short OTM strangle + long further OTM wings, profits from range-bound", "S&P 500 Iron Condor Strategy Return",                 "options_strategy",     "daily",     FALSE,            FALSE,           1986L,       "CBOE",                "cboe",        NA_character_,                                      "high",
    # ---- CBOE variance risk premium (forward-looking: implied minus realised spread) ----
    "VPD",               "CBOE Variance Premium Demand Index",      "Variance Risk Premium (Implied minus Realized Vol)",  "variance_premium",     "daily",     TRUE,             TRUE,            2007L,       "CBOE",                "cboe",        "S&P 500 options vs realized",                      "high",
    "VPN",               "CBOE Variance Premium Net Index",         "Net Variance Premium (Options Buyer/Seller P&L)",     "variance_premium",     "daily",     TRUE,             TRUE,            2008L,       "CBOE",                "cboe",        "S&P 500 options vs realized",                      "high",
    # ---- CBOE vol strategy (realised strategy returns, NOT forward-looking) ----
    "LOVOL",             "CBOE Long Vol: systematic long front-month VIX futures, profits from vol spikes", "Systematic Long VIX Futures Strategy Return",         "vol_strategy",         "daily",     FALSE,            FALSE,           2006L,       "CBOE",                "cboe",        NA_character_,                                      "medium",
    "SHORTVOL",          "CBOE Short Vol: systematic short front-month VIX futures, profits from contango carry", "Systematic Short VIX Futures Strategy Return",        "vol_strategy",         "daily",     FALSE,            FALSE,           2005L,       "CBOE",                "cboe",        NA_character_,                                      "medium",
    # ---- International implied vol indices ----
    "VSTOXX",            "Eurex VSTOXX: 30-day Euro Stoxx 50 implied vol from Eurex options",    "Euro Stoxx 50 Expected Volatility (Eurex Options)",   "implied_vol",          "daily",     TRUE,             TRUE,            1999L,       "Eurex/STOXX",         "stoxx",       "Euro Stoxx 50 options",                            "high",
    "VDAX",              "Eurex VDAX-NEW: 30-day DAX implied vol from Eurex options",            "DAX Expected Volatility (Eurex Options)",              "implied_vol",          "daily",     TRUE,             TRUE,            1992L,       "Eurex/STOXX",         "stoxx",       "DAX options",                                      "high",
    "VCAC",              "Euronext VCAC: 30-day CAC 40 implied vol",                             "CAC 40 Expected Volatility (Euronext Options)",        "implied_vol",          "daily",     TRUE,             TRUE,            2008L,       "Euronext",            "investing_com","CAC 40 options",                                   "medium",
    "VFTSE",             "LSEG VFTSE: 30-day FTSE 100 implied vol from LSE options",             "FTSE 100 Expected Volatility (LSE Options)",           "implied_vol",          "daily",     TRUE,             TRUE,            2000L,       "LSEG",                "lseg",        "FTSE 100 options",                                 "high",
    "VHSI",              "HKEX VHSI: 30-day Hang Seng implied vol",                              "Hang Seng Expected Volatility (HKEX Options)",        "implied_vol",          "daily",     TRUE,             TRUE,            2003L,       "HKEX",                "yahoo",       "Hang Seng options",                                "medium",
    "NKV1",              "JPX Nikkei 225 VI: 30-day Nikkei implied vol from Osaka Exchange options", "Nikkei 225 Expected Volatility (OSE Options)",     "implied_vol",          "daily",     TRUE,             TRUE,            2018L,       "JPX/Osaka",           "yahoo",       "Nikkei 225 options",                               "medium",
    "AXVI",              "S&P/ASX 200 VIX: 30-day ASX 200 implied vol",                          "S&P/ASX 200 Expected Volatility (ASX Options)",       "implied_vol",          "daily",     TRUE,             TRUE,            2008L,       "ASX/S&P",             "yahoo",       "ASX 200 options",                                  "medium",
    "INDIAVIX",          "NSE India VIX: 30-day NIFTY 50 implied vol (CBOE methodology)",        "NIFTY 50 Expected Volatility (NSE Options)",           "implied_vol",          "daily",     TRUE,             TRUE,            2008L,       "NSE India",           "yahoo",       "NIFTY 50 options",                                 "medium"
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
