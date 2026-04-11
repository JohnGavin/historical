# Fetch BTC daily via CoinGecko API (httr2/jsonlite)
#
# Standalone script for running OUTSIDE the T pipeline (needs network).
# The T pipeline's rn node embeds the fetch logic directly.
# This script is for manual/debug use.
#
# Usage:
#   Rscript scripts/fetch_crypto.R

library(httr2)
library(jsonlite)
library(dplyr)
library(arrow)

fetch_coin <- function(coin_id, ticker_label, output_dir = "data/raw") {
  resp <- httr2::request(
    paste0("https://api.coingecko.com/api/v3/coins/", coin_id, "/market_chart")
  ) |>
    httr2::req_url_query(vs_currency = "usd", days = "max", interval = "daily") |>
    httr2::req_user_agent("historical_data_pipeline/0.1") |>
    httr2::req_retry(max_tries = 3, backoff = ~ 10) |>
    httr2::req_perform()

  data <- httr2::resp_body_json(resp)

  prices <- do.call(rbind, lapply(data$prices, \(x) data.frame(ts = x[[1]], close = x[[2]])))
  volumes <- do.call(rbind, lapply(data$total_volumes, \(x) data.frame(ts = x[[1]], volume = x[[2]])))
  mcaps <- do.call(rbind, lapply(data$market_caps, \(x) data.frame(ts = x[[1]], market_cap = x[[2]])))

  out <- prices |>
    left_join(volumes, by = "ts") |>
    left_join(mcaps, by = "ts") |>
    transmute(
      date = as.Date(as.POSIXct(ts / 1000, origin = "1970-01-01")),
      close = close,
      volume = volume,
      market_cap = market_cap,
      ticker = ticker_label,
      source = "coingecko",
      asset_class = "crypto"
    ) |>
    distinct(date, .keep_all = TRUE)

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  out_path <- file.path(output_dir, paste0("geckor_", tolower(ticker_label), ".parquet"))
  arrow::write_parquet(out, out_path, compression = "zstd")

  cli::cli_inform(c("v" = "Wrote {nrow(out)} rows to {out_path}"))
  invisible(out_path)
}

fetch_coin("bitcoin", "BTC")
