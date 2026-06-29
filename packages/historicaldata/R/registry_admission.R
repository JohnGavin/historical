# Strategy Admission Registry — Pre-Registration (#496 Phase 1)
#
# Writes expected metrics at admission time into a dedicated
# `strategy_admission` table in the same registry.duckdb file.
# The pre-registered expectations can later be compared to realised metrics
# (Phase 3 / #482 expectation-vs-actual report).
#
# Table is stored in the default schema (not a sub-schema) to keep it
# accessible via the same hd_registry_open() connection.
#
# Idempotency contract (upsert-by-strategy):
#   - One row per strategy (latest admission).
#   - On re-registration: admission_uuid and admitted_at are PRESERVED from the
#     original registration, and all other fields are updated.
#   - This means re-calling hd_admission_register() updates expectations in
#     place without losing the original admission timestamp for audit purposes.

#' Idempotently create the `strategy_admission` table
#'
#' Creates the `strategy_admission` table in an existing DuckDB registry
#' connection. Safe to call on every session start — no-ops if the table
#' already exists.
#'
#' @param con A writable DBI connection from [hd_registry_open()] with
#'   `read_only = FALSE`.
#' @return Invisibly returns `TRUE`.
#' @family governance
#' @export
#' @examples
#' \dontrun{
#' con <- hd_registry_open(path = tempfile(fileext = ".duckdb"),
#'                         read_only = FALSE)
#' # hd_registry_open() requires the file to exist, so use DBI directly for
#' # temp files in examples.
#' withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
#' hd_admission_init(con)
#' }
hd_admission_init <- function(con) {
  rlang::check_installed(c("DBI", "duckdb"))
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS strategy_admission (
      admission_uuid        VARCHAR PRIMARY KEY,
      strategy              VARCHAR NOT NULL UNIQUE,
      admitted_at           TIMESTAMP,
      git_commit            VARCHAR,
      reviewer              VARCHAR,
      hypothesis            VARCHAR,
      expected_incr_sharpe  DOUBLE,
      expected_var_reduction DOUBLE,
      expected_target_regime VARCHAR,
      expected_max_corr     DOUBLE,
      gate_overall          VARCHAR,
      gate_detail_json      VARCHAR,
      override              BOOLEAN DEFAULT FALSE,
      override_reason       VARCHAR
    )
  ")
  invisible(TRUE)
}

