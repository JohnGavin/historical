# Queryable strategy ledger on top of the research log (Refs #962)
#
# The tracked research log (parquet under inst/extdata/research_log/) is the
# SYSTEM OF RECORD. This file adds NO table of its own (PR #511's bespoke
# `strategy_admission` table was removed for exactly that reason):
#
#   * a backlog idea is a row in the existing `hypotheses` table whose
#     extra_json carries kind = "strategy_idea" (same pattern as
#     kind = "strategy_admission" in admission_preregister.R);
#   * hd_strategy_ledger() / hd_strategy_trial_count() are READ-ONLY views
#     over that table (plus, optionally, bt.strategy from the registry);
#   * hd_strategy_ledger_register() creates a rebuildable DuckDB VIEW over the
#     same parquet files. registry.duckdb is gitignored, so the view is a query
#     layer only and is never a place where state lives.
#
# Grouping rule shared by the R reader and the SQL view (they must agree; a
# test compares them): rows with identical (economic_claim, predictor) are ONE
# ledger entry. A status change is a NEW row that repeats claim + name and sets
# parent_uuid to the earlier row. Nothing is ever edited or re-statused.

# ── Vocabulary ──────────────────────────────────────────────────────────────

#' Controlled vocabulary for a strategy idea's priority
#'
#' Returns the fixed set of values \code{hd_strategy_idea_append()} accepts for
#' \code{priority}, one row per value with a \code{description}. Defined once
#' here so the writer and any reader validate against the same set (compare
#' \code{hd_rlog_statuses()}).
#'
#' @return A tibble with columns \code{priority} and \code{description}.
#' @family research-log
#' @export
hd_strategy_idea_priorities <- function() {
  tibble::tribble(
    ~priority, ~description,
    "low",     "Parked: named in a source, not worth working on now.",
    "queued",  "Worth doing; waiting for a slot, data source or gate.",
    "active",  "Being worked on now (a pre-registration is the next step)."
  )
}

# ── Private helpers ─────────────────────────────────────────────────────────

.sl_scalar_string <- function(x, arg, call = rlang::caller_env()) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(trimws(x))) {
    cli::cli_abort(c(
      "x" = "{.arg {arg}} must be a single non-empty character string.",
      "i" = "Got {.val {x}}."
    ), call = call)
  }
  invisible(x)
}

# Parse each extra_json string to a list (NULL when absent/invalid JSON).
.sl_parse_extra <- function(extra_json) {
  lapply(extra_json, function(x) {
    if (length(x) != 1L || is.na(x) || !nzchar(x)) return(NULL)
    tryCatch(jsonlite::fromJSON(x, simplifyVector = FALSE),
             error = function(e) NULL)
  })
}

# One field out of parsed extra_json as character (NA when absent/null).
.sl_field <- function(parsed, field) {
  vapply(parsed, function(x) {
    v <- if (is.null(x)) NULL else x[[field]]
    if (is.null(v) || length(v) == 0L || is.na(v[[1]])) NA_character_
    else as.character(v[[1]])
  }, character(1))
}

# Latest non-NA value of `x` ordered by `ord` (NA if all NA).
.sl_latest_non_na <- function(x, ord) {
  keep <- which(!is.na(x))
  if (length(keep) == 0L) return(x[NA_integer_][1L])
  x[keep[ord[keep] == max(ord[keep])][1L]]
}

.sl_empty <- function() {
  tibble::tibble(
    ledger_id     = character(),
    name          = character(),
    kind          = character(),
    stage         = character(),
    priority      = character(),
    latest_status = character(),
    n_attempts    = integer(),
    source        = character(),
    issue         = integer(),
    strategy_id   = character(),
    last_updated  = as.POSIXct(character())
  )
}

