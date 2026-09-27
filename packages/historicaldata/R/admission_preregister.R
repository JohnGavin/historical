# Strategy Admission Pre-Registration via the Research Log (#496, supersedes PR #511)
#
# PR #511 added a bespoke `strategy_admission` table (registry_admission.R)
# whose upsert-by-strategy silently overwrote expectations on re-registration
# with no seal and no audit trail -- exactly the "resulting"/post-hoc
# rationalisation failure pre-registration exists to prevent (see
# .claude/rules/research-log-honesty.md and .claude/rules/resulting-prohibition.md).
#
# This module records a strategy-admission hypothesis as a `hypotheses` row
# in the EXISTING research-log store (research_log.R, research_log_seal.R)
# instead: sealed at inception via hd_rlog_seal(), append-only (no upsert, no
# UPDATE statement anywhere in this file), and a revision is a NEW row whose
# parent_uuid links back to the sealed row it revises -- never a silent
# overwrite. See #902 for the additional counterparty/kill_criterion fields.
#
# Field mapping onto the `hypotheses` schema (research_log.R):
#   economic_claim  -- the admission hypothesis (free text rationale)
#   dependent_var   -- fixed: "portfolio_incremental_sharpe" (what admission
#                      is actually a claim about -- the PORTFOLIO's
#                      risk-adjusted return, not the candidate's own return)
#   predictor       -- the candidate strategy identifier
#   sample_spec     -- the expected target regime (where a value was
#                      supplied) -- the closest existing field to "what
#                      regime/sample this hypothesis is scoped to"
#   null_hypothesis -- fixed, standard null for this hypothesis class
#   status          -- hd_rlog_statuses() vocabulary; "proposed" at
#                      pre-registration time
#   extra_json      -- everything the hypotheses schema has no column for:
#                      reviewer, expected_incr_sharpe, expected_var_reduction,
#                      expected_target_regime, expected_max_corr,
#                      counterparty (#902), kill_criterion (#902),
#                      expected_sharpe + its detection-power requirement,
#                      and the gate_result (if supplied), tagged
#                      kind = "strategy_admission" so hd_admission_read() can
#                      find these rows among all other hypotheses.

# ── Private helpers ──────────────────────────────────────────────────────────

.admission_empty_tibble <- function() {
  tibble::tibble(
    uuid                    = character(),
    parent_uuid             = character(),
    strategy                = character(),
    hypothesis              = character(),
    status                  = character(),
    commit_hash             = character(),
    sealed_at               = as.POSIXct(character()),
    admitted_at             = as.POSIXct(character()),
    reviewer                = character(),
    counterparty            = character(),
    kill_criterion          = character(),
    expected_incr_sharpe    = double(),
    expected_var_reduction  = double(),
    expected_target_regime  = character(),
    expected_max_corr       = double(),
    expected_sharpe         = double(),
    min_n_years             = double(),
    min_n_years_corrected   = double(),
    gate_overall            = character()
  )
}

# Pull one field out of a parsed extra_json list, or NA of the right type.
.admission_field <- function(parsed, field, na_value) {
  vapply(parsed, function(x) {
    v <- if (is.null(x)) NULL else x[[field]]
    if (is.null(v) || length(v) == 0L || (is.character(v) && !nzchar(v))) {
      na_value
    } else {
      v[[1]]
    }
  }, na_value)
}

# ── Writer ────────────────────────────────────────────────────────────────────