#' Pre-register a strategy in the admission table
#'
#' Inserts or updates one row in `strategy_admission` keyed on `strategy`.
#' On re-registration of an existing strategy, `admission_uuid` and
#' `admitted_at` are **preserved** from the original row and all other
#' fields are updated. This lets callers revise expectations without losing
#' the original admission timestamp.
#'
#' If the table does not exist yet, [hd_admission_init()] is called
#' automatically.
#'
#' @param con A writable DBI connection from [hd_registry_open()] with
#'   `read_only = FALSE`.
#' @param strategy Character. Unique strategy identifier (matches
#'   `bt.strategy.strategy_id` convention but is not enforced as a FK here
#'   — Phase 2 will add the FK).
#' @param hypothesis Character. Free-text hypothesis / rationale for
#'   admission. Required.
#' @param expected A named list of pre-registered expectations:
#'   \describe{
#'     \item{incr_sharpe}{Numeric. Expected incremental Sharpe contribution.}
#'     \item{var_reduction}{Numeric. Expected annualised variance reduction.}
#'     \item{target_regime}{Character. Market regime the strategy is designed
#'       for (e.g. `"trending"`, `"mean-reverting"`, `"all-weather"`).}
#'     \item{max_corr}{Numeric. Maximum expected correlation with existing
#'       strategies.}
#'   }
#'   Missing list elements are stored as `NULL`.
#' @param reviewer Character. Name or GitHub handle of the reviewer.
#' @param gate_result Optional tibble returned by [hd_strategy_value_gate()].
#'   If supplied, `gate_overall` is extracted from `attr(gate_result, "overall")`
#'   and the full tibble is serialised to `gate_detail_json` via
#'   [jsonlite::toJSON()].
#' @param override Logical. Set `TRUE` if admitting despite a `"reject"`
#'   gate result (requires `override_reason`). Default `FALSE`.
#' @param override_reason Character. Required when `override = TRUE`. Default
#'   `NA_character_`.
#' @return Invisibly returns the `admission_uuid` (character).
#' @family governance
#' @export
#' @examples
#' \dontrun{
#' tf  <- tempfile(fileext = ".duckdb")
#' con <- DBI::dbConnect(duckdb::duckdb(), dbdir = tf)
#' withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
#' hd_admission_init(con)
#' uuid <- hd_admission_register(
#'   con       = con,
#'   strategy  = "strat_demo",
#'   hypothesis = "Trend-following in EM equities adds diversification",
#'   expected  = list(incr_sharpe = 0.10, var_reduction = 0.002,
#'                    target_regime = "trending", max_corr = 0.35),
#'   reviewer  = "john"
#' )
#' uuid
#' }
hd_admission_register <- function(
    con,
    strategy,
    hypothesis,
    expected       = list(),
    reviewer,
    gate_result    = NULL,
    override       = FALSE,
    override_reason = NA_character_) {

  rlang::check_installed(c("DBI", "duckdb"))

  if (!is.character(strategy) || length(strategy) != 1L || !nzchar(strategy)) {
    cli::cli_abort(c(
      "x" = "{.arg strategy} must be a non-empty character string.",
      "i" = "Got {.val {strategy}}."
    ))
  }
  if (!is.character(hypothesis) || length(hypothesis) != 1L) {
    cli::cli_abort("{.arg hypothesis} must be a single character string.")
  }
  if (!is.character(reviewer) || length(reviewer) != 1L || !nzchar(reviewer)) {
    cli::cli_abort(c(
      "x" = "{.arg reviewer} must be a non-empty character string.",
      "i" = "Got {.val {reviewer}}."
    ))
  }
  if (isTRUE(override) && (is.na(override_reason) || !nzchar(override_reason))) {
    cli::cli_abort(c(
      "x" = "{.arg override_reason} must be supplied when {.arg override} is TRUE.",
      "i" = "Provide a non-empty reason string."
    ))
  }

  # Ensure table exists
  hd_admission_init(con)

  # Extract expected values
  exp_incr_sharpe  <- expected[["incr_sharpe"]]   %||% NA_real_
  exp_var_reduc    <- expected[["var_reduction"]]  %||% NA_real_
  exp_regime       <- expected[["target_regime"]]  %||% NA_character_
  exp_max_corr     <- expected[["max_corr"]]       %||% NA_real_

  # Gate result processing
  gate_overall_val     <- NA_character_
  gate_detail_json_val <- NA_character_
  if (!is.null(gate_result)) {
    rlang::check_installed("jsonlite")
    gate_overall_val     <- attr(gate_result, "overall")  %||% NA_character_
    gate_detail_json_val <- jsonlite::toJSON(
      as.data.frame(gate_result),
      auto_unbox = TRUE
    )
  }

  # Look up existing row to preserve admission_uuid + admitted_at
  existing <- DBI::dbGetQuery(
    con,
    "SELECT admission_uuid, admitted_at FROM strategy_admission WHERE strategy = ?",
    params = list(strategy)
  )

  if (nrow(existing) > 0L) {
    # Update path — preserve original uuid + admitted_at
    admission_uuid <- existing$admission_uuid[[1L]]
    DBI::dbExecute(
      con,
      "UPDATE strategy_admission
         SET git_commit             = ?,
             reviewer               = ?,
             hypothesis             = ?,
             expected_incr_sharpe   = ?,
             expected_var_reduction = ?,
             expected_target_regime = ?,
             expected_max_corr      = ?,
             gate_overall           = ?,
             gate_detail_json       = ?,
             override               = ?,
             override_reason        = ?
       WHERE strategy = ?",
      params = list(
        .resolve_git_sha(),
        reviewer,
        hypothesis,
        exp_incr_sharpe,
        exp_var_reduc,
        exp_regime,
        exp_max_corr,
        gate_overall_val,
        gate_detail_json_val,
        isTRUE(override),
        if (is.na(override_reason)) NA_character_ else override_reason,
        strategy
      )
    )
  } else {
    # Insert path — generate new uuid
    admission_uuid <- .new_uuid()
    DBI::dbExecute(
      con,
      "INSERT INTO strategy_admission (
         admission_uuid, strategy, admitted_at, git_commit,
         reviewer, hypothesis,
         expected_incr_sharpe, expected_var_reduction,
         expected_target_regime, expected_max_corr,
         gate_overall, gate_detail_json,
         override, override_reason
       ) VALUES (?, ?, CURRENT_TIMESTAMP, ?,
                 ?, ?,
                 ?, ?,
                 ?, ?,
                 ?, ?,
                 ?, ?)",
      params = list(
        admission_uuid, strategy, .resolve_git_sha(),
        reviewer, hypothesis,
        exp_incr_sharpe, exp_var_reduc,
        exp_regime, exp_max_corr,
        gate_overall_val, gate_detail_json_val,
        isTRUE(override),
        if (is.na(override_reason)) NA_character_ else override_reason
      )
    )
  }

  invisible(admission_uuid)
}

