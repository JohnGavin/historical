# Close the two sealed BDBB R-sizing hypotheses with the outcome from run.R.
#
# CONTEXT: commit 7706205 sealed two hypotheses (BTC c0e60522, SOL
# e9357c9b) at inception with status = "proposed". commit 67ecf37 then ran
# the pre-registered test (explorations/bdbb_r_sizing/run.R) and both
# resolved to "inconclusive-underpowered" (results/decision_table.csv).
# The log currently still says "proposed" for both, which is now stale --
# per research-log-honesty.md this script closes that gap.
#
# WHAT THIS DOES AND DOES NOT DO (research-log-honesty.md):
#   - The research-log store is APPEND-ONLY. This script never edits or
#     deletes the existing sealed parquet file -- it appends a NEW row per
#     uuid.
#   - `status` is the ONLY field that differs from the existing sealed row.
#     Every claim field (economic_claim, dependent_var, predictor,
#     sample_spec, null_hypothesis) is copied byte-identical from the
#     existing sealed row -- not re-typed, not re-derived.
#   - `commit_hash`, `sealed_at`, `seal_method` are carried over UNCHANGED
#     from the existing sealed row. This script does NOT call
#     hd_rlog_seal() and does NOT pass overwrite = TRUE anywhere --
#     re-sealing a hypothesis whose outcome is already known would
#     manufacture a pre-registration timestamp that never happened, which
#     is exactly what research-log-honesty.md prohibits.
#   - After appending, hd_rlog_seal_verify() is run on the NEW rows and the
#     recomputed hash is asserted to equal the (carried-over) stored hash.
#     If it does not match, a claim field was accidentally changed --
#     this script aborts rather than "fixing" it by resealing.
#
# The status value is read from results/decision_table.csv, never
# hand-typed (reproducible-ingestion rule). Both assets currently resolve
# to "inconclusive-underpowered" across every w_low weight tested -- this
# script asserts that per-asset uniqueness rather than assuming it, so a
# future re-run with a split verdict across weights fails loudly instead
# of silently picking one.
#
# APPEND-ONLY WARNING: re-running this script appends a SECOND status-update
# row per uuid (identical content, new timestamp) -- it is not idempotent
# by design, matching hd_rlog_append()'s own append-only contract. Do not
# re-run this after it has already closed these two hypotheses unless the
# intent is genuinely to record the closure again.
#
# Run:
#   nix develop . --command Rscript explorations/bdbb_r_sizing/close_hypotheses.R

suppressPackageStartupMessages({
  library(dplyr)
})
pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)

RES <- here::here("explorations", "bdbb_r_sizing", "results")

TARGET_UUIDS <- c(
  BTC = "c0e60522-5a51-4563-a619-14b4a557779c",
  SOL = "e9357c9b-d162-4317-bd6e-960736809c69"
)

# ── 1. Read the outcome from the committed result file (never hand-typed) ──
decision_table <- readr::read_csv(
  file.path(RES, "decision_table.csv"),
  show_col_types = FALSE
)

outcome_by_asset <- decision_table |>
  dplyr::group_by(asset) |>
  dplyr::summarise(status_vals = list(unique(status)), .groups = "drop")

missing_assets <- setdiff(names(TARGET_UUIDS), outcome_by_asset$asset)
if (length(missing_assets) > 0L) {
  cli::cli_abort(c(
    "x" = "decision_table.csv has no rows for asset{?s} {.val {missing_assets}}.",
    "i" = "Run run.R first -- it produces decision_table.csv for every asset."
  ))
}

non_unique <- outcome_by_asset |>
  dplyr::filter(lengths(status_vals) != 1L)
if (nrow(non_unique) > 0L) {
  cli::cli_abort(c(
    "x" = "Asset{?s} {.val {non_unique$asset}} resolve{?s/} to more than one status across w_low weights.",
    "i" = "This script closes one hypothesis with one status per asset; a split verdict needs a human decision, not an automatic pick."
  ))
}

final_status <- setNames(
  vapply(outcome_by_asset$status_vals, `[[`, character(1), 1),
  outcome_by_asset$asset
)
final_status <- final_status[names(TARGET_UUIDS)]

cli::cli_inform(c("i" = "Outcome read from results/decision_table.csv:"))
for (asset in names(TARGET_UUIDS)) {
  cli::cli_inform(c(" " = "  {asset} ({TARGET_UUIDS[[asset]]}): {final_status[[asset]]}"))
}

