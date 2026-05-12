# Dataset registry for cross-series alignment validation
#
# Enumerates dataset-shaped targets that have a date axis and may be joined
# across series. Phase 1 scope: ~15 targets already known to be joined
# cross-series. Used by `dv_join_key_types` (and future pairwise probes
# per #149).

DATASET_REGISTRY <- tibble::tribble(
  ~target_name,            ~kind,      ~freq,     ~date_anchor,    ~notes,
  # --- daily macro and equity ---
  "stk_universe",          "ohlcv",    "daily",   "trading_day",   "672 stocks; survivorship-biased per #150",
  "vix_daily",             "macro",    "daily",   "trading_day",   "VIXCLS from FRED via hd_macro",
  "vol_spikes",            "derived",  "daily",   "trading_day",   "from R/volatility_spike_analysis.R",
  "vix_ma_3m",             "derived",  "daily",   "trading_day",   "63-day rolling mean via roll_mean_safe",
  # --- monthly strategy returns (the #146 / #147 cluster) ---
  "fals_avoid_worst_input","returns",  "daily",   "trading_day",   NA,
  "fals_drif_input",       "returns",  "monthly", "mid_month",     "convention #147 — to migrate",
  "fals_fac_max_input",    "returns",  "monthly", "end_bizday",    NA,
  "fals_ltr_input",        "returns",  "monthly", "end_calendar",  "POSIXct stamps! see #146 close",
  "fals_rsc_input",        "returns",  "daily",   "trading_day",   NA,
  # --- circuit breaker (currently broken — see #145) ---
  "cb_data",               "macro",    "weekly",  "release_day",   "broken until #145 layer 2",
  "cb_regime",             "derived",  "weekly",  "release_day",   "depends on cb_data"
)

#' Dataset registry for cross-series alignment validation
#'
#' Enumerates dataset-shaped targets that have a date axis and may be joined
#' across series. Used by `dv_join_key_types` (and future pairwise probes per #149).
#'
#' @return Tibble with one row per registered target.
#' @export
dataset_registry <- function() DATASET_REGISTRY