#' Read the strategy admission table
#'
#' Returns the full `strategy_admission` table as a tibble. Opens a read-only
#' connection if `con` is not supplied.
#'
#' @param con Optional DBI connection. If `NULL` (default), opens a read-only
#'   connection to `path` and closes it on exit.
#' @param path Path to the registry DuckDB file. Defaults to
#'   [hd_registry_path()]. Ignored when `con` is supplied.
#' @return A tibble with one row per registered strategy and columns as defined
#'   in [hd_admission_init()]. Returns a zero-row tibble if the table has never
#'   been initialised.
#' @family governance
#' @export
#' @examples
#' \dontrun{
#' # Read against the default registry
#' hd_admission_read()
#' }
hd_admission_read <- function(con = NULL, path = hd_registry_path()) {
  rlang::check_installed(c("DBI", "duckdb"))

  own_con <- is.null(con)
  if (own_con) {
    if (!file.exists(path)) {
      # Return empty tibble with correct schema
      return(tibble::tibble(
        admission_uuid         = character(),
        strategy               = character(),
        admitted_at            = as.POSIXct(character()),
        git_commit             = character(),
        reviewer               = character(),
        hypothesis             = character(),
        expected_incr_sharpe   = double(),
        expected_var_reduction = double(),
        expected_target_regime = character(),
        expected_max_corr      = double(),
        gate_overall           = character(),
        gate_detail_json       = character(),
        override               = logical(),
        override_reason        = character()
      ))
    }
    con <- hd_registry_open(path, read_only = TRUE)
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  }

  tbl_exists <- tryCatch(
    {
      DBI::dbGetQuery(
        con,
        "SELECT 1 FROM information_schema.tables
         WHERE table_name = 'strategy_admission' LIMIT 1"
      )
    },
    error = function(e) data.frame()
  )

  if (nrow(tbl_exists) == 0L) {
    return(tibble::tibble(
      admission_uuid         = character(),
      strategy               = character(),
      admitted_at            = as.POSIXct(character()),
      git_commit             = character(),
      reviewer               = character(),
      hypothesis             = character(),
      expected_incr_sharpe   = double(),
      expected_var_reduction = double(),
      expected_target_regime = character(),
      expected_max_corr      = double(),
      gate_overall           = character(),
      gate_detail_json       = character(),
      override               = logical(),
      override_reason        = character()
    ))
  }

  tibble::as_tibble(
    DBI::dbGetQuery(con, "SELECT * FROM strategy_admission ORDER BY admitted_at")
  )
}

# ── Notes on shared helpers ───────────────────────────────────────────────────
# .new_uuid() and .resolve_git_sha() are defined in registry_writers.R and
# shared within the package. No redefinition needed here.
#
# %||% is imported from rlang (see NAMESPACE importFrom(rlang, "%||%")).
# No local definition needed.
