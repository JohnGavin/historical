#' Create a DuckDB connection for remote Parquet access
#'
#' Returns a DBI connection to an ephemeral DuckDB instance.
#' DuckDB 0.10+ supports `hf://datasets/...` URLs natively — no httpfs needed.
#' httpfs is loaded as a fallback for non-HF HTTPS URLs.
#'
#' @return DBI connection object
#' @family infrastructure
#' @export
hd_connect <- function() {
  con <- DBI::dbConnect(duckdb::duckdb())
  # hf:// protocol built into DuckDB 0.10+ — no extension needed
  # Load httpfs as fallback for non-HF HTTPS URLs (e.g. local servers)
  tryCatch(
    invisible(DBI::dbExecute(con, "INSTALL httpfs; LOAD httpfs;")),
    error = function(e) {
      cli::cli_warn(c(
        "!" = "httpfs extension not loaded: {conditionMessage(e)}",
        "i" = "Non-HF HTTPS sources (local servers, custom Parquet URLs) will fail. hf:// still works."
      ))
      NULL
    }
  )
  con
}

hd_read_parquet_sql <- function(con, path) {
  sprintf("read_parquet(%s)", as.character(DBI::dbQuoteString(con, path)))
}

#' Create a DuckDB connection over local cached Parquet files
#'
#' @param cache_dir Path to local cache directory
#' @return DBI connection with views registered
#' @family infrastructure
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
      "CREATE VIEW %s AS SELECT * FROM %s",
      as.character(DBI::dbQuoteIdentifier(con, view_name)),
      hd_read_parquet_sql(con, f)
    ))
  }

  con
}
