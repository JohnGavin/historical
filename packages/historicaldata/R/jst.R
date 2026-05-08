#' Fetch Jordà-Schularick-Taylor Macrohistory Database
#'
#' Downloads and parses the JST database (Release 6): 18 countries,
#' 1870-2020, annual data on equity, bond, housing, bills, inflation,
#' GDP, credit, and financial crises.
#'
#' @param cache If TRUE (default), cache downloaded file locally.
#' @return Tibble with 59 columns. Key columns:
#'   - `iso`: 3-letter country code (AUS, BEL, ..., USA)
#'   - `year`: 1870-2020
#'   - `eq_tr`: Equity total return index
#'   - `bond_tr`: Government bond total return
#'   - `housing_tr`: Housing total return (unique to JST)
#'   - `bill_rate`: Short-term bill rate
#'   - `cpi`: Consumer price index
#'   - `stir`: Short-term interest rate
#'   - `ltrate`: Long-term interest rate
#'   - `crisisJST`: Financial crisis indicator (0/1)
#' @family data-access
#' @export
#' @examplesIf interactive()
#' jst <- hd_jst()
#' # Equity premium per country
#' jst |> dplyr::filter(!is.na(eq_tr), !is.na(bill_rate)) |>
#'   dplyr::mutate(eq_premium = eq_tr - bill_rate) |>
#'   dplyr::summarise(mean_premium = mean(eq_premium), .by = iso)
hd_jst <- function(cache = TRUE) {
  cache_path <- file.path(hd_cache_path(), "jst_macrohistory.rds")

  if (cache && file.exists(cache_path)) {
    cli::cli_alert_info("Loading cached JST data")
    return(readRDS(cache_path))
  }

  if (!requireNamespace("haven", quietly = TRUE)) {
    cli::cli_abort("Package {.pkg haven} required for reading Stata .dta files.")
  }
  if (!requireNamespace("httr2", quietly = TRUE)) {
    cli::cli_abort("Package {.pkg httr2} required for downloading JST data.")
  }

  url <- "https://www.macrohistory.net/app/download/9834512469/JSTdatasetR6.dta"
  tmp <- tempfile(fileext = ".dta")

  cli::cli_alert_info("Downloading JST Macrohistory Database (Release 6)...")
  resp <- httr2::request(url) |>
    httr2::req_timeout(60) |>
    httr2::req_error(is_error = function(r) FALSE) |>
    httr2::req_perform()

  if (httr2::resp_status(resp) != 200L) {
    cli::cli_abort("JST download failed: HTTP {httr2::resp_status(resp)}")
  }

  writeBin(httr2::resp_body_raw(resp), tmp)
  jst <- haven::read_dta(tmp)
  unlink(tmp)

  # Strip Stata label attributes for cleaner tibble
  for (col in names(jst)) {
    attr(jst[[col]], "label") <- NULL
    attr(jst[[col]], "format.stata") <- NULL
  }

  jst <- tibble::as_tibble(jst)
  cli::cli_alert_success(
    "JST: {length(unique(jst$iso))} countries, {min(jst$year)}-{max(jst$year)}, {nrow(jst)} obs"
  )

  if (cache) {
    dir.create(dirname(cache_path), showWarnings = FALSE, recursive = TRUE)
    saveRDS(jst, cache_path)
    cli::cli_alert_info("Cached to {cache_path}")
  }

  jst
}

#' JST variable descriptions
#'
#' @return Tibble mapping variable names to descriptions
#' @family discovery
#' @export
hd_jst_variables <- function() {
  tibble::tribble(
    ~variable, ~category, ~description, ~coverage,
    "eq_tr", "Returns", "Equity total return (price + dividends)", "83%",
    "bond_tr", "Returns", "Government bond total return", "84%",
    "housing_tr", "Returns", "Housing total return (price + rent)", "70%",
    "bill_rate", "Returns", "Short-term bill rate", "86%",
    "eq_capgain", "Returns", "Equity capital gain (excl dividends)", "83%",
    "eq_dp", "Returns", "Equity dividend-price ratio", "83%",
    "housing_capgain", "Returns", "Housing capital gain (excl rent)", "70%",
    "housing_rent_yd", "Returns", "Housing rental yield", "70%",
    "capital_tr", "Returns", "Weighted equity + housing return", "70%",
    "risky_tr", "Returns", "Risky asset return (eq + housing)", "70%",
    "safe_tr", "Returns", "Safe asset return (bonds + bills)", "84%",
    "cpi", "Macro", "Consumer price index", "98%",
    "gdp", "Macro", "Nominal GDP", "95%",
    "rgdpmad", "Macro", "Real GDP per capita (Maddison)", "90%",
    "pop", "Macro", "Population", "98%",
    "unemp", "Macro", "Unemployment rate", "60%",
    "stir", "Rates", "Short-term interest rate", "93%",
    "ltrate", "Rates", "Long-term interest rate", "97%",
    "xrusd", "FX", "Exchange rate vs USD", "98%",
    "debtgdp", "Fiscal", "Government debt-to-GDP ratio", "92%",
    "tloans", "Credit", "Total bank lending", "91%",
    "tmort", "Credit", "Mortgage lending", "85%",
    "crisisJST", "Crisis", "Financial crisis indicator (0/1)", "100%",
    "money", "Money", "Broad money supply", "93%",
    "narrowm", "Money", "Narrow money supply", "96%"
  )
}
