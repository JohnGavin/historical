# Dense parameter-neighbourhood plateau-vs-peak check (#849)
#
# Source: "The Algorithmic Advantage" interview with John Bollinger
# (Simon M, Sep 3 2026): "If a 20-day moving average works but 16, 17, 18,
# 19, 21, 22, 23 and 24 don't produce broadly similar behaviour, the system
# gets thrown out. He doesn't optimise it."
#
# This is a materially stronger claim than the existing two-point ±20%
# sweep in backtest-robustness.md §1 (qa_parameter_robustness): (a) a DENSE
# neighbourhood of adjacent values, not two endpoints of a percentage
# sweep, (b) "broadly similar behaviour" across the WHOLE neighbourhood,
# and (c) failing it means the idea is discarded, not warned-about.
#
# hd_param_neighbourhood() implements the plateau-vs-peak verdict as a
# pure, package-level function so it can be reused as a QA gate (S39,
# R/plan_qa_gates.R) and independently unit-tested against synthetic
# fixtures (packages/historicaldata/tests/testthat/test-hd_param_
# neighbourhood.R) without needing a live backtest.

#' Minimum fraction of the centre value's metric a neighbour may retain
#' (S39, #849)
#'
#' Reuses, unchanged, the threshold already calibrated in `backtest-
#' robustness.md` §1's `qa_parameter_robustness` two-point ±20% sweep
#' ("FAIL if Sharpe drops >50% at any ±20% perturbation" -- `ratio < 0.5`).
#' This constant applies the SAME floor to every point in a dense
#' neighbourhood instead of just the two ±20% endpoints -- a strict
#' widening of coverage at an unchanged bar, not a new, uncalibrated
#' number.
#' @noRd
HD_PARAM_NEIGHBOURHOOD_MIN_RETENTION <- 0.5

#' Maximum coefficient of variation across a dense parameter neighbourhood
#' (S39, #849)
#'
#' A single point below [HD_PARAM_NEIGHBOURHOOD_MIN_RETENTION] catches a
#' catastrophic collapse at one value. It does NOT catch a neighbourhood
#' that swings up and down without ever crossing that floor at any single
#' point -- exactly the "wobbly" shape Bollinger's "broadly similar
#' behaviour" bar is meant to reject, and exactly the gap a two-point
#' sweep structurally cannot see (there is nothing to swing between with
#' only two endpoints). The coefficient of variation (`sd / |mean|`) of the
#' metric across the full neighbourhood (centre + all neighbours) is the
#' natural aggregate counterpart to the per-point floor above: it is
#' unitless (works for Sharpe, ROI, or any centred metric), and unlike a
#' raw range it is not dominated by neighbourhood density (adding more
#' neighbours does not mechanically widen a range the way `max - min`
#' would). `0.30` is set at roughly HALF of the 0.5 per-point retention
#' floor: a neighbourhood consistent enough to be a plateau should show
#' LESS aggregate dispersion than the worst single point is permitted to
#' show alone, because the floor already tolerates one point diverging by
#' up to 50% -- if the *typical* spread across many points were allowed to
#' be that wide too, the aggregate check would add nothing the floor
#' doesn't already cover. Tightening the aggregate bound relative to the
#' single-point bound is what makes it a genuinely distinct, non-redundant
#' second check.
#' @noRd
HD_PARAM_NEIGHBOURHOOD_MAX_CV <- 0.30

#' Minimum number of adjacent neighbours required to render a verdict
#' (S39, #849)
#'
#' Bollinger's own practice checks 8 adjacent integers (16-24 around 20).
#' `4` is set well below that as the floor for INDETERMINATE-vs-computable,
#' not as an endorsement of 4 being "dense enough" -- a caller that only
#' has 4 neighbours available still gets a verdict rather than a hard
#' abort, but a strategy proposal that only ever sweeps 4 neighbours is
#' doing a materially thinner check than Bollinger's stated practice and
#' that thinness is visible in `n_neighbours`, not hidden by it.
#' @noRd
HD_PARAM_NEIGHBOURHOOD_MIN_N <- 4L

