#' Create a DuckDB connection with httpfs enabled
#'
#' Returns a DBI connection to an ephemeral DuckDB instance
#' with the httpfs extension loaded for remote Parquet access.
#'
#' @return DBI connection object
#' @export
hd_connect <- function() {
  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
  con
}

#' Create a DuckDB connection over local cached Parquet files
#'
#' @param cache_dir Path to local cache directory
#' @return DBI connection with views registered
#' @export
hd_connect_local <- function(cache_dir = hd_cache_path()) {

  if (!dir.exists(cache_dir)) {
    cli::cli_abort(c(
      "Cache directory does not exist: {cache_dir}",
      "i" = "Run {.fn hd_download} first."
    ))
  }

  con <- DBI::dbConnect(duckdb::duckdb())

  # Register views for each cached dataset
  parquet_files <- list.files(cache_dir, pattern = "\\.parquet$", full.names = TRUE)
  for (f in parquet_files) {
    view_name <- tools::file_path_sans_ext(basename(f))
    DBI::dbExecute(con, sprintf(
      "CREATE VIEW %s AS SELECT * FROM read_parquet('%s')",
      view_name, f
    ))
  }

  con
}
