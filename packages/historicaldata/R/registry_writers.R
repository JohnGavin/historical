# Backtest registry — strategy + run writers (#347 PR 2/4)
#
# Builds on the schema + bootstrap shipped in PR 1/4.
# Adds:
#   hd_strategy_upsert(con, strategy_row)
#   hd_run_record(con, strategy_id, ...) → run_uuid
#   hd_run_upsert(con, strategy_id, ...) → run_uuid  [idempotent, #375]
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
#' ## `leg_count` / composite-book tracking (#839)
#'
#' `leg_count` records how many underlying signals/expressions are
#' equal-weighted blended into this one reported strategy. This matters
#' because blending correlated legs manufactures Sharpe inflation via
#' variance reduction that trial-count-based multiple-testing corrections
#' (`hd_strat_keff_vertox()`, `hd_deflated_sharpe()`) do not capture -- see
#' `.claude/rules/detection-power-required.md`'s sibling issue #839 and
#' [hd_zero_alpha_calibration()].
#'
#' Per `.claude/rules/fail-loud-not-null.md`, this is a "must not silently
#' default" field for composite writes: pass `underlying_signals` (the
#' character vector of signal names being blended) so the composite case is
#' detectable. When `length(underlying_signals) > 1` you MUST also supply
#' `leg_count` (and it must equal `length(underlying_signals)`) -- otherwise
#' this function `cli_abort()`s rather than silently writing `leg_count = 1`
#' or `NA` for a book that is, in fact, a blend of several signals. A
#' genuinely single-signal strategy (no `underlying_signals`, or
#' `underlying_signals` of length 1) is unaffected: `leg_count` defaults to
#' `1L`, matching every caller written before #839.
#'
#' @param con A DBI connection from [hd_registry_open()] opened with
#'   `read_only = FALSE`.
#' @param strategy_row A single-row tibble or named list with columns:
#'   `strategy_id` (required), `short_name`, `long_name`, `asset_class`,
#'   `frequency`, `ann_factor`, `directionality`, `liquidity_tier`,
#'   `time_horizon_days`, `trades_per_year`, `turnover_pct`, `tags`,
#'   `research_paper_doi`, `leg_count` (optional -- see below). Missing
#'   columns insert as NULL (`leg_count` defaults to `1L`).
#' @param underlying_signals Optional character vector naming the
#'   underlying signals/expressions blended into this strategy. When its
#'   length is `> 1`, `leg_count` (via the `leg_count` argument or a
#'   `leg_count` column in `strategy_row`) is REQUIRED and must equal
#'   `length(underlying_signals)`. `NULL` (default) skips this check
#'   entirely -- existing single-signal callers are unaffected.
#' @param leg_count Optional integer. Explicit leg count for this
#'   strategy. Falls back to `strategy_row$leg_count` if present, then to
#'   `1L`. Required (and cross-checked against
#'   `length(underlying_signals)`) whenever `underlying_signals` has length
#'   `> 1`.
#' @return Invisibly returns `strategy_row$strategy_id`.
#' @export
hd_strategy_upsert <- function(con, strategy_row, underlying_signals = NULL,
                               leg_count = NULL) {
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

  row <- as.list(strategy_row)

  # ── leg_count resolution + composite guard (#839) ──────────────────────
  resolved_leg_count <- leg_count
  if (is.null(resolved_leg_count) && !is.null(row$leg_count) && !is.na(row$leg_count)) {
    resolved_leg_count <- row$leg_count
  }

  n_signals <- if (is.null(underlying_signals)) NA_integer_ else length(underlying_signals)

  if (!is.na(n_signals) && n_signals > 1L) {
    if (is.null(resolved_leg_count) || is.na(resolved_leg_count)) {
      cli::cli_abort(c(
        "x" = "{.arg strategy_row} for {.val {sid}} is missing {.field leg_count}.",
        "i" = "{.arg underlying_signals} lists {n_signals} legs blended into this strategy.",
        "i" = "Composite (multi-leg) strategies must declare {.field leg_count} explicitly -- it is not safe to silently default to 1.",
        "i" = "Pass {.arg leg_count} = {n_signals} (or a {.field leg_count} column in {.arg strategy_row})."
      ))
    }
    if (resolved_leg_count != n_signals) {
      cli::cli_abort(c(
        "x" = "{.field leg_count} ({resolved_leg_count}) does not match {.code length(underlying_signals)} ({n_signals}) for {.val {sid}}.",
        "i" = "These must agree -- {.field leg_count} is meant to record exactly how many legs went into this book."
      ))
    }
  }

  if (is.null(resolved_leg_count) || is.na(resolved_leg_count)) {
    resolved_leg_count <- 1L
  }
  row$leg_count <- as.integer(resolved_leg_count)

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
    "tags", "research_paper_doi", "leg_count"
  )
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

#' Idempotently upsert a backtest run
#'
#' Like [hd_run_record()], but safe to call repeatedly with the same
#' `(strategy_id, partition, pipeline_version)` tuple. On a re-run:
#'
#' 1. Looks up the existing `run_uuid` in `bt.run`.
#' 2. Deletes any `bt.metric` rows for that UUID (the caller re-inserts
#'    fresh metrics immediately after).
#' 3. Updates `finished_at`, `duration_sec`, `status`, and `notes` on the
#'    existing run row.
#' 4. Returns the existing `run_uuid` — callers that subsequently call
#'    [hd_metric_record()] with this UUID will write updated metrics.
#'
#' If no existing row matches, falls back to [hd_run_record()] (insert path).
#'
#' This function fixes the deterministic-RNG UUID collision when `targets`
#' calls `set.seed(<target_hash>)` before a sentinel target, causing
#' [.new_uuid()] to return the same UUID on every re-run (#375).
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
#' @param pipeline_version Character. Optional pipeline tag. Defaults to NA.
#' @param partition Character. Optional sub-config tag. Defaults to NA.
#' @param universe_id,cost_model_id FK refs. Default NA.
#' @param parent_uuid Optional parent run for nested / dependency runs.
#' @param notes Optional free text.
#' @return Character — the `run_uuid` (existing or newly minted UUID v4).
#' @export
hd_run_upsert <- function(con,
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

  existing <- DBI::dbGetQuery(
    con,
    "SELECT run_uuid FROM bt.run
     WHERE strategy_id = ?
       AND COALESCE(partition, '') = COALESCE(?, '')
       AND COALESCE(pipeline_version, '') = COALESCE(?, '')
     LIMIT 1",
    params = list(strategy_id, partition, pipeline_version)
  )

  if (nrow(existing) > 0L) {
    run_uuid     <- existing$run_uuid[[1L]]
    duration_sec <- as.numeric(difftime(finished_at, started_at, units = "secs"))
    DBI::dbExecute(
      con,
      "DELETE FROM bt.metric WHERE run_uuid = ?",
      params = list(run_uuid)
    )
    DBI::dbExecute(
      con,
      "UPDATE bt.run
         SET finished_at = ?, duration_sec = ?, status = ?, notes = ?
       WHERE run_uuid = ?",
      params = list(finished_at, duration_sec, status, notes, run_uuid)
    )
    return(run_uuid)
  }

  # No existing row — fall back to insert.
  hd_run_record(
    con              = con,
    strategy_id      = strategy_id,
    started_at       = started_at,
    finished_at      = finished_at,
    status           = status,
    git_sha          = git_sha,
    git_dirty        = git_dirty,
    pipeline_version = pipeline_version,
    partition        = partition,
    universe_id      = universe_id,
    cost_model_id    = cost_model_id,
    parent_uuid      = parent_uuid,
    notes            = notes
  )
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
