#!/usr/bin/env Rscript
# Fetch Guardian business article counts (#89)
#
# Source: Guardian Content API (test key = 1 call/sec, no body text)
# With GUARDIAN_API_KEY env var: 12 calls/sec, full text available
#
# Usage: Rscript scripts/fetch_guardian.R

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
  library(httr2)
})

cli_h1("Guardian News Data Fetch")

source(here::here("packages/historicaldata/R/guardian.R"))

OUT_PATH <- here::here("data/raw/guardian_monthly.parquet")

# ── Configuration ─────────────────────────────────────────────────
KEYWORDS <- c("recession", "inflation", "interest rate",
              "stock market", "central bank", "trade war")
FROM_DATE <- "2020-01-01"

api_key <- Sys.getenv("GUARDIAN_API_KEY", "test")
cli_alert_info("API key: {if (api_key == 'test') 'test (1 call/sec)' else 'developer key'}")

# ── Fetch monthly counts per keyword ──────────────────────────────
results <- list()
for (kw in KEYWORDS) {
  cli_alert_info("Fetching: {kw}")
  counts <- hd_guardian_monthly(kw, from = FROM_DATE, api_key = api_key)
  if (nrow(counts) > 0) {
    results[[kw]] <- counts
    cli_alert_success("{kw}: {sum(counts$n_articles)} articles across {nrow(counts)} months")
  } else {
    cli_alert_warning("{kw}: no data")
  }
}

monthly <- bind_rows(results)
cli_alert_info("Total: {nrow(monthly)} keyword-month rows")

# ── Append to existing or create new ──────────────────────────────
if (file.exists(OUT_PATH)) {
  existing <- arrow::read_parquet(OUT_PATH)
  combined <- bind_rows(existing, monthly) |>
    distinct(year_month, keyword, .keep_all = TRUE) |>
    arrange(keyword, year_month)
  cli_alert_info("Merged: {nrow(combined)} rows (was {nrow(existing)})")
} else {
  combined <- monthly |> arrange(keyword, year_month)
}

arrow::write_parquet(combined, OUT_PATH)
cli_alert_success("Written to {OUT_PATH}")
