# Structural Break Detection in Sharpe Estimates
#
# Implements Carver's (2026) iterative forward-split structural break detector
# on vol-normalised returns, replicating the methodology from:
#   "Breaking badly: finding structural breaks in parameter estimates"
#   Rob Carver, qoppac.blogspot.com, 2026.
#
# External content read for IDEAS ONLY — this implementation is re-authored in
# project style per the zero-trust external-code rule.
#
# Key empirical finding from Carver: breaks are rarer than expected (~13% of
# instrument/forecast pairs at 1%), and "no break" frequently beats
# break-adjusted estimation OOS.  This function is therefore a GUARD against
# over-splitting, NOT an always-on re-estimator.
#
# Design notes:
#   - t.test() from base R (no external dependency)
#   - Multiple-testing note: scanning every candidate split date inflates the
#     false-break rate above the nominal alpha.  Documented in the return value
#     (see $multiple_testing_note).  Consider applying a Bonferroni or
#     min-segment penalty before acting on break findings.
#   - Look-ahead constraint: break detection is applied to the FULL historical
#     series for diagnostics; NEVER use a detected break index to select
#     parameters on data that includes the break-detection scan itself without
#     proper train/test separation.  See the look-ahead-bias-prevention rule.


# ── Public API ────────────────────────────────────────────────────────────────

#' Iterative structural break detection on vol-normalised returns
#'
#' Automates the "which history is still relevant?" decision for Sharpe-ratio
#' parameter estimation using Carver's (2026) iterative forward-split
#' procedure:
#'
#' 1. Normalise returns by their standard deviation (vol-normalised Sharpe-like
#'    series).
#' 2. Compare the first window (growing from 1 year) against the remainder
#'    using an independent two-sample t-test on the normalised values.
#' 3. If significant, record the break and restart on the post-break segment.
#' 4. Repeat until the remaining segment is shorter than `min_years`.
#'
#' **Multiple-testing note:** scanning every candidate split date is a
#' multiple-comparisons problem — the same family as K_eff_strat / deflated
#' Sharpe (#160).  The nominal `alpha` understates the false-break rate.
#' Treat reported breaks as *evidence* requiring further investigation, not
#' as grounds for immediate re-estimation (see `resulting-prohibition` rule).
#'
#' **Look-ahead constraint:** break indices are discovered from the FULL series.
#' Never use detected break positions to select parameters on the same series
#' without an independent OOS partition (see `look-ahead-bias-prevention` rule).
#'
#' @param returns Numeric vector of period returns (daily or monthly).  Must
#'   contain NO `NA` values — call `returns[!is.na(returns)]` before passing.
#'   Aborts with a structured cli message if NAs are detected.
#' @param alpha Significance level for the t-test.  Accepts `0.01` (1%),
#'   `0.05` (5%), or `0.10` (10%) to match the SSR thresholds in
#'   [hd_sharpe_stability_ratio()].  Default: `0.01` (most conservative,
#'   matching Carver's primary threshold).
#' @param min_years Minimum years of data required on EACH side of a candidate
#'   split.  Windows shorter than `floor(min_years * periods_per_year)` are
#'   not tested.  Default: `5`.
#' @param periods_per_year Number of periods per year.  `252L` for daily,
#'   `12L` for monthly.  Default: `252L`.
#'
#' @return Named list:
#'   \describe{
#'     \item{n_breaks}{Integer.  Number of breaks found.}
#'     \item{break_indices}{Integer vector of 1-based indices where breaks
#'       were detected (the LAST index of the pre-break segment).  Empty
#'       (`integer(0)`) when no breaks found.}
#'     \item{post_break_start}{Integer.  First index of the most recent
#'       post-break segment (1 when no breaks found, i.e. the full series).}
#'     \item{post_break_returns}{Numeric vector.  The post-break-start
#'       returns.  Equals `returns` when no breaks found.}
#'     \item{alpha}{The significance level used (echoed).}
#'     \item{min_periods}{Minimum segment length in periods (derived from
#'       `min_years * periods_per_year`).}
#'     \item{multiple_testing_note}{Character.  Reminder that scanning all
#'       splits inflates the false-break rate above `alpha`.}
#'   }
#'
#' @references
#' Carver, R. (2026). "Breaking badly: finding structural breaks in
#'   parameter estimates." qoppac.blogspot.com.
#'   Read for IDEAS only; implementation re-authored per zero-trust rule.
#'
#' @family falsification
#' @seealso [hd_sharpe_stability_ratio()], [hd_hac_sharpe()]
#' @export
hd_structural_breaks <- function(
    returns,
    alpha          = 0.01,
    min_years      = 5,
    periods_per_year = 252L
) {
  # ── Input validation ────────────────────────────────────────────────────────
  if (!is.numeric(returns)) {
    cli::cli_abort(c(
      "x" = "{.arg returns} must be a numeric vector.",
      "i" = "Got {.cls {class(returns)[[1]]}}, not numeric."
    ))
  }
  if (anyNA(returns)) {
    cli::cli_abort(c(
      "x" = "{.arg returns} must not contain {.code NA} values.",
      "i" = "Strip NAs before calling: {.code returns[!is.na(returns)]}.",
      "i" = "Found {sum(is.na(returns))} NA{?s} in a vector of length {length(returns)}."
    ))
  }
  if (!is.numeric(alpha) || length(alpha) != 1L || alpha <= 0 || alpha >= 1) {
    cli::cli_abort(c(
      "x" = "{.arg alpha} must be a single numeric value in (0, 1).",
      "i" = "Typical values: 0.01, 0.05, 0.10."
    ))
  }
  if (!is.numeric(min_years) || length(min_years) != 1L || min_years <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg min_years} must be a positive numeric scalar.",
      "i" = "Got {.val {min_years}}."
    ))
  }
  if (!is.numeric(periods_per_year) || length(periods_per_year) != 1L ||
      periods_per_year < 1L) {
    cli::cli_abort(c(
      "x" = "{.arg periods_per_year} must be a positive numeric scalar.",
      "i" = "Typical values: 252 (daily) or 12 (monthly)."
    ))
  }

  min_periods <- as.integer(floor(min_years * periods_per_year))

  # ── Core iterative break search ─────────────────────────────────────────────
  break_indices <- .hd_find_breaks(returns, alpha, min_periods)

  post_break_start <- if (length(break_indices) == 0L) {
    1L
  } else {
    break_indices[length(break_indices)] + 1L
  }

  list(
    n_breaks          = length(break_indices),
    break_indices     = break_indices,
    post_break_start  = post_break_start,
    post_break_returns = returns[post_break_start:length(returns)],
    alpha             = alpha,
    min_periods       = min_periods,
    multiple_testing_note = paste0(
      "Scanning all candidate split dates inflates the false-break rate above ",
      "the nominal alpha (", alpha, "). ",
      "Treat breaks as evidence requiring further investigation, not as grounds ",
      "for immediate re-estimation (see resulting-prohibition rule)."
    )
  )
}


