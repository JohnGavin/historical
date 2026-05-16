# Dataset registry for cross-series alignment validation
#
# Enumerates dataset-shaped targets that have a date axis and may be joined
# across series. Phase 1 scope: 33 targets known to be joined cross-series.
# Used by dv_join_key_types, dv_frequency_alignment, dv_monthly_convention
# (existing), and dv_pairwise_alignment_matrix (Phase 2, #149).
#
# Schema:
#   target_name  — targets store name
#   kind         — ohlcv / macro / returns / derived / factors
#   freq         — daily / weekly / monthly / quarterly / annual
#   date_anchor  — trading_day / mid_month / end_bizday / end_calendar / release_day
#   currency     — ISO-4217 (USD / EUR / local) or NA when not applicable
#   units        — decimal / percent / bps / price / count / index or NA
#   identity_col — join-key column for cross-sectional series (ticker / factor_name)
#                  NA for aggregate (one-row-per-date) series
#   notes        — free-text; NA when nothing to flag

DATASET_REGISTRY <- tibble::tribble(
  ~target_name,            ~kind,      ~freq,       ~date_anchor,    ~currency, ~units,    ~identity_col,   ~notes,
  # --- daily macro and equity ---
  "stk_universe",          "ohlcv",    "daily",     "trading_day",   "USD",     "price",   "ticker",        "672 stocks; survivorship-biased per #150",
  "vix_daily",             "macro",    "daily",     "trading_day",   NA,        "index",   NA,              "VIXCLS from FRED via hd_macro",
  "vol_spikes",            "derived",  "daily",     "trading_day",   NA,        "count",   NA,              "from R/volatility_spike_analysis.R",
  "vix_ma_3m",             "derived",  "daily",     "trading_day",   NA,        "index",   NA,              "63-day rolling mean via roll_mean_safe",
  # --- falsification bridge inputs (the #146 / #147 cluster) ---
  "fals_avoid_worst_input","returns",  "daily",     "trading_day",   "USD",     "decimal", NA,              NA,
  "fals_drif_input",       "returns",  "monthly",   "mid_month",     "USD",     "decimal", NA,              "convention #147 — to migrate",
  "fals_fac_max_input",    "returns",  "monthly",   "end_bizday",    "USD",     "decimal", NA,              NA,
  "fals_ltr_input",        "returns",  "monthly",   "end_calendar",  "USD",     "decimal", NA,              "POSIXct stamps! see #146 close",
  "fals_rsc_input",        "returns",  "daily",     "trading_day",   "USD",     "decimal", NA,              NA,
  # --- circuit breaker (currently broken — see #145) ---
  "cb_data",               "macro",    "weekly",    "release_day",   NA,        "index",   NA,              "broken until #145 layer 2",
  "cb_regime",             "derived",  "weekly",    "release_day",   NA,        "count",   NA,              "depends on cb_data",
  # --- daily factor returns (Fama-French / momentum) ---
  "drif_daily",            "factors",  "daily",     "trading_day",   "USD",     "percent", "factor_name",   "FF5+Mom daily via hd_factors; used in DRIF plan",
  "fm_daily",              "factors",  "daily",     "trading_day",   "USD",     "percent", "factor_name",   "FF5+Mom daily via hd_factors; used in Factor MAX plan",
  "aw_daily_ff",           "factors",  "daily",     "trading_day",   "USD",     "percent", NA,              "Mkt-RF + RF daily via hd_factors; 1926+ from French",
  "fals_factors",          "factors",  "daily",     "trading_day",   "USD",     "percent", "factor_name",   "FF5+Mom daily for falsification tests",
  "fals_rf",               "macro",    "daily",     "trading_day",   "USD",     "percent", NA,              "daily risk-free rate (RF) from FF5 via hd_factors",
  # --- daily equity universe data ---
  "aw_daily_returns",      "ohlcv",    "daily",     "trading_day",   "USD",     "decimal", "ticker",        "SPY/QQQ/IWM/DIA daily returns via hd_ohlcv",
  "aw_vix_daily",          "macro",    "daily",     "trading_day",   NA,        "index",   NA,              "SPY + VIXCLS joined; VIX from hd_macro",
  "etf_daily",             "ohlcv",    "daily",     "trading_day",   "USD",     "price",   "ticker",        "VLUE/MTUM/QUAL/USMV/VTV/IWD factor ETFs daily",
  "ltr_universe",          "ohlcv",    "daily",     "trading_day",   "USD",     "price",   "ticker",        "US non-ETF equity universe; ~672 tickers",
  "stk_daily_ret",         "ohlcv",    "daily",     "trading_day",   "USD",     "decimal", "ticker",        "stock-level daily returns from stk_universe",
  "mr_daily",              "ohlcv",    "daily",     "trading_day",   "USD",     "price",   "ticker",        "30-ticker mean-reversion universe daily returns",
  "vmo_daily",             "ohlcv",    "daily",     "trading_day",   "USD",     "price",   "ticker",        "TLT/GLD/DBC/UUP + VIX; macro overlay inputs",
  "vvix_daily",            "macro",    "daily",     "trading_day",   NA,        "index",   NA,              "VVIX from CBOE parquet; vol-of-vol series",
  "rsc_data",              "macro",    "daily",     "trading_day",   NA,        "index",   NA,              "SPY+VIXCLS+VIX3M+VVIX+RF joined; rsc inputs",
  # --- monthly aggregates and strategy portfolios ---
  # NOTE: fm_monthly excluded — uses `last_date` not `date` as its date column.
  # Re-add when the registry schema gains a `date_col` field (or fm_monthly is renamed).
  "fm_portfolio",          "returns",  "monthly",   "end_bizday",    "USD",     "decimal", NA,              "Factor MAX monthly portfolio returns",
  "drif_portfolio",        "returns",  "monthly",   "mid_month",     "USD",     "decimal", NA,              "DRIF factor-level monthly portfolio; date=last_date",
  "bt_prices",             "ohlcv",    "monthly",   "end_bizday",    "USD",     "price",   "ticker",        "multi-ticker monthly snapshot prices from bt plan",
  "bt_returns",            "returns",  "monthly",   "end_bizday",    "USD",     "decimal", "ticker",        "monthly returns from bt_prices via lag(adjusted)",
  "etf_monthly",           "ohlcv",    "monthly",   "end_bizday",    "USD",     "price",   "ticker",        "factor ETF monthly returns; end-of-month price",
  "stk_monthly",           "ohlcv",    "monthly",   "end_bizday",    "USD",     "decimal", "ticker",        "stock-level monthly returns from stk_universe",
  "ltr_portfolio",         "returns",  "monthly",   "end_bizday",    "USD",     "decimal", NA,              "LambdaMART long-short monthly; pre-computed parquet",
  "rafi_data",             "factors",  "monthly",   "end_calendar",  "USD",     "percent", "factor_name",   "FF5+Mom wide-format monthly; date=first-of-month",
  "nyt_keywords",          "macro",    "monthly",   "mid_month",     NA,        "count",   "keyword",       "NYT article counts per keyword; 12-month rolling avg",
  # --- annual / low-frequency ---
  # NOTE: jst_raw excluded — panel data (year × country), not a single time series
  # with a `date` join key. Schema is keyed by (year, country); not a candidate
  # for cross-series date alignment.
)

#' Dataset registry for cross-series alignment validation
#'
#' Enumerates dataset-shaped targets that have a date axis and may be joined
#' across series. Used by `dv_join_key_types`, `dv_frequency_alignment`,
#' `dv_monthly_convention`, and `dv_pairwise_alignment_matrix` (#149).
#'
#' @return Tibble with one row per registered target. Columns:
#'   `target_name`, `kind`, `freq`, `date_anchor`, `currency`, `units`,
#'   `identity_col`, `notes`.
#' @export
dataset_registry <- function() DATASET_REGISTRY
