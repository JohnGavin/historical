# Silence R CMD check NOTEs for dplyr NSE
utils::globalVariables(c("first_filed", "ticker", "xbrl_tag", "cik"))

#' Coerce an `as_of` argument to a single Date, aborting loudly on failure
#'
#' Never returns `NA` silently -- an unparseable `as_of` is a caller error
#' and must stop the pipeline, not fall through as an unfiltered query
#' (`fail-loud-not-null` rule).
#'
#' @param x Value passed as `as_of`.
#' @return A length-1 `Date`.
#' @noRd
.hd_fundamentals_coerce_as_of <- function(x) {
  d <- tryCatch(as.Date(x), error = function(e) NA)
  if (length(d) != 1L || is.na(d)) {
    cli::cli_abort(
      c(
        "x" = "{.arg as_of} could not be coerced to a single Date: {.val {x}}.",
        "i" = "Pass a {.cls Date} or an unambiguous character string, e.g. {.val 2020-01-31}."
      ),
      class = "hd_fundamentals_bad_as_of"
    )
  }
  d
}

#' Validate a `cik` filter argument (#865)
#'
#' A CIK is the SEC's issuer key: a 10-digit zero-padded CHARACTER string.
#' Numeric input would lose the leading zeros and silently match nothing, so
#' it is rejected rather than coerced.
#'
#' @param x Value passed as `cik`.
#' @return `x`, invisibly, when valid.
#' @noRd
.hd_fundamentals_check_cik <- function(x) {
  bad <- !is.character(x) || length(x) == 0L || anyNA(x) ||
    !all(grepl("^[0-9]{10}$", x))
  if (bad) {
    cli::cli_abort(
      c(
        "x" = "{.arg cik} must be a character vector of 10-digit zero-padded CIKs.",
        "i" = "Got {.val {x}}. Pass a string left-padded with zeros to 10 digits, e.g. {.val 0000320193}."
      ),
      class = "hd_fundamentals_bad_cik"
    )
  }
  invisible(x)
}

