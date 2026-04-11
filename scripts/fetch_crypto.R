# Fetch crypto daily via Yahoo Finance (BTC-USD style tickers)
#
# CoinGecko free API is rate-limited and requires auth for /market_chart/range.
# Yahoo Finance has all major crypto as {SYMBOL}-USD tickers — same API as equities,
# no auth needed, and we already know the chunked fetch pattern works.
#
# Usage:
#   Rscript scripts/fetch_crypto.R

library(dplyr)
library(arrow)
library(httr2)
library(jsonlite)

# 16 tokens: Solana ecosystem + major coins
# Yahoo tickers use {SYMBOL}-USD format
TOKENS <- list(
  # Major coins
  list(yahoo = "BTC-USD",  ticker = "BTC"),
  list(yahoo = "ETH-USD",  ticker = "ETH"),
  list(yahoo = "BNB-USD",  ticker = "BNB"),
  list(yahoo = "SOL-USD",  ticker = "SOL"),
  list(yahoo = "XRP-USD",  ticker = "XRP"),
  list(yahoo = "ADA-USD",  ticker = "ADA"),
  list(yahoo = "DOGE-USD", ticker = "DOGE"),
  list(yahoo = "DOT-USD",  ticker = "DOT"),
  # Stablecoins
  list(yahoo = "USDC-USD", ticker = "USDC"),
  list(yahoo = "USDT-USD", ticker = "USDT"),
  # Solana ecosystem
  list(yahoo = "JUP31-USD",  ticker = "JUP"),
  list(yahoo = "RAY-USD",    ticker = "RAY"),
  list(yahoo = "HNT-USD",    ticker = "HNT"),
  list(yahoo = "RNDR-USD",   ticker = "RNDR"),
  list(yahoo = "BONK-USD",   ticker = "BONK"),
  list(yahoo = "PYTH-USD",   ticker = "PYTH")
)

fetch_yahoo_crypto <- function(yahoo_ticker, label, start_year = 2014) {
  base <- paste0("https://query2.finance.yahoo.com/v8/finance/chart/", yahoo_ticker)
  headers <- list(`User-Agent` = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)")

  boundaries <- c(
    as.integer(as.POSIXct(paste0(start_year, "-01-01"), tz = "UTC")),
    as.integer(as.POSIXct("2020-01-01", tz = "UTC")),
    as.integer(Sys.time())
  )

  all_chunks <- list()
  for (i in seq_len(length(boundaries) - 1)) {
    url <- paste0(base, "?period1=", boundaries[i], "&period2=", boundaries[i + 1], "&interval=1d")
    tryCatch({
      resp <- httr2::request(url) |>
        httr2::req_headers(`User-Agent` = "Mozilla/5.0") |>
        httr2::req_perform()
      raw <- httr2::resp_body_json(resp)
      result <- raw$chart$result[[1]]
      if (is.null(result$timestamp)) next

      ts <- unlist(result$timestamp)
      quote <- result$indicators$quote[[1]]

      df <- tibble(
        date = as.Date(as.POSIXct(ts, origin = "1970-01-01", tz = "UTC")),
        open = as.double(unlist(quote$open)),
        high = as.double(unlist(quote$high)),
        low = as.double(unlist(quote$low)),
        close = as.double(unlist(quote$close)),
        volume = as.double(unlist(quote$volume))
      ) |>
        filter(!is.na(close))
      all_chunks[[length(all_chunks) + 1]] <- df
    }, error = function(e) NULL)
    Sys.sleep(0.5)
  }

  if (length(all_chunks) == 0) return(NULL)

  bind_rows(all_chunks) |>
    distinct(date, .keep_all = TRUE) |>
    arrange(date) |>
    mutate(
      ticker = label,
      source = "yahoo",
      asset_class = "crypto"
    )
}

cli::cli_h1("Fetching {length(TOKENS)} crypto tokens")

all_data <- list()
for (i in seq_along(TOKENS)) {
  tok <- TOKENS[[i]]
  cli::cli_inform("  [{i}/{length(TOKENS)}] {tok$ticker} ({tok$yahoo})...")
  df <- fetch_yahoo_crypto(tok$yahoo, tok$ticker)
  if (!is.null(df)) {
    cli::cli_inform(c("v" = "    {nrow(df)} rows ({min(df$date)} to {max(df$date)})"))
    all_data[[length(all_data) + 1]] <- df
  } else {
    cli::cli_warn("    FAILED")
  }
  Sys.sleep(1)
}

combined <- bind_rows(all_data)
dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
out_path <- "data/raw/crypto_all.parquet"
arrow::write_parquet(combined, out_path, compression = "zstd")

cli::cli_h2("Summary")
cli::cli_inform(c(
  "v" = "Total: {nrow(combined)} rows, {n_distinct(combined$ticker)} tokens",
  "i" = "Date range: {min(combined$date)} to {max(combined$date)}",
  "i" = "File: {out_path} ({round(file.info(out_path)$size / 1e3)} KB)"
))
