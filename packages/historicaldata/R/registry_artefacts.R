# Backtest registry — art.* writers + QA gate (#347 PR 4/4)
#
# Closes the umbrella: every published vignette and diagram becomes a row,
# and a build-time gate catches references to rendered HTML that doesn't
# actually exist on disk. The gate is the precise check that would have
# caught the mermaid-test.html + examples.html regressions.

#' Idempotently upsert a vignette artefact row
#'
#' Inserts one row into `art.vignette` keyed on `vignette_id`. No-op if
#' a row with the same id already exists.
#'
#' @param con DBI connection (writable).
#' @param vignette_row A single-row tibble or named list. Required columns:
#'   `vignette_id`. Optional: `qmd_path`, `html_path`, `url`, `status`,
#'   `last_rendered_at`, `last_render_sha`, `render_warnings_n`,
#'   `owner_note`.
#' @return Invisibly, the `vignette_id`.
#' @export
hd_art_vignette_upsert <- function(con, vignette_row) {
  rlang::check_installed("DBI")
  if (is.list(vignette_row) && !is.data.frame(vignette_row)) {
    vignette_row <- tibble::as_tibble(vignette_row)
  }
  if (nrow(vignette_row) != 1L) {
    cli::cli_abort("{.arg vignette_row} must be a single row.")
  }
  vid <- vignette_row$vignette_id
  if (is.null(vid) || is.na(vid) || !nzchar(vid)) {
    cli::cli_abort("{.field vignette_id} is required and non-empty.")
  }

  existing <- DBI::dbGetQuery(
    con,
    "SELECT 1 FROM art.vignette WHERE vignette_id = ?",
    params = list(vid)
  )
  if (nrow(existing) > 0L) return(invisible(vid))

  cols <- c("vignette_id", "qmd_path", "html_path", "url", "status",
            "last_rendered_at", "last_render_sha",
            "render_warnings_n", "owner_note")
  row <- as.list(vignette_row)
  vals <- lapply(cols, function(col) if (is.null(row[[col]])) NA else row[[col]])

  DBI::dbExecute(
    con,
    sprintf(
      "INSERT INTO art.vignette (%s) VALUES (%s)",
      paste(cols, collapse = ", "),
      paste(rep("?", length(cols)), collapse = ", ")
    ),
    params = vals
  )
  invisible(vid)
}

#' Idempotently upsert a diagram artefact row
#'
#' Inserts one row into `art.diagram`. `vignette_id` must already exist
#' in `art.vignette` (FK enforced).
#'
#' @param con DBI connection (writable).
#' @param diagram_row A single-row tibble or named list. Required:
#'   `diagram_id`, `vignette_id`. Optional: `section`, `diagram_type`
#'   (mermaid / plotly / ggplot / dot / image), `target_name`, `purpose`.
#' @return Invisibly, the `diagram_id`.
#' @export
hd_art_diagram_upsert <- function(con, diagram_row) {
  rlang::check_installed("DBI")
  if (is.list(diagram_row) && !is.data.frame(diagram_row)) {
    diagram_row <- tibble::as_tibble(diagram_row)
  }
  if (nrow(diagram_row) != 1L) {
    cli::cli_abort("{.arg diagram_row} must be a single row.")
  }
  did <- diagram_row$diagram_id
  vid <- diagram_row$vignette_id
  if (is.null(did) || is.na(did) || !nzchar(did)) {
    cli::cli_abort("{.field diagram_id} is required.")
  }
  if (is.null(vid) || is.na(vid) || !nzchar(vid)) {
    cli::cli_abort("{.field vignette_id} is required.")
  }

  existing <- DBI::dbGetQuery(
    con,
    "SELECT 1 FROM art.diagram WHERE diagram_id = ?",
    params = list(did)
  )
  if (nrow(existing) > 0L) return(invisible(did))

  cols <- c("diagram_id", "vignette_id", "section",
            "diagram_type", "target_name", "purpose")
  row <- as.list(diagram_row)
  vals <- lapply(cols, function(col) if (is.null(row[[col]])) NA else row[[col]])

  DBI::dbExecute(
    con,
    sprintf(
      "INSERT INTO art.diagram (%s) VALUES (%s)",
      paste(cols, collapse = ", "),
      paste(rep("?", length(cols)), collapse = ", ")
    ),
    params = vals
  )
  invisible(did)
}

#' Validate artefact registry against disk
#'
#' Reads every row from `art.vignette` and verifies that the file at
#' `html_path` (interpreted relative to `docs_dir`) actually exists.
#' Vignettes with `html_path = NA` or `status = 'draft'` are skipped.
#'
#' This is the gate that would have caught the `mermaid-test.html` +
#' `examples.html` regressions in 2026-05: registry rows survived even
#' after the files were removed by a render-cleanup pass.
#'
#' @param con DBI connection (read-only is fine).
#' @param docs_dir Directory where rendered HTML lives (typically
#'   `here::here("docs")`).
#' @param strict Logical. If `TRUE` (default), missing artefacts cause an
#'   `rlang::abort()` via `cli::cli_abort`. If `FALSE`, return the
#'   missing-issues tibble without aborting.
#' @return Invisibly, a tibble of missing artefacts:
#'   `tibble(vignette_id, html_path, abs_path)`. Empty when all paths
#'   resolve.
#' @export
check_artefact_registry <- function(con, docs_dir, strict = TRUE) {
  rlang::check_installed("DBI")
  if (!dir.exists(docs_dir)) {
    cli::cli_abort("docs_dir {.path {docs_dir}} does not exist.")
  }

  rows <- DBI::dbGetQuery(
    con,
    "SELECT vignette_id, html_path, status FROM art.vignette
     WHERE html_path IS NOT NULL
       AND COALESCE(status, 'published') <> 'draft'"
  )

  if (nrow(rows) == 0L) {
    return(invisible(tibble::tibble(
      vignette_id = character(),
      html_path   = character(),
      abs_path    = character()
    )))
  }

  abs_paths <- file.path(docs_dir, rows$html_path)
  missing   <- !file.exists(abs_paths)

  issues <- tibble::tibble(
    vignette_id = rows$vignette_id[missing],
    html_path   = rows$html_path[missing],
    abs_path    = abs_paths[missing]
  )

  if (nrow(issues) > 0L && isTRUE(strict)) {
    cli::cli_abort(c(
      "Artefact registry references {nrow(issues)} missing HTML file{?s}:",
      stats::setNames(
        paste0("{.path ", issues$abs_path, "}"),
        rep("x", nrow(issues))
      ),
      "i" = "Either re-render the vignette or mark its row as
             {.code status = 'draft'} / {.code status = 'archived'}."
    ))
  }

  invisible(issues)
}
