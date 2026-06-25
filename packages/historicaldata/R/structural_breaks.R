# Iterative structural-break detector for return series
#
# Implements Rob Carver's forward-split method ("Breaking badly", qoppac 2026):
# compare a growing early window against the residual tail using Welch two-sample
# t-tests on volatility-normalised returns.  Breaks are rarer than expected
# (~13% of series at alpha=1%), and "no break" often wins OOS — so this is a
# DIAGNOSTIC / guard against over-splitting, not an always-on re-estimator.
#
# Design decisions vs Carver's description:
#   - "First significant split" approach: we return the first candidate split s
#     (from min_obs to n - min_obs) whose Welch p-value < alpha.  We do NOT
#     search for the most-significant split (which would maximise the
#     multiple-testing problem).  This matches Carver's sequential scan.
#   - Multi-break: after one break is found we RESTART detection on the
#     post-break tail, honouring min_obs on both the residual tail and the
#     candidate early window within that tail.
#   - Volatility normalisation: each candidate segment is divided by its own
#     SD before the t-test.  A segment with SD == 0 (constant returns) cannot
#     be normalised; we skip it (NA p-value) and continue.
#   - Multiple-testing inflation: scanning every candidate s inflates the
#     apparent alpha.  The function documents but does NOT automatically correct
#     for this (same family as K_eff_strat / deflated Sharpe, issue #160).
#     Users should treat reported breaks as *evidence* requiring judgement, not
#     automatic triggers.
#   - Look-ahead: this function operates on the full supplied vector; callers
#     running in a rolling/expanding window must supply only data available at
#     the estimation date (look-ahead-bias-prevention rule).


# ── Internal helpers ──────────────────────────────────────────────────────────

# Detect the first significant break in a sub-segment.
# Returns the absolute index (in r's coordinate space) of the break point,
# or NA_integer_ if no break is found.
# `offset` is the 0-based position of r[1] in the original series.
.hd_detect_one_break <- function(r, min_obs, alpha, offset = 0L) {
  n <- length(r)
  if (n < 2L * min_obs) return(list(break_at = NA_integer_, p_value = NA_real_))

  # Sweep candidate split from min_obs to n - min_obs (inclusive)
  for (s in min_obs:(n - min_obs)) {
    left  <- r[seq_len(s)]
    right <- r[(s + 1L):n]

    sd_l <- stats::sd(left)
    sd_r <- stats::sd(right)

    # Cannot normalise a zero-variance segment; skip
    if (sd_l == 0 || sd_r == 0) next

    left_norm  <- left  / sd_l
    right_norm <- right / sd_r

    tt <- stats::t.test(left_norm, right_norm)
    if (tt$p.value < alpha) {
      return(list(
        break_at = as.integer(offset + s),
        p_value  = tt$p.value
      ))
    }
  }

  list(break_at = NA_integer_, p_value = NA_real_)
}


# ── Exported function ─────────────────────────────────────────────────────────

