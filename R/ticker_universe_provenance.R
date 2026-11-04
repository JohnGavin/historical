# Provenance for a universe selected from a CURRENT metadata snapshot (#865).
#
# A ticker is a reusable string (#865: APC was Anadarko, now ARKO Corp).
# `stk_top_tickers` picks today's top-N by market cap from the metadata
# snapshot and `stk_universe` then applies that ticker list to the FULL
# price history. A point-in-time universe is #816 and is not built here.
# What this records is WHICH snapshot the selection came from, so the
# limitation is visible next to the output instead of implicit.

#' Provenance row for a snapshot-selected ticker universe
#'
#' `metadata_as_of_proxy` is `max(end_date)` over the selected metadata rows:
#' the last price bar the snapshot's computed fields cover. The metadata
#' parquet has no snapshot-date column, so this is a proxy, not the fetch
#' time. TODO(#816): replace with a real snapshot date once a point-in-time
#' universe exists; whether a ticker's price history predates the issuer now
#' holding the symbol cannot be decided from metadata alone (its
#' `start_date` is the first price bar of the same series), and EDGAR filing
#' ranges are only held for the 10 fundamentals pilot tickers.
#'
#' @param meta Data frame with columns `ticker`, `market_cap`, `end_date`
#'   (the metadata rows the selection was made from).
#' @param selected Character vector of selected tickers.
#' @param top_n Integer, the N used for the selection.
#' @return A one-row tibble: `n_selected`, `top_n`, `key`, `basis`,
#'   `metadata_as_of_proxy`, `min_selected_market_cap`, `caveat`.
ticker_universe_provenance <- function(meta, selected, top_n = NA_integer_) {
  need <- c("ticker", "market_cap", "end_date")
  if (!is.data.frame(meta) || !all(need %in% names(meta))) {
    cli::cli_abort(
      c(
        "x" = "{.arg meta} must be a data frame with columns {.field {need}}.",
        "i" = "Got columns: {.field {if (is.data.frame(meta)) names(meta) else class(meta)}}."
      ),
      class = "ticker_universe_provenance_bad_input"
    )
  }
  if (!is.character(selected) || length(selected) == 0L || anyNA(selected)) {
    cli::cli_abort(
      c("x" = "{.arg selected} must be a non-empty character vector without NA."),
      class = "ticker_universe_provenance_bad_input"
    )
  }

  missing_tk <- setdiff(selected, meta$ticker)
  if (length(missing_tk) > 0L) {
    cli::cli_abort(
      c(
        "x" = "{length(missing_tk)} selected ticker{?s} not found in the metadata snapshot: {.val {missing_tk}}.",
        "i" = "The selection and the snapshot must come from the same read."
      ),
      class = "ticker_universe_provenance_missing_ticker"
    )
  }

  rows <- meta[meta$ticker %in% selected, , drop = FALSE]
  dup <- unique(rows$ticker[duplicated(rows$ticker)])
  if (length(dup) > 0L) {
    cli::cli_warn(
      c(
        "!" = "{length(dup)} ticker{?s} occur more than once in the metadata snapshot: {.val {dup}}.",
        "i" = "One ticker string with several rows is the recycled-ticker symptom (#865)."
      ),
      class = "ticker_universe_provenance_duplicate_ticker"
    )
  }

  end_dates <- as.Date(rows$end_date)
  if (all(is.na(end_dates))) {
    cli::cli_abort(
      c(
        "x" = "No usable {.field end_date} among the {nrow(rows)} selected metadata row{?s}.",
        "i" = "Refusing to report an unknown snapshot as-of date."
      ),
      class = "ticker_universe_provenance_no_asof"
    )
  }

  dplyr::tibble(
    n_selected              = length(unique(selected)),
    top_n                   = as.integer(top_n),
    key                     = "ticker",
    basis                   = "current market-cap snapshot (not point-in-time)",
    metadata_as_of_proxy    = max(end_dates, na.rm = TRUE),
    min_selected_market_cap = if (all(is.na(rows$market_cap))) NA_real_ else min(rows$market_cap, na.rm = TRUE),
    caveat                  = paste0(
      "Selected on today's metadata and applied to full history keyed on ",
      "ticker alone (no cik); a recycled ticker would attach the current ",
      "holder's rank to an earlier issuer's prices (#865). Point-in-time ",
      "universe: #816."
    )
  )
}