#' Pre-register a strategy-admission hypothesis in the research log
#'
#' Records a candidate strategy's admission hypothesis as a SEALED
#' (see [hd_rlog_seal()]) row in the research log's `hypotheses` table,
#' following [research-log-honesty](../../../.claude/rules/research-log-honesty.md):
#' sealed at inception, before any outcome is known, and never silently
#' overwritten. If a SEALED admission hypothesis already exists for
#' `strategy`, this function aborts unless `revises = TRUE`, in which case
#' the new row's `parent_uuid` links back to the prior sealed row -- a
#' revision is always a new, linked row, never an edit to the old one (the
#' research log is append-only in any case: there is no UPDATE path here).
#'
#' @param strategy Character. Unique strategy identifier (matches
#'   `strategy_names$code_name` convention).
#' @param hypothesis Character. Free-text rationale for admission (evidence,
#'   not outcome -- see `.claude/rules/resulting-prohibition.md`).
#' @param expected A named list of pre-registered expectations:
#'   \describe{
#'     \item{incr_sharpe}{Numeric. Expected incremental Sharpe contribution.}
#'     \item{var_reduction}{Numeric. Expected annualised variance reduction.}
#'     \item{target_regime}{Character. Market regime the strategy is designed
#'       for (e.g. `"trending"`, `"mean-reverting"`, `"all-weather"`).}
#'     \item{max_corr}{Numeric. Maximum expected correlation with existing
#'       strategies.}
#'   }
#'   Missing list elements are stored as `NA`.
#' @param reviewer Character. Name or GitHub handle of the reviewer. Required.
#' @param counterparty Character. Who is expected to be on the other side of
#'   this trade, and why they are willing to give up the edge (#902 row 5 --
#'   "If I can't name the mechanism and the counterparty, I don't have an
#'   edge"). Default `NA_character_`.
#' @param kill_criterion Character. A machine-checkable condition under which
#'   this strategy should be withdrawn, stated BEFORE admission (#902 row 9).
#'   Default `NA_character_`.
#' @param expected_sharpe Numeric scalar > 0, or `NA_real_` (default). The
#'   Sharpe ratio this strategy is expected to deliver. When supplied,
#'   [hd_detection_power()] is called to compute the sample (in years) that
#'   would be needed to detect it, recorded alongside the expectation --
#'   `.claude/rules/detection-power-required.md` requirement 4: state the
#'   required sample BEFORE backtesting, not after.
#' @param ann_factor Numeric. Periods per year, passed to
#'   [hd_detection_power()] when `expected_sharpe` is supplied. Default `12`.
#' @param n_tests,correction Passed to [hd_detection_power()]'s
#'   multiple-testing correction. Defaults `1`, `"none"`.
#' @param target_power Passed to [hd_detection_power()]. Default `0.80`.
#' @param gate_result Optional tibble returned by [hd_strategy_value_gate()].
#'   If supplied, its `attr(gate_result, "overall")` is recorded and the full
#'   tibble is serialised into `extra_json` via [jsonlite::toJSON()].
#' @param revises Logical. Must be `TRUE` to pre-register a strategy that
#'   already has a SEALED admission hypothesis -- see Details. Default
#'   `FALSE`.
#' @param base_dir Override research-log base directory (see
#'   [hd_rlog_path()]).
#' @param seal Logical. Seal the new row immediately via [hd_rlog_seal()].
#'   Default `TRUE`. Set `FALSE` only for genuinely provisional drafts that
#'   are not yet a real pre-registration.
#'
#' @return Invisibly returns the new row's `uuid` (character).
#' @family governance
#' @export
#' @examples
#' \dontrun{
#' hd_admission_preregister(
#'   strategy       = "trend_em",
#'   hypothesis     = "Adds trend-following diversification in EM; uncorrelated with value tilt",
#'   expected       = list(incr_sharpe = 0.08, var_reduction = 0.002,
#'                         target_regime = "trending", max_corr = 0.35),
#'   reviewer       = "john",
#'   counterparty   = "EM local funds forced to de-risk into drawdowns",
#'   kill_criterion = "trailing 36-month incremental Sharpe <= 0",
#'   expected_sharpe = 0.6
#' )
#' }
hd_admission_preregister <- function(
    strategy,
    hypothesis,
    expected        = list(),
    reviewer,
    counterparty    = NA_character_,
    kill_criterion  = NA_character_,
    expected_sharpe = NA_real_,
    ann_factor      = 12,
    n_tests         = 1,
    correction      = c("none", "bonferroni"),
    target_power    = 0.80,
    gate_result     = NULL,
    revises         = FALSE,
    base_dir        = NULL,
    seal            = TRUE) {

  correction <- match.arg(correction)

  if (!is.character(strategy) || length(strategy) != 1L || !nzchar(strategy)) {
    cli::cli_abort(c(
      "x" = "{.arg strategy} must be a non-empty character string.",
      "i" = "Got {.val {strategy}}."
    ))
  }
  if (!is.character(hypothesis) || length(hypothesis) != 1L || !nzchar(hypothesis)) {
    cli::cli_abort(c(
      "x" = "{.arg hypothesis} must be a non-empty character string.",
      "i" = "Got {.val {hypothesis}}."
    ))
  }
  if (missing(reviewer) || !is.character(reviewer) || length(reviewer) != 1L || !nzchar(reviewer)) {
    cli::cli_abort(c(
      "x" = "{.arg reviewer} must be a non-empty character string.",
      "i" = "Got {.val {reviewer}}."
    ))
  }

  # ── Sealed-claim guard: never silently overwrite (research-log-honesty) ──
  existing <- hd_admission_read(strategy = strategy, base_dir = base_dir)
  parent_uuid <- NA_character_
  if (nrow(existing) > 0L) {
    sealed_existing <- existing[!is.na(existing$commit_hash) & nzchar(existing$commit_hash), , drop = FALSE]
    if (nrow(sealed_existing) > 0L) {
      if (!isTRUE(revises)) {
        latest <- sealed_existing[order(sealed_existing$sealed_at), ][nrow(sealed_existing), ]
        cli::cli_abort(c(
          "x" = "A sealed admission hypothesis already exists for strategy {.val {strategy}}.",
          "i" = "Sealed at {.val {format(latest$sealed_at)}}; uuid {.val {latest$uuid}}.",
          "i" = paste0(
            "Pass {.arg revises} = TRUE to record this as a NEW row that links back to ",
            "the sealed claim -- a sealed hypothesis is never silently overwritten ",
            "(.claude/rules/research-log-honesty.md)."
          )
        ))
      }
      latest <- sealed_existing[order(sealed_existing$sealed_at), ][nrow(sealed_existing), ]
      parent_uuid <- latest$uuid
    }
  }

  # ── Expected-metric extraction ────────────────────────────────────────────
  exp_incr_sharpe <- expected[["incr_sharpe"]]    %||% NA_real_
  exp_var_reduc   <- expected[["var_reduction"]]  %||% NA_real_
  exp_regime      <- expected[["target_regime"]]  %||% NA_character_
  exp_max_corr    <- expected[["max_corr"]]       %||% NA_real_

  # ── Detection power on the EXPECTED Sharpe (requirement 4: state the
  # required sample BEFORE backtesting) ─────────────────────────────────────
  detection <- NULL
  if (!is.na(expected_sharpe)) {
    if (!is.numeric(expected_sharpe) || expected_sharpe <= 0) {
      cli::cli_abort(c(
        "x" = "{.arg expected_sharpe} must be NA or a single positive number.",
        "i" = "Got {.val {expected_sharpe}}."
      ))
    }
    detection <- hd_detection_power(
      sharpe_annual = expected_sharpe,
      ann_factor    = ann_factor,
      target_power  = target_power,
      n_tests       = n_tests,
      correction    = correction
    )
  }

  gate_overall <- NA_character_
  gate_json    <- NULL
  if (!is.null(gate_result)) {
    rlang::check_installed("jsonlite")
    gate_overall <- attr(gate_result, "overall") %||% NA_character_
    gate_json    <- jsonlite::toJSON(as.data.frame(gate_result), auto_unbox = TRUE)
  }

  rlang::check_installed("jsonlite")
  extra <- list(
    kind                    = "strategy_admission",
    reviewer                = reviewer,
    counterparty            = counterparty,
    kill_criterion          = kill_criterion,
    expected_incr_sharpe    = exp_incr_sharpe,
    expected_var_reduction  = exp_var_reduc,
    expected_target_regime  = exp_regime,
    expected_max_corr       = exp_max_corr,
    expected_sharpe         = expected_sharpe,
    detection_min_n_years   = if (is.null(detection)) NA_real_ else detection$min_n_years,
    detection_min_n_years_corrected = if (is.null(detection)) NA_real_ else detection$min_n_years_corrected,
    detection_n_tests       = if (is.null(detection)) NA_real_ else detection$n_tests,
    detection_correction    = if (is.null(detection)) NA_character_ else detection$correction,
    gate_overall            = gate_overall,
    gate_detail_json        = if (is.null(gate_json)) NA_character_ else as.character(gate_json)
  )

  row <- tibble::tibble(
    uuid            = hd_rlog_uuid(),
    parent_uuid     = parent_uuid,
    economic_claim  = hypothesis,
    dependent_var   = "portfolio_incremental_sharpe",
    predictor       = strategy,
    sample_spec     = exp_regime,
    null_hypothesis = paste0(
      "Candidate strategy '", strategy, "' adds no incremental value to the ",
      "existing portfolio (incremental Sharpe <= 0, no diversification benefit)."
    ),
    status          = "proposed",
    extra_json      = as.character(jsonlite::toJSON(extra, auto_unbox = TRUE, null = "null", na = "null"))
  )

  if (isTRUE(seal)) {
    row <- hd_rlog_seal(row)
  }

  hd_rlog_append("hypotheses", row, base_dir = base_dir)

  invisible(row$uuid[[1]])
}

