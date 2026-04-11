# targets plan for the historical_data analysis rn node.
#
# Runs INSIDE the Nix-sandboxed rn node. The enclosing rn command:
#   1. Writes equity_api, crypto_api, static tables to tmp_*.parquet
#   2. Calls tar_make()
#   3. Reads consolidated outputs as node results
#
# Prototype scope: AAPL (equity) + BTC (crypto), 2 sources each.

library(targets)
library(crew)

tar_option_set(
  packages = c("dplyr", "arrow", "pointblank", "rlang"),
  controller = crew_controller_local(workers = 2L),
  memory = "transient",
  garbage_collection = TRUE,
  format = "rds"
)

# Source pure R functions
tar_source("R/validate.R")
tar_source("R/clean.R")
tar_source("R/cross_reference.R")
tar_source("R/consolidate.R")

list(
  # --- Inputs (parquet files written by the rn node) ---
  tar_target(equity_api_file,    "tmp_equity_api.parquet",    format = "file"),
  tar_target(equity_static_file, "tmp_equity_static.parquet", format = "file"),
  tar_target(crypto_api_file,    "tmp_crypto_api.parquet",    format = "file"),
  tar_target(crypto_static_file, "tmp_crypto_static.parquet", format = "file"),

  tar_target(equity_api_raw,    arrow::read_parquet(equity_api_file)),
  tar_target(equity_static_raw, arrow::read_parquet(equity_static_file)),
  tar_target(crypto_api_raw,    arrow::read_parquet(crypto_api_file)),
  tar_target(crypto_static_raw, arrow::read_parquet(crypto_static_file)),

  # --- Validation (pointblank) ---
  tar_target(equity_api_valid,    validate_equity(equity_api_raw, "yahoo")),
  tar_target(equity_static_valid, validate_equity(equity_static_raw, "kaggle")),
  tar_target(crypto_api_valid,    validate_crypto(crypto_api_raw, "coingecko")),
  tar_target(crypto_static_valid, validate_crypto(crypto_static_raw, "backfill")),

  # --- Cross-reference (compare sources) ---
  tar_target(
    xref_equity,
    cross_reference(equity_api_valid, equity_static_valid,
                    by = c("ticker", "date"), compare_col = "close",
                    tolerance = 0.001, label = "AAPL: Yahoo vs Kaggle")
  ),
  tar_target(
    xref_crypto,
    cross_reference(crypto_api_valid, crypto_static_valid,
                    by = c("ticker", "date"), compare_col = "close",
                    tolerance = 0.01, label = "BTC: CoinGecko vs backfill")
  ),
  tar_target(
    xref_report,
    dplyr::bind_rows(xref_equity, xref_crypto)
  ),

  # --- Clean (dedup, adjust, impute) ---
  tar_target(
    equity_clean,
    clean_equity(equity_api_valid, equity_static_valid)
  ),
  tar_target(
    crypto_clean,
    clean_crypto(crypto_api_valid, crypto_static_valid)
  ),

  # --- Consolidate (Hive partitions -> single Parquet per asset class) ---
  tar_target(
    consolidated_equity,
    consolidate_parquet(equity_clean, "equity")
  ),
  tar_target(
    consolidated_crypto,
    consolidate_parquet(crypto_clean, "crypto")
  )
)
