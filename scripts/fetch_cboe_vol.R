#!/usr/bin/env Rscript
# fetch_cboe_vol.R
# Fetches 45 CBOE implied series from the CBOE CDN plus ICE BofA MOVE via
# Yahoo Finance. Writes to data/raw/cboe_vol.parquet (46 series total).
#
# Categories:
#   VIX term structure : VIX1D, VIX9D, VIX3M, VIX6M, VIX1Y, VVIX
#   Equity index vol   : VXN (Nasdaq), VXD (DJIA), RVX (Russell 2000)
#   International vol  : VXEEM, VXEWZ, VXFXI, VXEFA
#   Single-stock vol   : VXAPL, VXAZN, VXGOG, VXGS, VXIBM
#   Commodity/FX vol   : OVX, GVZ, VXSLV, VXGDX
#   Bond vol           : VXTLT
#   Skew               : SKEW
#   Implied correlation: COR1M, COR3M, COR6M, COR1Y
#   Implied dispersion : DSPX
#   Options strategies : BXM, BXY, BXMD, BXMC, BXMW, PUT, WPUT, PPUT, CLL,
#                        CLLZ, BFLY, CNDR
#   Variance premium   : VPD, VPN
#   Vol strategy       : LOVOL, SHORTVOL
#   Bond vol (Yahoo)   : MOVE (ICE BofA ^MOVE)
#
# Note: VIX is intentionally excluded — we use VIXCLS from FRED (longer
# history from 1990). OVXCLS/GVZCLS from FRED are retained separately;
# OVX/GVZ here are the direct CBOE CDN versions.

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
  # ---- VIX term structure ----
  list(symbol = "VIX9D",     series_id = "VIX9D"),
  list(symbol = "VIX3M",     series_id = "VIX3M"),
  list(symbol = "VIX6M",     series_id = "VIX6M"),
  list(symbol = "VIX1Y",     series_id = "VIX1Y"),
  list(symbol = "VIX1D",     series_id = "VIX1D"),
  list(symbol = "VVIX",      series_id = "VVIX"),
  # ---- Equity index vol ----
  list(symbol = "VXN",       series_id = "VXN"),
  list(symbol = "VXD",       series_id = "VXD"),
  list(symbol = "RVX",       series_id = "RVX"),
  # ---- International / ETF vol ----
  list(symbol = "VXEEM",     series_id = "VXEEM"),
  list(symbol = "VXEWZ",     series_id = "VXEWZ"),
  list(symbol = "VXFXI",     series_id = "VXFXI"),
  list(symbol = "VXEFA",     series_id = "VXEFA"),
  # ---- Single-stock vol ----
  list(symbol = "VXAPL",     series_id = "VXAPL"),
  list(symbol = "VXAZN",     series_id = "VXAZN"),
  list(symbol = "VXGOG",     series_id = "VXGOG"),
  list(symbol = "VXGS",      series_id = "VXGS"),
  list(symbol = "VXIBM",     series_id = "VXIBM"),
  # ---- Commodity / FX vol ----
  list(symbol = "OVX",       series_id = "OVX"),
  list(symbol = "GVZ",       series_id = "GVZ"),
  list(symbol = "VXSLV",     series_id = "VXSLV"),
  list(symbol = "VXGDX",     series_id = "VXGDX"),
  # ---- Bond vol ----
  list(symbol = "VXTLT",     series_id = "VXTLT"),
  # ---- Skew ----
  list(symbol = "SKEW",      series_id = "SKEW"),
  # ---- Implied correlation ----
  list(symbol = "COR1M",     series_id = "COR1M"),
  list(symbol = "COR3M",     series_id = "COR3M"),
  list(symbol = "COR6M",     series_id = "COR6M"),
  list(symbol = "COR1Y",     series_id = "COR1Y"),
  # ---- Implied dispersion ----
  list(symbol = "DSPX",      series_id = "DSPX"),
  # ---- Options strategy benchmarks ----
  list(symbol = "BXM",       series_id = "BXM"),
  list(symbol = "BXY",       series_id = "BXY"),
  list(symbol = "BXMD",      series_id = "BXMD"),
  list(symbol = "BXMC",      series_id = "BXMC"),
  list(symbol = "BXMW",      series_id = "BXMW"),
  list(symbol = "PUT",       series_id = "PUT"),
  list(symbol = "WPUT",      series_id = "WPUT"),
  list(symbol = "PPUT",      series_id = "PPUT"),
  list(symbol = "CLL",       series_id = "CLL"),
  list(symbol = "CLLZ",      series_id = "CLLZ"),
  list(symbol = "BFLY",      series_id = "BFLY"),
  list(symbol = "CNDR",      series_id = "CNDR"),
  # ---- Variance risk premium ----
  list(symbol = "VPD",       series_id = "VPD"),
  list(symbol = "VPN",       series_id = "VPN"),
  # ---- Vol strategy ----
  list(symbol = "LOVOL",     series_id = "LOVOL"),
  list(symbol = "SHORTVOL",  series_id = "SHORTVOL")
)

results <- lapply(cboe_series, function(s) {
  out <- fetch_cboe(s$symbol, s$series_id)
  Sys.sleep(1)  # respect CBOE CDN rate limit (~15 req/min)
  out
})
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
