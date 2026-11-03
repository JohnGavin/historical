# Append OLMAR-1's research-log lineage (Refs #968, option c).
#
# Builds (tar_make) no longer write the research log: the `olmar_research_log`
# target only PLANS the rows. This script is the one explicit, owner-run writer.
# It reads the four OLMAR inputs (olmar_metrics, olmar_params, olmar_prices,
# olmar_portfolio) from the targets store, re-plans against the log AS IT IS
# NOW (same idempotency rule as before), and appends only what is new:
#   hypothesis -> implementation -> results -> critiques + robustness
# (the two critiques and two robustness rows hang off the results row). Status
# is "testing" (never the deprecated "tested"); the hypothesis is deliberately
# unsealed (see .claude/rules/research-log-honesty.md). It never edits or
# deletes an existing row. No rows are written when the inputs are unchanged.
#
# Exit codes (a check has three outcomes, not two):
#   0  rows were appended
#   1  nothing to write: the log already holds this result (a normal no-op)
#   3  INDETERMINATE: the store, an input target, or the log could not be read;
#      nothing was written. The reason is printed.
#
# Run (repo root, after a build has produced the OLMAR targets):
#   nix develop . --command Rscript scripts/seed_olmar_research_log.R
#
# Optional arguments: 1) research-log base_dir (tests/dry runs; default is the
# tracked inst/extdata/research_log/), 2) targets store (default docs/_targets).

pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
source(here::here("R", "plan_olmar.R"))

args <- commandArgs(trailingOnly = TRUE)
base_dir <- if (length(args) >= 1L && nzchar(args[[1]])) args[[1]] else NULL
store    <- if (length(args) >= 2L) args[[2]] else here::here("docs", "_targets")

indeterminate <- function(msg) {
  cat("seed_olmar_research_log: INDETERMINATE -- ", msg, "\n", sep = "")
  cat("  nothing was written\n")
  quit(save = "no", status = 3L)
}

if (!dir.exists(store)) {
  indeterminate(paste0("targets store not found: ", store))
}

inputs <- c("olmar_metrics", "olmar_params", "olmar_prices", "olmar_portfolio")
vals <- list()
for (nm in inputs) {
  vals[[nm]] <- tryCatch(
    targets::tar_read_raw(nm, store = store),
    error = function(e) {
      indeterminate(paste0("cannot read target ", nm, ": ", conditionMessage(e)))
    }
  )
}

plan <- tryCatch(
  .olmar_research_log_plan(
    olmar_metrics   = vals$olmar_metrics,
    olmar_params    = vals$olmar_params,
    olmar_prices    = vals$olmar_prices,
    olmar_portfolio = vals$olmar_portfolio,
    base_dir        = base_dir
  ),
  error = function(e) indeterminate(paste0("cannot plan: ", conditionMessage(e)))
)

if (plan$n_pending == 0L) {
  cat("seed_olmar_research_log: written=0 (log already holds this result)\n")
  quit(save = "no", status = 1L)
}

written <- tryCatch(
  .olmar_research_log_commit(plan, base_dir = base_dir),
  error = function(e) indeterminate(paste0("cannot write: ", conditionMessage(e)))
)
cat("seed_olmar_research_log: written=", sum(written), "\n", sep = "")
for (tbl in names(written)) cat("  ", tbl, ": ", written[[tbl]], "\n", sep = "")
cat("  hyp_id:", plan$ids$hyp_id, "\n")
cat("  impl_id:", plan$ids$impl_id, "\n")
cat("  res_id:", plan$ids$res_id, "\n")
quit(save = "no", status = 0L)
