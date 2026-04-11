-- historical_data: Prototype pipeline (AAPL + BTC)
--
-- Architecture:
--   pyn (fetch equity) + rn (fetch crypto + ingest static)
--   → rn (targets DAG: validate, cross-ref, clean, consolidate)
--   → Quarto report
--
-- Prerequisites:
--   Place static files in data/raw/ before running:
--     data/raw/kaggle_aapl.csv       — Kaggle NASDAQ AAPL daily OHLCV
--     data/raw/btc_backfill.parquet  — CoinGecko/Kaggle BTC daily OHLCV

p = pipeline {

  -- 1. Python: fetch AAPL daily OHLCV via yfinance
  equity_api = pyn(
    command = <{
import yfinance as yf
import pyarrow as pa
import pyarrow.parquet as pq
from datetime import datetime

ticker = yf.Ticker("AAPL")
df = ticker.history(period="max")
df = df.reset_index()
df = df.rename(columns={
    "Date": "date", "Open": "open", "High": "high", "Low": "low",
    "Close": "close", "Volume": "volume", "Dividends": "dividends",
    "Stock Splits": "stock_splits"
})
df["ticker"] = "AAPL"
df["source"] = "yahoo"
df["asset_class"] = "equity"
df["date"] = df["date"].dt.tz_localize(None)

table = pa.Table.from_pandas(df)
equity_api = table
    }>,
    serializer = ^arrow
  )

  -- 2. R: fetch BTC daily via geckor + ingest static files
  crypto_api = rn(
    command = <{
      library(arrow)
      library(geckor)
      library(dplyr)

      btc <- geckor::coin_history_range(
        coin_id = "bitcoin",
        vs_currency = "usd",
        from = as.POSIXct("2015-01-01"),
        to = Sys.time()
      )

      crypto_api <- btc |>
        transmute(
          date = as.Date(timestamp),
          price_close = price,
          volume = total_volume,
          market_cap = market_cap,
          ticker = "BTC",
          source = "coingecko",
          asset_class = "crypto"
        )
    }>,
    serializer = ^arrow
  )

  -- 3. R: ingest static files (Kaggle AAPL CSV + BTC backfill)
  static_data = rn(
    command = <{
      library(arrow)
      library(dplyr)

      # Kaggle AAPL CSV (raw OHLCV, unadjusted)
      aapl_kaggle <- read.csv("data/raw/kaggle_aapl.csv") |>
        as_tibble() |>
        mutate(
          date = as.Date(Date),
          open = Open, high = High, low = Low,
          close = Close, volume = as.numeric(Volume),
          ticker = "AAPL",
          source = "kaggle",
          asset_class = "equity"
        ) |>
        select(date, open, high, low, close, volume, ticker, source, asset_class)

      # BTC backfill (Parquet or CSV)
      btc_static_path <- "data/raw/btc_backfill.parquet"
      if (file.exists(btc_static_path)) {
        btc_static <- arrow::read_parquet(btc_static_path) |>
          as_tibble() |>
          mutate(source = "backfill", asset_class = "crypto")
      } else {
        btc_static_path_csv <- "data/raw/btc_backfill.csv"
        btc_static <- read.csv(btc_static_path_csv) |>
          as_tibble() |>
          mutate(
            date = as.Date(date),
            source = "backfill",
            asset_class = "crypto",
            ticker = "BTC"
          )
      }

      static_data <- list(
        aapl_kaggle = aapl_kaggle,
        btc_static = btc_static
      )
    }>,
    include = [
      "data/raw/kaggle_aapl.csv",
      "data/raw/btc_backfill.parquet"
    ],
    serializer = ^arrow
  )

  -- 4. R: targets DAG — validate, cross-reference, clean, consolidate
  analysis = rn(
    command = <{
      library(arrow)
      library(targets)

      # Write inputs for targets to read
      arrow::write_parquet(equity_api,  "tmp_equity_api.parquet")
      arrow::write_parquet(crypto_api,  "tmp_crypto_api.parquet")

      # static_data is a list of two tables
      arrow::write_parquet(static_data$aapl_kaggle, "tmp_equity_static.parquet")
      arrow::write_parquet(static_data$btc_static,  "tmp_crypto_static.parquet")

      tar_make(reporter = "silent")

      # Read consolidated outputs
      analysis <- list(
        equity  = tar_read(consolidated_equity),
        crypto  = tar_read(consolidated_crypto),
        xref    = tar_read(xref_report)
      )
    }>,
    deserializer = [
      equity_api:  ^arrow,
      crypto_api:  ^arrow,
      static_data: ^arrow
    ],
    include = [
      "_targets.R",
      "R/validate.R",
      "R/clean.R",
      "R/cross_reference.R",
      "R/consolidate.R"
    ],
    serializer = ^arrow
  )

  -- 5. Quarto report: prototype results
  report = node(script = "docs/prototype-results.qmd", runtime = Quarto)
}

populate_pipeline(p, build = true, verbose = 1)
pipeline_copy()
