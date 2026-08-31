# Plan: Live leverage sigma_target computation (#635)
#
# #635 derived sigma_target -- the per-strategy volatility target that sets
# G_i = sigma_target / vol_per_unit_gross_i -- by hand, in an issue comment,
# FOUR separate times (2026-08-05, 2026-08-18, 2026-08-22, 2026-08-23), each
# time re-typing the same arithmetic against a fresh `tar_read(leaderboard)`
# snapshot. Three of those four derivations were invalidated by a data-
# quality bug discovered AFTER the number had been posted and, in two cases,
# provisionally adopted (#641 truncated PSO Optimal; #717 CMR annualised at
# the wrong factor; #722 CMR's risk-free rate inherited the wrong constant).
# Each time the arithmetic was correct and an input was wrong -- see the
# issue's own "Nth derivation of this number" table.
#
# This plan closes that loop: sigma_target is now a `targets` target,
# computed directly from `leaderboard` (R/plan_leaderboard.R) and
# `strategy_gross_convention` (R/plan_exposure.R, already joined into
# `leaderboard`). The NEXT time an upstream data bug changes `vol` or
# `gross_convention`, this number moves automatically on the next
# `tar_make()` instead of requiring a fifth manual re-derivation.
#
# ── Definition: budget-neutral sigma_target ─────────────────────────────────
# #635's Option B ("anchor on the book's current realised volatility") could
# not be executed as originally framed -- the only whole-book return series
# in the pipeline is `PSO Optimal`, and per-strategy `vol`/`gross_convention`
# are what #635's own recommendation actually needs (a PER-STRATEGY target,
# not a book-level one -- see G_i = sigma_target / vol_per_unit_gross_i).
# The adopted substitute, unchanged since #635's 2026-08-05 decision comment,
# is the level at which introducing the control changes NO strategy's gross
# budget on day one:
#
#   sigma_target such that  sum(G_i) == sum(gross_convention_i)
#
# Since G_i = sigma_target / vol_per_unit_gross_i = sigma_target * gross_i / vol_i,
# solving for sigma_target:
#
#   sigma_target = sum(gross_convention_i) / sum(gross_convention_i / vol_i)
#
# This is a GROSS-BUDGET-NEUTRALITY statement, not a book-volatility claim --
# it ignores cross-strategy correlation entirely (see #635's repeated
# caveat: "do not quote this as the book's volatility anywhere"). The
# genuine book-level anchor is `tar_read(port_metrics)` / PSO Optimal's own
# vol (~6.6% at last measurement) and is a separate, already-live figure.
#
# `is_cap` rows (Managed Futures, TOM, Risk State, Avoid Worst -- see
# R/plan_exposure.R) are INCLUDED in this sum, matching every one of #635's
# four manual derivations: excluding them was never how the historical
# figure was computed, only the *interpretation* of their resulting implied
# G_i was flagged as understated. `Value (HML)` and `PSO Optimal` are
# excluded by construction -- both carry NA `gross_convention` (no explicit
# weight vector to measure; see R/plan_exposure.R header).
#
# ── Regime check (#635 DoD item 7) ──────────────────────────────────────────
# `leverage_regime_stress_ratio` reproduces the Training-vs-Testing stress
# ratio table #635's 2026-08-05/08-18 comments computed by hand
# (vol_per_unit_gross in the Testing partition divided by the Training
# partition, per strategy) as a live target, so it re-derives automatically
# alongside sigma_target rather than needing a matching manual re-run every
# time an upstream fix (#717, #722, #667) changes the underlying vol.

# compute_vol_per_unit_gross(): per-(strategy, period) vol_per_unit_gross =
# vol / gross_convention, restricted to rows with a measurable
# gross_convention (excludes Value (HML) and PSO Optimal, both NA by
# construction) and a non-NA vol. `is_cap` is carried through unchanged so
# downstream consumers can flag ceiling rows as understated per #635/#626.
compute_vol_per_unit_gross <- function(leaderboard_df,
                                        periods = c("Training", "Testing", "Full Period")) {
  if (!is.data.frame(leaderboard_df)) {
    cli::cli_abort(c(
      "x" = "{.arg leaderboard_df} must be a data frame, not {.cls {class(leaderboard_df)}}.",
      "i" = "compute_vol_per_unit_gross() expects the {.field leaderboard} target."
    ))
  }
  required_cols <- c("strategy", "period", "vol", "gross_convention", "is_cap")
  missing_cols <- setdiff(required_cols, names(leaderboard_df))
  if (length(missing_cols) > 0) {
    cli::cli_abort(c(
      "x" = "{.arg leaderboard_df} is missing required column{?s}: {.field {missing_cols}}.",
      "i" = "compute_vol_per_unit_gross() needs {.field {required_cols}}."
    ))
  }

  leaderboard_df |>
    dplyr::filter(
      period %in% periods,
      !is.na(gross_convention),
      gross_convention > 0,
      !is.na(vol)
    ) |>
    dplyr::transmute(
      strategy,
      period,
      vol,
      gross_convention,
      is_cap,
      vol_per_unit_gross = vol / gross_convention
    ) |>
    dplyr::arrange(period, vol_per_unit_gross)
}

