#!/usr/bin/env Rscript
# Fetch ECB Statistical Data Warehouse series (#88)
#
# Source: ECB SDMX REST API (no auth required)
# 29 series: FX, interest rates, yield curve, CISS stress, macro
#
# Usage: Rscript scripts/fetch_ecb.R

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
  library(httr2)
})

cli_h1("ECB Data Fetch")

# ── Source the package function ────────────────────────────────────
source(here::here("packages/historicaldata/R/ecb.R"))

OUT_PATH <- here::here("data/raw/ecb_series.parquet")

# ── Fetch all registered series ────────────────────────────────────
registry <- hd_ecb_registry()
cli_alert_info("Fetching {length(registry)} ECB series...")

results <- list()
for (nm in names(registry)) {
  info <- registry[[nm]]
  df <- hd_ecb(info$key, start = "2000-01-01")
  if (!is.null(df)) {
    df$series_name <- nm
    df$description <- info$description
    df$unit <- info$unit
    results[[nm]] <- df
    cli_alert_success("{nm}: {nrow(df)} obs")
  } else {
    cli_alert_warning("{nm}: FAILED")
  }
}

all_ecb <- bind_rows(results)
cli_alert_info("Total: {length(results)}/{length(registry)} series, {format(nrow(all_ecb), big.mark=',')} obs")

# ── Append to existing or create new ──────────────────────────────
if (file.exists(OUT_PATH)) {
  existing <- arrow::read_parquet(OUT_PATH)
  # Deduplicate: keep latest fetch for each (date, series_key) pair
  combined <- bind_rows(existing, all_ecb) |>
    distinct(date, series_key, .keep_all = TRUE) |>
    arrange(series_name, date)
  cli_alert_info("Merged with existing: {nrow(combined)} total rows (was {nrow(existing)})")
} else {
  combined <- all_ecb |> arrange(series_name, date)
}

arrow::write_parquet(combined, OUT_PATH)
cli_alert_success("Written to {OUT_PATH}")

# ── Summary ───────────────────────────────────────────────────────
summary <- combined |>
  group_by(series_name) |>
  summarise(n = n(), from = min(date), to = max(date), .groups = "drop") |>
  arrange(desc(n))
cli_h2("Series summary")
print(as.data.frame(summary), row.names = FALSE)