#' Dense parameter-neighbourhood plateau-vs-peak verdict
#'
#' Implements John Bollinger's stated practice (see `@references`): a
#' chosen parameter value is trustworthy only if a DENSE neighbourhood of
#' adjacent values produces "broadly similar behaviour" -- not merely if
#' the metric survives two sweep endpoints. This is stricter, on three
#' axes, than the existing `qa_parameter_robustness` two-point ±20% sweep
#' documented in `backtest-robustness.md` §1: it inspects every point in a
#' dense neighbourhood (not just two endpoints), it uses an aggregate
#' dispersion bound in addition to a per-point floor (so a neighbourhood
#' that never breaches the floor at any single point can still fail on
#' being "wobbly"), and its intended consequence in the QA gate built on
#' top of it is a hard, cited decision rather than a bare `cli_warn()`.
#'
#' @section Three-state verdict:
#' Returns exactly one of `"plateau"`, `"peak"`, or `"indeterminate"` --
#' never a value that could be mistaken for a pass when the neighbourhood
#' could not actually be assessed (`checks-must-distinguish-unknown.md`).
#' `"indeterminate"` fires before either substantive check runs, for
#' three distinct, individually reported reasons (see `reason`): too few
#' neighbours to be a meaningful density check, a missing (`NA`) metric
#' anywhere in the neighbourhood (a dropped point is never silently
#' excluded -- `fail-loud-not-null.md`), or a non-positive centre metric
#' (the retention-ratio floor is undefined when dividing by a non-positive
#' baseline; a strategy with a non-positive centre Sharpe should not be
#' asking "is this a plateau" in the first place).
#'
#' @section Two criteria, floor first:
#' \enumerate{
#'   \item \strong{Per-point floor.} Every neighbour's metric must retain
#'     at least `min_retention` of the centre's metric
#'     (`neighbour_metric / centre_metric >= min_retention`). This is the
#'     dense-neighbourhood generalisation of the existing two-point ±20%
#'     sweep's `ratio < 0.5` fail condition -- same threshold, applied to
#'     every point instead of two.
#'   \item \strong{Aggregate dispersion.} The coefficient of variation of
#'     the metric across the WHOLE neighbourhood (centre + all neighbours)
#'     must not exceed `max_cv`. This catches a neighbourhood that swings
#'     up and down without any single point crossing the floor -- a shape
#'     the floor alone cannot see.
#' }
#' When the floor is breached, `reason` is `"floor"` regardless of the CV
#' outcome -- a single collapsed point is the more severe, easier-to-name
#' failure and takes priority for reporting. `"dispersion"` is reported
#' only when the floor holds everywhere but the aggregate CV still exceeds
#' `max_cv`.
#'
#' @param param_values Numeric vector of parameter values tested (the
#'   centre plus its neighbours), e.g. `16:24` for a dense integer
#'   neighbourhood around `20`. Must be the same length as
#'   `metric_values` and contain `centre` exactly once.
#' @param metric_values Numeric vector of the metric (e.g. annualised
#'   Sharpe ratio) evaluated at each corresponding `param_values` entry.
#'   `NA` values are never silently dropped -- their presence anywhere in
#'   the neighbourhood makes the verdict `"indeterminate"`.
#' @param centre Numeric scalar, the chosen/production parameter value.
#'   Must appear exactly once in `param_values`.
#' @param min_retention Numeric scalar in `(0, 1]`. Minimum fraction of the
#'   centre metric a neighbour must retain. Default
#'   [HD_PARAM_NEIGHBOURHOOD_MIN_RETENTION] (`0.5`) -- see that constant's
#'   roxygen for its derivation.
#' @param max_cv Numeric scalar `> 0`. Maximum coefficient of variation
#'   (`sd / |mean|`) across the full neighbourhood. Default
#'   [HD_PARAM_NEIGHBOURHOOD_MAX_CV] (`0.30`) -- see that constant's
#'   roxygen for its derivation.
#' @param min_neighbours Positive integer scalar. Minimum number of
#'   neighbours (excluding the centre) required to render a plateau/peak
#'   verdict rather than `"indeterminate"`. Default
#'   [HD_PARAM_NEIGHBOURHOOD_MIN_N] (`4L`).
#'
#' @return Named list:
#'   \describe{
#'     \item{verdict}{One of `"plateau"`, `"peak"`, `"indeterminate"`.}
#'     \item{reason}{`"broadly_similar"` (plateau); `"floor"` or
#'       `"dispersion"` (peak); `"too_few_neighbours"`,
#'       `"na_metric_values"`, or `"centre_not_positive"`
#'       (indeterminate).}
#'     \item{centre, centre_metric}{Echoed centre value and its metric.}
#'     \item{n_neighbours}{Number of neighbours actually evaluated.}
#'     \item{min_retention_ratio, cv}{The two computed statistics
#'       (`NA_real_` when indeterminate before they could be computed).}
#'     \item{min_retention, max_cv, min_neighbours}{Echoed thresholds.}
#'   }
#'
#' @references
#' The Algorithmic Advantage, "The honest truth about Bollinger Bands"
#' (Simon M interviewing John Bollinger, Sep 3 2026):
#' \url{https://algoadvantage.substack.com/p/the-honest-truth-about-bollinger}
#'
#' @examples
#' # A robust neighbourhood -- Bollinger's own passing case
#' hd_param_neighbourhood(
#'   param_values  = 16:24,
#'   metric_values = c(0.97, 1.00, 0.98, 1.02, 1.00, 0.99, 1.01, 0.98, 1.00),
#'   centre        = 20
#' )$verdict
#'
#' # An isolated peak -- Bollinger's own failing case
#' hd_param_neighbourhood(
#'   param_values  = 16:24,
#'   metric_values = c(0.1, 0.1, 0.1, 0.1, 2.0, 0.1, 0.1, 0.1, 0.1),
#'   centre        = 20
#' )$verdict
#'
#' @family falsification
#' @export
hd_param_neighbourhood <- function(
    param_values, metric_values, centre,
    min_retention  = HD_PARAM_NEIGHBOURHOOD_MIN_RETENTION,
    max_cv         = HD_PARAM_NEIGHBOURHOOD_MAX_CV,
    min_neighbours = HD_PARAM_NEIGHBOURHOOD_MIN_N) {

  if (!is.numeric(param_values) || length(param_values) < 2L) {
    cli::cli_abort(c(
      "x" = "{.arg param_values} must be a numeric vector of length >= 2.",
      "i" = "Got {.cls {class(param_values)}} of length {length(param_values)}."
    ))
  }
  if (!is.numeric(metric_values)) {
    cli::cli_abort(c(
      "x" = "{.arg metric_values} must be a numeric vector.",
      "i" = "Got {.cls {class(metric_values)}}."
    ))
  }
  if (length(param_values) != length(metric_values)) {
    cli::cli_abort(c(
      "x" = "{.arg param_values} and {.arg metric_values} must be the same length.",
      "i" = "Got {length(param_values)} and {length(metric_values)}."
    ))
  }
  if (!is.numeric(centre) || length(centre) != 1L || is.na(centre)) {
    cli::cli_abort(c(
      "x" = "{.arg centre} must be a single non-missing numeric value.",
      "i" = "Got {.val {centre}}."
    ))
  }
  if (!is.numeric(min_retention) || length(min_retention) != 1L ||
      is.na(min_retention) || min_retention <= 0 || min_retention > 1) {
    cli::cli_abort(c(
      "x" = "{.arg min_retention} must be a single number in (0, 1].",
      "i" = "Got {.val {min_retention}}."
    ))
  }
  if (!is.numeric(max_cv) || length(max_cv) != 1L || is.na(max_cv) || max_cv <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg max_cv} must be a single positive number.",
      "i" = "Got {.val {max_cv}}."
    ))
  }
  if (!is.numeric(min_neighbours) || length(min_neighbours) != 1L ||
      is.na(min_neighbours) || min_neighbours < 1 ||
      min_neighbours != floor(min_neighbours)) {
    cli::cli_abort(c(
      "x" = "{.arg min_neighbours} must be a single positive integer.",
      "i" = "Got {.val {min_neighbours}}."
    ))
  }

  centre_idx <- which(param_values == centre)
  if (length(centre_idx) != 1L) {
    cli::cli_abort(c(
      "x" = "{.arg centre} ({.val {centre}}) must appear exactly once in {.arg param_values}.",
      "i" = "Found it {length(centre_idx)} time{?s}.",
      "i" = "hd_param_neighbourhood() (S39, #849) needs an unambiguous centre point."
    ))
  }

  centre_metric      <- metric_values[[centre_idx]]
  neighbour_metrics  <- metric_values[-centre_idx]
  n_neighbours       <- length(neighbour_metrics)

  base_out <- list(
    centre         = centre,
    centre_metric  = centre_metric,
    n_neighbours   = n_neighbours,
    min_retention  = min_retention,
    max_cv         = max_cv,
    min_neighbours = min_neighbours
  )

  if (n_neighbours < min_neighbours) {
    return(c(base_out, list(
      verdict = "indeterminate", reason = "too_few_neighbours",
      min_retention_ratio = NA_real_, cv = NA_real_
    )))
  }

  if (anyNA(metric_values)) {
    return(c(base_out, list(
      verdict = "indeterminate", reason = "na_metric_values",
      min_retention_ratio = NA_real_, cv = NA_real_
    )))
  }

  if (centre_metric <= 0) {
    return(c(base_out, list(
      verdict = "indeterminate", reason = "centre_not_positive",
      min_retention_ratio = NA_real_, cv = NA_real_
    )))
  }

  retention_ratios    <- neighbour_metrics / centre_metric
  min_retention_ratio <- min(retention_ratios)
  cv                  <- stats::sd(metric_values) / abs(mean(metric_values))

  floor_fail <- min_retention_ratio < min_retention
  cv_fail    <- cv > max_cv

  verdict <- if (floor_fail || cv_fail) "peak" else "plateau"
  reason  <- if (floor_fail) {
    "floor"
  } else if (cv_fail) {
    "dispersion"
  } else {
    "broadly_similar"
  }

  c(base_out, list(
    verdict = verdict, reason = reason,
    min_retention_ratio = min_retention_ratio, cv = cv
  ))
}
