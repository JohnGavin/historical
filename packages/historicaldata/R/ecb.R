#' Fetch ECB Statistical Data Warehouse series
#'
#' Queries the ECB SDMX REST API for financial time series data.
#' Returns a tidy tibble with date, value, and series metadata.
#'
#' @param series_key ECB SDMX series key (e.g., "EXR/D.USD.EUR.SP00.A")
#' @param start Start date (character "YYYY-MM-DD" or Date). Default: "2000-01-01".
#' @param end End date (character or Date). Default: today.
#' @return Tibble with columns: date, value, series_key, frequency
#' @family data-access
#' @export
#' @examplesIf interactive()
#' hd_ecb("EXR/D.USD.EUR.SP00.A", start = "2024-01-01")
#' hd_ecb("FM/M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA")
hd_ecb <- function(series_key, start = "2000-01-01", end = NULL) {
  if (!requireNamespace("httr2", quietly = TRUE)) {
    cli::cli_abort("Package {.pkg httr2} required for ECB data. Available in nix shell.")
  }

  url <- paste0("https://data-api.ecb.europa.eu/service/data/", series_key)
  req <- httr2::request(url) |>
    httr2::req_headers(Accept = "text/csv") |>
    httr2::req_url_query(startPeriod = as.character(start), detail = "dataonly")

  if (!is.null(end)) {
    req <- req |> httr2::req_url_query(endPeriod = as.character(end))
  }

  resp <- req |>
    httr2::req_error(is_error = function(r) FALSE) |>
    httr2::req_perform()

  if (httr2::resp_status(resp) != 200L) {
    cli::cli_warn(c(
      "!" = "ECB API returned status {httr2::resp_status(resp)} for {series_key}",
      "i" = "Check series key at https://data.ecb.europa.eu/"
    ))
    return(NULL)
  }

  raw <- utils::read.csv(text = httr2::resp_body_string(resp))

  if (!"OBS_VALUE" %in% names(raw) || !"TIME_PERIOD" %in% names(raw)) {
    cli::cli_warn("Unexpected schema from ECB for {series_key}")
    return(NULL)
  }

  # Parse date — monthly series use "YYYY-MM", daily use "YYYY-MM-DD"
  dates <- raw$TIME_PERIOD
  parsed_dates <- if (all(nchar(dates) == 7L)) {
    as.Date(paste0(dates, "-01"))
  } else {
    as.Date(dates)
  }

  tibble::tibble(
    date       = parsed_dates,
    value      = as.numeric(raw$OBS_VALUE),
    series_key = series_key,
    frequency  = if (all(nchar(dates) == 7L)) "monthly" else "daily"
  )
}

