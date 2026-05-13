# Dataset registry for cross-series alignment validation
#
# Enumerates dataset-shaped targets that have a date axis and may be joined
# across series. Phase 1 scope: ~15 targets already known to be joined
# cross-series. Used by `dv_join_key_types` (and future pairwise probes
# per #149).

DATASET_REGISTRY <- tibble::tribble(
  ~target_name,            ~kind,      ~freq,       ~date_anchor,    ~notes,
  # --- daily macro and equity ---
  "stk_universe",          "ohlcv",    "daily",     "trading_day",   "672 stocks; survivorship-biased per #150",
  "vix_daily",             "macro",    "daily",     "trading_day",   "VIXCLS from FRED via hd_macro",
  "vol_spikes",            "derived",  "daily",     "trading_day",   "from R/volatility_spike_analysis.R",
  "vix_ma_3m",             "derived",  "daily",     "trading_day",   "63-day rolling mean via roll_mean_safe",
  # --- monthly strategy returns (the #146 / #147 cluster) ---
  "fals_avoid_worst_input","returns",  "daily",     "trading_day",   NA,
  "fals_drif_input",       "returns",  "monthly",   "mid_month",     "convention #147 — to migrate",
  "fals_fac_max_input",    "returns",  "monthly",   "end_bizday",    NA,
  "fals_ltr_input",        "returns",  "monthly",   "end_calendar",  "POSIXct stamps! see #146 close",
  "fals_rsc_input",        "returns",  "daily",     "trading_day",   NA,
  # --- circuit breaker (currently broken — see #145) ---
  "cb_data",               "macro",    "weekly",    "release_day",   "broken until #145 layer 2",
  "cb_regime",             "derived",  "weekly",    "release_day",   "depends on cb_data",
  # --- daily factor returns (Fama-French / momentum) ---
  "drif_daily",            "factors",  "daily",     "trading_day",   "FF5+Mom daily via hd_factors; used in DRIF plan",
  "fm_daily",              "factors",  "daily",     "trading_day",   "FF5+Mom daily via hd_factors; used in Factor MAX plan",
  "aw_daily_ff",           "factors",  "daily",     "trading_day",   "Mkt-RF + RF daily via hd_factors; 1926+ from French",
  "fals_factors",          "factors",  "daily",     "trading_day",   "FF5+Mom daily for falsification tests",
  "fals_rf",               "macro",    "daily",     "trading_day",   "daily risk-free rate (RF) from FF5 via hd_factors",
  # --- daily equity universe data ---
  "aw_daily_returns",      "ohlcv",    "daily",     "trading_day",   "SPY/QQQ/IWM/DIA daily returns via hd_ohlcv",
  "aw_vix_daily",          "macro",    "daily",     "trading_day",   "SPY + VIXCLS joined; VIX from hd_macro",
  "etf_daily",             "ohlcv",    "daily",     "trading_day",   "VLUE/MTUM/QUAL/USMV/VTV/IWD factor ETFs daily",
  "ltr_universe",          "ohlcv",    "daily",     "trading_day",   "US non-ETF equity universe; ~672 tickers",
  "stk_daily_ret",         "ohlcv",    "daily",     "trading_day",   "stock-level daily returns from stk_universe",
  "mr_daily",              "ohlcv",    "daily",     "trading_day",   "30-ticker mean-reversion universe daily returns",
  "vmo_daily",             "ohlcv",    "daily",     "trading_day",   "TLT/GLD/DBC/UUP + VIX; macro overlay inputs",
  "vvix_daily",            "macro",    "daily",     "trading_day",   "VVIX from CBOE parquet; vol-of-vol series",
  "rsc_data",              "macro",    "daily",     "trading_day",   "SPY+VIXCLS+VIX3M+VVIX+RF joined; rsc inputs",
  # --- monthly aggregates and strategy portfolios ---
  "fm_monthly",            "factors",  "monthly",   "end_bizday",    "FF5+Mom monthly compound returns from fm_daily",
  "fm_portfolio",          "returns",  "monthly",   "end_bizday",    "Factor MAX monthly portfolio returns",
  "drif_portfolio",        "returns",  "monthly",   "mid_month",     "DRIF factor-level monthly portfolio; date=last_date",
  "bt_prices",             "ohlcv",    "monthly",   "end_bizday",    "multi-ticker monthly snapshot prices from bt plan",
  "bt_returns",            "returns",  "monthly",   "end_bizday",    "monthly returns from bt_prices via lag(adjusted)",
  "etf_monthly",           "ohlcv",    "monthly",   "end_bizday",    "factor ETF monthly returns; end-of-month price",
  "stk_monthly",           "ohlcv",    "monthly",   "end_bizday",    "stock-level monthly returns from stk_universe",
  "ltr_portfolio",         "returns",  "monthly",   "end_bizday",    "LambdaMART long-short monthly; pre-computed parquet",
  "rafi_data",             "factors",  "monthly",   "end_calendar",  "FF5+Mom wide-format monthly; date=first-of-month",
  "nyt_keywords",          "macro",    "monthly",   "mid_month",     "NYT article counts per keyword; 12-month rolling avg",
  # --- annual / low-frequency ---
  "jst_raw",               "macro",    "annual",    "end_calendar",  "JST Macrohistory DB; 155yr global asset returns"
)

#' Dataset registry for cross-series alignment validation
#'
#' Enumerates dataset-shaped targets that have a date axis and may be joined
#' across series. Used by `dv_join_key_types` (and future pairwise probes per #149).
#'
#' @return Tibble with one row per registered target.
#' @export
dataset_registry <- function() DATASET_REGISTRY
