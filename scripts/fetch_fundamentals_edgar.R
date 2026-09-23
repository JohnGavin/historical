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
# TICKER RECYCLING (#865): SEC's company_tickers.json is a *current*
# snapshot -- a delisted/acquired issuer is absent from it, so a recycled
# ticker resolves to whoever holds the symbol TODAY (worked example: APC
# used to mean Anadarko Petroleum, acquired 2019; the live SEC map
# resolves it to an unrelated later company). Ticker-string coincidence
# alone is not proof of company identity. Two independent guards close
# this for the CIK-resolution step:
#   1. resolve_ticker_cik() refuses (cli_abort) if the map ever returns
#      more than one CIK candidate for a requested ticker -- previously
#      silently resolved via distinct(ticker, .keep_all = TRUE), keeping
#      an arbitrary first row.
#   2. validate_cik_filing_overlap() refuses (cli_abort) unless the
#      candidate CIK's own 10-K/10-Q filing dates overlap the date range
#      we intend to hold data for that ticker (PILOT_DATA_START/_END
#      below) -- reusing the SAME SEC companyfacts payload
#      fetch_companyfacts() already fetches, not a new endpoint.
# PILOT_DATA_START/_END are deliberately wide-open ("all time up to
# today") because PILOT_TICKERS is ten CURRENT mega-caps with no
# historical/delisted coverage -- the check will not reject any of them
# today (#865's own "Severity today: latent, not live"). It becomes
# load-bearing the moment this script (or a descendant of it) is pointed
# at a historical or delisted universe. Carrying CIK as a first-class
# column throughout the repo, and a repo-wide audit of every other
# ticker-keyed join, are explicitly OUT OF SCOPE here -- see #865 items 3
# and 4, which remain open follow-up work.
#
# User-Agent: SEC's fair-access policy requires a descriptive, non-generic
# User-Agent (https://www.sec.gov/os/webmaster-faq#developers) --
# malformed/generic UAs are rejected with HTTP 403 (confirmed empirically
# while building this script). Uses a project identifier plus an RFC 2606
# reserved example.com contact address -- satisfies SEC's format
# requirement without sending any real personal contact to a third-party
# service (credential-management rule: no PII to unrelated services).
#
# Testability: resolution logic (resolve_ticker_cik(),
# filing_date_range_from_facts(), validate_cik_filing_overlap()) is
# defined as ordinary functions with no side effects, and the network-
# fetching driver is wrapped in .ffe_main(), which only runs when this
# file is the Rscript entry point (sys.nframe() == 0) -- same pattern as
# scripts/check_pkg_staleness.R / scripts/check_pipeline_errors.R.
# tests/testthat/test-fetch-fundamentals-edgar.R source()s this file
# (sys.nframe() > 0) to load the functions without triggering a live run.
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
# trap named in #553). Also the form set the #865 filing-overlap check
# requires -- see validate_cik_filing_overlap().
KEEP_FORMS <- c("10-K", "10-Q")

# Date range this pilot script holds/requests fundamentals data for, per
# ticker (#865 item 1). See the "TICKER RECYCLING" header note above for
# why this is deliberately wide-open for the current pilot universe.
PILOT_DATA_START <- as.Date("1900-01-01")
PILOT_DATA_END   <- Sys.Date()

#' Fetch SEC's canonical ticker -> CIK mapping (never hand-typed)
fetch_cik_map <- function() {
  cli::cli_inform(c("i" = "Fetching SEC ticker->CIK map..."))
  resp <- request(SEC_TICKERS_URL) |>
    req_user_agent(SEC_USER_AGENT) |>
    req_timeout(30) |>
    req_perform() |>
    resp_body_json()

  purrr::map_dfr(resp, function(x) {
    tibble(ticker = x$ticker, cik = sprintf("%010d", x$cik_str), title = x$title)
  })
}

# SEC endpoint URLs (named constants so no function body contains a raw
# literal URL -- referenced from fetch_cik_map()/fetch_companyfacts()).
SEC_TICKERS_URL <- "https://www.sec.gov/files/company_tickers.json"
SEC_COMPANYFACTS_URL_FMT <- "https://data.sec.gov/api/xbrl/companyfacts/CIK%s.json"

