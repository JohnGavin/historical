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
    hicp_inflation = list(
      key = "ICP/M.U2.N.000000.4.ANR",
      description = "HICP annual rate of change (euro area headline inflation)",
      frequency = "monthly",
      unit = "percent_yoy"
    )
  )
}
