#!/usr/bin/env Rscript
# fetch_intl_vol.R
# Fetches 8 international implied volatility indices and writes to
# data/raw/intl_vol.parquet.
#
# Sources by series:
#   STOXX .txt (semicolon-sep, European dates/decimals):
#     VSTOXX  - Euro Stoxx 50 30-day implied vol (Eurex, 1999+)
#     VDAX    - DAX 30-day implied vol (Eurex, 1992+)
#   Yahoo Finance (quantmod::getSymbols):
#     VHSI    - Hang Seng 30-day implied vol (^HSIL)
#     NKV1    - Nikkei 225 VI (^NKVI.OS)
#     AXVI    - S&P/ASX 200 VIX (^AXVI)
#     INDIAVIX - NIFTY 50 India VIX (^INDIAVIX)
#   TODO (stale/unavailable on Yahoo):
#     VCAC    - CAC 40 implied vol (Euronext / Investing.com)
#     VFTSE   - FTSE 100 implied vol (LSEG / ^VFTSE on Yahoo)

suppressPackageStartupMessages({
  library(httr2)
  library(tibble)
  library(dplyr)
  library(arrow)
  library(cli)
  library(quantmod)
})

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

#' Fetch a STOXX historical data .txt file and extract the 30-day close column.
#'
#' The STOXX format is semicolon-separated with:
#'   - European date format: DD.MM.YYYY
#'   - Comma as decimal separator
#'   - A header row containing column names
#'
#' The 30-day close column for VSTOXX is typically labelled "V2TX" (the
#' official Bloomberg/Eurex ticker). For VDAX-NEW it is "VDAX". We attempt
#' to identify the main index column by checking for known names first, then
#' falling back to the second numeric column.
fetch_stoxx_txt <- function(url, series_id, close_col_candidates) {
  cli::cli_progress_step("Fetching {series_id} from STOXX .txt ({url})")
  tryCatch(
    {
      raw_lines <- readLines(url, warn = FALSE)
      if (length(raw_lines) < 2L) {
        cli::cli_warn("{series_id}: file has fewer than 2 lines, skipping")
        return(NULL)
      }
      # STOXX files: 2 header rows, then comma-separated data with period decimals
      df <- utils::read.csv(
        text = paste(raw_lines[-(1:2)], collapse = "\n"),
        stringsAsFactors = FALSE,
        check.names = FALSE,
        na.strings = c("", "NA", "N/A", "#N/A", "-")
      )
      # Find date column (first column, typically named "Date" or "Datum")
      date_col <- names(df)[1L]
      # Find close column: prefer explicit candidates, fall back to second col
      close_col <- NULL
      for (candidate in close_col_candidates) {
        if (candidate %in% names(df)) {
          close_col <- candidate
          break
        }
      }
      if (is.null(close_col)) {
        numeric_cols <- names(df)[vapply(df, is.numeric, logical(1))]
        if (length(numeric_cols) == 0L) {
          # All columns may be character due to comma decimals — convert first
          for (col in names(df)[-1L]) {
            converted <- suppressWarnings(as.numeric(gsub(",", ".", df[[col]])))
            if (sum(!is.na(converted)) > 0L) {
              close_col <- col
              break
            }
          }
        } else {
          close_col <- numeric_cols[1L]
        }
      }
      if (is.null(close_col)) {
        cli::cli_warn("{series_id}: could not identify close column, skipping")
        return(NULL)
      }
      cli::cli_alert_info("{series_id}: using column {.val {close_col}}")
      # Parse dates: DD.MM.YYYY
      dates <- tryCatch(
        as.Date(df[[date_col]], format = "%d.%m.%Y"),
        error = function(e) {
          # Fallback: try ISO format
          as.Date(df[[date_col]])
        }
      )
      # Parse values: handle comma decimals if still character
      values <- df[[close_col]]
      if (is.character(values)) {
        values <- suppressWarnings(as.numeric(gsub(",", ".", values)))
      } else {
        values <- as.numeric(values)
      }
      result <- tibble::tibble(
        date      = dates,
        value     = values,
        series_id = series_id,
        source    = "stoxx"
      ) |>
        dplyr::filter(!is.na(date), !is.na(value))
      cli::cli_alert_success("{series_id}: {nrow(result)} rows fetched")
      result
    },
    error = function(e) {
      cli::cli_warn("Failed to fetch {series_id}: {conditionMessage(e)}")
      NULL
    }
  )
}

