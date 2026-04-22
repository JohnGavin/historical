# Fetch key FRED macro series via direct CSV download (no API key needed)
#
# Usage:
#   Rscript scripts/fetch_macro.R

library(dplyr)
library(arrow)

# 28 key macro series covering:
# - Equity indices (SP500)
# - Volatility (VIX)
# - Interest rates (DGS2, DGS10, DGS30, FEDFUNDS, DFF)
# - Credit spreads (BAMLH0A0HYM2, BAMLC0A4CBBB, BAMLH0A2HYB)
# - Macro (GDP, UNRATE, CPIAUCSL, PCEPI)
# - Commodities (DCOILWTICO, GOLDAMGBD228NLBM)
# - Currency (DTWEXBGS)
# - Housing (CSUSHPISA)
# - Money supply (M2SL)
# - Leading indicators (T10Y2Y, T10YIE)
# - Forward-looking implied volatility (VXVCLS, OVXCLS, GVZCLS, EVZCLS)
# - Forward-looking inflation/rates (T5YIE, T5YIFR, T10Y3M)

series_list <- c(
  "SP500",              # S&P 500 (daily)
  "VIXCLS",             # VIX (daily)
  "DGS2",               # 2-Year Treasury (daily)
  "DGS10",              # 10-Year Treasury (daily)
  "DGS30",              # 30-Year Treasury (daily)
  "DFF",                # Federal Funds Rate (daily)
  "FEDFUNDS",           # Effective Federal Funds Rate (monthly)
  "BAMLH0A0HYM2",       # ICE BofA US High Yield Spread (daily)
  "BAMLC0A4CBBB",       # ICE BofA BBB Corporate Spread (daily)
  "GDP",                # GDP (quarterly)
  "UNRATE",             # Unemployment Rate (monthly)
  "CPIAUCSL",           # CPI (monthly)
  "PCEPI",              # PCE Price Index (monthly)
  "DCOILWTICO",         # WTI Crude Oil (daily)
  "GOLDAMGBD228NLBM",   # Gold Price London Fix (daily)
  "DTWEXBGS",           # Trade-Weighted USD Index (daily)
  "CSUSHPISA",          # Case-Shiller Home Price Index (monthly)
  "M2SL",               # M2 Money Supply (monthly)
  "T10Y2Y",             # 10Y-2Y Spread (daily, yield curve)
  "T10YIE",             # 10Y Breakeven Inflation (daily)
  # Forward-looking implied volatility
  "VXVCLS",              # VXV 93-day VIX (vol term structure)
  "OVXCLS",              # OVX crude oil implied vol
  "GVZCLS",              # GVZ gold implied vol
  "EVZCLS",              # EVZ EUR/USD implied vol
  # Forward-looking inflation/rates
  "T5YIE",               # 5-Year Breakeven Inflation
  "T5YIFR",              # 5Y-5Y Forward Inflation Expectation
  "T10Y3M",              # 10Y-3M Spread (recession signal)
  # Additional credit
  "BAMLH0A2HYB"          # ICE BofA BB High Yield Spread
)

fetch_fred_csv <- function(series_id) {
  url <- paste0("https://fred.stlouisfed.org/graph/fredgraph.csv?id=", series_id)
  tryCatch({
    df <- read.csv(url, stringsAsFactors = FALSE)
    names(df) <- c("date", "value")
    df <- df |>
      mutate(
        date = as.Date(date),
        value = suppressWarnings(as.numeric(value))  # "." becomes NA
      ) |>
      filter(!is.na(date))
    df$series_id <- series_id
    df$source <- "fred"
    cli::cli_inform(c("v" = "{series_id}: {nrow(df)} obs, {sum(!is.na(df$value))} non-NA"))
    df
  }, error = function(e) {
    cli::cli_warn("Failed to fetch {series_id}: {conditionMessage(e)}")
    NULL
  })
}

cli::cli_h1("Fetching {length(series_list)} FRED series")

# Try batch download first (single HTTP request for all series)
cli::cli_inform("Attempting batch download (1 request for all {length(series_list)} series)...")
batch_url <- paste0("https://fred.stlouisfed.org/graph/fredgraph.csv?id=",
                     paste(series_list, collapse = ","))
batch_result <- tryCatch({
  df <- read.csv(batch_url, stringsAsFactors = FALSE, check.names = FALSE)
  names(df)[1] <- "date"
  df$date <- as.Date(df$date)
  # Pivot wide to long
  long <- df |>
    tidyr::pivot_longer(-date, names_to = "series_id", values_to = "value") |>
    mutate(
      value = suppressWarnings(as.numeric(as.character(value))),
      source = "fred"
    ) |>
    filter(!is.na(date)) |>
    as_tibble()
  cli::cli_inform(c("v" = "Batch OK: {nrow(long)} obs, {n_distinct(long$series_id)} series"))
  long
}, error = function(e) {
  cli::cli_warn("Batch failed ({conditionMessage(e)}), falling back to per-series...")
  NULL
})

# Fallback: per-series download if batch failed
if (is.null(batch_result)) {
  all_data <- lapply(series_list, function(sid) {
    Sys.sleep(0.5)
    fetch_fred_csv(sid)
  })
  combined <- dplyr::bind_rows(Filter(Negate(is.null), all_data)) |>
    as_tibble()
} else {
  combined <- batch_result
}

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
out_path <- "data/raw/fred_macro.parquet"
arrow::write_parquet(combined, out_path, compression = "zstd")

cli::cli_h2("Summary")
cli::cli_inform(c(
  "v" = "Total: {nrow(combined)} observations across {n_distinct(combined$series_id)} series",
  "i" = "Date range: {min(combined$date)} to {max(combined$date)}",
  "i" = "File: {out_path} ({round(file.info(out_path)$size / 1e3)} KB)"
))