# Research-log part of the ledger: one row per (economic_claim, predictor).
.sl_from_log <- function(base_dir) {
  base_dir <- hd_rlog_path(base_dir)
  files <- list.files(file.path(base_dir, "hypotheses"),
                      pattern = "\\.parquet$")
  rows <- if (length(files) == 0L) {
    hd_rlog_schema("hypotheses")
  } else {
    hd_rlog_query("hypotheses", base_dir = base_dir)
  }
  if (nrow(rows) == 0L) return(.sl_empty())

  # Fail loud: a status outside the vocabulary (a file written by bypassing
  # hd_rlog_append()) must not be silently carried into the ledger.
  valid_statuses <- hd_rlog_statuses()$status
  bad <- unique(rows$status[is.na(rows$status) | !rows$status %in% valid_statuses])
  if (length(bad) > 0L) {
    cli::cli_abort(c(
      "x" = "Hypotheses in the research log have status outside the vocabulary: {.val {bad}}",
      "i" = "Allowed values: {.val {valid_statuses}}"
    ), call = rlang::caller_env())
  }

  rlang::check_installed("jsonlite")
  parsed <- .sl_parse_extra(rows$extra_json)
  rows$.kind     <- .sl_field(parsed, "kind")
  rows$.name     <- .sl_field(parsed, "name")
  rows$.priority <- .sl_field(parsed, "priority")
  rows$.source   <- .sl_field(parsed, "source")
  rows$.issue    <- .sl_field(parsed, "issue")
  rows$.strategy <- .sl_field(parsed, "strategy_id")
  rows$.gkey <- paste(
    ifelse(is.na(rows$economic_claim), "<NA>", rows$economic_claim),
    ifelse(is.na(rows$predictor), "<NA>", rows$predictor),
    sep = "\x1f"
  )

  out <- lapply(split(seq_len(nrow(rows)), rows$.gkey), function(idx) {
    g   <- rows[idx, , drop = FALSE]
    # newest first / oldest first, ties broken by uuid so the order is total
    o_new <- order(g$timestamp, g$uuid, decreasing = TRUE)
    o_old <- order(g$timestamp, g$uuid)
    newest <- g[o_new[1L], , drop = FALSE]
    is_idea <- any(g$.kind == "strategy_idea", na.rm = TRUE)
    nm <- newest$.name
    if (is.na(nm)) nm <- newest$predictor
    if (is.na(nm)) nm <- substr(newest$economic_claim, 1L, 60L)
    ts <- as.numeric(g$timestamp)
    tibble::tibble(
      ledger_id     = g$uuid[o_old[1L]],
      name          = nm,
      kind          = if (is_idea) "idea" else "hypothesis",
      stage         = newest$status,
      priority      = .sl_latest_non_na(g$.priority, ts),
      latest_status = newest$status,
      n_attempts    = nrow(g),
      source        = .sl_latest_non_na(g$.source, ts),
      issue         = suppressWarnings(
        as.integer(.sl_latest_non_na(g$.issue, ts))
      ),
      strategy_id   = .sl_latest_non_na(g$.strategy, ts),
      last_updated  = newest$timestamp
    )
  })
  out <- dplyr::bind_rows(out)
  out$n_attempts <- as.integer(out$n_attempts)
  out[order(out$ledger_id), , drop = FALSE]
}