#' Resolve a ticker -> CIK mapping, refusing a ticker with >1 candidate
#'
#' #865 item 2: SEC's map is a current snapshot keyed by ticker string; if
#' it ever returns more than one CIK for a requested ticker, that is a
#' finding worth surfacing, not something to silently de-duplicate. The
#' previous code (`distinct(ticker, .keep_all = TRUE)`) kept an arbitrary
#' first row and never reported the collision.
#'
#' @param cik_map Tibble with columns ticker, cik, title (see
#'   fetch_cik_map()).
#' @param tickers Character vector of tickers to resolve.
#' @return Tibble with one row per successfully-resolved ticker (tickers
#'   absent from `cik_map` are simply not present in the result -- callers
#'   check for those via `setdiff()`, unchanged from before).
resolve_ticker_cik <- function(cik_map, tickers) {
  candidates <- cik_map |> filter(ticker %in% tickers)

  dupe_counts <- candidates |> count(ticker) |> filter(n > 1L)
  if (nrow(dupe_counts) > 0L) {
    dupe_detail <- purrr::map_chr(dupe_counts$ticker, function(tk) {
      rows <- candidates |> filter(ticker == tk)
      paste0("{.val ", tk, "}: ", paste(sprintf("CIK %s (%s)", rows$cik, rows$title), collapse = " vs "))
    })
    cli::cli_abort(c(
      "x" = "SEC's ticker->CIK map returned {nrow(dupe_counts)} ticker{?s} with multiple CIK candidates.",
      "i" = "Refusing to silently keep the first candidate (#865) -- resolve manually:",
      stats::setNames(dupe_detail, rep("i", length(dupe_detail)))
    ))
  }

  candidates
}

#' Extract the 10-K/10-Q filing-date range from an SEC companyfacts payload
#'
#' #865 item 1: reuses the SAME companyfacts payload fetch_companyfacts()
#' already fetches (no new SEC endpoint) -- scans every us-gaap tag
#' present (not just PILOT_TAGS, since a candidate CIK may not report
#' PILOT_TAGS at all) and returns the min/max `filed` date among entries
#' whose `form` is in KEEP_FORMS.
#'
#' @param facts Parsed JSON payload from fetch_companyfacts() (or an
#'   equivalently-shaped list -- see the test file's synthetic fixtures).
#' @return list(min_filed = Date, max_filed = Date). Both NA if no
#'   KEEP_FORMS filing was found anywhere in the payload.
filing_date_range_from_facts <- function(facts) {
  na_range <- list(min_filed = as.Date(NA), max_filed = as.Date(NA))
  if (is.null(facts) || is.null(facts$facts) || is.null(facts$facts[["us-gaap"]])) {
    return(na_range)
  }
  tags <- facts$facts[["us-gaap"]]
  filed_strs <- unlist(lapply(tags, function(node) {
    units <- node$units
    if (is.null(units) || length(units) == 0L) return(character(0))
    entries <- units[[names(units)[1]]]
    if (length(entries) == 0L) return(character(0))
    vapply(entries, function(e) {
      form <- e$form %||% NA_character_
      if (!is.na(form) && form %in% KEEP_FORMS) (e$filed %||% NA_character_) else NA_character_
    }, character(1))
  }), use.names = FALSE)

  filed_dates <- suppressWarnings(as.Date(filed_strs))
  filed_dates <- filed_dates[!is.na(filed_dates)]
  if (length(filed_dates) == 0L) return(na_range)

  list(min_filed = min(filed_dates), max_filed = max(filed_dates))
}