#' ECB series registry
#'
#' Maps human-readable names to ECB SDMX series keys with metadata.
#'
#' @return Named list of ECB series definitions
#' @family discovery
#' @export
hd_ecb_registry <- function() {
  list(
    eurusd = list(
      key = "EXR/D.USD.EUR.SP00.A",
      description = "EUR/USD exchange rate",
      frequency = "daily",
      unit = "USD per EUR"
    ),
    eurgbp = list(
      key = "EXR/D.GBP.EUR.SP00.A",
      description = "EUR/GBP exchange rate",
      frequency = "daily",
      unit = "GBP per EUR"
    ),
    eurjpy = list(
      key = "EXR/D.JPY.EUR.SP00.A",
      description = "EUR/JPY exchange rate",
      frequency = "daily",
      unit = "JPY per EUR"
    ),
    euribor_3m = list(
      key = "FM/M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA",
      description = "EURIBOR 3-month rate",
      frequency = "monthly",
      unit = "percent"
    ),
    ecb_refi_rate = list(
      key = "FM/D.U2.EUR.4F.KR.MRR_FR.LEV",
      description = "ECB main refinancing operations rate",
      frequency = "daily",
      unit = "percent"
    ),
    yield_curve_10y = list(
      key = "YC/B.U2.EUR.4F.G_N_A.SV_C_YM.SR_10Y",
      description = "Euro area AAA-rated 10Y government bond yield (ECB yield curve)",
      frequency = "business_daily",
      unit = "percent"
    ),
    eurchf = list(
      key = "EXR/D.CHF.EUR.SP00.A",
      description = "EUR/CHF exchange rate",
      frequency = "daily",
      unit = "CHF per EUR"
    ),
    euribor_6m = list(
      key = "FM/M.U2.EUR.RT.MM.EURIBOR6MD_.HSTA",
      description = "EURIBOR 6-month rate",
      frequency = "monthly",
      unit = "percent"
    ),
    yield_curve_5y = list(
      key = "YC/B.U2.EUR.4F.G_N_A.SV_C_YM.SR_5Y",
      description = "Euro area AAA-rated 5Y government bond yield",
      frequency = "business_daily",
      unit = "percent"
    ),
    yield_curve_2y = list(
      key = "YC/B.U2.EUR.4F.G_N_A.SV_C_YM.SR_2Y",
      description = "Euro area AAA-rated 2Y government bond yield",
      frequency = "business_daily",
      unit = "percent"
    ),
    yield_curve_1y = list(
      key = "YC/B.U2.EUR.4F.G_N_A.SV_C_YM.SR_1Y",
      description = "Euro area AAA-rated 1Y government bond yield",
      frequency = "business_daily",
      unit = "percent"
    ),
    yc_level = list(
      key = "YC/B.U2.EUR.4F.G_N_A.SV_C_YM.BETA0",
      description = "Svensson yield curve level (beta0)",
      frequency = "business_daily",
      unit = "percent"
    ),
    yc_slope = list(
      key = "YC/B.U2.EUR.4F.G_N_A.SV_C_YM.BETA1",
      description = "Svensson yield curve slope (beta1) — steepens in stress",
      frequency = "business_daily",
      unit = "percent"
    ),
    yc_curvature = list(
      key = "YC/B.U2.EUR.4F.G_N_A.SV_C_YM.BETA2",
      description = "Svensson yield curve curvature (beta2) — spikes in crises",
      frequency = "business_daily",
      unit = "percent"
    ),
    # ── CISS: Composite Indicator of Systemic Stress ─────────────────
    ciss_composite = list(
      key = "CISS/D.U2.Z0Z.4F.EC.SS_CIN.IDX",
      description = "CISS composite systemic stress (0=calm, 1=crisis)",
      frequency = "daily",
      unit = "index_0_1"
    ),
    ciss_bond = list(
      key = "CISS/D.U2.Z0Z.4F.EC.SS_BMN.CON",
      description = "CISS bond market stress contribution",
      frequency = "daily",
      unit = "index_0_1"
    ),
    ciss_equity = list(
      key = "CISS/D.U2.Z0Z.4F.EC.SS_EMN.CON",
      description = "CISS equity market stress contribution (implied vol proxy)",
      frequency = "daily",
      unit = "index_0_1"
    ),
    ciss_fx = list(
      key = "CISS/D.U2.Z0Z.4F.EC.SS_FXN.CON",
      description = "CISS FX market stress contribution",
      frequency = "daily",
      unit = "index_0_1"
    ),
    ciss_money = list(
      key = "CISS/D.U2.Z0Z.4F.EC.SS_MMN.CON",
      description = "CISS money market stress contribution",
      frequency = "daily",
      unit = "index_0_1"
    ),
    ciss_financial = list(
      key = "CISS/D.U2.Z0Z.4F.EC.SS_FIN.CON",
      description = "CISS financial intermediary stress contribution",
      frequency = "daily",
      unit = "index_0_1"
    ),
    ciss_correlation = list(
      key = "CISS/D.U2.Z0Z.4F.EC.SS_CON.CON",
      description = "CISS cross-market correlation (more negative = less contagion)",
      frequency = "daily",
      unit = "correlation"
    ),
    ciss_sovereign = list(
      key = "CISS/D.U2.Z0Z.4F.EC.SOV_EWN.IDX",
      description = "CISS sovereign stress (equal-weighted euro area)",
      frequency = "daily",
      unit = "index_0_1"
    ),
    # ── CISS per country ─────────────────────────────────────────────
    ciss_de = list(
      key = "CISS/D.DE.Z0Z.4F.EC.SS_CIN.IDX",
      description = "CISS Germany systemic stress",
      frequency = "daily",
      unit = "index_0_1"
    ),
    ciss_fr = list(
      key = "CISS/D.FR.Z0Z.4F.EC.SS_CIN.IDX",
      description = "CISS France systemic stress",
      frequency = "daily",
      unit = "index_0_1"
    ),
    ciss_it = list(
      key = "CISS/D.IT.Z0Z.4F.EC.SS_CIN.IDX",
      description = "CISS Italy systemic stress",
      frequency = "daily",
      unit = "index_0_1"
    ),
    ciss_gb = list(
      key = "CISS/D.GB.Z0Z.4F.EC.SS_CIN.IDX",
      description = "CISS UK systemic stress",
      frequency = "daily",
      unit = "index_0_1"
    ),
    ciss_us = list(
      key = "CISS/D.US.Z0Z.4F.EC.SS_CIN.IDX",
      description = "CISS US systemic stress (ECB-computed, comparable with euro area)",
      frequency = "daily",
      unit = "index_0_1"
    ),
    # ── Macro ────────────────────────────────────────────────────────
    m3_money_supply = list(
      key = "BSI/M.U2.Y.V.M30.X.1.U2.2300.Z01.E",
      description = "M3 money supply (euro area, EUR millions)",
      frequency = "monthly",
      unit = "eur_millions"
    ),
    hicp_inflation = list(
      key = "ICP/M.U2.N.000000.4.ANR",
      description = "HICP annual rate of change (euro area headline inflation)",
      frequency = "monthly",
      unit = "percent_yoy"
    )
  )
}
