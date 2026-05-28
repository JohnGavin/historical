# plan_add_signal.R — Anomaly-Driven Demand (ADD) scaffold
#
# Angle B of issue #279: ADD as a candidate signal.
# Kjær & Posselt (2025) "Anomaly-Driven Demand" — Aarhus University / DFI.
# See knowledge/wiki/anomaly-driven-demand.md for full digest.
#
# ── Multiple-testing budget NOTE (#160) ─────────────────────────────────────
#
# Before ADD is promoted to the leaderboard, its effective degree of freedom
# must be budgeted against the existing K_eff_strat count tracked in #160.
#
# ADD is a cross-sectional long/short signal derived from the 209
# Chen-Zimmermann anomalies.  Its H-L spread (Sharpe ~0.61) will be
# correlated with every other anomaly-based strategy on our leaderboard,
# since all draw from the same US equity universe.  Adding ADD without
# deflating for this correlation inflates the apparent menu size and
# overstates the expected maximum in-sample Sharpe.
#
# Required before leaderboard integration:
#   1. Compute ADD's pairwise correlation with existing leaderboard strategies
#      using their monthly return series.
#   2. Update K_eff_strat (via the SR_eff formula in plan_tail_keff.R) to
#      include ADD.
#   3. Apply the deflated Sharpe ratio threshold at the updated K_eff_strat.
#
# See also: R/plan_tail_keff.R, R/plan_falsification.R
#
# ── Pipeline overview ────────────────────────────────────────────────────────
#
# Stage 1 — source registration (no download)
#   add_dataset_meta  ← hd_register_add_dataset()
#
# Stage 2 — load quintile assignments (PLACEHOLDER — download not yet wired)
#   add_quintiles_raw ← placeholder; downstream targets depend on this
#
# Stage 3 — compute ADD
#   add_signal_tbl    ← hd_compute_add(add_quintiles_raw)
#
# Stage 4 — aggregate
#   add_composite     ← hd_aggregate_add(add_signal_tbl)
#
# ── NOT wired into plan_leaderboard.R in this PR ────────────────────────────
# Integration is a follow-up: after (a) actual dataset download, (b) K_eff
# budget, (c) falsification plan.

plan_add_signal <- function() {

  list(

    # ── Stage 1: Dataset source registration ────────────────────────────────
    #
    # Returns the metadata list from hd_register_add_dataset().
    # This target is always valid and costs nothing to re-run.
    tar_target(
      add_dataset_meta,
      hd_register_add_dataset()
    ),

    # ── Stage 2: Load quintile assignments (PLACEHOLDER) ────────────────────
    #
    # TODO: Replace this stub with real data ingestion once the Chen-Zimmermann
    # quintile CSV has been downloaded and validated.  The expected schema is:
    #   (stock, date, anomaly_id, quintile)
    # where:
    #   stock      = PERMNO or ticker identifier
    #   date       = first-of-month Date (monthly frequency)
    #   anomaly_id = one of the 209 anomaly identifiers from the dataset
    #   quintile   = integer 1-5 (1 = short, 5 = long leg)
    #
    # Source details: hd_register_add_dataset()$portal_url
    # Data coverage:  1990-01 to 2023-12 (US NYSE, AMEX, NASDAQ)
    # Look-ahead note: only post-publication anomalies count at each date.
    tar_target(
      add_quintiles_raw,
      {
        # Placeholder: returns an empty tibble with the correct schema so
        # downstream targets fail gracefully rather than with a cryptic error.
        # Remove once real ingestion is wired.
        cli::cli_inform(c(
          "i" = "add_quintiles_raw is a PLACEHOLDER target.",
          "i" = "Download Chen-Zimmermann quintile data from: {add_dataset_meta$portal_url}",
          "i" = "See hd_register_add_dataset() for schema and citation."
        ))
        tibble::tibble(
          stock      = character(),
          date       = as.Date(character()),
          anomaly_id = character(),
          quintile   = integer()
        )
      },
      packages = "tibble"
    ),

    # ── Stage 3: Compute per-anomaly ADD ────────────────────────────────────
    #
    # hd_compute_add() expects a non-empty tibble; this target will abort
    # with an informative message from hd_compute_add() when Stage 2 is
    # still a placeholder (empty tibble).
    # Un-comment the tar_skip() guard below once Stage 2 is populated.
    tar_target(
      add_signal_tbl,
      {
        if (nrow(add_quintiles_raw) == 0L) {
          cli::cli_abort(c(
            "x" = "{.target add_signal_tbl} cannot proceed: {.target add_quintiles_raw} is empty.",
            "i" = "Populate {.target add_quintiles_raw} with Chen-Zimmermann quintile data first.",
            "i" = "See {.fn hd_register_add_dataset} and issue #279."
          ))
        }
        hd_compute_add(add_quintiles_raw)
      },
      packages = c("dplyr", "tibble", "cli")
    ),

    # ── Stage 4: Aggregate to per-stock composite ADD score ─────────────────
    #
    # Collapses across all 209 anomalies to produce one ADD score per
    # (stock, month) pair.  The add_sum column is the quantity to use as the
    # trading signal: long high-add_sum, short low-add_sum stocks, with
    # rebalancing in the first ~6 trading days of the month.
    tar_target(
      add_composite,
      hd_aggregate_add(add_signal_tbl, by = "stock_date"),
      packages = c("dplyr", "tibble", "cli")
    )

  )
}
