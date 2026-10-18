# Append a row moving OLMAR-1 to `inconclusive-underpowered` (Refs #962, #937).
#
# The newest OLMAR-1 row (a correction, PR #971 lineage) kept
# `inconclusive-unmeasurable`, a status chosen on the false claim that no
# results were linked. Results exist (hypothesis -> implementation -> results),
# the return basis conforms to #937, and a detection-power analysis has now been
# run. On that evidence the honest status is `inconclusive-underpowered`: the
# point estimate is positive, but after a multiple-testing correction the sample
# is too short to detect a Sharpe of the observed size with 80% power.
#
# This script APPENDS one row. It never edits or deletes an existing row and
# never seals (a status record on a pre-existing hypothesis, not a
# pre-registration; sealing after the fact would be dishonest).
#
# What is computed here vs quoted:
#   * Computed at run time from the results table: the number of results rows,
#     their n_obs, the stored Sharpe, and years = n_obs / 252.
#   * QUOTED, not recomputed here: the detection-power, HAC, deflated-Sharpe,
#     benchmark and permutation figures. They come from a one-off analysis
#     script run on 2026-10-18 against the pipeline's stored OLMAR series; that
#     script and its output were not committed. Recomputing them needs the
#     price matrix and the nix shell, which this seeding script deliberately
#     does not load. `extra_json$metrics_source` says so on the row itself.
#   * No value is written to any `sharpe_hac` field: the stored
#     `results.sharpe_hac` for OLMAR is a naive value (#975).
#
# Idempotent: if any OLMAR-1 row of the same claim + predictor already has
# status `inconclusive-underpowered`, nothing is written.
#
# Run (repo root):
#   nix develop . --command Rscript scripts/seed_olmar_status_underpowered.R
#
# Optional first argument: a base_dir override (tests/dry runs); default is the
# tracked inst/extdata/research_log/.

pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
base_dir <- if (length(args) >= 1L) args[[1]] else NULL

OLMAR_CLAIM_PREFIX     <- "Equity prices mean-revert toward a short moving average"
OLMAR_PREDICTOR_PREFIX <- "MA/price ratio (OLMAR-1)"
OLD_STATUS <- "inconclusive-unmeasurable"
NEW_STATUS <- "inconclusive-underpowered"
FULL_PERIOD_N_OBS <- 4063L   # the rf-covered sample the leaderboard reports on

hyp <- hd_rlog_query("hypotheses", base_dir = base_dir)
olmar <- hyp[startsWith(hyp$economic_claim, OLMAR_CLAIM_PREFIX) &
               startsWith(hyp$predictor, OLMAR_PREDICTOR_PREFIX), , drop = FALSE]
if (nrow(olmar) == 0L) {
  cli::cli_abort(c(
    "x" = "No OLMAR-1 hypothesis row found in the research log.",
    "i" = "Looked for claim starting {.val {OLMAR_CLAIM_PREFIX}} and predictor starting {.val {OLMAR_PREDICTOR_PREFIX}}."
  ))
}

if (any(olmar$status == NEW_STATUS)) {
  cat("seed_olmar_status_underpowered: written=0 skipped=1\n")
  cat("  skipped (OLMAR-1 already has status", NEW_STATUS, ")\n")
  quit(save = "no", status = 0L)
}

newest <- olmar[order(olmar$timestamp, olmar$uuid, decreasing = TRUE)[1L], ,
                drop = FALSE]
if (!identical(newest$status, OLD_STATUS)) {
  cli::cli_abort(c(
    "x" = "The newest OLMAR-1 row has status {.val {newest$status}}, not {.val {OLD_STATUS}}.",
    "i" = "This script supersedes {.val {OLD_STATUS}} only."
  ))
}
claim <- newest$economic_claim
pred  <- newest$predictor

# Lineage: hypothesis -> implementation -> results.
impl <- hd_rlog_query("implementations", base_dir = base_dir)
res  <- hd_rlog_query("results", base_dir = base_dir)
impl_olmar <- impl[impl$parent_uuid %in% olmar$uuid, , drop = FALSE]
res_olmar  <- res[res$parent_uuid %in% impl_olmar$uuid, , drop = FALSE]
res_full <- res_olmar[res_olmar$n_obs == FULL_PERIOD_N_OBS, , drop = FALSE]
if (nrow(res_full) == 0L) {
  cli::cli_abort(c(
    "x" = "No OLMAR results rows with n_obs = {FULL_PERIOD_N_OBS} reachable via implementations.",
    "i" = "The underpowered status rests on that sample; it cannot be written without it."
  ))
}
stored_sharpe <- unique(round(res_full$sharpe_hac, 3L))
if (length(stored_sharpe) != 1L) {
  cli::cli_abort(c(
    "x" = "Stored Sharpe values on n_obs = {FULL_PERIOD_N_OBS} disagree: {.val {stored_sharpe}}."
  ))
}
years <- FULL_PERIOD_N_OBS / 252

