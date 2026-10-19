# Append a CORRECTION row for the stored OLMAR `sharpe_hac` values
# (Refs #974, #975, #962, #937).
#
# The tracked log holds 10 OLMAR results rows (hypothesis -> implementation ->
# results). Neither Sharpe value stored in `results.sharpe_hac` is a HAC Sharpe:
#   * 0.78 (8 rows): the naive geometric rf-adjusted Sharpe from olmar_metrics
#     (#975).
#   * 0.883 (2 rows): the arithmetic total-return Sharpe with no risk-free rate
#     deducted, over 4,093 rows. OLMAR-1 is a total-return series, so on the
#     #937 basis rf is deducted; these rows are on the wrong basis (#974).
# The log is append-only, so the rows stay as they are. This script APPENDS one
# row to the `critiques` table.
#
# Why `critiques`: it is the table for "a defect found in an existing result"
# (columns defect_class, severity, finding, cell_ref, resolved), it hangs off a
# results row via parent_uuid, and it never touches `hypotheses` (so the
# strategy ledger status is unchanged) or `results` (so no metric row, and no
# value in any `sharpe_hac` field, is created). `robustness` is for numeric
# metric_value rows; `results` would add a metric row. The critiques schema has
# no `extra_json`, so the uuids of the affected rows are carried in `finding`
# as an `affected_rows:` list of `uuid@timestamp` entries (several old rows
# share one uuid, so the timestamp is needed to tell them apart).
#
# What is computed here vs quoted:
#   * Computed at run time from the results table: the affected rows, their
#     uuids and timestamps, the two stored values, the per-value row counts and
#     the n_obs of the 0.883 rows.
#   * QUOTED, not recomputed here: the HAC t-statistic (3.723), HAC Sharpe
#     (0.9271), arithmetic excess Sharpe (0.8117) and geometric rf-adjusted
#     Sharpe (0.78). They come from a one-off analysis run on 2026-10-18 against
#     the pipeline's stored OLMAR series (output not committed). Recomputing
#     them needs the price matrix and the nix shell, which this seeding script
#     deliberately does not load. The 0.9271 is hac_tstat * sqrt(252 / 4063).
#   * No value is written to any `sharpe_hac` field.
#
# Idempotent: if a critique of defect_class `metric-basis` already hangs off any
# OLMAR results row, nothing is written.
#
# Run (repo root):
#   nix develop . --command Rscript scripts/seed_olmar_results_correction.R
#
# Optional first argument: a base_dir override (tests/dry runs); default is the
# tracked inst/extdata/research_log/.

pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
base_dir <- if (length(args) >= 1L) args[[1]] else NULL

OLMAR_CLAIM_PREFIX     <- "Equity prices mean-revert toward a short moving average"
OLMAR_PREDICTOR_PREFIX <- "MA/price ratio (OLMAR-1)"
DEFECT_CLASS <- "metric-basis"
NAIVE_GEOMETRIC <- 0.78    # stored by the current-basis rows
NO_RF_ARITHMETIC <- 0.883  # stored by the wrong-basis rows

hyp <- hd_rlog_query("hypotheses", base_dir = base_dir)
olmar <- hyp[startsWith(hyp$economic_claim, OLMAR_CLAIM_PREFIX) &
               startsWith(hyp$predictor, OLMAR_PREDICTOR_PREFIX), , drop = FALSE]
if (nrow(olmar) == 0L) {
  cli::cli_abort(c(
    "x" = "No OLMAR-1 hypothesis row found in the research log.",
    "i" = "Looked for claim starting {.val {OLMAR_CLAIM_PREFIX}} and predictor starting {.val {OLMAR_PREDICTOR_PREFIX}}."
  ))
}

# Lineage: hypothesis -> implementation -> results. Results are parented on the
# implementation row, never on the hypothesis.
impl <- hd_rlog_query("implementations", base_dir = base_dir)
res  <- hd_rlog_query("results", base_dir = base_dir)
crit <- hd_rlog_query("critiques", base_dir = base_dir)
impl_olmar <- impl[impl$parent_uuid %in% olmar$uuid, , drop = FALSE]
res_olmar  <- res[res$parent_uuid %in% impl_olmar$uuid &
                    res$strategy_id == "olmar", , drop = FALSE]
if (nrow(res_olmar) == 0L) {
  cli::cli_abort(c(
    "x" = "No OLMAR results rows reachable from the OLMAR-1 hypotheses via implementations.",
    "i" = "A correction of stored Sharpe values cannot be written when none are found."
  ))
}

if (any(crit$defect_class == DEFECT_CLASS &
          crit$parent_uuid %in% res_olmar$uuid)) {
  cat("seed_olmar_results_correction: written=0 skipped=1\n")
  cat("  skipped (a", DEFECT_CLASS, "critique already hangs off an OLMAR results row)\n")
  quit(save = "no", status = 0L)
}

