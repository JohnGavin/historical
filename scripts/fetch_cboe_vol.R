#!/usr/bin/env Rscript
# fetch_cboe_vol.R
# Fetches CBOE volatility term structure and skew indicators from the CBOE CDN
# and ICE BofA MOVE via Yahoo Finance. Writes to data/raw/cboe_vol.parquet.
#
# Indicators:
#   VIX9D, VIX3M, VIX6M, VIX1Y  — CBOE VIX term structure (CDN JSON)
#   SKEW                          — CBOE Skew Index (CDN JSON)
#   MOVE                          — ICE BofA MOVE Index (Yahoo Finance ^MOVE)

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
  library(tibble)
  library(dplyr)
  library(arrow)
  library(cli)
  library(quantmod)
})

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

fetch_cboe <- function(symbol, series_id) {
  url <- paste0(
    "https://cdn.cboe.com/api/global/delayed_quotes/charts/historical/_",
    symbol, ".json"
  )
  cli::cli_progress_step("Fetching {series_id} from CBOE CDN")
  tryCatch(
    {
      resp <- httr2::request(url) |>
        httr2::req_timeout(30) |>
        httr2::req_perform()
      raw  <- httr2::resp_body_json(resp, simplifyVector = FALSE)
      data <- raw$data
      tibble::tibble(
        date      = as.Date(vapply(data, \(x) x$date, character(1))),
        value     = vapply(data, \(x) as.numeric(x$close), numeric(1)),
        series_id = series_id,
        source    = "cboe"
      )
    },
    error = function(e) {
      cli::cli_warn("Failed to fetch {series_id}: {conditionMessage(e)}")
      NULL
    }
  )
}

fetch_move <- function() {
  cli::cli_progress_step("Fetching MOVE from Yahoo Finance (^MOVE)")
  tryCatch(
    {
      raw <- quantmod::getSymbols(
        "^MOVE",
        src         = "yahoo",
        auto.assign = FALSE,
        warnings    = FALSE
      )
      close_col <- quantmod::Cl(raw)
      tibble::tibble(
        date      = as.Date(zoo::index(close_col)),
        value     = as.numeric(close_col),
        series_id = "MOVE",
        source    = "ice_via_yahoo"
      ) |>
        dplyr::filter(!is.na(value))
    },
    error = function(e) {
      cli::cli_warn("Failed to fetch MOVE: {conditionMessage(e)}")
      NULL
    }
  )
}

# ---------------------------------------------------------------------------
# Fetch all series
# ---------------------------------------------------------------------------

cli::cli_h1("CBOE Volatility Indicators Fetch")

cboe_series <- list(
  list(symbol = "VIX9D", series_id = "VIX9D"),
  list(symbol = "VIX3M",  series_id = "VIX3M"),
  list(symbol = "VIX6M",  series_id = "VIX6M"),
  list(symbol = "VIX1Y",  series_id = "VIX1Y"),
  list(symbol = "SKEW",   series_id = "SKEW")
)

results <- lapply(cboe_series, function(s) fetch_cboe(s$symbol, s$series_id))
results[["MOVE"]] <- fetch_move()

combined <- dplyr::bind_rows(Filter(Negate(is.null), results))

cli::cli_alert_info(
  "Fetched {nrow(combined)} rows across {length(unique(combined$series_id))} series"
)

# ---------------------------------------------------------------------------
# Write to parquet
# ---------------------------------------------------------------------------

out_path <- here::here("data", "raw", "cboe_vol.parquet")
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)

if (file.exists(out_path)) {
  existing <- arrow::read_parquet(out_path)
  # Deduplicate: keep newest fetch for any (date, series_id) duplicate
  combined <- dplyr::bind_rows(existing, combined) |>
    dplyr::distinct(date, series_id, .keep_all = TRUE) |>
    dplyr::arrange(series_id, date)
  cli::cli_alert_info("Merged with existing file; {nrow(combined)} total rows")
}

arrow::write_parquet(combined, out_path)
cli::cli_alert_success("Written to {.path {out_path}}")
