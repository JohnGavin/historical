# Record OLMAR-1's status as `inconclusive-unmeasurable` (Refs #962, #937).
#
# User decision, 2026-10-18: OLMAR-1 is `inconclusive-unmeasurable` for now.
# The writer in R/plan_olmar.R logged every build with the deprecated status
# `tested`, which records no outcome. (The original claim that no `results` row
# is linked was FALSE: see scripts/seed_olmar_status_correction.R.)
#
# Per .claude/rules/research-log-honesty.md and the append-only log, this
# script APPENDS one status row. It never edits or deletes an existing row and
# never seals (the row is a status record on a pre-existing hypothesis, not a
# pre-registration). The claim and predictor strings are read from the newest
# existing OLMAR-1 row at run time, not retyped, so the ledger groups the new
# row with the old ones; parent_uuid is that newest row.
#
# Idempotent: if a row with the same claim + predictor already has status
# `inconclusive-unmeasurable`, nothing is written.
#
# Run (repo root):
#   nix develop . --command Rscript scripts/seed_olmar_status.R
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

same_group <- olmar$economic_claim == claim & olmar$predictor == pred
if (any(same_group & olmar$status == NEW_STATUS)) {
  cat("seed_olmar_status: written=0 skipped=1\n")
  cat("  skipped (status already recorded for this claim)\n")
  quit(save = "no", status = 0L)
}

STATUS_BASIS <- paste0(
  "The deprecated status 'tested' recorded no outcome. The research log ",
  "holds no linked results row for this hypothesis (0), so no Sharpe, ",
  "deflated Sharpe or sample size is recorded. The owner chose this status ",
  "on 2026-10-18, pending a re-measurement on the issue #937 return basis. ",
  "This is not a verdict on the strategy."
)

uuid <- hd_strategy_idea_append(
  name                = pred,
  economic_claim      = claim,
  source              = paste0("owner decision 2026-10-18; ",
                               "JohnGavin/historical#937, #962"),
  priority            = NA_character_,
  asset_class         = "equity",
  issue               = 937L,
  status              = NEW_STATUS,
  parent_uuid         = newest$uuid,
  seal_omitted_reason = paste0(
    "status record appended on a pre-existing hypothesis, not a new ",
    "pre-registration; the original row's seal state is untouched"
  ),
  extra               = list(
    status_basis    = STATUS_BASIS,
    status_set_on   = "2026-10-18",
    backfill_issue  = 962L
  ),
  base_dir            = base_dir
)

cat("seed_olmar_status: written=1 skipped=0\n")
cat("  uuid:", uuid, "\n")
cat("  parent_uuid:", newest$uuid, "\n")
