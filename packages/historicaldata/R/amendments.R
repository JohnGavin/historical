#' Get data amendments (Point-in-Time tracking)
#'
#' Returns the amendment log showing corrections made to historical data.
#' Each row records: what was changed, when, why, and the original value.
#'
#' @param ticker Filter to one ticker. NULL = all.
#' @return Tibble with amendment records
#' @export
hd_amendments <- function(ticker = NULL) {
  con <- hd_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  ds <- hd_datasets()[["amendments"]]
  if (is.null(ds)) {
    cli::cli_inform("No amendments.parquet found — no corrections recorded yet.")
    return(dplyr::tibble(
      ticker = character(), date = as.Date(character()),
      amendment_type = character(), description = character(),
      original_close = double(), corrected_close = double(),
      adjustment_factor = double(), source = character(),
      amended_at = as.POSIXct(character()), amended_by = character()
    ))
  }

  sql <- sprintf("SELECT * FROM read_parquet('%s')", ds$url)
  if (!is.null(ticker)) {
    sql <- paste0(sql, sprintf(" WHERE ticker = '%s'", ticker))
  }
  sql <- paste(sql, "ORDER BY ticker, date")

  DBI::dbGetQuery(con, sql) |> dplyr::as_tibble()
}
