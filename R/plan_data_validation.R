# Plan: Pairwise dataset alignment regression matrix (#149 Phase 1)
#
# Builds a summary tibble of pairwise alignment probes across all registered
# datasets. Each pair is probed on Dimension 1 (date_class). Future PRs will
# extend to Dimension 2-4 (freq, value, schema) per the issue spec.
#
# cue = "always": this target re-runs on every tar_make() so new data
# sources that change type or convention are caught immediately.
#
# NOT wired into docs/_targets.R in Phase 1 — manual step after reviewing
# the registry. See #149 PR description.
#
# Probe function: probe_pairwise_alignment() in R/utils_validation.R
# Registry:       dataset_registry()            in R/dataset_registry.R

plan_data_validation <- function() {
  list(

    targets::tar_target(
      dv_pairwise_alignment_matrix,
      {
        reg <- dataset_registry()

        # All unique pairs (indices into registry rows)
        n   <- nrow(reg)
        idx <- utils::combn(seq_len(n), 2L, simplify = FALSE)

        # Probe each pair; skip pairs where both targets are excluded from
        # the live store (e.g. cb_data / cb_regime pending #145).
        # probe_pairwise_alignment() handles cache-miss gracefully.
        results <- purrr::map(idx, function(pair_idx) {
          reg_slice <- reg[pair_idx, ]
          probe_pairwise_alignment(reg_slice)
        })

        result <- dplyr::bind_rows(results)

        # Emit a summary count — informational, does not abort
        n_warn    <- sum(result$status == "warn",    na.rm = TRUE)
        n_missing <- sum(result$status == "missing", na.rm = TRUE)
        n_ok      <- sum(result$status == "ok",      na.rm = TRUE)

        if (n_warn > 0L) {
          cli::cli_warn(c(
            "!" = paste0(
              "dv_pairwise_alignment_matrix: ", n_warn, " pair{?s} flagged, ",
              n_ok, " ok, ", n_missing, " skipped (not cached)."
            ),
            "i" = "Run {.code targets::tar_read(dv_pairwise_alignment_matrix)} to inspect."
          ))
        } else {
          cli::cli_inform(c(
            "v" = paste0(
              "dv_pairwise_alignment_matrix: all ", n_ok, " probed pairs ok. ",
              n_missing, " skipped (not cached)."
            )
          ))
        }

        result
      },
      cue = targets::tar_cue(mode = "always")
    )

  )
}