# compute_budget_neutral_sigma(): sigma_target per partition, defined so that
# sum(G_i) == sum(gross_convention_i) within that partition -- see the plan
# header derivation. `is_headline` flags the Full Period row: that is the
# figure #635 adopted (0.1354 at the 2026-08-23 hand derivation) and the one
# any consumer citing "sigma_target" should read.
compute_budget_neutral_sigma <- function(vpug_df) {
  required_cols <- c("period", "vol", "gross_convention", "vol_per_unit_gross")
  missing_cols <- setdiff(required_cols, names(vpug_df))
  if (length(missing_cols) > 0) {
    cli::cli_abort(c(
      "x" = "{.arg vpug_df} is missing required column{?s}: {.field {missing_cols}}.",
      "i" = "compute_budget_neutral_sigma() needs {.field {required_cols}} (see compute_vol_per_unit_gross())."
    ))
  }
  if (nrow(vpug_df) == 0) {
    cli::cli_abort(c(
      "x" = "{.arg vpug_df} has zero rows.",
      "i" = "No strategy has a measurable gross_convention -- check the {.field leaderboard} and {.field strategy_gross_convention} targets."
    ))
  }

  vpug_df |>
    dplyr::group_by(period) |>
    dplyr::summarise(
      n = dplyr::n(),
      mean_vol_per_unit_gross = mean(vol_per_unit_gross),
      sum_gross_convention = sum(gross_convention),
      sum_gross_over_vol = sum(gross_convention / vol),
      sigma_target_budget_neutral = sum_gross_convention / sum_gross_over_vol,
      .groups = "drop"
    ) |>
    dplyr::select(-sum_gross_over_vol) |>
    dplyr::mutate(is_headline = period == "Full Period") |>
    dplyr::arrange(dplyr::desc(is_headline), period)
}

# compute_regime_stress_ratio(): per-strategy Testing/Training ratio of
# vol_per_unit_gross -- how much a strategy's risk-per-unit-of-gross rose
# (or fell) in the 2020-22 stress partition relative to the calm Training
# partition. Strategies missing either partition (the #648 coverage gap:
# CMR, Mom Pre-Peak, Mom Post-Peak, Mom 12-2 have no Training row; Managed
# Futures has no Testing row) are silently absent from the result -- this is
# a real coverage limitation, not a bug, and is reported as such by callers
# (see docs/leaderboard.qmd and the #635 PR body), not papered over here.
compute_regime_stress_ratio <- function(vpug_df) {
  required_cols <- c("strategy", "period", "vol_per_unit_gross")
  missing_cols <- setdiff(required_cols, names(vpug_df))
  if (length(missing_cols) > 0) {
    cli::cli_abort(c(
      "x" = "{.arg vpug_df} is missing required column{?s}: {.field {missing_cols}}.",
      "i" = "compute_regime_stress_ratio() needs {.field {required_cols}} (see compute_vol_per_unit_gross())."
    ))
  }

  wide <- vpug_df |>
    dplyr::filter(period %in% c("Training", "Testing")) |>
    dplyr::select(strategy, period, vol_per_unit_gross) |>
    tidyr::pivot_wider(names_from = period, values_from = vol_per_unit_gross)

  # Both columns may legitimately be absent if the leaderboard currently has
  # zero rows in one of the two partitions -- abort loudly rather than
  # returning a silently-empty/malformed table (fail-loud-not-null.md).
  missing_partition <- setdiff(c("Training", "Testing"), names(wide))
  if (length(missing_partition) > 0) {
    cli::cli_abort(c(
      "x" = "leaderboard has no {.field {missing_partition}} rows with a measurable gross_convention.",
      "i" = "compute_regime_stress_ratio() needs at least one strategy with both a Training and a Testing row."
    ))
  }

  wide |>
    dplyr::filter(!is.na(Training), !is.na(Testing)) |>
    dplyr::mutate(stress_ratio = Testing / Training) |>
    dplyr::arrange(dplyr::desc(stress_ratio))
}

plan_leverage <- function() {
  list(
    # Per-(strategy, period) vol_per_unit_gross -- the intermediate #635's
    # own derivations recomputed by hand at every re-measurement.
    targets::tar_target(leverage_vol_per_unit_gross, {
      compute_vol_per_unit_gross(leaderboard)
    }),

    # The live replacement for #635's hand-typed sigma_target. Read the
    # `is_headline == TRUE` (Full Period) row for the figure any consumer
    # should cite as "sigma_target".
    targets::tar_target(leverage_sigma_target, {
      compute_budget_neutral_sigma(leverage_vol_per_unit_gross)
    }),

    # Training-vs-Testing stress ratio of vol_per_unit_gross, per strategy --
    # the live replacement for #635's hand-run regime check.
    targets::tar_target(leverage_regime_stress_ratio, {
      compute_regime_stress_ratio(leverage_vol_per_unit_gross)
    })
  )
}