#' Validate a candidate ticker->CIK mapping against filing-date overlap
#'
#' #865 item 1: guards against ticker recycling -- a delisted/acquired
#' issuer's ticker can be reassigned to an unrelated company, and SEC's
#' *current* ticker->CIK map (fetch_cik_map()) would silently resolve the
#' recycled ticker to today's holder. This requires the candidate CIK's
#' own 10-K/10-Q filing dates to overlap the date range we intend to hold
#' data for that ticker; if they don't overlap, the candidate is provably
#' the wrong company for that window and this aborts rather than silently
#' accepting it (fail-loud-not-null) -- it does NOT pick a "best" CIK.
#'
#' @param ticker Ticker symbol being resolved.
#' @param cik Candidate CIK (character, zero-padded).
#' @param company_title Candidate company name (for the abort message).
#' @param filing_range list(min_filed, max_filed) as returned by
#'   filing_date_range_from_facts().
#' @param data_start,data_end Date range of data we intend to hold for
#'   this ticker (see PILOT_DATA_START/_END).
#' @return TRUE (invisibly) if the candidate is accepted; aborts otherwise.
validate_cik_filing_overlap <- function(ticker, cik, company_title, filing_range,
                                         data_start = PILOT_DATA_START,
                                         data_end = PILOT_DATA_END) {
  forms_str <- paste(KEEP_FORMS, collapse = "/")

  if (is.na(filing_range$min_filed) || is.na(filing_range$max_filed)) {
    cli::cli_abort(c(
      "x" = "No {forms_str} filings found for candidate CIK {cik} ({company_title}), resolved from ticker {.val {ticker}}.",
      "i" = "Cannot verify this CIK is the company our data is actually about -- refusing a ticker-string-only match (#865)."
    ))
  }

  overlaps <- filing_range$min_filed <= data_end && filing_range$max_filed >= data_start
  if (!overlaps) {
    cli::cli_abort(c(
      "x" = "Ticker {.val {ticker}} resolves to CIK {cik} ({company_title}), whose {forms_str} filings ({filing_range$min_filed} to {filing_range$max_filed}) do not overlap the {data_start} to {data_end} window we hold data for.",
      "i" = "This is the ticker-recycling failure mode (#865): {.val {ticker}} may refer to a different, earlier company than SEC's current ticker map resolves to.",
      "i" = "Verify the correct CIK manually rather than trusting a ticker-string match from the current SEC map."
    ))
  }

  invisible(TRUE)
}

#' Fetch one company's full XBRL companyfacts payload
fetch_companyfacts <- function(cik, ticker) {
  url <- sprintf(SEC_COMPANYFACTS_URL_FMT, cik)
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

.ffe_main <- function() {
  cik_map <- fetch_cik_map()
  resolved <- resolve_ticker_cik(cik_map, PILOT_TICKERS)

  missing_tickers <- setdiff(PILOT_TICKERS, resolved$ticker)
  if (length(missing_tickers) > 0L) {
    cli::cli_abort(c(
      "x" = "Could not resolve CIK for: {missing_tickers}.",
      "i" = "Check {SEC_TICKERS_URL} for the current ticker spelling."
    ))
  }

  cli::cli_h1("Fetching fundamentals for {nrow(resolved)} pilot tickers, {length(PILOT_TAGS)} tags")

  all_raw <- purrr::map_dfr(seq_len(nrow(resolved)), function(i) {
    tk    <- resolved$ticker[i]
    cik   <- resolved$cik[i]
    title <- resolved$title[i]
    cli::cli_inform(c("i" = "  {tk} (CIK {cik})..."))
    Sys.sleep(0.15)  # SEC fair-access: stay well under the 10 req/sec ceiling
    facts <- fetch_companyfacts(cik, tk)
    if (is.null(facts)) return(NULL)

    # #865 item 1 -- validate BEFORE extracting any values, reusing the
    # companyfacts payload just fetched (no second SEC call).
    filing_range <- filing_date_range_from_facts(facts)
    validate_cik_filing_overlap(tk, cik, title, filing_range)

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

  invisible(0L)
}

# Only run when this file is the Rscript entry point (sys.nframe() == 0),
# never when source()'d for its functions -- same pattern as
# scripts/check_pkg_staleness.R and scripts/check_pipeline_errors.R.
# tests/testthat/test-fetch-fundamentals-edgar.R source()s this file and
# must NOT trigger a live run against SEC EDGAR.
if (sys.nframe() == 0) {
  .ffe_main()
}
