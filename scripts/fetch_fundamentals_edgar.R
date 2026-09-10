# Fetch SEC EDGAR XBRL company fundamentals for a fixed pilot ticker universe
#
# Ratified schema (#553): a revision triangle, ONE ROW per
# (ticker, xbrl_tag, fiscal_period), carrying both the value as first
# reported (original_value) and the value after any later restatement
# (latest_value), keyed by first_filed -- the date the filing became
# public. See packages/historicaldata/R/fundamentals.R (hd_fundamentals())
# and R/registry.R's `fundamentals` dataset entry.
#
# PILOT SCOPE (deliberate, per #553's own instruction to scope a pilot
# rather than a broad-universe parser in one session): 10 large-cap US
# tickers with clean XBRL filings, and 4 representative us-gaap tags
# (revenue, diluted EPS, stockholders' equity, operating cash flow). NOT a
# broad-universe fetcher. Extending ticker/tag coverage is a follow-up.
#
# Reproducible Ingestion rule compliance: CIK numbers are resolved from
# SEC's own canonical ticker->CIK mapping
# (https://www.sec.gov/files/company_tickers.json) at RUN TIME, never
# hand-typed from memory -- a wrong hand-typed CIK silently pulls the
# wrong company's data with no error. Values (Revenues, EPS, etc.) are
# read directly from SEC's XBRL companyfacts API, never transcribed.
#
# User-Agent: SEC's fair-access policy requires a descriptive, non-generic
# User-Agent (https://www.sec.gov/os/webmaster-faq#developers) --
# malformed/generic UAs are rejected with HTTP 403 (confirmed empirically
# while building this script). Uses a project identifier plus an RFC 2606
# reserved example.com contact address -- satisfies SEC's format
# requirement without sending any real personal contact to a third-party
# service (credential-management rule: no PII to unrelated services).
#
# Usage:
#   Rscript scripts/fetch_fundamentals_edgar.R
#
# Output: data/dist/fundamentals.parquet (gitignored -- upload to the HF
# dataset repo is a separate, credentialed step via scripts/upload_hf.sh,
# not run by this script).

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(httr2)
})

`%||%` <- function(x, y) if (is.null(x)) y else x

SEC_USER_AGENT <- "HistoricalDataRPackage contact@example.com"

# Pilot ticker universe (#553) -- well-known large caps with clean XBRL
# filings. Extending coverage to a broader universe is deferred; see the
# PR notes for #553/#554/#555.
PILOT_TICKERS <- c("AAPL", "MSFT", "GOOGL", "AMZN", "JNJ",
                    "WMT", "PG", "JPM", "XOM", "KO")

# One representative XBRL tag per financial statement (revenue,
# profitability, balance sheet, cash flow) -- all under us-gaap.
PILOT_TAGS <- c(
  "Revenues",
  "EarningsPerShareDiluted",
  "StockholdersEquity",
  "NetCashProvidedByUsedInOperatingActivities"
)

# Filing forms to keep. 10-K/10-Q only -- excludes 8-K and other filing
# types whose XBRL facts are typically restatements-in-passing or partial
# disclosures rather than the primary periodic report (the G6 stub-period
# trap named in #553).
KEEP_FORMS <- c("10-K", "10-Q")

#' Fetch SEC's canonical ticker -> CIK mapping (never hand-typed)
fetch_cik_map <- function() {
  cli::cli_inform(c("i" = "Fetching SEC ticker->CIK map..."))
  resp <- request("https://www.sec.gov/files/company_tickers.json") |>
    req_user_agent(SEC_USER_AGENT) |>
    req_timeout(30) |>
    req_perform() |>
    resp_body_json()

  purrr::map_dfr(resp, function(x) {
    tibble(ticker = x$ticker, cik = sprintf("%010d", x$cik_str), title = x$title)
  })
}

#' Fetch one company's full XBRL companyfacts payload
fetch_companyfacts <- function(cik, ticker) {
  url <- sprintf("https://data.sec.gov/api/xbrl/companyfacts/CIK%s.json", cik)
  tryCatch({
    request(url) |>
      req_user_agent(SEC_USER_AGENT) |>
      req_timeout(30) |>
      req_perform() |>
      resp_body_json(simplifyVector = FALSE)
  }, error = function(e) {
    cli::cli_warn("  Failed {ticker} ({cik}): {conditionMessage(e)}")
    NULL
  })
}