STATUS_BASIS <- paste0(
  "Supersedes ", newest$uuid, " (inconclusive-unmeasurable), which was chosen ",
  "on a false claim of no linked results. The log holds ", nrow(res_full),
  " OLMAR results rows on ", FULL_PERIOD_N_OBS, " observations (",
  sprintf("%.2f", years), " years, stored Sharpe ",
  sprintf("%.2f", stored_sharpe), "). The return basis conforms to #937: ",
  "registry basis total, risk-free rate deducted, Sharpe ",
  sprintf("%.2f", stored_sharpe), " is geometric and rf-adjusted. ",
  "Quoted from a one-off analysis (see metrics_source): arithmetic excess ",
  "Sharpe 0.8117, HAC t 3.723, HAC Sharpe 0.9271. At the observed Sharpe of ",
  sprintf("%.2f", stored_sharpe), " the sample needs 10.17 years to detect it ",
  "with 80% power for one trial, but 20.52 years at the ledger trial count ",
  "(K = 14), 20.63 at the effective count (14.43) and 21.27 at K = 17, ",
  "against ", sprintf("%.2f", years), " years available. Deflated Sharpe at ",
  "K = 14 is 0.3856 (p 0.0608), matching the leaderboard. So the effect is ",
  "positive but not separable from selection across the trials, and more ",
  "data of the same kind could settle it: inconclusive-underpowered. Two ",
  "results cut against reading it as a working strategy: an equal-weight ",
  "portfolio of the same 20 tickers has a higher arithmetic excess Sharpe ",
  "(0.9504; active return -1.09%/yr, 95% CI -3.4% to +1.2%, one-sided p ",
  "0.824), and 0 of 20 signal permutations beat the actual ",
  sprintf("%.2f", stored_sharpe), " (null max 0.7097; the smallest p ",
  "attainable with 20 permutations is 0.0476). Open caveats, NOT resolved: ",
  "the older 0.883 rows are on the wrong basis (no rf), #974; ",
  "results.sharpe_hac holds a naive value, #975; the universe is 20 tickers ",
  "not 30, #976; survivorship is unverified, #977. This row is not a ",
  "verdict that the strategy works."
)

uuid <- hd_strategy_idea_append(
  name                = pred,
  economic_claim      = claim,
  source              = paste0("detection-power analysis 2026-10-18; ",
                               "supersedes ", substr(newest$uuid, 1L, 8L),
                               "; JohnGavin/historical#962, #937"),
  priority            = NA_character_,
  asset_class         = "equity",
  issue               = 962L,
  status              = NEW_STATUS,
  parent_uuid         = newest$uuid,
  seal_omitted_reason = paste0(
    "status record written after the outcome and the power analysis were ",
    "known; not a pre-registration and never sealed"
  ),
  extra               = list(
    status_basis    = STATUS_BASIS,
    status_set_on   = "2026-10-18",
    supersedes      = newest$uuid,
    metrics_source  = paste0(
      "n_obs, stored Sharpe and years computed from the results table at run ",
      "time; all other metrics QUOTED from a one-off analysis script run ",
      "2026-10-18 (not committed), not recomputed by this seeding script"
    ),
    n_obs_full      = FULL_PERIOD_N_OBS,
    years_of_data   = round(years, 2),
    return_basis    = list(
      registry_basis = "total", rf_deducted = TRUE,
      sharpe_geometric_rf_adjusted = as.numeric(stored_sharpe),
      arithmetic_excess_sharpe = 0.8117, hac_tstat = 3.723,
      hac_sharpe = 0.9271
    ),
    detection_power = list(
      years_needed_at_stored_sharpe = list(
        K1 = 10.17, K14_ledger = 20.52, k_eff_14.43 = 20.63, K17 = 21.27
      ),
      dsr_K14 = 0.3856, dsr_K14_p = 0.0608
    ),
    benchmark_equal_weight = list(
      arithmetic_excess_sharpe = 0.9504, active_return_pct_per_year = -1.09,
      active_ci95_pct = c(-3.4, 1.2), one_sided_p = 0.824
    ),
    signal_null = list(
      permutations = 20L, n_beat_actual = 0L, null_max_sharpe = 0.7097,
      smallest_attainable_p = 0.0476
    ),
    open_caveats    = c("#974 old 0.883 rows on wrong basis",
                        "#975 results.sharpe_hac holds a naive value",
                        "#976 universe is 20 tickers not 30",
                        "#977 survivorship unverified"),
    backfill_issue  = 962L
  ),
  base_dir            = base_dir
)

cat("seed_olmar_status_underpowered: written=1 skipped=0\n")
cat("  uuid:", uuid, "\n")
cat("  parent_uuid:", newest$uuid, "\n")
