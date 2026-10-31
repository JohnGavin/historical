#!/usr/bin/env Rscript
# Fetch ECB Statistical Data Warehouse series (#88)
#
# Source: ECB SDMX REST API (no auth required)
# 29 series: FX, interest rates, yield curve, CISS stress, macro
#
# Usage: Rscript scripts/fetch_ecb.R
#
# Failure handling: each series is fetched in isolation. A series that errors
# (e.g. a timeout) or returns NULL is recorded and skipped; every series that
# succeeded is still written to parquet, and the script then exits non-zero if
# ANY series failed (a partial run is never reported as success).

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
  library(httr2)
})

# ── Source the package function ────────────────────────────────────
source(here::here("packages/historicaldata/R/ecb.R"))

# Fetch every series in `registry` independently.
#
# `fetch_fn(key, start = )` is hd_ecb() by default (injectable for tests).
# Returns list(results = named list of tibbles, failed = data.frame(series,
# reason)). A condition raised by one series is handled explicitly (recorded
# and surfaced via cli) -- it never aborts the others.
fetch_ecb_series <- function(registry, fetch_fn = hd_ecb, start = "2000-01-01") {
  results <- list()
  failed <- list()
  for (nm in names(registry)) {
    info <- registry[[nm]]
    outcome <- tryCatch(
      list(df = fetch_fn(info$key, start = start), reason = NA_character_),
      error = function(e) list(df = NULL, reason = conditionMessage(e))
    )
    if (!is.null(outcome$df)) {
      df <- outcome$df
      df$series_name <- nm
      df$description <- info$description
      df$unit <- info$unit
      results[[nm]] <- df
      cli_alert_success("{nm}: {nrow(df)} obs")
    } else {
      reason <- if (is.na(outcome$reason)) "returned NULL" else outcome$reason
      failed[[nm]] <- reason
      cli_alert_danger("{nm}: FAILED ({reason})")
    }
  }
  list(
    results = results,
    failed = data.frame(
      series = names(failed),
      reason = unlist(failed, use.names = FALSE),
      stringsAsFactors = FALSE
    )
  )
}

# One-line summary of failed series, or NA_character_ when none failed.
ecb_failure_summary <- function(failed) {
  if (nrow(failed) == 0L) return(NA_character_)
  paste0(nrow(failed), " ECB series failed: ",
         paste(failed$series, collapse = ", "))
}

.fetch_ecb_main <- function() {
  cli_h1("ECB Data Fetch")
  OUT_PATH <- here::here("data/raw/ecb_series.parquet")

  registry <- hd_ecb_registry()
  cli_alert_info("Fetching {length(registry)} ECB series...")

  fetched <- fetch_ecb_series(registry)
  results <- fetched$results
  failed <- fetched$failed

  all_ecb <- bind_rows(results)
  cli_alert_info("Total: {length(results)}/{length(registry)} series, {format(nrow(all_ecb), big.mark=',')} obs")

  # ── Append to existing or create new ────────────────────────────
  # Written even on a partial run so successful series are not discarded.
  if (nrow(all_ecb) > 0L) {
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

    summary <- combined |>
      group_by(series_name) |>
      summarise(n = n(), from = min(date), to = max(date), .groups = "drop") |>
      arrange(desc(n))
    cli_h2("Series summary")
    print(as.data.frame(summary), row.names = FALSE)
  } else {
    cli_alert_warning("No series fetched; nothing written")
  }

  # ── Fail loud on any failed series ──────────────────────────────
  msg <- ecb_failure_summary(failed)
  if (!is.na(msg)) {
    cli_alert_danger(msg)
    quit(save = "no", status = 1L)
  }
  invisible(TRUE)
}

# Run only as the Rscript entry point; source()'ing from tests loads the
# functions without fetching.
if (sys.nframe() == 0L) {
  .fetch_ecb_main()
}