#' Query point-in-time equity fundamentals (revision triangle)
#'
#' Returns fundamental/accounting data (XBRL line items from SEC EDGAR
#' filings) as it was known at a given `as_of` date, protecting backtests
#' from the filing-lag and restatement leaks documented in GitHub issue
#' \href{https://github.com/JohnGavin/historical/issues/553}{#553}.
#'
#' @details
#' The underlying `fundamentals` dataset stores ONE ROW per
#' `(ticker, xbrl_tag, fiscal_period)`, carrying both the value AS FIRST
#' REPORTED (`original_value`) and the value AFTER any later restatement
#' (`latest_value`), keyed by `first_filed` -- the date the filing became
#' public. This mirrors the pattern used for macro data
#' ([hd_macro_vintages()]) but condenses the full filing history to
#' first/latest rather than storing every intermediate revision as its own
#' row (a deliberate scope simplification -- see the #553 schema decision).
#'
#' By default this function returns only `original_value` and enforces
#' `first_filed <= as_of` when `as_of` is supplied -- exactly what a
#' backtest must use to avoid peeking at numbers the market could not yet
#' see. Returning `latest_value` is an explicit opt-in
#' (`include_latest = TRUE`) for CURRENT screening use only: it is NOT
#' point-in-time safe (the restated filing can post-date `as_of`) and must
#' never be used inside a backtest.
#'
#' **Coverage (as of the #553/#554/#555 pilot):** a fixed set of large-cap
#' US tickers and 4 XBRL tags, fetched by
#' `scripts/fetch_fundamentals_edgar.R`. This is NOT a broad-universe
#' dataset -- see [hd_datasets()]`$fundamentals$description` for the exact
#' pilot scope. A ticker not in the pilot list returns zero rows, not an
#' error.
#'
#' @param ticker Character vector. `NULL` (default) returns all tickers.
#' @param xbrl_tag Character vector of XBRL tags (e.g. `"Revenues"`,
#'   `"EarningsPerShareDiluted"`). `NULL` (default) returns all tags.
#' @param as_of Date (or coercible). When supplied, only rows with
#'   `first_filed <= as_of` (or `first_filed < as_of` when
#'   `strict_same_day = TRUE`) are returned -- the point-in-time cutoff.
#'   `NULL` (default) applies no cutoff and returns the full history --
#'   this is NOT point-in-time safe; see the `look-ahead-bias-prevention`
#'   rule.
#' @param strict_same_day If `TRUE`, use `first_filed < as_of` (a filing on
#'   the same day as `as_of` is NOT considered visible yet). Default
#'   `FALSE` treats a filing as visible on its own filing date (inclusive).
#' @param include_latest If `TRUE`, also return `latest_value` and
#'   `restated` (post-restatement values, screening-only -- see Details).
#'   Default `FALSE` returns only the as-first-reported `original_value`.
#' @param local If `TRUE`, resolve to the local cache path instead of the
#'   registry's remote URL. See [hd_dataset_source()].
#' @param collect If `TRUE` (default), materialise. If `FALSE`, return a
#'   lazy duckplyr frame.
#' @param cik Character vector of 10-digit zero-padded SEC CIKs (the issuer
#'   key). `NULL` (default) applies no CIK filter. Tickers are recycled
#'   (#865: `APC` was Anadarko, CIK `0000773910`, and is now ARKO Corp, CIK
#'   `0001835022`), so a ticker-only query can match more than one issuer;
#'   supply `cik` to pin the issuer. When `ticker` is given without `cik`
#'   and `collect = TRUE`, a warning of class
#'   `hd_fundamentals_ticker_multi_cik` is raised if one ticker maps to more
#'   than one CIK in the result.
#' @return Tibble (or lazy frame) with columns `ticker`, `cik`, `fiscal_period`,
#'   `period_end`, `first_filed`, `xbrl_tag`, `original_value`, `source`,
#'   plus `latest_value` and `restated` when `include_latest = TRUE`.
#' @family data-access
#' @export
#' @examplesIf interactive()
#' hd_fundamentals("AAPL", as_of = "2020-01-31")
#' hd_fundamentals("AAPL", xbrl_tag = "EarningsPerShareDiluted", as_of = Sys.Date())
#' hd_fundamentals("AAPL", include_latest = TRUE)  # screening only, NOT PIT-safe
hd_fundamentals <- function(ticker = NULL, xbrl_tag = NULL, as_of = NULL,
                             strict_same_day = FALSE, include_latest = FALSE,
                             local = FALSE, collect = TRUE, cik = NULL) {
  if (!is.null(cik)) .hd_fundamentals_check_cik(cik)
  ds <- hd_datasets()[["fundamentals"]]
  if (is.null(ds)) {
    cli::cli_abort("Unknown dataset: {.val fundamentals}. See {.fn hd_datasets}.")
  }

  lf <- duckplyr::read_parquet_duckdb(hd_dataset_source("fundamentals", local))

  # A parquet without `cik` predates #865; fail loudly rather than return an
  # output that cannot distinguish issuers sharing a recycled ticker.
  if (!"cik" %in% names(lf |> head(0) |> dplyr::collect())) {
    cli::cli_abort(
      c(
        "x" = "The {.val fundamentals} parquet has no {.field cik} column.",
        "i" = "Ticker alone cannot identify an issuer (recycled tickers, #865). Re-run {.file scripts/fetch_fundamentals_edgar.R} to publish a CIK-keyed triangle."
      ),
      class = "hd_fundamentals_no_cik_column"
    )
  }

  if (!is.null(ticker)) {
    lf <- lf |> dplyr::filter(ticker %in% !!ticker)
  }
  if (!is.null(cik)) {
    lf <- lf |> dplyr::filter(cik %in% !!cik)
  }
  if (!is.null(xbrl_tag)) {
    lf <- lf |> dplyr::filter(xbrl_tag %in% !!xbrl_tag)
  }

  if (!is.null(as_of)) {
    as_of_date <- .hd_fundamentals_coerce_as_of(as_of)

    # Defensive type coercion (#453-class): first_filed may be Date or
    # POSIXct depending on how the parquet was written; comparing against
    # the wrong type silently returns zero matches rather than erroring.
    schema0 <- lf |> head(0) |> dplyr::collect()
    filed_coerce <- if (inherits(schema0[["first_filed"]], "POSIXct")) {
      function(x) as.POSIXct(x, tz = "UTC")
    } else {
      as.Date
    }
    as_of_coerced <- filed_coerce(as_of_date)

    lf <- if (isTRUE(strict_same_day)) {
      lf |> dplyr::filter(first_filed < !!as_of_coerced)
    } else {
      lf |> dplyr::filter(first_filed <= !!as_of_coerced)
    }
  }

  out_cols <- c("ticker", "cik", "fiscal_period", "period_end", "first_filed",
                "xbrl_tag", "original_value", "source")
  if (isTRUE(include_latest)) {
    out_cols <- c(out_cols, "latest_value", "restated")
  }

  lf <- lf |>
    dplyr::select(dplyr::all_of(out_cols)) |>
    dplyr::arrange(ticker, xbrl_tag, period_end)

  if (!collect) return(lf)

  out <- dplyr::collect(lf)
  if (!is.null(ticker) && is.null(cik) && nrow(out) > 0L) {
    n_cik <- tapply(out$cik, out$ticker, function(x) length(unique(x)))
    multi <- names(n_cik)[n_cik > 1L]
    if (length(multi) > 0L) {
      detail <- vapply(multi, function(tk) {
        paste0(tk, ": ", paste(sort(unique(out$cik[out$ticker == tk])), collapse = ", "))
      }, character(1))
      cli::cli_warn(
        c(
          "!" = "Recycled-ticker risk (#865): {length(multi)} ticker{?s} with more than one CIK.",
          stats::setNames(detail, rep("*", length(detail))),
          "i" = "Pass {.arg cik} to pin the issuer."
        ),
        class = "hd_fundamentals_ticker_multi_cik"
      )
    }
  }
  out
}
