# Research-log DB: typed 5-table parquet store with lineage
#
# hd_rlog_tables()    — character vector of table names
# hd_rlog_schema()    — zero-row typed tibble for one table
# hd_rlog_path()      — default base directory
# hd_rlog_append()    — append rows to a table's parquet store
# hd_rlog_query()     — read all rows from a table
# hd_rlog_connect()   — DuckDB connection with one VIEW per table
# hd_rlog_lineage()   — walk parent_uuid chain across all tables
#
# Internal helpers (not exported):
#   hd_rlog_uuid()       — UUID-v4 via base R
#   hd_rlog_git_commit() — current HEAD SHA via system2
#   hd_rlog_env_hash()   — MD5 of flake.lock

# ── Internal helpers ────────────────────────────────────────────────────────

#' Generate a UUID-v4 using base R
#'
#' Generates a version-4 UUID using base R's random number generator only.
#' No external packages are required.  Useful for pre-generating ids before
#' calling \code{hd_rlog_append()} so that parent-child lineage chains can be
#' set before any row is written.
#'
#' @return A single character string in the canonical 8-4-4-4-12 lowercase
#'   hex format (e.g. \code{"550e8400-e29b-41d4-a716-446655440000"}).
#' @family research-log
#' @export
hd_rlog_uuid <- function() {
  b <- sample(0:255L, 16L, replace = TRUE)
  # Set version nibble (byte 7, high nibble) to 4
  b[7L] <- bitwOr(bitwAnd(b[7L], 0x0fL), 0x40L)
  # Set variant bits (byte 9, high two bits) to 10xx
  b[9L] <- bitwOr(bitwAnd(b[9L], 0x3fL), 0x80L)
  # Format as 8-4-4-4-12 lowercase hex
  hex <- sprintf("%02x", b)
  paste0(
    paste0(hex[1:4],   collapse = ""), "-",
    paste0(hex[5:6],   collapse = ""), "-",
    paste0(hex[7:8],   collapse = ""), "-",
    paste0(hex[9:10],  collapse = ""), "-",
    paste0(hex[11:16], collapse = "")
  )
}

# Return current HEAD SHA or NA_character_ on failure.
hd_rlog_git_commit <- function(repo = here::here()) {
  tryCatch(
    system2("git", c("-C", repo, "rev-parse", "HEAD"),
            stdout = TRUE, stderr = FALSE),
    error = function(e) NA_character_
  )
}

# MD5 of flake.lock at the repo root, or NA_character_ if absent.
hd_rlog_env_hash <- function() {
  path <- file.path(here::here(), "flake.lock")
  if (!file.exists(path)) return(NA_character_)
  unname(tools::md5sum(path))
}

# ── Lineage columns (shared by all 5 tables) ────────────────────────────────

.rlog_lineage_cols <- function() {
  tibble::tibble(
    uuid               = character(),
    parent_uuid        = character(),
    timestamp          = as.POSIXct(character()),
    git_commit         = character(),
    sandbox_image_hash = character()
  )
}

# ── 1. Table names ──────────────────────────────────────────────────────────

#' Names of the five research-log tables
#'
#' Returns a character vector of the table names that make up the
#' research-log database.
#'
#' @return Character vector of length 5.
#' @family research-log
#' @export
hd_rlog_tables <- function() {
  c("hypotheses", "implementations", "results", "critiques", "robustness")
}

# ── 2. Schema ───────────────────────────────────────────────────────────────

#' Zero-row typed tibble for one research-log table
#'
#' Returns an empty tibble with correctly typed columns.  Lineage columns
#' (\code{uuid}, \code{parent_uuid}, \code{timestamp}, \code{git_commit},
#' \code{sandbox_image_hash}) come first; table-specific columns follow.
#'
#' @param table One of \code{hd_rlog_tables()}.
#' @return Zero-row tibble with all columns typed.
#' @family research-log
#' @export
hd_rlog_schema <- function(table) {
  valid <- hd_rlog_tables()
  if (!table %in% valid) {
    cli::cli_abort(c(
      "x" = "Unknown research-log table: {.val {table}}",
      "i" = "Must be one of: {.val {valid}}"
    ))
  }
  lineage <- .rlog_lineage_cols()
  specific <- switch(table,
    # Commitment columns (#598): a hypothesis row is "sealed" when its
    # substantive fields have been canonically serialised and hashed, so the
    # claim cannot be silently edited after the outcome is known.  See
    # hd_rlog_seal().  NA in all three means an unsealed row.
    hypotheses = tibble::tibble(
      economic_claim = character(),
      dependent_var  = character(),
      predictor      = character(),
      sample_spec    = character(),
      null_hypothesis = character(),
      status         = character(),
      commit_hash    = character(),
      sealed_at      = as.POSIXct(character()),
      seal_method    = character(),
      extra_json     = character()
    ),
    implementations = tibble::tibble(
      code_ref      = character(),
      notebook_path = character(),
      params_json   = character(),
      extra_json    = character()
    ),
    results = tibble::tibble(
      strategy_id        = character(),
      partition          = character(),
      cagr               = double(),
      sharpe_hac         = double(),
      max_dd             = double(),
      turnover_annual    = double(),
      n_obs              = integer(),
      results_db_run_date = as.Date(character()),
      extra_json         = character()
    ),
    critiques = tibble::tibble(
      defect_class = character(),
      severity     = character(),
      finding      = character(),
      cell_ref     = character(),
      resolved     = logical()
    ),
    robustness = tibble::tibble(
      panel_name   = character(),
      variation    = character(),
      metric_name  = character(),
      metric_value = double(),
      passed       = logical(),
      extra_json   = character()
    )
  )
  dplyr::bind_cols(lineage, specific)
}