#' Iterative structural-break detector for return series
#'
#' Implements Rob Carver's forward-split method ("Breaking badly", qoppac 2026):
#' at each candidate split point, the series is divided into a left (early)
#' segment and a right (tail) segment; each segment is volatility-normalised by
#' its own standard deviation; a Welch two-sample t-test compares the
#' normalised means; the **first** split whose p-value is below \code{alpha} is
#' recorded as a break.  After a break is found, detection **restarts** on the
#' post-break tail (multi-break support), always honouring the \code{min_years}
#' floor on both sub-segments.
#'
#' @section Caveats:
#' \itemize{
#'   \item **Multiple-testing inflation.** Scanning every candidate split date
#'     inflates the effective false-break rate above the nominal \code{alpha}
#'     (the same family as the K_eff / deflated-Sharpe problem, issue \#160).
#'     Treat detected breaks as *evidence* requiring judgement, not automatic
#'     re-estimation triggers.
#'   \item **Breaks are rare.** Carver's own empirical finding: only ~13\% of
#'     strategy/instrument pairs show a significant break at \code{alpha = 0.01},
#'     and "no break" frequently outperforms break-adjusted estimates OOS.  This
#'     function is primarily a **diagnostic and guard against over-splitting**,
#'     not an always-on re-estimator.
#'   \item **Look-ahead discipline.** The function operates on the full supplied
#'     vector.  In rolling or expanding-window contexts, callers must supply only
#'     data available at the estimation date
#'     (see \code{look-ahead-bias-prevention} rule).
#' }
#'
#' @param returns Numeric vector of period returns (daily, weekly, etc.).
#'   Must be free of \code{NA}; use \code{returns[!is.na(returns)]} before
#'   calling.  (NA values are never silently dropped — per the NA-propagation
#'   discipline enforced in this package.)
#' @param alpha Numeric in (0, 1).  Significance level for the Welch t-test.
#'   Common choices: \code{0.01} (1\%, default; Carver's baseline), \code{0.05}
#'   (5\%), \code{0.10} (10\%).  Consistent with the critical-value levels used
#'   in \code{\link{hd_sharpe_stability_ratio}}.
#' @param min_years Positive numeric.  Minimum window length in *years* that
#'   both the left and right candidate segments must satisfy.  Default 5, per
#'   Carver's recommendation (approximately 1\,260 trading days).
#' @param periods_per_year Positive integer.  Number of periods per year
#'   matching the frequency of \code{returns} (default 252 for daily).
#'
#' @return A named list with components:
#'   \describe{
#'     \item{\code{break_indices}}{Integer vector of break positions (1-based,
#'       inclusive cut points: the break falls \emph{after} position
#'       \code{break_indices[k]}).  Empty integer vector if no break found.}
#'     \item{\code{n_breaks}}{Integer.  Number of breaks detected.}
#'     \item{\code{segments}}{A [tibble][tibble::tibble] with columns
#'       \code{start} (1-based), \code{end} (1-based inclusive), \code{n_obs}
#'       (integer), and \code{p_value} (numeric; the t-test p-value that
#'       \emph{triggered} the next break, or \code{NA} for the final segment).}
#'     \item{\code{post_break_start}}{Integer.  1-based index where the FINAL
#'       segment begins.  Use \code{returns[post_break_start:length(returns)]}
#'       for parameter estimation.  Equals \code{1L} when no break is detected.}
#'     \item{\code{alpha}}{The significance level used (echoed).}
#'     \item{\code{min_obs}}{The minimum segment length in periods (echoed).}
#'   }
#'
#' @examples
#' set.seed(1)
#' n  <- 6L * 252L
#' r  <- c(rnorm(n, mean = 0.0008, sd = 0.01),
#'         rnorm(n, mean = -0.0008, sd = 0.01))
#' hd_structural_breaks(r)
#'
#' @references
#' Carver, R. (2026). "Breaking badly: finding structural breaks in parameter
#'   estimates." qoppac.blogspot.com.
#'
#' @seealso [hd_sharpe_stability_ratio()], [hd_hac_sharpe()]
#'
#' @family falsification
#' @export
hd_structural_breaks <- function(
    returns,
    alpha           = 0.01,
    min_years       = 5,
    periods_per_year = 252L
) {

  # ── Input validation ─────────────────────────────────────────────────────────

  if (!is.numeric(returns)) {
    cli::cli_abort(c(
      "x" = "{.arg returns} must be a numeric vector.",
      "i" = "Got {.cls {class(returns)}}."
    ))
  }

  if (anyNA(returns)) {
    cli::cli_abort(c(
      "x" = "{.arg returns} must not contain {.code NA} values.",
      "i" = "Filter NAs before calling: {.code returns[!is.na(returns)]}.",
      "i" = "See the NA-propagation discipline in the package conventions."
    ))
  }

  if (!is.numeric(alpha) || length(alpha) != 1L || alpha <= 0 || alpha >= 1) {
    cli::cli_abort(c(
      "x" = "{.arg alpha} must be a single numeric value in (0, 1).",
      "i" = "Got {.val {alpha}}."
    ))
  }

  if (!is.numeric(min_years) || length(min_years) != 1L || min_years <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg min_years} must be a positive numeric scalar.",
      "i" = "Got {.val {min_years}}."
    ))
  }

  if (!is.numeric(periods_per_year) || length(periods_per_year) != 1L ||
      periods_per_year < 1L || periods_per_year != floor(periods_per_year)) {
    cli::cli_abort(c(
      "x" = "{.arg periods_per_year} must be a positive integer scalar.",
      "i" = "Got {.val {periods_per_year}}."
    ))
  }

  # ── Setup ────────────────────────────────────────────────────────────────────

  min_obs <- ceiling(min_years * periods_per_year)
  n_total <- length(returns)

  break_indices <- integer(0L)
  p_values      <- numeric(0L)

  # ── Iterative break detection ────────────────────────────────────────────────
  # Start with the full series; after each break restart on the tail segment.

  search_start <- 1L   # 1-based start of the current search window

  repeat {
    # Sub-series from search_start to end
    sub  <- returns[search_start:n_total]
    res  <- .hd_detect_one_break(sub, min_obs, alpha, offset = search_start - 1L)

    if (is.na(res$break_at)) break  # no further break found

    break_indices <- c(break_indices, res$break_at)
    p_values      <- c(p_values,      res$p_value)

    # Restart search at the observation immediately after the break
    search_start <- res$break_at + 1L

    # Safety: if the remaining tail is too short to ever find another break, stop
    if ((n_total - search_start + 1L) < 2L * min_obs) break
  }

  # ── Build segments tibble ─────────────────────────────────────────────────────

  n_breaks <- length(break_indices)

  if (n_breaks == 0L) {
    starts    <- 1L
    ends      <- n_total
    seg_pvals <- NA_real_
  } else {
    starts    <- c(1L,                         break_indices + 1L)
    ends      <- c(break_indices,              n_total)
    seg_pvals <- c(p_values,                   NA_real_)
  }

  segments <- tibble::tibble(
    start   = as.integer(starts),
    end     = as.integer(ends),
    n_obs   = as.integer(ends - starts + 1L),
    p_value = seg_pvals
  )

  post_break_start <- if (n_breaks == 0L) 1L else as.integer(break_indices[n_breaks] + 1L)

  list(
    break_indices    = break_indices,
    n_breaks         = as.integer(n_breaks),
    segments         = segments,
    post_break_start = post_break_start,
    alpha            = alpha,
    min_obs          = as.integer(min_obs)
  )
}
