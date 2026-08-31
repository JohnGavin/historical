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

# ── Allocator gross-exposure target (#626 production implementation) ───────
#
# #626's own 2026-08-03 comment adopted a LAYERED construction, confirmed
# again in the #626 comment thread the day this landed: a vol-normalised
# allocator sets each strategy's RELATIVE sizing; a gross-exposure cap is the
# backstop that binds the TOTAL. Net-exposure and cash-borrowing
# formulations were explicitly rejected. This section implements that layer
# pair as live targets, replacing the throwaway prototype in
# docs/_prototypes/leverage-allocator-prototype.qmd (#827) with the real
# thing, approved via that PR's Phase 0 sign-off.
#
#   G_implied = sigma_target / vol_per_unit_gross_i        (relative sizing)
#   G_capped  = min(G_implied, backstop)                   (the cap/backstop)
#
# The backstop LEVEL is explicitly PROVISIONAL (#626 decision D1 is still
# open at the time this lands) -- see LEVERAGE_GROSS_BACKSTOP_DEFAULT below.
# The #827 prototype's live read of the leaderboard found a p90-based
# candidate near 1.8x-2.0x (materially below the stale 3.5x #626's
# 2026-08-05 hand-derivation used, before the #717/#722 CMR
# vol-annualisation fixes) -- 2.0x is adopted here as a clearly-labelled,
# overridable default, not a decision this file makes on D1's behalf.

#' PROVISIONAL default gross-exposure backstop (#626 decision D1 -- NOT
#' finalized)
#'
#' See the header comment above `plan_leverage()`'s allocator section for the
#' derivation. Override via the `HD_LEVERAGE_GROSS_BACKSTOP` environment
#' variable for sensitivity testing -- read and validated eagerly by
#' `.leverage_gross_backstop()` below, per
#' `.claude/rules/fail-loud-not-null.md`'s requirement that a malformed
#' config value abort rather than silently fall back to the default.
#' @noRd
LEVERAGE_GROSS_BACKSTOP_DEFAULT <- 2.0

#' Resolve the gross-exposure backstop, validating any override eagerly
#'
#' `as.numeric()` on a non-numeric string returns `NA` with a coercion
#' warning that `tar_make()` output can easily bury -- this function
#' `cli_abort()`s instead, naming the offending value, rather than letting a
#' typo'd env var silently fall back to the default (or worse, silently
#' produce an `NA` backstop that `compute_allocator_gross()` would then
#' reject one layer downstream with a less specific message).
#'
#' @param env_var Character. Defaults to reading
#'   `Sys.getenv("HD_LEVERAGE_GROSS_BACKSTOP", "")`.
#' @return Numeric scalar: the validated override if set, else
#'   `LEVERAGE_GROSS_BACKSTOP_DEFAULT`.
#' @noRd
.leverage_gross_backstop <- function(env_var = Sys.getenv("HD_LEVERAGE_GROSS_BACKSTOP", "")) {
  if (!nzchar(env_var)) {
    return(LEVERAGE_GROSS_BACKSTOP_DEFAULT)
  }
  val <- suppressWarnings(as.numeric(env_var))
  if (is.na(val) || val <= 0) {
    cli::cli_abort(c(
      "x" = "HD_LEVERAGE_GROSS_BACKSTOP = {.val {env_var}} is not a positive number.",
      "i" = paste0(
        "Unset it to use the default ", LEVERAGE_GROSS_BACKSTOP_DEFAULT,
        "x (PROVISIONAL, #626 D1), or set a positive numeric override."
      )
    ))
  }
  val
}