#' Extract one XBRL tag's raw filing-level facts into a long tibble
extract_tag_facts <- function(facts, ticker, tag) {
  node <- facts$facts[["us-gaap"]][[tag]]
  if (is.null(node)) return(NULL)
  units <- node$units
  if (is.null(units) || length(units) == 0L) return(NULL)
  unit_name <- names(units)[1]  # USD, USD/shares, etc -- first available unit
  entries <- units[[unit_name]]
  if (length(entries) == 0L) return(NULL)

  purrr::map_dfr(entries, function(e) {
    tibble(
      ticker       = ticker,
      xbrl_tag     = tag,
      unit         = unit_name,
      period_end   = suppressWarnings(as.Date(e$end %||% NA_character_)),
      fy           = e$fy %||% NA_integer_,
      fp           = e$fp %||% NA_character_,
      form         = e$form %||% NA_character_,
      filed        = suppressWarnings(as.Date(e$filed %||% NA_character_)),
      accn         = e$accn %||% NA_character_,
      val          = suppressWarnings(as.numeric(e$val %||% NA_real_))
    )
  })
}

#' Collapse raw filing-level facts into the ratified revision-triangle
#' schema: one row per (ticker, xbrl_tag, period_end).
build_triangle <- function(raw) {
  raw |>
    filter(form %in% KEEP_FORMS, !is.na(val), !is.na(filed), !is.na(period_end)) |>
    group_by(ticker, xbrl_tag, period_end) |>
    summarise(
      fiscal_period  = fp[which.min(filed)],
      first_filed    = min(filed),
      original_value = val[which.min(filed)],
      latest_value   = val[which.max(filed)],
      source         = paste0("SEC EDGAR XBRL companyfacts (", accn[which.min(filed)], ")"),
      .groups = "drop"
    ) |>
    mutate(
      restated = abs(latest_value - original_value) > 0.005 * pmax(abs(original_value), 1e-9)
    ) |>
    select(ticker, fiscal_period, period_end, first_filed, xbrl_tag,
           original_value, latest_value, restated, source) |>
    arrange(ticker, xbrl_tag, period_end)
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

cik_map <- fetch_cik_map()
resolved <- cik_map |>
  filter(ticker %in% PILOT_TICKERS) |>
  distinct(ticker, .keep_all = TRUE)

missing_tickers <- setdiff(PILOT_TICKERS, resolved$ticker)
if (length(missing_tickers) > 0L) {
  cli::cli_abort(c(
    "x" = "Could not resolve CIK for: {missing_tickers}.",
    "i" = "Check https://www.sec.gov/files/company_tickers.json for the current ticker spelling."
  ))
}

cli::cli_h1("Fetching fundamentals for {nrow(resolved)} pilot tickers, {length(PILOT_TAGS)} tags")

all_raw <- purrr::map_dfr(seq_len(nrow(resolved)), function(i) {
  tk  <- resolved$ticker[i]
  cik <- resolved$cik[i]
  cli::cli_inform(c("i" = "  {tk} (CIK {cik})..."))
  Sys.sleep(0.15)  # SEC fair-access: stay well under the 10 req/sec ceiling
  facts <- fetch_companyfacts(cik, tk)
  if (is.null(facts)) return(NULL)
  purrr::map_dfr(PILOT_TAGS, function(tag) {
    extract_tag_facts(facts, tk, tag) %||% tibble()
  })
})

if (nrow(all_raw) == 0L) {
  cli::cli_abort("No fundamentals data fetched!")
}

triangle <- build_triangle(all_raw)

dir.create("data/dist", recursive = TRUE, showWarnings = FALSE)
out_path <- "data/dist/fundamentals.parquet"
arrow::write_parquet(triangle, out_path, compression = "zstd")

cli::cli_h2("Summary")
cli::cli_inform(c(
  "v" = "Total: {nrow(triangle)} (ticker, xbrl_tag, period) rows",
  "i" = "Tickers: {dplyr::n_distinct(triangle$ticker)}",
  "i" = "Restated: {sum(triangle$restated)} ({round(100 * mean(triangle$restated), 1)}%)",
  "i" = "Period range: {min(triangle$period_end)} to {max(triangle$period_end)}",
  "i" = "File: {out_path} ({round(file.info(out_path)$size / 1e3)} KB)"
))
