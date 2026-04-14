# Fetch FRED macro data vintages via the ALFRED API
#
# ALFRED (Archival FRED) provides the value of each series as it was
# known on each publication date — the "revision triangle".
#
# This is critical for avoiding lookahead bias: GDP=2.3% today may have
# been initially published as GDP=1.9% and revised upward over months.
#
# Requires FRED API key: set FRED_API_KEY env var or use fredr::fredr_set_key()
#
# Usage:
#   Rscript scripts/fetch_macro_vintages.R

library(dplyr)
library(tidyr)
library(arrow)
library(httr2)

# Key macro series where revisions matter
VINTAGE_SERIES <- c(
  "GDP",          # Real GDP (quarterly, heavily revised)
  "GDPC1",        # Real GDP (chained 2017 dollars)
  "CPIAUCSL",     # CPI (monthly, occasionally revised)
  "UNRATE",       # Unemployment rate (monthly, revised)
  "PAYEMS",       # Nonfarm payrolls (monthly, heavily revised)
  "PCEPI",        # PCE price index (monthly, revised)
  "INDPRO",       # Industrial production (monthly, revised)
  "HOUST",        # Housing starts (monthly, revised)
  "RSAFS",        # Retail sales (monthly, revised)
  "DPCERA3M086SBEA"  # Real personal consumption (monthly)
)

fetch_alfred_series <- function(series_id, api_key,
                                 realtime_start = "2000-01-01",
                                 realtime_end = format(Sys.Date())) {
  cli::cli_inform(c("i" = "Fetching {series_id} vintages..."))

  # FRED ALFRED API: returns observations with realtime_start/end
  # Each observation has the value as known between realtime_start and realtime_end
  url <- paste0("https://api.stlouisfed.org/fred/series/observations",
                "?series_id=", series_id,
                "&api_key=", api_key,
                "&file_type=json",
                "&realtime_start=", realtime_start,
                "&realtime_end=", realtime_end,
                "&output_type=2")  # output_type=2 gives vintage dates

  resp <- tryCatch({
    request(url) |>
      req_timeout(30) |>
      req_perform() |>
      resp_body_json()
  }, error = function(e) {
    cli::cli_warn("  Failed {series_id}: {conditionMessage(e)}")
    return(NULL)
  })

  if (is.null(resp) || is.null(resp$observations)) {
    cli::cli_warn("  No data for {series_id}")
    return(NULL)
  }

  obs <- resp$observations
  if (length(obs) == 0) return(NULL)

  # Parse: each observation has date, realtime_start, realtime_end, value
  df <- bind_rows(lapply(obs, function(o) {
    tibble(
      series_id = series_id,
      date = as.Date(o$date),
      pub_date = as.Date(o$realtime_start),
      value = suppressWarnings(as.numeric(o$value))
    )
  })) |>
    filter(!is.na(value))

  cli::cli_inform(c("v" = "  {series_id}: {nrow(df)} vintage observations, {n_distinct(df$pub_date)} publication dates"))
  df
}

# Main
api_key <- Sys.getenv("FRED_API_KEY")
if (nzchar(api_key)) {
  # Use env var
} else {
  # Try fredr
  tryCatch({
    api_key <- fredr::fredr_get_key()
  }, error = function(e) {
    cli::cli_abort(c(
      "!" = "FRED API key required",
      "i" = "Set FRED_API_KEY env var or run fredr::fredr_set_key('your-key')"
    ))
  })
}

cli::cli_h1("Fetching {length(VINTAGE_SERIES)} FRED vintage series")

all_data <- lapply(VINTAGE_SERIES, function(sid) {
  Sys.sleep(0.5)  # Rate limit: max 120 requests/minute
  fetch_alfred_series(sid, api_key)
})

combined <- bind_rows(Filter(Negate(is.null), all_data))

if (nrow(combined) == 0) {
  cli::cli_abort("No vintage data fetched!")
}

# Write to dist
dir.create("data/dist", recursive = TRUE, showWarnings = FALSE)
out_path <- "data/dist/macro_vintages.parquet"
arrow::write_parquet(combined, out_path, compression = "zstd")

cli::cli_h2("Summary")
cli::cli_inform(c(
  "v" = "Total: {nrow(combined)} vintage observations",
  "i" = "Series: {n_distinct(combined$series_id)}",
  "i" = "Publication dates: {n_distinct(combined$pub_date)}",
  "i" = "Date range: {min(combined$date)} to {max(combined$date)}",
  "i" = "File: {out_path} ({round(file.info(out_path)$size / 1e3)} KB)"
))