#' Per-strategy allocator gross exposure under the vol-normalised allocator,
#' capped by a gross-exposure backstop (#626)
#'
#' Restricted to Full Period rows -- the allocator sizes against the whole
#' available sample, matching every #635 hand-derivation and the #827
#' prototype this replaces. `is_cap` is carried through unchanged (same
#' meaning as `compute_vol_per_unit_gross()`'s own `is_cap`: a strategy whose
#' OWN construction gross is itself a ceiling, e.g. Managed Futures'
#' vol-targeting 3.0x cap -- independent of whether the ALLOCATOR's backstop
#' also binds for that strategy).
#'
#' @param vpug_df Tibble -- the output of `compute_vol_per_unit_gross()`
#'   (needs `strategy`, `period`, `vol_per_unit_gross`, `is_cap`).
#' @param sigma_target Numeric scalar > 0 -- the Full Period budget-neutral
#'   sigma_target (`compute_budget_neutral_sigma()`'s `is_headline` row).
#' @param backstop Numeric scalar > 0 -- the gross-exposure ceiling. Defaults
#'   to `.leverage_gross_backstop()` (PROVISIONAL, #626 D1).
#' @return Tibble: `strategy`, `is_cap`, `vol_per_unit_gross`, `G_implied`,
#'   `G_capped`, `backstop_binds`, `backstop_used`, `sigma_target_used` --
#'   one row per strategy with a measurable `vol_per_unit_gross`, sorted
#'   descending by `G_implied`.
#' @noRd
compute_allocator_gross <- function(vpug_df, sigma_target,
                                     backstop = .leverage_gross_backstop()) {
  required_cols <- c("strategy", "period", "vol_per_unit_gross", "is_cap")
  missing_cols <- setdiff(required_cols, names(vpug_df))
  if (length(missing_cols) > 0) {
    cli::cli_abort(c(
      "x" = "{.arg vpug_df} is missing required column{?s}: {.field {missing_cols}}.",
      "i" = "compute_allocator_gross() needs {.field {required_cols}} (see compute_vol_per_unit_gross())."
    ))
  }
  if (!is.numeric(sigma_target) || length(sigma_target) != 1L || is.na(sigma_target) || sigma_target <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg sigma_target} must be a single positive number, not {.val {sigma_target}}.",
      "i" = "compute_allocator_gross() expects the Full Period sigma_target_budget_neutral from compute_budget_neutral_sigma()."
    ))
  }
  if (!is.numeric(backstop) || length(backstop) != 1L || is.na(backstop) || backstop <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg backstop} must be a single positive number, not {.val {backstop}}.",
      "i" = "compute_allocator_gross() expects a positive gross-exposure ceiling -- see LEVERAGE_GROSS_BACKSTOP_DEFAULT (PROVISIONAL, #626 D1)."
    ))
  }

  full <- vpug_df[vpug_df$period == "Full Period", , drop = FALSE]
  if (nrow(full) == 0L) {
    cli::cli_abort(c(
      "x" = "{.arg vpug_df} has no Full Period rows.",
      "i" = "compute_allocator_gross() sizes against the whole available sample, not a sub-partition."
    ))
  }

  full |>
    dplyr::transmute(
      strategy, is_cap, vol_per_unit_gross,
      G_implied = sigma_target / vol_per_unit_gross,
      G_capped = pmin(G_implied, backstop),
      backstop_binds = G_implied > backstop,
      backstop_used = backstop,
      sigma_target_used = sigma_target
    ) |>
    dplyr::arrange(dplyr::desc(G_implied))
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
    }),

    # PROVISIONAL gross-exposure backstop actually used this build (#626 D1
    # not finalized) -- a target (not a bare constant) so it is visible in
    # `tar_meta()`/`tar_read()` and any change to HD_LEVERAGE_GROSS_BACKSTOP
    # correctly invalidates leverage_allocator_gross downstream.
    targets::tar_target(leverage_gross_backstop, {
      .leverage_gross_backstop()
    }),

    # Per-strategy allocator gross exposure (#626 production implementation,
    # replacing the #827 prototype). Reads the Full Period headline
    # sigma_target from leverage_sigma_target.
    targets::tar_target(leverage_allocator_gross, {
      sigma_headline <- leverage_sigma_target$sigma_target_budget_neutral[leverage_sigma_target$is_headline]
      compute_allocator_gross(leverage_vol_per_unit_gross, sigma_headline, leverage_gross_backstop)
    })
  )
}