# ── 3. Path ─────────────────────────────────────────────────────────────────

#' Default base directory for the research-log store
#'
#' @param base_dir Override path, or \code{NULL} to use the default
#'   (\code{inst/extdata/research_log/} under the package root).
#' @return Scalar character path.
#' @family research-log
#' @export
hd_rlog_path <- function(base_dir = NULL) {
  if (!is.null(base_dir)) return(base_dir)
  file.path(here::here(), "inst", "extdata", "research_log")
}

# ── 4. Append ───────────────────────────────────────────────────────────────

#' Append rows to a research-log table
#'
#' Coerces \code{rows} to the table schema (adds missing columns as
#' \code{NA}, drops extras, coerces types).  Lineage columns are
#' auto-filled per row when missing or \code{NA}:
#' \itemize{
#'   \item \code{uuid} — UUID-v4 from base R.
#'   \item \code{timestamp} — \code{Sys.time()}.
#'   \item \code{git_commit} — current HEAD SHA via \code{system2("git")}.
#'   \item \code{sandbox_image_hash} — MD5 of \code{flake.lock}.
#' }
#' Each call writes a single parquet file named
#' \code{<first-uuid>_<timestamp>.parquet} under
#' \code{<base_dir>/<table>/}.  This is append-only (audit log);
#' rows are never deduped or overwritten.
#'
#' @param table One of \code{hd_rlog_tables()}.
#' @param rows Data frame or tibble of rows to append.
#' @param base_dir Override base directory (see \code{hd_rlog_path()}).
#' @return Invisible path to the written parquet file.
#' @family research-log
#' @export
hd_rlog_append <- function(table, rows, base_dir = NULL) {
  base_dir <- hd_rlog_path(base_dir)
  schema   <- hd_rlog_schema(table)

  # ── Schema conformance ───────────────────────────────────────────────────
  for (col in names(schema)) {
    if (!col %in% names(rows)) {
      rows[[col]] <- NA
    }
    target_class <- class(schema[[col]])[1L]
    cur_class    <- class(rows[[col]])[1L]
    if (identical(target_class, cur_class)) next
    rows[[col]] <- switch(target_class,
      "Date"      = as.Date(rows[[col]]),
      "POSIXct"   = as.POSIXct(rows[[col]]),
      "integer"   = as.integer(rows[[col]]),
      "numeric"   = as.numeric(rows[[col]]),
      "logical"   = as.logical(rows[[col]]),
      "character" = as.character(rows[[col]]),
      rows[[col]]
    )
  }
  rows <- rows[, names(schema), drop = FALSE]

  # ── Auto-fill lineage per row ────────────────────────────────────────────
  n <- nrow(rows)
  git_sha  <- hd_rlog_git_commit()
  env_hash <- hd_rlog_env_hash()

  for (i in seq_len(n)) {
    if (is.na(rows$uuid[i]) || rows$uuid[i] == "") {
      rows$uuid[i] <- hd_rlog_uuid()
    }
    if (is.na(rows$timestamp[i])) {
      rows$timestamp[i] <- Sys.time()
    }
    if (is.na(rows$git_commit[i])) {
      rows$git_commit[i] <- git_sha
    }
    if (is.na(rows$sandbox_image_hash[i])) {
      rows$sandbox_image_hash[i] <- env_hash
    }
  }

  # ── Write parquet ────────────────────────────────────────────────────────
  table_dir <- file.path(base_dir, table)
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

  first_uuid <- rows$uuid[1L]
  ts_str     <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out_path   <- file.path(table_dir, paste0(first_uuid, "_", ts_str, ".parquet"))

  arrow::write_parquet(rows, out_path, compression = "zstd")

  cli::cli_inform(c("v" = "Appended {n} row(s) to {.path {out_path}}"))
  invisible(out_path)
}

# ── 5. Query ────────────────────────────────────────────────────────────────

