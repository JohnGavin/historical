# targets plan for the historical_data analysis rn node.
#
# Runs INSIDE the Nix-sandboxed rn node. The enclosing rn command:
#   1. Writes equity_api, crypto_api, static tables to tmp_*.parquet
#   2. Calls tar_make()
#   3. Reads consolidated outputs as node results
#
# Scope: 50+ equity tickers + BTC crypto + 19 FRED macro series.

library(targets)
library(crew)

tar_option_set(
  packages = c("dplyr", "arrow", "pointblank", "rlang", "cli"),
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
tar_source("R/validate_macro.R")

list(
  # === EQUITY (50+ tickers from Yahoo + Kaggle AAPL for cross-ref) ===
  tar_target(equity_api_file,    "tmp_equity_api.parquet",    format = "file"),
  tar_target(equity_static_file, "tmp_equity_static.parquet", format = "file"),
  tar_target(equity_api_raw,    arrow::read_parquet(equity_api_file)),
  tar_target(equity_static_raw, arrow::read_parquet(equity_static_file)),

  tar_target(equity_api_valid,    validate_equity(equity_api_raw, "yahoo")),
  tar_target(equity_static_valid, validate_equity(equity_static_raw, "kaggle")),

  # Cross-reference: only AAPL has both sources
  tar_target(
    xref_equity,
    cross_reference(
      equity_api_valid |> dplyr::filter(ticker == "AAPL"),
      equity_static_valid,
      by = c("ticker", "date"), compare_col = "close",
      tolerance = 0.001, label = "AAPL: Yahoo vs Kaggle"
    )
  ),

  # Clean: merge API (all tickers) + static (AAPL only)
  tar_target(equity_clean, clean_equity(equity_api_valid, equity_static_valid)),

  tar_target(consolidated_equity, consolidate_parquet(equity_clean, "equity")),

  # === CRYPTO (BTC from 2 sources) ===
  tar_target(crypto_api_file,    "tmp_crypto_api.parquet",    format = "file"),
  tar_target(crypto_static_file, "tmp_crypto_static.parquet", format = "file"),
  tar_target(crypto_api_raw,    arrow::read_parquet(crypto_api_file)),
  tar_target(crypto_static_raw, arrow::read_parquet(crypto_static_file)),

  tar_target(crypto_api_valid,    validate_crypto(crypto_api_raw, "coingecko")),
  tar_target(crypto_static_valid, validate_crypto(crypto_static_raw, "backfill")),

  tar_target(
    xref_crypto,
    cross_reference(crypto_api_valid, crypto_static_valid,
                    by = c("ticker", "date"), compare_col = "close",
                    tolerance = 0.01, label = "BTC: CoinGecko vs backfill")
  ),

  tar_target(crypto_clean, clean_crypto(crypto_api_valid, crypto_static_valid)),
  tar_target(consolidated_crypto, consolidate_parquet(crypto_clean, "crypto")),

  # === CROSS-REFERENCE REPORT ===
  tar_target(xref_report, dplyr::bind_rows(xref_equity, xref_crypto)),

  # === MACRO (FRED) ===
  tar_target(macro_file, "tmp_macro.parquet", format = "file"),
  tar_target(macro_raw, arrow::read_parquet(macro_file)),
  tar_target(macro_valid, validate_macro(macro_raw)),
  tar_target(consolidated_macro, {
    out <- macro_valid |>
      dplyr::mutate(updated_at = Sys.time()) |>
      dplyr::arrange(series_id, date)
    n_series <- dplyr::n_distinct(out$series_id)
    cli::cli_inform(c("v" = "Consolidated macro: {n_series} series, {nrow(out)} rows"))
    out
  })
)