# Live strategies from the registry's bt.strategy, or NULL (with an inform
# saying WHY) when the optional source is unavailable.
.sl_live_strategies <- function(registry_path) {
  if (is.null(registry_path)) {
    cli::cli_inform(c(
      "i" = "No {.arg registry_path}: ledger lists research-log rows only (no live strategies)."
    ))
    return(NULL)
  }
  if (!file.exists(registry_path)) {
    cli::cli_inform(c(
      "i" = "Registry file not found at {.path {registry_path}}: ledger lists research-log rows only (no live strategies)."
    ))
    return(NULL)
  }
  con <- hd_registry_open(registry_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  has_bt <- DBI::dbGetQuery(
    con,
    "SELECT count(*) AS n FROM information_schema.tables
     WHERE table_schema = 'bt' AND table_name = 'strategy'"
  )$n
  if (has_bt == 0L) {
    cli::cli_inform(c(
      "i" = "Registry at {.path {registry_path}} has no {.code bt.strategy}: ledger lists research-log rows only (no live strategies)."
    ))
    return(NULL)
  }
  DBI::dbGetQuery(
    con,
    "SELECT strategy_id, short_name, lifecycle, created_at
     FROM bt.strategy WHERE lifecycle = 'stable'"
  )
}

# ── Writer ──────────────────────────────────────────────────────────────────

#' Append a backlog strategy idea to the research log
#'
#' Records an idea as a row in the EXISTING \code{hypotheses} table with
#' \code{extra_json$kind = "strategy_idea"} (the same pattern as
#' \code{kind = "strategy_admission"} in \code{hd_admission_preregister()}).
#' No new table is created.
#'
#' The row is UNSEALED by design and is never sealed afterwards: a backlog idea
#' is not a pre-registration. Pre-registration (and the seal) happens at
#' admission via \code{hd_admission_preregister()}. Per
#' \code{.claude/rules/research-log-honesty.md} the omission is recorded
#' explicitly (\code{preregistered = FALSE}, \code{seal_omitted_reason}) rather
#' than left as three ambiguous NAs.
#'
#' The log is append-only: to change an idea's priority or status, append a NEW
#' row with the same \code{name} and \code{economic_claim} and \code{parent_uuid}
#' set to the earlier row's uuid. \code{hd_strategy_ledger()} reads the newest
#' row as the current state.
#'
#' @param name Character. Short unique name of the idea (stored as
#'   \code{predictor}).
#' @param economic_claim Character. What the idea claims, in the source's own
#'   terms. Do not invent a mechanism the source does not state.
#' @param source Character. REQUIRED. URL or issue reference the idea came from.
#' @param priority One of \code{hd_strategy_idea_priorities()$priority}, or
#'   \code{NA_character_} when \code{status} is anything other than
#'   \code{"proposed"} (a finished test has no queue position). A
#'   \code{"proposed"} idea always needs a priority.
#' @param asset_class Character. Asset class the idea trades.
#' @param issue Optional. A single GitHub issue number.
#' @param strategy_id Optional character. Links the idea to a
#'   \code{bt.strategy} row.
#' @param status Character. One of \code{hd_rlog_statuses()$status}, except the
#'   deprecated \code{"tested"}, which is refused. Default \code{"proposed"}.
#' @param parent_uuid Optional character. uuid of the earlier row this row
#'   follows up (a status/priority change).
#' @param base_dir Override research-log base directory (see
#'   \code{hd_rlog_path()}).
#' @param seal_omitted_reason Optional character. Why the row is unsealed.
#'   \code{NULL} (default) records the backlog-idea reason; a row written after
#'   its outcome was known must say so here instead.
#' @param extra Optional named list of additional \code{extra_json} fields (for
#'   example \code{outcome_source}). Names must be unique, non-empty and must
#'   not collide with the fields this function writes itself.
#' @return Invisibly, the new row's \code{uuid}.
#' @family research-log
#' @export
#' @examples
#' \dontrun{
#' hd_strategy_idea_append(
#'   name = "spy_tlt_month_end",
#'   economic_claim = "SPY/TLT month-end rebalance trade",
#'   source = "https://algoadvantage.substack.com/p/the-questions-that-change-everything",
#'   priority = "low",
#'   asset_class = "equity/bond"
#' )
#' }
hd_strategy_idea_append <- function(name,
                                    economic_claim,
                                    source,
                                    priority,
                                    asset_class,
                                    issue       = NULL,
                                    strategy_id = NULL,
                                    status      = "proposed",
                                    parent_uuid = NULL,
                                    base_dir    = NULL,
                                    seal_omitted_reason = NULL,
                                    extra       = NULL) {
  .sl_scalar_string(name, "name")
  .sl_scalar_string(economic_claim, "economic_claim")
  if (missing(source)) {
    cli::cli_abort(c(
      "x" = "{.arg source} is required: an idea with no origin cannot be audited.",
      "i" = "Pass a URL or an issue reference."
    ))
  }
  .sl_scalar_string(source, "source")
  .sl_scalar_string(asset_class, "asset_class")

  # Status is validated BEFORE priority: whether a priority may be NA depends
  # on it.
  allowed_statuses <- hd_rlog_statuses()$status
  if (!is.character(status) || length(status) != 1L || is.na(status) ||
      !status %in% allowed_statuses) {
    cli::cli_abort(c(
      "x" = "Unknown idea {.arg status}: {.val {status}}",
      "i" = "Allowed values: {.val {setdiff(allowed_statuses, 'tested')}}"
    ))
  }
  if (identical(status, "tested")) {
    cli::cli_abort(c(
      "x" = "Status {.val tested} is deprecated and ambiguous; it is refused for new ideas.",
      "i" = "Use one of: {.val {setdiff(allowed_statuses, 'tested')}}"
    ))
  }

  # A priority is a queue position. It is meaningless for a finished test, so
  # NA is allowed there, but a proposed idea must still say where it queues.
  allowed_priorities <- hd_strategy_idea_priorities()$priority
  priority_is_na <- !missing(priority) && length(priority) == 1L &&
    (is.character(priority) || is.logical(priority)) && is.na(priority)
  if (priority_is_na && identical(status, "proposed")) {
    cli::cli_abort(c(
      "x" = "{.arg priority} is required when {.arg status} is {.val proposed}.",
      "i" = "Allowed values: {.val {allowed_priorities}}",
      "i" = "{.code NA} is accepted only for a non-proposed status."
    ))
  }
  if (!priority_is_na &&
      (missing(priority) || !is.character(priority) || length(priority) != 1L ||
       !priority %in% allowed_priorities)) {
    got <- if (missing(priority)) "<missing>" else priority
    cli::cli_abort(c(
      "x" = "Unknown idea {.arg priority}: {.val {got}}",
      "i" = "Allowed values: {.val {allowed_priorities}}"
    ))
  }

  if (!is.null(seal_omitted_reason)) {
    .sl_scalar_string(seal_omitted_reason, "seal_omitted_reason")
  }
  reserved_extra <- c("kind", "name", "priority", "asset_class", "source",
                      "issue", "strategy_id", "preregistered",
                      "seal_omitted_reason")
  if (!is.null(extra)) {
    if (!is.list(extra) || length(extra) == 0L || is.null(names(extra)) ||
        anyNA(names(extra)) || any(!nzchar(names(extra))) ||
        anyDuplicated(names(extra)) > 0L) {
      cli::cli_abort(c(
        "x" = "{.arg extra} must be NULL or a non-empty list with unique, non-empty names.",
        "i" = "Got {length(extra)} element{?s} with names {.val {as.character(names(extra))}}."
      ))
    }
    clash <- intersect(names(extra), reserved_extra)
    if (length(clash) > 0L) {
      cli::cli_abort(c(
        "x" = "{.arg extra} may not set fields the writer owns: {.val {clash}}",
        "i" = "Use the matching argument instead (for example {.arg seal_omitted_reason})."
      ))
    }
  }

  if (!is.null(issue)) {
    if (!is.numeric(issue) || length(issue) != 1L || is.na(issue) ||
        issue < 1 || issue != round(issue)) {
      cli::cli_abort(c(
        "x" = "{.arg issue} must be NULL or a single positive whole number.",
        "i" = "Got {.val {issue}}."
      ))
    }
  }
  if (!is.null(strategy_id)) .sl_scalar_string(strategy_id, "strategy_id")
  if (!is.null(parent_uuid)) .sl_scalar_string(parent_uuid, "parent_uuid")

  rlang::check_installed("jsonlite")
  payload <- list(
    kind                = "strategy_idea",
    name                = name,
    priority            = if (priority_is_na) NULL else priority,
    asset_class         = asset_class,
    source              = source,
    issue               = if (is.null(issue)) NULL else as.integer(issue),
    strategy_id         = strategy_id,
    preregistered       = FALSE,
    seal_omitted_reason = if (is.null(seal_omitted_reason)) {
      paste0(
        "backlog idea; pre-registration happens at admission ",
        "(hd_admission_preregister)"
      )
    } else {
      seal_omitted_reason
    }
  )
  if (!is.null(extra)) payload <- c(payload, extra)

  row <- tibble::tibble(
    uuid            = hd_rlog_uuid(),
    parent_uuid     = if (is.null(parent_uuid)) NA_character_ else parent_uuid,
    economic_claim  = economic_claim,
    dependent_var   = NA_character_,
    predictor       = name,
    sample_spec     = asset_class,
    null_hypothesis = NA_character_,
    status          = status,
    extra_json      = as.character(
      jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null", na = "null")
    )
  )

  hd_rlog_append("hypotheses", row, base_dir = base_dir)
  invisible(row$uuid[[1]])
}

# ── Reader ──────────────────────────────────────────────────────────────────

#' One queryable ledger of strategies, hypotheses and backlog ideas
#'
#' Returns one row per strategy-or-idea, assembled from the research log (the
#' system of record) and, optionally, the registry's \code{bt.strategy}.
#'
#' @section Grouping (lineage and duplicates):
#' Rows of the \code{hypotheses} table with identical \code{economic_claim} AND
#' \code{predictor} are ONE ledger entry. \code{n_attempts} is the number of
#' hypothesis rows in that group. This is a GROUPING, not an edit: the 10
#' OLMAR-1 rows are the same claim logged repeatedly, so they appear as one
#' entry with \code{n_attempts = 10}, and the rows themselves are untouched.
#' The log is append-only, so a status change is a NEW row (same claim and
#' name, \code{parent_uuid} pointing at the earlier row); the entry's
#' \code{latest_status} is the status of the newest row by \code{timestamp}
#' (ties broken by uuid) and \code{last_updated} is that timestamp.
#' \code{priority}, \code{source}, \code{issue} and \code{strategy_id} are the
#' newest non-missing values in the group.
#'
#' @section Kinds and stage:
#' \code{kind = "idea"} when any row in the group has
#' \code{extra_json$kind == "strategy_idea"}; every other hypothesis group is
#' \code{"hypothesis"}. \code{kind = "live_strategy"} rows come from
#' \code{bt.strategy} where \code{lifecycle = 'stable'}; their \code{stage} is
#' \code{"live"}, \code{latest_status} is the lifecycle, and \code{n_attempts}
#' is the total attempts of research-log entries whose \code{strategy_id}
#' links to them (0 if none). For ideas and hypotheses \code{stage} equals
#' \code{latest_status}. \code{priority} is \code{NA} for non-ideas.
#'
#' @section Optional registry:
#' When \code{registry_path} is \code{NULL}, the file is absent, or it has no
#' \code{bt.strategy}, only the research-log part is returned (no
#' \code{live_strategy} rows) and a \code{cli::cli_inform()} says why. This is
#' never an error and never silent.
#'
#' @param base_dir Override research-log base directory (see
#'   \code{hd_rlog_path()}).
#' @param registry_path Path to the registry DuckDB file, or \code{NULL}
#'   (default) to skip live strategies.
#' @return A tibble with columns \code{ledger_id}, \code{name}, \code{kind},
#'   \code{stage}, \code{priority}, \code{latest_status}, \code{n_attempts},
#'   \code{source}, \code{issue}, \code{strategy_id}, \code{last_updated}.
#' @family research-log
#' @export
hd_strategy_ledger <- function(base_dir = NULL, registry_path = NULL) {
  log_part <- .sl_from_log(base_dir)
  live <- .sl_live_strategies(registry_path)
  if (is.null(live) || nrow(live) == 0L) return(log_part)

  linked <- vapply(live$strategy_id, function(id) {
    as.integer(sum(log_part$n_attempts[!is.na(log_part$strategy_id) &
                                         log_part$strategy_id == id]))
  }, integer(1))
  live_part <- tibble::tibble(
    ledger_id     = live$strategy_id,
    name          = live$short_name,
    kind          = "live_strategy",
    stage         = "live",
    priority      = NA_character_,
    latest_status = live$lifecycle,
    n_attempts    = unname(linked),
    source        = NA_character_,
    issue         = NA_integer_,
    strategy_id   = live$strategy_id,
    last_updated  = as.POSIXct(live$created_at)
  )
  dplyr::bind_rows(log_part, live_part)
}

#' Count strategy ideas/hypotheses that have been tried
#'
#' Returns the number of distinct ledger entries (see
#' \code{hd_strategy_ledger()} for the grouping) of kind \code{"idea"} or
#' \code{"hypothesis"} whose latest status is \code{refuted}, \code{supported},
#' \code{inconclusive-underpowered}, \code{inconclusive-unmeasurable} or
#' \code{testing}.
#'
#' It counts REJECTED attempts too: a refuted idea was still a trial, and any
#' multiple-testing correction must account for it. This is the quantity that
#' can later feed an effective-trials (K_eff) estimate; it is not wired into
#' any QA gate.
#'
#' Entries still at a legacy \code{tested} status are NOT counted (that status
#' does not say what was concluded). When any exist, a
#' \code{cli::cli_inform()} reports how many were left out, so the count is not
#' silently low.
#'
#' @param base_dir Override research-log base directory (see
#'   \code{hd_rlog_path()}).
#' @return A single integer.
#' @family research-log
#' @export
hd_strategy_trial_count <- function(base_dir = NULL) {
  led <- .sl_from_log(base_dir)
  counted <- c("refuted", "supported", "inconclusive-underpowered",
               "inconclusive-unmeasurable", "testing")
  n_legacy <- sum(led$latest_status == "tested", na.rm = TRUE)
  if (n_legacy > 0L) {
    cli::cli_inform(c(
      "i" = "{n_legacy} entr{?y/ies} with deprecated status {.val tested} not counted as trials (outcome unknown)."
    ))
  }
  as.integer(sum(led$latest_status %in% counted))
}

# ── Query layer (rebuildable DuckDB view) ───────────────────────────────────

#' Register the strategy ledger as a DuckDB view
#'
#' Creates \code{CREATE SCHEMA IF NOT EXISTS research} and the view
#' \code{research.strategy_ledger} on a read-write registry connection. The
#' view reads the research-log parquet files directly
#' (\code{read_parquet(<glob>)}, as \code{hd_rlog_connect()} does) and unions
#' \code{bt.strategy} rows with \code{lifecycle = 'stable'}. It stores no
#' data: \code{registry.duckdb} is gitignored and rebuilt, so the view is only
#' a query layer and is safe to drop and recreate. The grouping rules are those
#' of \code{hd_strategy_ledger()}.
#'
#' @param con Read-write DBI connection to the registry (see
#'   \code{hd_registry_open(read_only = FALSE)}); must already contain
#'   \code{bt.strategy} (\code{hd_registry_init()}).
#' @param base_dir Override research-log base directory (see
#'   \code{hd_rlog_path()}).
#' @return Invisibly, \code{"research.strategy_ledger"}.
#' @family research-log
#' @export
hd_strategy_ledger_register <- function(con, base_dir = NULL) {
  base_dir <- hd_rlog_path(base_dir)
  files <- list.files(file.path(base_dir, "hypotheses"),
                      pattern = "\\.parquet$")
  if (length(files) == 0L) {
    cli::cli_abort(c(
      "x" = "No hypotheses parquet files under {.path {file.path(base_dir, 'hypotheses')}}.",
      "i" = "The view needs at least one file to bind its schema."
    ))
  }
  glob <- as.character(DBI::dbQuoteString(
    con, file.path(base_dir, "hypotheses", "*.parquet")
  ))
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS research")
  # The DuckDB `json` extension is NOT assumed available (it is not bundled
  # with every R duckdb build and cannot be auto-installed offline), so the
  # fields are pulled out of extra_json with regexp_extract(). The pattern
  # tolerates escaped quotes inside string values; hd_strategy_idea_append()
  # writes compact jsonlite output, and a test compares this view with the R
  # reader so any drift between the two is caught.
  str_field <- function(key) {
    sub("@KEY@", key, fixed = TRUE,
        r"--(nullif(regexp_extract(extra_json, '"@KEY@":"((?:[^"\\]|\\.)*)"', 1), ''))--")
  }
  int_field <- function(key) {
    sub("@KEY@", key, fixed = TRUE,
        r"--(TRY_CAST(nullif(regexp_extract(extra_json, '"@KEY@":([0-9]+)', 1), '') AS INTEGER))--")
  }
  sql <- "
CREATE OR REPLACE VIEW research.strategy_ledger AS
WITH h AS (
  SELECT uuid, timestamp, economic_claim, predictor, status,
         @KIND@ AS k,
         coalesce(@NAME@, predictor, substr(economic_claim, 1, 60)) AS nm,
         @PRIORITY@ AS priority,
         @SOURCE@ AS source,
         @ISSUE@ AS issue,
         @STRATEGY@ AS strategy_id,
         coalesce(economic_claim, '<NA>') || chr(31) ||
           coalesce(predictor, '<NA>') AS gkey
  FROM read_parquet(@GLOB@)
), grp AS (
  SELECT
    arg_min(uuid, (timestamp, uuid))                          AS ledger_id,
    arg_max(nm, (timestamp, uuid))                            AS name,
    CASE WHEN coalesce(bool_or(k = 'strategy_idea'), false)
         THEN 'idea' ELSE 'hypothesis' END                     AS kind,
    arg_max(status, (timestamp, uuid))                         AS latest_status,
    arg_max(priority, timestamp) FILTER (WHERE priority IS NOT NULL)       AS priority,
    CAST(count(*) AS INTEGER)                                  AS n_attempts,
    arg_max(source, timestamp) FILTER (WHERE source IS NOT NULL)           AS source,
    arg_max(issue, timestamp) FILTER (WHERE issue IS NOT NULL)             AS issue,
    arg_max(strategy_id, timestamp) FILTER (WHERE strategy_id IS NOT NULL) AS strategy_id,
    max(timestamp)                                             AS last_updated
  FROM h
  GROUP BY gkey
)
SELECT ledger_id, name, kind, latest_status AS stage, priority,
       latest_status, n_attempts, source, issue, strategy_id, last_updated
FROM grp
UNION ALL
SELECT s.strategy_id, s.short_name, 'live_strategy', 'live',
       CAST(NULL AS VARCHAR), s.lifecycle,
       CAST(coalesce((SELECT sum(g.n_attempts) FROM grp g
                      WHERE g.strategy_id = s.strategy_id), 0) AS INTEGER),
       CAST(NULL AS VARCHAR), CAST(NULL AS INTEGER), s.strategy_id,
       CAST(s.created_at AS TIMESTAMP)
FROM bt.strategy s
WHERE s.lifecycle = 'stable'"
  for (p in list(
    c("@KIND@", str_field("kind")), c("@NAME@", str_field("name")),
    c("@PRIORITY@", str_field("priority")), c("@SOURCE@", str_field("source")),
    c("@ISSUE@", int_field("issue")), c("@STRATEGY@", str_field("strategy_id")),
    c("@GLOB@", glob)
  )) {
    # split/paste, not sub(): the replacement contains backslashes
    sql <- paste(strsplit(sql, p[[1]], fixed = TRUE)[[1]], collapse = p[[2]])
  }
  DBI::dbExecute(con, sql)
  invisible("research.strategy_ledger")
}