#' Query all rows from a research-log table
#'
#' Reads all parquet files under \code{<base_dir>/<table>/} and returns
#' a single tibble.  Returns an empty schema tibble with a warning if no
#' files are found.
#'
#' @param table One of \code{hd_rlog_tables()}.
#' @param base_dir Override base directory (see \code{hd_rlog_path()}).
#' @return Tibble of all rows, or a zero-row schema tibble if no files exist.
#' @family research-log
#' @export
hd_rlog_query <- function(table, base_dir = NULL) {
  base_dir  <- hd_rlog_path(base_dir)
  table_dir <- file.path(base_dir, table)
  files     <- list.files(table_dir, pattern = "\\.parquet$", full.names = TRUE)
  if (length(files) == 0L) {
    cli::cli_warn("No parquet files found for table {.val {table}} in {table_dir}")
    return(hd_rlog_schema(table))
  }
  purrr::map_dfr(files, arrow::read_parquet)
}

# ── 6. Connect ──────────────────────────────────────────────────────────────

#' DuckDB connection with research-log tables registered as VIEWs
#'
#' Opens an in-memory DuckDB connection and registers each table that has
#' parquet files as a VIEW named after the table.  Tables with no parquet
#' files are silently skipped.
#'
#' The caller is responsible for disconnecting with
#' \code{DBI::dbDisconnect(con, shutdown = TRUE)}.
#'
#' @param base_dir Override base directory (see \code{hd_rlog_path()}).
#' @return DBI connection object.
#' @family research-log
#' @export
hd_rlog_connect <- function(base_dir = NULL) {
  base_dir <- hd_rlog_path(base_dir)
  con      <- DBI::dbConnect(duckdb::duckdb())

  for (tbl in hd_rlog_tables()) {
    table_dir <- file.path(base_dir, tbl)
    glob_path <- file.path(table_dir, "*.parquet")
    # Only register if at least one parquet file exists
    files <- list.files(table_dir, pattern = "\\.parquet$", full.names = FALSE)
    if (length(files) == 0L) next

    DBI::dbExecute(con, sprintf(
      "CREATE VIEW %s AS SELECT * FROM read_parquet(%s)",
      as.character(DBI::dbQuoteIdentifier(con, tbl)),
      as.character(DBI::dbQuoteString(con, glob_path))
    ))
  }

  con
}

# ── 7. Lineage ──────────────────────────────────────────────────────────────

#' Walk the parent_uuid chain for a given uuid
#'
#' Searches all five research-log tables for \code{uuid}, then walks the
#' \code{parent_uuid} chain (across any table), returning one row per
#' ancestor in traversal order (nearest ancestor first).  Guards against
#' cycles by capping depth at 100.
#'
#' @param uuid Character.  UUID to look up.
#' @param base_dir Override base directory (see \code{hd_rlog_path()}).
#' @return Tibble with columns \code{table}, \code{uuid}, \code{parent_uuid},
#'   \code{timestamp}, ordered from the starting node's parent up to the root.
#' @family research-log
#' @export
hd_rlog_lineage <- function(uuid, base_dir = NULL) {
  base_dir <- hd_rlog_path(base_dir)

  # Load all tables and build a lookup list: uuid -> list(table, parent_uuid, timestamp)
  lookup <- list()
  for (tbl in hd_rlog_tables()) {
    rows <- tryCatch(
      hd_rlog_query(tbl, base_dir = base_dir),
      warning = function(w) hd_rlog_schema(tbl)  # empty — no files
    )
    if (nrow(rows) == 0L) next
    for (i in seq_len(nrow(rows))) {
      uid <- rows$uuid[i]
      if (is.na(uid) || uid == "") next
      lookup[[uid]] <- list(
        table       = tbl,
        uuid        = uid,
        parent_uuid = rows$parent_uuid[i],
        timestamp   = rows$timestamp[i]
      )
    }
  }

  # Walk from starting uuid's parent upward
  result_rows <- list()
  current_uuid <- uuid
  depth <- 0L
  max_depth <- 100L

  while (!is.na(current_uuid) && current_uuid != "" && depth < max_depth) {
    entry <- lookup[[current_uuid]]
    if (is.null(entry)) break
    result_rows <- c(result_rows, list(entry))
    next_uuid <- entry$parent_uuid
    if (is.na(next_uuid) || next_uuid == "") break
    current_uuid <- next_uuid
    depth <- depth + 1L
  }

  if (length(result_rows) == 0L) {
    return(tibble::tibble(
      table       = character(),
      uuid        = character(),
      parent_uuid = character(),
      timestamp   = as.POSIXct(character())
    ))
  }

  tibble::tibble(
    table       = vapply(result_rows, `[[`, character(1L), "table"),
    uuid        = vapply(result_rows, `[[`, character(1L), "uuid"),
    parent_uuid = vapply(result_rows, function(x) {
      v <- x$parent_uuid
      if (is.na(v)) NA_character_ else v
    }, character(1L)),
    timestamp   = do.call(c, lapply(result_rows, `[[`, "timestamp"))
  )
}
