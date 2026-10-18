# Append a CORRECTION row for OLMAR-1's status (Refs #968, #962, #937).
#
# Owner decision, 2026-10-18: "keep that status with a correction note".
# The row fd0588bf (PR #967) recorded `inconclusive-unmeasurable` with a basis
# saying no results row is linked to OLMAR-1. That statement is false: the check
# joined `results` straight to the hypothesis, but results are parented on the
# IMPLEMENTATION row (hypothesis -> implementation -> results), see
# R/plan_olmar.R.
#
# This script APPENDS one row. It never edits or deletes an existing row and
# never seals (a status/correction record on a pre-existing hypothesis, not a
# pre-registration). The status stays `inconclusive-unmeasurable`. Every number
# in the basis text is read from the results table at run time; none is typed.
# Nothing is computed beyond counting rows and reading the stored values: no
# deflated Sharpe, no detection power, no return-basis re-check (#937).
#
# Idempotent: if a row of the same claim + predictor already has status
# `inconclusive-unmeasurable` AND extra_json carries `correction_of`, nothing is
# written.
#
# Run (repo root):
#   nix develop . --command Rscript scripts/seed_olmar_status_correction.R
#
# Optional first argument: a base_dir override (tests/dry runs); default is the
# tracked inst/extdata/research_log/.

pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
base_dir <- if (length(args) >= 1L) args[[1]] else NULL

OLMAR_CLAIM_PREFIX     <- "Equity prices mean-revert toward a short moving average"
OLMAR_PREDICTOR_PREFIX <- "MA/price ratio (OLMAR-1)"
NEW_STATUS <- "inconclusive-unmeasurable"

hyp <- hd_rlog_query("hypotheses", base_dir = base_dir)
olmar <- hyp[startsWith(hyp$economic_claim, OLMAR_CLAIM_PREFIX) &
               startsWith(hyp$predictor, OLMAR_PREDICTOR_PREFIX), , drop = FALSE]
if (nrow(olmar) == 0L) {
  cli::cli_abort(c(
    "x" = "No OLMAR-1 hypothesis row found in the research log.",
    "i" = "Looked for claim starting {.val {OLMAR_CLAIM_PREFIX}} and predictor starting {.val {OLMAR_PREDICTOR_PREFIX}}."
  ))
}
newest <- olmar[order(olmar$timestamp, olmar$uuid, decreasing = TRUE)[1L], ,
                drop = FALSE]
claim <- newest$economic_claim
pred  <- newest$predictor

if (!identical(newest$status, NEW_STATUS)) {
  cli::cli_abort(c(
    "x" = "The newest OLMAR-1 row has status {.val {newest$status}}, not {.val {NEW_STATUS}}.",
    "i" = "There is no earlier status row to correct; run scripts/seed_olmar_status.R first."
  ))
}

same_group <- olmar$economic_claim == claim & olmar$predictor == pred
has_correction <- vapply(olmar$extra_json, function(j) {
  !is.na(j) && !is.null(jsonlite::fromJSON(j)$correction_of)
}, logical(1L), USE.NAMES = FALSE)
if (any(same_group & olmar$status == NEW_STATUS & has_correction)) {
  cat("seed_olmar_status_correction: written=0 skipped=1\n")
  cat("  skipped (correction already recorded for this claim)\n")
  quit(save = "no", status = 0L)
}

# Lineage: hypothesis -> implementation -> results. Results are parented on the
# implementation row, never on the hypothesis.
impl <- hd_rlog_query("implementations", base_dir = base_dir)
res  <- hd_rlog_query("results", base_dir = base_dir)
impl_olmar <- impl[impl$parent_uuid %in% olmar$uuid, , drop = FALSE]
res_olmar  <- res[res$parent_uuid %in% impl_olmar$uuid, , drop = FALSE]
if (nrow(res_olmar) == 0L) {
  cli::cli_abort(c(
    "x" = "No results rows reachable from the OLMAR-1 hypotheses via implementations.",
    "i" = "A correction saying results exist cannot be written when none are found."
  ))
}

n_rows  <- nrow(res_olmar)
n_uuids <- length(unique(res_olmar$uuid))
res_olmar <- res_olmar[order(res_olmar$timestamp), , drop = FALSE]
n_obs_levels <- unique(res_olmar$n_obs)
groups <- vapply(n_obs_levels, function(k) {
  g <- res_olmar[res_olmar$n_obs == k, , drop = FALSE]
  sh <- unique(formatC(g$sharpe_hac, format = "f", digits = 3L))
  sprintf("sharpe_hac %s on n_obs %s in %d row%s (runs %s to %s)",
          paste(sh, collapse = "/"), k, nrow(g),
          if (nrow(g) == 1L) "" else "s",
          format(min(g$timestamp), "%Y-%m-%d"),
          format(max(g$timestamp), "%Y-%m-%d"))
}, character(1L))
parts <- paste(unique(res_olmar$partition), collapse = ", ")

STATUS_BASIS <- paste0(
  "CORRECTION of row ", newest$uuid, ": that row said no results row was ",
  "linked to this hypothesis and that no Sharpe or sample size was recorded. ",
  "That was wrong. It joined results straight to the hypothesis, but results ",
  "are parented on the implementation row (hypothesis, implementation, ",
  "results). Through that lineage the log holds ", n_rows, " OLMAR results ",
  "rows (", n_uuids, " distinct result uuids, partition ", parts, "): ",
  paste(groups, collapse = "; "), ". ",
  "The status ", NEW_STATUS, " is retained by the owner's explicit decision ",
  "on 2026-10-18, not because the log lacks results. Because results are ",
  "present, the status is not supported by absence of data and should be ",
  "revisited once a detection-power check and the issue #937 return-basis ",
  "check have been done; neither has been done, and no deflated Sharpe is ",
  "recorded. This row is not a verdict on the strategy."
)

uuid <- hd_strategy_idea_append(
  name                = pred,
  economic_claim      = claim,
  source              = paste0("owner decision 2026-10-18; correction of ",
                               substr(newest$uuid, 1L, 8L),
                               "; JohnGavin/historical#968, #962"),
  priority            = NA_character_,
  asset_class         = "equity",
  issue               = 968L,
  status              = NEW_STATUS,
  parent_uuid         = newest$uuid,
  seal_omitted_reason = paste0(
    "status and correction record on a pre-existing hypothesis, not a new ",
    "pre-registration; the original rows' seal state is untouched"
  ),
  extra               = list(
    status_basis    = STATUS_BASIS,
    status_set_on   = "2026-10-18",
    correction_of   = newest$uuid,
    backfill_issue  = 962L
  ),
  base_dir            = base_dir
)

cat("seed_olmar_status_correction: written=1 skipped=0\n")
cat("  uuid:", uuid, "\n")
cat("  parent_uuid:", newest$uuid, "\n")
