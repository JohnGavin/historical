-- historical_data: Prototype pipeline (AAPL + BTC)
--
-- Prerequisites: Fetch data first (outside Nix sandbox — needs network):
--   python scripts/fetch_equity.py            → data/raw/yfinance_aapl.parquet
--   Rscript scripts/fetch_crypto.R            → data/raw/geckor_btc.parquet
--   (static files already in data/raw/)
--
-- Architecture: include parquet/csv → rn (targets DAG) → Quarto report

p = pipeline {

  -- 1. R: read AAPL API data (yfinance, pre-fetched)
  equity_api = rn(
    command = <{
      library(arrow)
      library(dplyr)
      equity_api <- arrow::read_parquet("data/raw/yfinance_aapl.parquet") |>
        as_tibble() |>
        transmute(
          date = as.Date(Date),
          open = Open, high = High, low = Low,
          close = Close, adjusted = `Adj Close`,
          volume = as.double(Volume),
          ticker = "AAPL", source = "yahoo", asset_class = "equity"
        )
    }>,
    include = ["data/raw/yfinance_aapl.parquet"],
    serializer = ^arrow
  )

  -- 2. R: read BTC API data (CoinGecko, pre-fetched)
  crypto_api = rn(
    command = <{
      library(arrow)
      crypto_api <- arrow::read_parquet("data/raw/geckor_btc.parquet") |>
        as.data.frame()
    }>,
    include = ["data/raw/geckor_btc.parquet"],
    serializer = ^arrow
  )

  -- 3. R: read AAPL static data (Kaggle CSV)
  equity_static = rn(
    command = <{
      library(dplyr)
      equity_static <- read.csv("data/raw/kaggle_aapl.csv") |>
        as_tibble() |>
        transmute(
          date = as.Date(Date),
          open = Open, high = High, low = Low,
          close = Close, volume = as.numeric(Volume),
          ticker = "AAPL", source = "kaggle", asset_class = "equity"
        )
    }>,
    include = ["data/raw/kaggle_aapl.csv"],
    serializer = ^arrow
  )

  -- 4. R: read BTC static data (backfill)
  crypto_static = rn(
    command = <{
      library(arrow)
      library(dplyr)
      crypto_static <- arrow::read_parquet("data/raw/btc_backfill.parquet") |>
        as_tibble() |>
        mutate(source = "backfill", asset_class = "crypto")
    }>,
    include = ["data/raw/btc_backfill.parquet"],
    serializer = ^arrow
  )

  -- 5. R: read FRED macro data (pre-fetched)
  macro_data = rn(
    command = <{
      library(arrow)
      macro_data <- arrow::read_parquet("data/raw/fred_macro.parquet") |>
        as.data.frame()
    }>,
    include = ["data/raw/fred_macro.parquet"],
    serializer = ^arrow
  )

  -- 6. R: targets DAG — validate, cross-reference, clean, consolidate
  analysis = rn(
    command = <{
      library(arrow)
      library(targets)

      arrow::write_parquet(equity_api,    "tmp_equity_api.parquet")
      arrow::write_parquet(crypto_api,    "tmp_crypto_api.parquet")
      arrow::write_parquet(equity_static, "tmp_equity_static.parquet")
      arrow::write_parquet(crypto_static, "tmp_crypto_static.parquet")
      arrow::write_parquet(macro_data,    "tmp_macro.parquet")

      tar_make(reporter = "silent")

      eq <- tar_read(consolidated_equity)
      cr <- tar_read(consolidated_crypto)
      ma <- tar_read(consolidated_macro)
      xref <- tar_read(xref_report)

      arrow::write_parquet(eq, "output_equity.parquet")
      arrow::write_parquet(cr, "output_crypto.parquet")
      arrow::write_parquet(ma, "output_macro.parquet")

      analysis <- xref
    }>,
    deserializer = [
      equity_api:    ^arrow,
      crypto_api:    ^arrow,
      equity_static: ^arrow,
      crypto_static: ^arrow,
      macro_data:    ^arrow
    ],
    include = [
      "_targets.R",
      "R/validate.R",
      "R/validate_macro.R",
      "R/clean.R",
      "R/cross_reference.R",
      "R/consolidate.R"
    ],
    serializer = ^arrow
  )

  -- 6. Quarto report: prototype results
  report = node(script = "docs/prototype-results.qmd", runtime = Quarto)
}

populate_pipeline(p, build = true, verbose = 1)
pipeline_copy()