# ── 2. Read the EXISTING sealed rows -- source of the carried-over fields ──
existing_hyps <- hd_rlog_query("hypotheses")
existing_target <- existing_hyps[existing_hyps$uuid %in% TARGET_UUIDS, , drop = FALSE]

missing_uuids <- setdiff(TARGET_UUIDS, existing_target$uuid)
if (length(missing_uuids) > 0L) {
  cli::cli_abort(c(
    "x" = "Sealed hypothesis uuid{?s} not found in the research log: {.val {missing_uuids}}.",
    "i" = "These must already exist (commit 7706205) before they can be closed."
  ))
}

unsealed <- existing_target |>
  dplyr::filter(is.na(commit_hash) | !nzchar(commit_hash))
if (nrow(unsealed) > 0L) {
  cli::cli_abort(c(
    "x" = "uuid{?s} {.val {unsealed$uuid}} {?has/have} no commit_hash -- {?it/they} {?was/were} never sealed.",
    "i" = "Only sealed rows can be closed by this script; seal at inception, not after the fact."
  ))
}

# Take the MOST RECENT existing row per uuid as the source of truth for the
# carried-over fields (in case a prior close already appended a row -- this
# script always closes from the latest known state, never from a stale one).
latest_existing <- existing_target |>
  dplyr::arrange(uuid, dplyr::desc(timestamp)) |>
  dplyr::distinct(uuid, .keep_all = TRUE)

# ── 3. Build the new rows: every claim + seal field carried over BYTE-
#        IDENTICAL, only status changes. Lineage columns (timestamp,
#        git_commit, sandbox_image_hash) are cleared to NA so
#        hd_rlog_append() stamps them with the CURRENT append time/commit,
#        correctly recording WHEN the closure was recorded -- this is
#        distinct from sealed_at, which stays untouched. uuid is kept
#        (same row identity); parent_uuid carried over unchanged.
asset_by_uuid <- setNames(names(TARGET_UUIDS), TARGET_UUIDS)

new_rows <- latest_existing |>
  dplyr::mutate(
    status = unname(final_status[asset_by_uuid[uuid]]),
    timestamp = as.POSIXct(NA),
    git_commit = NA_character_,
    sandbox_image_hash = NA_character_
    # economic_claim, dependent_var, predictor, sample_spec, null_hypothesis,
    # commit_hash, sealed_at, seal_method, extra_json, parent_uuid: untouched
  )

stopifnot(all(new_rows$status %in% hd_rlog_statuses()$status))

# ── 4. Verify the seal on the OLD rows BEFORE appending (sanity check that
#        nothing has drifted since sealing) ─────────────────────────────
verify_before <- hd_rlog_seal_verify(latest_existing, strict = TRUE)
cli::cli_inform(c("v" = "Pre-append seal verification: {sum(verify_before$ok)}/{nrow(verify_before)} rows OK."))

# ── 5. Append ────────────────────────────────────────────────────────────
out_path <- hd_rlog_append("hypotheses", new_rows)

# ── 6. Verify the seal on the NEWLY APPENDED rows -- recomputed hash must
#        equal the carried-over stored hash exactly, since status is
#        excluded from the hash by construction. Any mismatch means a
#        claim field was accidentally altered in this script, not a
#        legitimate change -- abort, do not reseal. ───────────────────────
reread <- hd_rlog_query("hypotheses")
appended <- reread[reread$uuid %in% TARGET_UUIDS, , drop = FALSE] |>
  dplyr::arrange(uuid, dplyr::desc(timestamp)) |>
  dplyr::distinct(uuid, .keep_all = TRUE)

verify_after <- hd_rlog_seal_verify(appended, strict = TRUE)
if (!all(verify_after$ok)) {
  cli::cli_abort(c(
    "x" = "Seal verification FAILED on the newly appended rows.",
    "i" = "A claim field changed during closure -- this must not be silently fixed by resealing."
  ))
}
cli::cli_inform(c(
  "v" = "Post-append seal verification: {sum(verify_after$ok)}/{nrow(verify_after)} rows OK -- recomputed hash == stored hash for both."
))

cli::cli_inform(c("v" = "Closed {nrow(new_rows)} hypothes{?is/es} -> {.path {out_path}}"))
print(appended[, c("uuid", "status", "commit_hash", "sealed_at")], n = 10)