# Every stored value must be one of the two known ones; anything else means the
# premise of this correction is out of date and it must not be written blind.
stored <- round(res_olmar$sharpe_hac, 3L)
unknown <- setdiff(unique(stored), c(NAIVE_GEOMETRIC, NO_RF_ARITHMETIC))
if (length(unknown) > 0L || anyNA(stored)) {
  cli::cli_abort(c(
    "x" = "OLMAR results rows hold sharpe_hac values other than {.val {c(NAIVE_GEOMETRIC, NO_RF_ARITHMETIC)}}: {.val {unknown}}.",
    "i" = "This correction describes exactly those two values; re-audit before writing."
  ))
}

res_olmar <- res_olmar[order(res_olmar$timestamp, res_olmar$uuid), , drop = FALSE]
stored <- round(res_olmar$sharpe_hac, 3L)
geo <- res_olmar[stored == NAIVE_GEOMETRIC, , drop = FALSE]
arith <- res_olmar[stored == NO_RF_ARITHMETIC, , drop = FALSE]
n_total <- nrow(res_olmar)
n_geo <- nrow(geo)
n_arith <- nrow(arith)
arith_n_obs <- unique(arith$n_obs)
if (n_arith > 0L && length(arith_n_obs) != 1L) {
  cli::cli_abort(c(
    "x" = "The {.val {NO_RF_ARITHMETIC}} rows disagree on n_obs: {.val {arith_n_obs}}."
  ))
}

# The newest results row (by timestamp, uuid as tie-break) is the parent.
newest <- res_olmar[nrow(res_olmar), , drop = FALSE]

row_ref <- function(d) {
  paste0(d$uuid, "@", format(d$timestamp, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
}
geo_refs   <- row_ref(geo)
arith_refs <- row_ref(arith)

FINDING <- paste0(
  "CORRECTION of the stored OLMAR sharpe_hac values; the ", n_total,
  " results rows are append-only and are left unchanged. Neither stored ",
  "value is a HAC Sharpe. (1) ", n_geo, " rows hold ",
  sprintf("%.2f", NAIVE_GEOMETRIC), " in sharpe_hac. That is the naive ",
  "geometric rf-adjusted Sharpe (CAGR minus mean rf, over volatility), not a ",
  "HAC Sharpe ([#975](https://github.com/JohnGavin/historical/issues/975)). ",
  "The HAC Sharpe on the same series is 0.9271 (HAC t 3.723 times ",
  "sqrt(252/4063)); quoted from a one-off analysis of 2026-10-18, not ",
  "recomputed by this script. (2) ", n_arith, " rows hold ",
  sprintf("%.3f", NO_RF_ARITHMETIC), " in sharpe_hac. That is the arithmetic ",
  "total-return Sharpe with no risk-free rate deducted, over ",
  paste(arith_n_obs, collapse = "/"), " rows. OLMAR-1 is a total-return ",
  "series, so on the #937 basis rf is deducted; the comparable figures are ",
  "0.8117 (arithmetic, excess) and ", sprintf("%.2f", NAIVE_GEOMETRIC),
  " (geometric, excess), both quoted from the same analysis. Those rows are ",
  "on the wrong basis ",
  "([#974](https://github.com/JohnGavin/historical/issues/974)). The writer ",
  "fix is in [PR #979](https://github.com/JohnGavin/historical/pull/979): ",
  "new results rows carry the HAC value. Read the stored column as: ",
  sprintf("%.2f", NAIVE_GEOMETRIC), " = naive geometric rf-adjusted; ",
  sprintf("%.3f", NO_RF_ARITHMETIC), " = arithmetic, no rf. Tracked under ",
  "[#962](https://github.com/JohnGavin/historical/issues/962). This row is ",
  "not a verdict on the strategy. ",
  "affected_rows (uuid@timestamp), naive_geometric_", sprintf("%.2f", NAIVE_GEOMETRIC),
  " [", n_geo, "]: ", paste(geo_refs, collapse = ", "),
  "; arithmetic_no_rf_", sprintf("%.3f", NO_RF_ARITHMETIC),
  " [", n_arith, "]: ", paste(arith_refs, collapse = ", "), "."
)

invisible(hd_rlog_append("critiques", tibble::tibble(
  parent_uuid  = newest$uuid,
  defect_class = DEFECT_CLASS,
  severity     = "major",
  finding      = FINDING,
  cell_ref     = paste0("results:strategy_id=olmar (", n_total,
                        " rows); sharpe_hac"),
  resolved     = FALSE
), base_dir = base_dir))

# hd_rlog_append() returns the written path; report the new row's uuid.
new_rows <- hd_rlog_query("critiques", base_dir = base_dir)
new_row <- new_rows[new_rows$defect_class == DEFECT_CLASS &
                      new_rows$parent_uuid == newest$uuid, , drop = FALSE]
cat("seed_olmar_results_correction: written=1 skipped=0\n")
cat("  uuid:", new_row$uuid[[1]], "\n")
cat("  parent_uuid:", newest$uuid, "\n")
cat("  affected_rows:", n_total, "(", n_geo, "x naive geometric,", n_arith,
    "x arithmetic no-rf )\n")
