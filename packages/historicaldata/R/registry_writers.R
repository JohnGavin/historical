# Backtest registry — strategy + run writers (#347 PR 2/4)
#
# Builds on the schema + bootstrap shipped in PR 1/4.
# Adds:
#   hd_strategy_upsert(con, strategy_row)
#   hd_run_record(con, strategy_id, ...) → run_uuid
#
# These are the writer-side primitives. Per-strategy targets call them
# from a sentinel tar_target (see plan_commodities_mean_reversion.R for the
# CMR pilot wiring).

#' Idempotently upsert a strategy definition
#'
#' Inserts one row into `bt.strategy`. If a row with the same `strategy_id`
#' already exists, this call is a no-op (no update). Use [hd_strategy_update()]
#' (PR 3/4) if a keyword needs to change after creation.
#'
#' @param con A DBI connection from [hd_registry_open()] opened with
#'   `read_only = FALSE`.
#' @param strategy_row A single-row tibble or named list with columns:
#'   `strategy_id` (required), `short_name`, `long_name`, `asset_class`,
#'   `frequency`, `ann_factor`, `directionality`, `liquidity_tier`,
#'   `time_horizon_days`, `trades_per_year`, `turnover_pct`, `tags`,
#'   `research_paper_doi`. Missing columns insert as NULL.
#' @return Invisibly returns `strategy_row$strategy_id`.
#' @export
hd_strategy_upsert <- function(con, strategy_row) {
  rlang::check_installed("DBI")
  if (is.list(strategy_row) && !is.data.frame(strategy_row)) {
    strategy_row <- tibble::as_tibble(strategy_row)
  }
  if (nrow(strategy_row) != 1L) {
    cli::cli_abort("{.arg strategy_row} must be a single row.")
  }
  sid <- strategy_row$strategy_id
  if (is.null(sid) || is.na(sid) || !nzchar(sid)) {
    cli::cli_abort("{.field strategy_id} is required and must be non-empty.")
  }

  existing <- DBI::dbGetQuery(
    con,
    "SELECT 1 FROM bt.strategy WHERE strategy_id = ?",
    params = list(sid)
  )
  if (nrow(existing) > 0L) {
    return(invisible(sid))
  }

  cols <- c(
    "strategy_id", "short_name", "long_name", "asset_class",
    "frequency", "ann_factor", "directionality", "liquidity_tier",
    "time_horizon_days", "trades_per_year", "turnover_pct",
    "tags", "research_paper_doi"
  )
  row <- as.list(strategy_row)
  vals <- lapply(cols, function(col) if (is.null(row[[col]])) NA else row[[col]])

  placeholders <- paste(rep("?", length(cols)), collapse = ", ")
  col_list     <- paste(cols, collapse = ", ")

  DBI::dbExecute(
    con,
    sprintf(
      "INSERT INTO bt.strategy (%s) VALUES (%s)",
      col_list, placeholders
    ),
    params = vals
  )
  invisible(sid)
}

#' Record a backtest run
#'
#' Inserts a new row into `bt.run` and returns the freshly-minted
#' `run_uuid`. Called from a sentinel target wired downstream of the
#' strategy's main return target.
#'
#' @param con DBI connection (writable).
#' @param strategy_id The strategy this run belongs to. Must already exist
#'   in `bt.strategy` (FK enforced).
#' @param started_at,finished_at POSIXct timestamps. Defaults: now / now.
#' @param status Character. `"success"`, `"failed"`, `"partial"`. Default
#'   `"success"`.
#' @param git_sha Character. Defaults to `Sys.getenv("HD_GIT_SHA")` or
#'   `git rev-parse HEAD` if the env var is unset and `git` is on PATH.
#' @param git_dirty Logical. Defaults to `FALSE` if not provided.
#' @param pipeline_version Character. Optional pipeline tag (e.g.,
#'   `"phase1"`, `"2026-Q2"`). Defaults to NA.
#' @param partition Character. Optional sub-config tag (e.g., `"1m"`,
#'   `"3m"` for CMR lookback). Defaults to NA.
#' @param universe_id,cost_model_id FK refs. Default NA.
#' @param parent_uuid Optional parent run for nested / dependency runs.
#' @param notes Optional free text.
#' @return Character — the new `run_uuid` (UUID v4).
#' @export
hd_run_record <- function(con,
                          strategy_id,
                          started_at      = Sys.time(),
                          finished_at     = Sys.time(),
                          status          = "success",
                          git_sha         = NULL,
                          git_dirty       = FALSE,
                          pipeline_version = NA_character_,
                          partition       = NA_character_,
                          universe_id     = NA_character_,
                          cost_model_id   = NA_character_,
                          parent_uuid     = NA_character_,
                          notes           = NA_character_) {
  rlang::check_installed("DBI")

  if (is.null(git_sha)) {
    env_sha <- Sys.getenv("HD_GIT_SHA", "")
    git_sha <- if (nzchar(env_sha)) env_sha else .resolve_git_sha()
  }

  run_uuid <- .new_uuid()
  duration_sec <- as.numeric(
    difftime(finished_at, started_at, units = "secs")
  )

  DBI::dbExecute(
    con,
    "INSERT INTO bt.run (
       run_uuid, strategy_id, parent_uuid, git_sha, git_dirty,
       pipeline_version, partition, universe_id, cost_model_id,
       started_at, finished_at, duration_sec, status, notes
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(
      run_uuid, strategy_id, parent_uuid, git_sha, isTRUE(git_dirty),
      pipeline_version, partition, universe_id, cost_model_id,
      started_at, finished_at, duration_sec, status, notes
    )
  )

  run_uuid
}

# ── internals ─────────────────────────────────────────────────────────────

# UUID v4. Avoids the uuid package dependency; uses base R only.
.new_uuid <- function() {
  hex <- format(as.hexmode(sample.int(16, 32, replace = TRUE) - 1L), width = 1L)
  # Set v4 marker (13th hex = 4) and variant bits (17th hex in {8,9,a,b}).
  hex[13] <- "4"
  hex[17] <- c("8", "9", "a", "b")[sample.int(4L, 1L)]
  paste0(
    paste(hex[1:8],   collapse = ""), "-",
    paste(hex[9:12],  collapse = ""), "-",
    paste(hex[13:16], collapse = ""), "-",
    paste(hex[17:20], collapse = ""), "-",
    paste(hex[21:32], collapse = "")
  )
}

# Best-effort git SHA resolver. NA if git unavailable or not in a repo.
.resolve_git_sha <- function() {
  tryCatch(
    {
      out <- suppressWarnings(
        system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)
      )
      if (length(out) >= 1L && nzchar(out[1])) out[1] else NA_character_
    },
    error = function(e) NA_character_
  )
}
