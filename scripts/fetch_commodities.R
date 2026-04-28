#!/usr/bin/env Rscript
# Fetch commodity price and volatility series (#68)
#
# Sources:
# - FRED: IMF commodity price indexes (monthly)
# - Yahoo Finance: futures ETFs (daily)
# - CBOE: commodity vol indices (already in fetch_cboe_vol.R)
#
# Usage: Rscript scripts/fetch_commodities.R

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
})

pkgload::load_all(
  file.path(here::here(), "packages/historicaldata"),
  quiet = TRUE
)

cli_h1("Commodity Data Fetch")

# ── FRED monthly IMF price indexes ─────────────────────────────
fred_series <- c(
  # Energy
  "POILBREUSDM",   # Brent crude ($/bbl, monthly)
  "POILWTIUSDM",   # WTI crude ($/bbl, monthly)
  "PNGASEUUSDM",   # Natural gas EU ($/mmbtu, monthly)
  "PNGASUSUSDM",   # Natural gas US ($/mmbtu, monthly)
  "PCOALAUUSDM",   # Coal AU ($/mt, monthly)


  # Metals
  "PGOLDUSDM",     # Gold ($/troy oz, monthly)
  "PSILVERUSDM",   # Silver ($/troy oz, monthly)
  "PCOPPUSDM",     # Copper ($/mt, monthly)
  "PAABORUSDM",    # Aluminium ($/mt, monthly)
  "PNICKUSDM",     # Nickel ($/mt, monthly)
  "PIRONUSDM",     # Iron ore ($/mt, monthly)

  # Grains
  "PWHEAMTUSDM",   # Wheat ($/mt, monthly)
  "PCORNGLUSDM",   # Corn ($/mt, monthly)
  "PSOYBUSDM",     # Soybeans ($/mt, monthly)
  "PRICEUSDM",     # Rice ($/mt, monthly)

  # Softs
  "PCOFFOTMUSDM",  # Coffee (¢/lb, monthly)
  "PSUGAISAUSDM",  # Sugar (¢/lb, monthly)
  "PCOCOUSDM",     # Cocoa ($/mt, monthly)
  "PCOTTINDUSDM",  # Cotton (¢/lb, monthly)

  # Livestock
  "PBEEFINDUSDM",  # Beef (¢/lb, monthly)
  "PPABORUSDM"     # Pork (¢/lb, monthly)  # Note: may not exist
)

cli_inform(c("i" = "Fetching {length(fred_series)} FRED commodity series..."))

# Use fredr or direct FRED API
fred_key <- Sys.getenv("FRED_API_KEY")
if (nchar(fred_key) == 0) {
  cli_abort("Set FRED_API_KEY environment variable. Get one at: https://fred.stlouisfed.org/docs/api/api_key.html")
}

fetch_fred <- function(series_id) {
  url <- sprintf(
    "https://api.stlouisfed.org/fred/series/observations?series_id=%s&api_key=%s&file_type=json",
    series_id, fred_key
  )
  resp <- tryCatch(
    jsonlite::fromJSON(url),
    error = function(e) { cli_warn("Failed: {series_id}: {e$message}"); NULL }
  )
  if (is.null(resp) || is.null(resp$observations)) return(NULL)
  obs <- resp$observations
  if (nrow(obs) == 0) return(NULL)
  tibble(
    date = as.Date(obs$date),
    value = as.numeric(obs$value),
    series_id = series_id,
    source = "fred_imf"
  ) |> filter(!is.na(value))
}

fred_data <- lapply(fred_series, function(s) {
  Sys.sleep(0.5)  # rate limit
  fetch_fred(s)
})
fred_data <- bind_rows(Filter(Negate(is.null), fred_data))
cli_inform(c("v" = "FRED: {nrow(fred_data)} rows, {n_distinct(fred_data$series_id)} series"))

# ── Yahoo Finance: commodity futures ETFs (daily) ──────────────
yahoo_tickers <- c(
  "CL=F",   # WTI Crude futures
  "BZ=F",   # Brent Crude futures
  "NG=F",   # Natural Gas futures
  "GC=F",   # Gold futures
  "SI=F",   # Silver futures
  "HG=F",   # Copper futures
  "PL=F",   # Platinum futures
  "PA=F",   # Palladium futures
  "ZW=F",   # Wheat futures
  "ZC=F",   # Corn futures
  "ZS=F",   # Soybeans futures
  "KC=F",   # Coffee futures
  "SB=F",   # Sugar futures
  "CC=F",   # Cocoa futures
  "CT=F",   # Cotton futures
  "LE=F",   # Live Cattle futures
  "HE=F",   # Lean Hogs futures
  "DBA",    # Agriculture ETF
  "DBB",    # Base Metals ETF
  "DBC",    # Commodities Broad ETF
  "USO",    # US Oil ETF
  "GLD",    # Gold ETF
  "SLV",    # Silver ETF
  "PDBC"    # Diversified Commodity ETF
)

cli_inform(c("i" = "Fetching {length(yahoo_tickers)} Yahoo commodity tickers..."))

yahoo_data <- lapply(yahoo_tickers, function(tkr) {
  Sys.sleep(1)  # rate limit
  tryCatch({
    d <- hd_ohlcv(tkr)
    if (nrow(d) == 0) return(NULL)
    d |>
      mutate(series_id = tkr, source = "yahoo") |>
      select(date, value = adjusted, series_id, source)
  }, error = function(e) {
    cli_warn("Failed: {tkr}: {e$message}")
    NULL
  })
})
yahoo_data <- bind_rows(Filter(Negate(is.null), yahoo_data))
cli_inform(c("v" = "Yahoo: {nrow(yahoo_data)} rows, {n_distinct(yahoo_data$series_id)} tickers"))

# ── Combine and write ──────────────────────────────────────────
all_data <- bind_rows(fred_data, yahoo_data)

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
out_path <- "data/raw/commodities.parquet"
arrow::write_parquet(all_data, out_path, compression = "zstd")

cli_h2("Summary")
cli_inform(c(
  "v" = "{nrow(all_data)} total rows",
  "i" = "{n_distinct(all_data$series_id)} series",
  "i" = "FRED: {nrow(fred_data)} rows ({n_distinct(fred_data$series_id)} series)",
  "i" = "Yahoo: {nrow(yahoo_data)} rows ({n_distinct(yahoo_data$series_id)} tickers)",
  "i" = "File: {out_path} ({round(file.info(out_path)$size / 1e6, 1)} MB)"
))
