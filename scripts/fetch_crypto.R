# Fetch BTC daily via geckor (CoinGecko)
#
# Standalone script for running OUTSIDE the T pipeline (needs network).
# The T pipeline's rn node embeds the fetch logic directly.
# This script is for manual/debug use.
#
# Usage:
#   Rscript scripts/fetch_crypto.R

library(geckor)
library(dplyr)
library(arrow)

fetch_coin <- function(coin_id, ticker_label, output_dir = "data/raw") {
  btc <- geckor::coin_history_range(
    coin_id = coin_id,
    vs_currency = "usd",
    from = as.POSIXct("2015-01-01"),
    to = Sys.time()
  )

  out <- btc |>
    transmute(
      date = as.Date(timestamp),
      close = price,
      volume = total_volume,
      market_cap = market_cap,
      ticker = ticker_label,
      source = "coingecko",
      asset_class = "crypto"
    )

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  out_path <- file.path(output_dir, paste0("geckor_", tolower(ticker_label), ".parquet"))
  arrow::write_parquet(out, out_path, compression = "zstd")

  cli::cli_inform(c("v" = "Wrote {nrow(out)} rows to {out_path}"))
  invisible(out_path)
}

fetch_coin("bitcoin", "BTC")