#' Fetch a series via Yahoo Finance using quantmod::getSymbols.
fetch_yahoo <- function(yahoo_ticker, series_id) {
  cli::cli_progress_step("Fetching {series_id} from Yahoo Finance ({yahoo_ticker})")
  tryCatch(
    {
      raw <- quantmod::getSymbols(
        yahoo_ticker,
        src         = "yahoo",
        auto.assign = FALSE,
        warnings    = FALSE
      )
      close_col <- quantmod::Cl(raw)
      result <- tibble::tibble(
        date      = as.Date(zoo::index(close_col)),
        value     = as.numeric(close_col),
        series_id = series_id,
        source    = "yahoo"
      ) |>
        dplyr::filter(!is.na(value))
      if (nrow(result) == 0L) {
        cli::cli_warn("{series_id}: Yahoo returned 0 non-NA rows (data may be stale)")
        return(NULL)
      }
      cli::cli_alert_success("{series_id}: {nrow(result)} rows fetched")
      result
    },
    error = function(e) {
      cli::cli_warn("Failed to fetch {series_id} ({yahoo_ticker}): {conditionMessage(e)}")
      NULL
    }
  )
}

# ---------------------------------------------------------------------------
# Fetch all series
# ---------------------------------------------------------------------------

cli::cli_h1("International Implied Volatility Fetch")

results <- list()

# ---- STOXX sources ----
# VSTOXX: the main 30-day rolling tenor column is labelled "V2TX" (Bloomberg)
# or may appear as "VSTOXX" in some file versions.
results[["VSTOXX"]] <- fetch_stoxx_txt(
  url                   = "https://www.stoxx.com/document/Indices/Current/HistoricalData/h_vstoxx.txt",
  series_id             = "VSTOXX",
  close_col_candidates  = c("V2TX", "VSTOXX", "SX5E VSTOXX")
)

# VDAX-NEW: 30-day rolling tenor column
results[["VDAX"]] <- fetch_stoxx_txt(
  url                   = "https://www.stoxx.com/document/Indices/Current/HistoricalData/h_vdax.txt",
  series_id             = "VDAX",
  close_col_candidates  = c("VDAX", "VDAXNEW", "V1XI")
)

# ---- Yahoo Finance sources ----
yahoo_series <- list(
  list(yahoo_ticker = "^HSIL",      series_id = "VHSI"),
  list(yahoo_ticker = "^NKVI.OS",   series_id = "NKV1"),
  list(yahoo_ticker = "^AXVI",      series_id = "AXVI"),
  list(yahoo_ticker = "^INDIAVIX",  series_id = "INDIAVIX")
)

for (s in yahoo_series) {
  results[[s$series_id]] <- fetch_yahoo(s$yahoo_ticker, s$series_id)
  Sys.sleep(1)  # respect Yahoo rate limit
}

# ---- TODO: VCAC and VFTSE ----
# VCAC (CAC 40 vol): Euronext does not expose a simple bulk download URL.
#   Investing.com is a possible source but requires scraping (TOS concern).
#   Yahoo symbol ^VCAC exists but is rarely updated.
#
# VFTSE (FTSE 100 vol): LSEG distributes via terminal; no free bulk endpoint.
#   Yahoo symbol ^VFTSE exists but data availability is limited.
#
# Both are registered in hd_macro_registry() with source_type "investing_com"
# and "lseg" respectively as a reminder that a dedicated fetch is needed.
cli::cli_alert_info("VCAC and VFTSE skipped — no reliable free bulk source available (see TODO comments)")

# ---------------------------------------------------------------------------
# Combine and summarise
# ---------------------------------------------------------------------------

non_null <- Filter(Negate(is.null), results)
if (length(non_null) == 0L) {
  cli::cli_abort("All fetches failed — no data to write")
}

combined <- dplyr::bind_rows(non_null)

cli::cli_alert_info(
  "Fetched {nrow(combined)} rows across {length(unique(combined$series_id))} series"
)

combined |>
  dplyr::summarise(
    n    = dplyr::n(),
    from = min(date, na.rm = TRUE),
    to   = max(date, na.rm = TRUE),
    .by  = series_id
  ) |>
  dplyr::arrange(series_id) |>
  print()

# ---------------------------------------------------------------------------
# Write to parquet
# ---------------------------------------------------------------------------

out_path <- here::here("data", "raw", "intl_vol.parquet")
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)

if (file.exists(out_path)) {
  existing <- arrow::read_parquet(out_path)
  combined <- dplyr::bind_rows(existing, combined) |>
    dplyr::distinct(date, series_id, .keep_all = TRUE) |>
    dplyr::arrange(series_id, date)
  cli::cli_alert_info("Merged with existing file; {nrow(combined)} total rows")
}

arrow::write_parquet(combined, out_path)
cli::cli_alert_success("Written to {.path {out_path}}")
