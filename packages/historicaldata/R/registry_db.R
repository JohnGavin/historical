# Backtest registry — bootstrap (#347 PR 1/4)
#
# Provides hd_registry_path() / hd_registry_init() / hd_registry_open()
# / hd_registry_schema_version() for the Phase-1 registry DuckDB file.
#
# Schema definition ships inside the installed package at
# inst/extdata/registry/schema.sql.

#' Path to the backtest registry DuckDB file
#'
#' Resolution order:
#'   1. `Sys.getenv("HD_REGISTRY_PATH")` if non-empty
#'   2. `here::here("inst/extdata/registry/registry.duckdb")` if running
#'      inside the historical project AND the `here` package is available
#'   3. `tools::R_user_dir("historicaldata", "data")/registry/registry.duckdb`
#'
#' @return Absolute path as a character string.
#' @export
#' @examples
#' \dontrun{
#' hd_registry_path()
#' }
hd_registry_path <- function() {
  env_path <- Sys.getenv("HD_REGISTRY_PATH", "")
  if (nzchar(env_path)) {
    return(normalizePath(env_path, mustWork = FALSE))
  }

  if (requireNamespace("here", quietly = TRUE)) {
    project_path <- tryCatch(
      here::here("inst", "extdata", "registry", "registry.duckdb"),
      error = function(e) NULL
    )
    if (!is.null(project_path) &&
        dir.exists(here::here("inst", "extdata"))) {
      return(project_path)
    }
  }

  file.path(
    tools::R_user_dir("historicaldata", "data"),
    "registry",
    "registry.duckdb"
  )
}

#' Initialise the backtest registry DuckDB file
#'
#' Creates the DuckDB file if missing, then runs the bundled `schema.sql`
#' to ensure every table in `bt.*` and `art.*` exists. Idempotent — safe
#' to call on every session start.
#'
#' @param path Path to the registry DuckDB file. Defaults to
#'   [hd_registry_path()].
#' @return Invisibly returns `path`.
#' @export
#' @examples
#' \dontrun{
#' hd_registry_init()
#' }
hd_registry_init <- function(path = hd_registry_path()) {
  rlang::check_installed(c("DBI", "duckdb"))

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

  schema_path <- system.file(
    "extdata", "registry", "schema.sql",
    package = "historicaldata"
  )
  if (!nzchar(schema_path)) {
    # When running tests via load_all() against source, system.file()
    # returns "". Fall back to the source path.
    schema_path <- tryCatch(
      file.path(
        find.package("historicaldata"),
        "inst", "extdata", "registry", "schema.sql"
      ),
      error = function(e) NULL
    )
  }
  if (is.null(schema_path) || !file.exists(schema_path)) {
    cli::cli_abort(
      c(
        "Cannot locate {.file schema.sql} in the installed package.",
        "i" = "Reinstall {.pkg historicaldata} or run from a clean
              {.code devtools::load_all()}."
      )
    )
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = path)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  sql_text <- paste(readLines(schema_path, warn = FALSE), collapse = "\n")
  # Strip SQL line comments (-- ...) so they don't end up split inside a
  # statement after we split on ;\n.
  sql_text <- gsub("--[^\n]*", "", sql_text)
  statements <- strsplit(sql_text, ";\\s*\n")[[1]]
  statements <- statements[nzchar(trimws(statements))]

  for (st in statements) {
    DBI::dbExecute(con, st)
  }

  invisible(path)
}

#' Open the backtest registry
#'
#' Returns a DBI connection to the DuckDB registry file. The caller is
#' responsible for closing it via [DBI::dbDisconnect()] (use
#' `withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))` to guarantee
#' cleanup).
#'
#' @param path Path to the registry DuckDB file. Defaults to
#'   [hd_registry_path()].
#' @param read_only Logical. Open read-only (default `TRUE`). Set to
#'   `FALSE` when appending runs / metrics.
#' @return A DBI connection object (class `duckdb_connection`).
#' @export
#' @examples
#' \dontrun{
#' con <- hd_registry_open()
#' withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
#' DBI::dbGetQuery(con, "SELECT * FROM bt.strategy LIMIT 5")
#' }
hd_registry_open <- function(path = hd_registry_path(),
                             read_only = TRUE) {
  rlang::check_installed(c("DBI", "duckdb"))
  if (!file.exists(path)) {
    cli::cli_abort(
      c(
        "Registry file not found at {.path {path}}.",
        "i" = "Call {.code hd_registry_init()} first."
      )
    )
  }
  DBI::dbConnect(
    duckdb::duckdb(),
    dbdir     = path,
    read_only = isTRUE(read_only)
  )
}

#' Current registry schema version
#'
#' Reads `schema_version.version` from the registry. Returns `NA_character_`
#' if the file does not exist or has no row in `schema_version`.
#'
#' @param path Path to the registry DuckDB file. Defaults to
#'   [hd_registry_path()].
#' @return Character version string (e.g., `"1.0.0"`) or `NA_character_`.
#' @export
hd_registry_schema_version <- function(path = hd_registry_path()) {
  if (!file.exists(path)) {
    return(NA_character_)
  }
  con <- hd_registry_open(path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  vers <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT version FROM schema_version
       ORDER BY applied_at DESC LIMIT 1"
    ),
    error = function(e) NULL
  )
  if (is.null(vers) || nrow(vers) == 0L) {
    return(NA_character_)
  }
  vers$version[1]
}