# ── Internals ─────────────────────────────────────────────────────────────────

#' Iterative break finder (internal)
#'
#' Recursively scans `r` for the earliest significant break, then restarts
#' on the post-break segment.  Returns a vector of break indices (1-based,
#' each pointing to the last observation of its pre-break segment).
#'
#' @param r Numeric vector of returns (NA-free).
#' @param alpha Significance level.
#' @param min_periods Minimum segment length.
#'
#' @return Integer vector of break indices.
#' @keywords internal
.hd_find_breaks <- function(r, alpha, min_periods) {
  n <- length(r)
  breaks_so_far <- integer(0L)

  # Vol-normalise once for the full segment (consistent with Carver: normalise
  # by SD of the segment under consideration so the t-test compares Sharpe-like
  # means, not raw means).
  seg_sd <- stats::sd(r)
  if (is.na(seg_sd) || seg_sd <= .Machine$double.eps) {
    return(breaks_so_far)
  }
  r_norm <- r / seg_sd

  # We need at least 2 * min_periods observations to test any split.
  if (n < 2L * min_periods) {
    return(breaks_so_far)
  }

  # Forward scan: grow the early window from min_periods to n - min_periods.
  # The t-test compares early window vs the remaining tail.
  for (split_at in min_periods:(n - min_periods)) {
    early <- r_norm[1L:split_at]
    late  <- r_norm[(split_at + 1L):n]

    test_res <- tryCatch(
      stats::t.test(early, late),
      error = function(e) NULL
    )
    if (is.null(test_res)) next

    if (test_res$p.value < alpha) {
      # Break found at split_at (last index of early window).
      breaks_so_far <- c(breaks_so_far, split_at)

      # Restart recursively on the post-break segment if long enough.
      post_seg <- r[(split_at + 1L):n]
      if (length(post_seg) >= 2L * min_periods) {
        child_breaks <- .hd_find_breaks(post_seg, alpha, min_periods)
        # Adjust child break indices to be relative to the original r.
        breaks_so_far <- c(breaks_so_far, child_breaks + split_at)
      }
      break  # stop the forward scan; recursion handles the tail
    }
  }

  breaks_so_far
}
