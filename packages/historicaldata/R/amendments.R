#' Get price data amendments (Point-in-Time tracking)
#'
#' Returns the amendment log showing corrections made to historical price data.
#' Each row records: what was changed, when, why, and the original value.
#'
#' @param ticker Filter to one ticker. NULL = all.
#' @return Tibble with amendment records
#' @family quality-audit
#' @export
hd_amendments <- function(ticker = NULL) {
  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  ds <- hd_datasets()[["amendments"]]
  if (is.null(ds)) {
    cli::cli_inform("No price amendments recorded yet.")
    return(dplyr::tibble())
  }

  sql <- sprintf("SELECT * FROM read_parquet('%s')", ds$url)
  if (!is.null(ticker)) {
    sql <- paste0(sql, sprintf(" WHERE ticker = '%s'", ticker))
  }

  DBI::dbGetQuery(con, sql) |> dplyr::as_tibble()
}

#' Get metadata amendments (Point-in-Time tracking)
#'
#' Returns the PIT log of all metadata changes: computed fields, enrichments,
#' corrections. Every change to metadata.parquet is tracked with old/new values,
#' source, method, and timestamp.
#'
#' @param ticker Filter to one ticker. NULL = all.
#' @param field Filter to one field (e.g. "beta_3yr"). NULL = all.
#' @return Tibble with: ticker, field, old_value, new_value, source, method,
#'   amended_at, amended_by, reversible
#' @export
#' @examples
#' \donttest{
#' hd_metadata_amendments("AAPL")
#' hd_metadata_amendments(field = "beta_3yr")
#' }
hd_metadata_amendments <- function(ticker = NULL, field = NULL) {
  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

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

  wheres <- character()
  if (!is.null(ticker)) wheres <- c(wheres, sprintf("ticker = '%s'", ticker))
  if (!is.null(field)) wheres <- c(wheres, sprintf("field = '%s'", field))

  sql <- sprintf("SELECT * FROM read_parquet('%s')", ds$url)
  if (length(wheres) > 0) sql <- paste(sql, "WHERE", paste(wheres, collapse = " AND "))
  sql <- paste(sql, "ORDER BY amended_at DESC, ticker, field")

  DBI::dbGetQuery(con, sql) |> dplyr::as_tibble()
}
