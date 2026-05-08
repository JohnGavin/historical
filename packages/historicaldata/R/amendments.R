#' Get price data amendments (Point-in-Time tracking)
#'
#' Returns the amendment log showing corrections made to historical price data.
#' Each row records: what was changed, when, why, and the original value.
#'
#' @param ticker Filter to one ticker. NULL = all.
#' @param collect If TRUE (default), materialise. If FALSE, return lazy frame.
#' @return Tibble or lazy duckplyr frame with amendment records
#' @family quality-audit
#' @export
hd_amendments <- function(ticker = NULL, collect = TRUE) {
  ds <- hd_datasets()[["amendments"]]
  if (is.null(ds)) {
    cli::cli_inform("No price amendments recorded yet.")
    return(dplyr::tibble())
  }

  lf <- duckplyr::read_parquet_duckdb(ds$url)
  if (!is.null(ticker)) lf <- lf |> dplyr::filter(ticker == !!ticker)

  if (collect) dplyr::collect(lf) else lf
}

#' Get metadata amendments (Point-in-Time tracking)
#'
#' Returns the PIT log of all metadata changes: computed fields, enrichments,
#' corrections. Every change to metadata.parquet is tracked with old/new values,
#' source, method, and timestamp.
#'
#' @param ticker Filter to one ticker. NULL = all.
#' @param field Filter to one field (e.g. "beta_3yr"). NULL = all.
#' @param collect If TRUE (default), materialise. If FALSE, return lazy frame.
#' @return Tibble or lazy duckplyr frame
#' @family quality-audit
#' @export
#' @examplesIf interactive()
#' hd_metadata_amendments("AAPL")
#' hd_metadata_amendments(field = "beta_3yr")
hd_metadata_amendments <- function(ticker = NULL, field = NULL, collect = TRUE) {
  ds <- hd_datasets()[["metadata_amendments"]]
  if (is.null(ds)) {
    cli::cli_inform("No metadata amendments recorded yet.")
    return(dplyr::tibble(
      ticker = character(), field = character(),
      old_value = character(), new_value = character(),
      source = character(), method = character(),
      amended_at = character(), amended_by = character(),
      reversible = logical()
    ))
  }

  lf <- duckplyr::read_parquet_duckdb(ds$url)
  if (!is.null(ticker)) lf <- lf |> dplyr::filter(ticker == !!ticker)
  if (!is.null(field))  lf <- lf |> dplyr::filter(field == !!field)
  lf <- lf |> dplyr::arrange(dplyr::desc(amended_at), ticker, field)

  if (collect) dplyr::collect(lf) else lf
}