# ── Reader ────────────────────────────────────────────────────────────────────

#' Read strategy-admission pre-registrations from the research log
#'
#' Returns every `hypotheses` row written by [hd_admission_preregister()]
#' (identified by `extra_json$kind == "strategy_admission"`), with the
#' admission-specific fields unpacked into columns. A strategy that has been
#' revised (see [hd_admission_preregister()]'s `revises` argument) appears
#' as multiple rows linked via `parent_uuid` -- this function returns ALL of
#' them (oldest first); pass `strategy` to filter, or take the last row per
#' `strategy` for "current" expectations.
#'
#' @param strategy Optional character scalar. If supplied, returns only rows
#'   for this strategy.
#' @param base_dir Override research-log base directory (see
#'   [hd_rlog_path()]).
#' @return A tibble, one row per pre-registration, oldest first. Zero rows
#'   (with the correct columns) if no admission hypotheses have been
#'   recorded yet.
#' @family governance
#' @export
#' @examples
#' \dontrun{
#' hd_admission_read()
#' hd_admission_read(strategy = "trend_em")
#' }
hd_admission_read <- function(strategy = NULL, base_dir = NULL) {
  rows <- tryCatch(
    hd_rlog_query("hypotheses", base_dir = base_dir),
    warning = function(w) hd_rlog_schema("hypotheses")
  )
  if (nrow(rows) == 0L) return(.admission_empty_tibble())

  rlang::check_installed("jsonlite")
  parsed <- lapply(rows$extra_json, function(x) {
    if (is.na(x) || !nzchar(x)) return(NULL)
    tryCatch(jsonlite::fromJSON(x), error = function(e) NULL)
  })
  is_admission <- vapply(parsed, function(x) {
    !is.null(x) && !is.null(x$kind) && identical(x$kind[[1]], "strategy_admission")
  }, logical(1))

  rows   <- rows[is_admission, , drop = FALSE]
  parsed <- parsed[is_admission]
  if (nrow(rows) == 0L) return(.admission_empty_tibble())

  out <- tibble::tibble(
    uuid                   = rows$uuid,
    parent_uuid            = rows$parent_uuid,
    strategy               = rows$predictor,
    hypothesis             = rows$economic_claim,
    status                 = rows$status,
    commit_hash            = rows$commit_hash,
    sealed_at              = rows$sealed_at,
    admitted_at            = rows$timestamp,
    reviewer               = .admission_field(parsed, "reviewer", NA_character_),
    counterparty           = .admission_field(parsed, "counterparty", NA_character_),
    kill_criterion         = .admission_field(parsed, "kill_criterion", NA_character_),
    expected_incr_sharpe   = as.double(.admission_field(parsed, "expected_incr_sharpe", NA_real_)),
    expected_var_reduction = as.double(.admission_field(parsed, "expected_var_reduction", NA_real_)),
    expected_target_regime = .admission_field(parsed, "expected_target_regime", NA_character_),
    expected_max_corr      = as.double(.admission_field(parsed, "expected_max_corr", NA_real_)),
    expected_sharpe        = as.double(.admission_field(parsed, "expected_sharpe", NA_real_)),
    min_n_years            = as.double(.admission_field(parsed, "detection_min_n_years", NA_real_)),
    min_n_years_corrected  = as.double(.admission_field(parsed, "detection_min_n_years_corrected", NA_real_)),
    gate_overall           = .admission_field(parsed, "gate_overall", NA_character_)
  )

  out <- out[order(out$sealed_at, out$admitted_at), ]

  if (!is.null(strategy)) {
    out <- out[!is.na(out$strategy) & out$strategy == strategy, , drop = FALSE]
  }

  tibble::as_tibble(out)
}
