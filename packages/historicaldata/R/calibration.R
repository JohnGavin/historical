# Interval-calibration helpers (#597)
#
# Backs the qa_interval_coverage QA gate: given intervals we published and
# outcomes that later resolved, did the intervals contain the outcomes at the
# stated rate?  Coverage alone is a weak diagnostic — an interval of +/- Inf
# has perfect coverage — so the interval score (Gneiting & Raftery 2007) is
# reported alongside it, penalising width and misses jointly.
#
# Origin: https://statmodeling.stat.columbia.edu/2026/07/29/over-coverage-caught-by-pre-registration-47-of-56-inside-a-stated-50-interval/
# Reference: Gneiting, T. & Raftery, A. E. (2007), "Strictly Proper Scoring
#   Rules, Prediction, and Estimation", JASA 102(477), 359-378.
#   Sellke, T., Bayarri, M. J. & Berger, J. O. (2001), "Calibration of p Values
#   for Testing Precise Null Hypotheses", The American Statistician 55(1), 62-71.

# ── Internal: recycle a bound to the length of y ────────────────────────────

.hd_recycle_bound <- function(x, n, arg) {
  if (length(x) == n) return(as.numeric(x))
  if (length(x) == 1L) return(rep_len(as.numeric(x), n))
  cli::cli_abort(c(
    "x" = "{.arg {arg}} must have length 1 or {n}, not {length(x)}.",
    "i" = "Bounds are recycled against {.arg y}."
  ))
}

# ── 1. Interval score ───────────────────────────────────────────────────────

#' Interval score for a central prediction interval
#'
#' Computes the Gneiting-Raftery interval score for a central
#' \code{(1 - alpha) * 100\%} prediction interval.  The score is negatively
#' oriented — **lower is better** — and penalises interval width and misses
#' jointly:
#'
#' \deqn{IS_\alpha = (u - l)
#'   + \frac{2}{\alpha}(l - y)\mathbf{1}\{y < l\}
#'   + \frac{2}{\alpha}(y - u)\mathbf{1}\{y > u\}}
#'
#' Use this wherever coverage is reported.  Coverage on its own cannot
#' distinguish a well-calibrated interval from an absurdly wide one: an
#' interval of \code{c(-Inf, Inf)} has perfect coverage and no information
#' content.  The width term makes that trade-off visible.
#'
#' @param y Numeric vector of realised outcomes.  \code{NA} propagates.
#' @param lower,upper Numeric.  Interval bounds, each of length 1 or
#'   \code{length(y)} (recycled).
#' @param alpha Numeric scalar in \code{(0, 1)}.  The interval's nominal
#'   non-coverage, i.e. \code{1 - nominal_coverage}.  A 90\% interval has
#'   \code{alpha = 0.1}.
#'
#' @return Numeric vector the same length as \code{y}.  Lower is better.
#'
#' @examples
#' # Outcome inside the interval: score is just the width
#' hd_interval_score(2, lower = 1, upper = 3, alpha = 0.1)
#'
#' # Outcome below the interval: width plus (2/alpha) * shortfall
#' hd_interval_score(0, lower = 1, upper = 3, alpha = 0.1)
#'
#' @family calibration
#' @export
hd_interval_score <- function(y, lower, upper, alpha) {
  if (!is.numeric(alpha) || length(alpha) != 1L || is.na(alpha) ||
      alpha <= 0 || alpha >= 1) {
    cli::cli_abort(c(
      "x" = "{.arg alpha} must be a single number in (0, 1).",
      "i" = "A 90% interval has {.code alpha = 0.1}.",
      "x" = "Got: {.val {alpha}}"
    ))
  }

  y <- as.numeric(y)
  n <- length(y)
  lower <- .hd_recycle_bound(lower, n, "lower")
  upper <- .hd_recycle_bound(upper, n, "upper")

  crossed <- which(!is.na(lower) & !is.na(upper) & upper < lower)
  if (length(crossed) > 0L) {
    cli::cli_abort(c(
      "x" = "{.arg upper} is below {.arg lower} at {length(crossed)} position{?s}.",
      "i" = "First offending index: {crossed[1]} ({.val {lower[crossed[1]]}} > {.val {upper[crossed[1]]}}).",
      "i" = "Bounds may have been supplied in the wrong order."
    ))
  }

  width <- upper - lower
  below <- ifelse(!is.na(y) & y < lower, (2 / alpha) * (lower - y), 0)
  above <- ifelse(!is.na(y) & y > upper, (2 / alpha) * (y - upper), 0)

  out <- width + below + above
  out[is.na(y)] <- NA_real_
  out
}

# ── 2. False-positive risk at equipoise ─────────────────────────────────────

#' False-positive risk for a p-value at an equipoise prior
#'
#' Converts a p-value into the probability that the null is true, given a
#' 50/50 prior, using the Sellke-Bayarri-Berger minimum-Bayes-factor
#' calibration \eqn{B(p) = -e \, p \ln p}.  The returned value is
#' \eqn{B / (1 + B)}.
#'
#' The project's \code{statistical-reporting} rule requires this to be
#' reported alongside any p-value: \code{p = 0.05} corresponds to a
#' false-positive risk near 29\%, not 5\%.
#'
#' @param p Numeric vector of p-values.
#'
#' @return Numeric vector the same length as \code{p}.  \code{NA_real_} where
#'   \code{p >= exp(-1)}, above which the bound is not defined (the
#'   calibration only applies to p-values small enough to be evidential).
#'
#' @examples
#' hd_fpr_equipoise(c(0.05, 0.01, 0.001))
#'
#' @family calibration
#' @export
hd_fpr_equipoise <- function(p) {
  p <- as.numeric(p)
  out <- rep(NA_real_, length(p))
  ok <- !is.na(p) & p > 0 & p < exp(-1)
  b <- -exp(1) * p[ok] * log(p[ok])
  out[ok] <- b / (1 + b)
  out
}

# ── 3. Coverage summary ─────────────────────────────────────────────────────

#' Realised coverage of a set of stated intervals
#'
#' Summarises how often outcomes fell inside the intervals that were stated
#' for them, and how that compares with the nominal rate.
#'
#' **Over-coverage is a defect, not free safety.** An interval that contains
#' 84\% of outcomes when it claimed 50\% is miscalibrated in a way that
#' destroys its information content, and this function flags it as loudly as
#' under-coverage.
#'
#' **Effective sample size.** When intervals are produced on a rolling origin
#' with a horizon longer than the step, consecutive observations share most of
#' their outcome window and are not independent.  Pass the overlap factor
#' (\code{horizon / step}) as \code{overlap}; the reported p-value is computed
#' on \code{n_eff = n / overlap}, not on \code{n}.  A binomial p-value on the
#' nominal \code{n} of overlapping windows can be wrong by orders of
#' magnitude.
#'
#' @param y Numeric vector of realised outcomes.  \code{NA} entries are
#'   dropped from both numerator and denominator.
#' @param lower,upper Numeric.  Stated interval bounds, length 1 or
#'   \code{length(y)}.
#' @param nominal Numeric scalar in \code{(0, 1)}.  The coverage the intervals
#'   claimed, e.g. \code{0.90} for a 5th-95th percentile interval.
#' @param overlap Numeric scalar \code{>= 1}.  Number of consecutive
#'   observations sharing an outcome window.  Default \code{1} (independent).
#' @param p_threshold Numeric scalar.  p-value below which coverage is called
#'   inconsistent with nominal.  Default \code{0.05}.
#'
#' @return A one-row tibble with columns \code{n}, \code{n_eff},
#'   \code{n_covered}, \code{coverage}, \code{nominal}, \code{excess},
#'   \code{mean_width}, \code{mean_interval_score}, \code{p_binom_eff},
#'   \code{fpr_equipoise} and \code{verdict} (one of \code{"consistent"},
#'   \code{"over_covered"}, \code{"under_covered"}, \code{"insufficient_data"}).
#'
#' @examples
#' # 20 of 20 outcomes inside a stated 50% interval - badly over-covered
#' hd_interval_coverage(
#'   y = rep(0, 20), lower = rep(-1, 20), upper = rep(1, 20), nominal = 0.5
#' )
#'
#' @family calibration
#' @export
hd_interval_coverage <- function(y, lower, upper, nominal,
                                 overlap = 1, p_threshold = 0.05) {
  if (!is.numeric(nominal) || length(nominal) != 1L || is.na(nominal) ||
      nominal <= 0 || nominal >= 1) {
    cli::cli_abort(c(
      "x" = "{.arg nominal} must be a single number in (0, 1).",
      "i" = "A 5th-95th percentile interval has {.code nominal = 0.9}.",
      "x" = "Got: {.val {nominal}}"
    ))
  }
  if (!is.numeric(overlap) || length(overlap) != 1L || is.na(overlap) ||
      overlap < 1) {
    cli::cli_abort(c(
      "x" = "{.arg overlap} must be a single number >= 1.",
      "i" = "Pass {.code horizon / step} for rolling-origin windows; {.code 1} means independent.",
      "x" = "Got: {.val {overlap}}"
    ))
  }

  alpha <- 1 - nominal
  y <- as.numeric(y)
  n_in <- length(y)
  lower <- .hd_recycle_bound(lower, n_in, "lower")
  upper <- .hd_recycle_bound(upper, n_in, "upper")

  score <- hd_interval_score(y, lower, upper, alpha = alpha)

  keep <- !is.na(y) & !is.na(lower) & !is.na(upper)
  y <- y[keep]; lower <- lower[keep]; upper <- upper[keep]; score <- score[keep]

  n <- length(y)
  if (n == 0L) {
    return(tibble::tibble(
      n = 0L, n_eff = 0, n_covered = 0L, coverage = NA_real_,
      nominal = nominal, excess = NA_real_, mean_width = NA_real_,
      mean_interval_score = NA_real_, p_binom_eff = NA_real_,
      fpr_equipoise = NA_real_, verdict = "insufficient_data"
    ))
  }

  covered <- y >= lower & y <= upper
  n_covered <- sum(covered)
  coverage <- n_covered / n
  n_eff <- n / overlap

  # Binomial test on the EFFECTIVE count, never the nominal one.  Rounding to
  # at least 1 trial keeps binom.test defined at very small n_eff; the p-value
  # is then uninformative by construction, which is the honest outcome.
  n_eff_trials <- max(1L, as.integer(round(n_eff)))
  n_eff_cov <- as.integer(round(coverage * n_eff_trials))
  p_binom <- stats::binom.test(n_eff_cov, n_eff_trials, p = nominal)$p.value

  verdict <- if (p_binom >= p_threshold) {
    "consistent"
  } else if (coverage > nominal) {
    "over_covered"
  } else {
    "under_covered"
  }

  tibble::tibble(
    n                   = as.integer(n),
    n_eff               = n_eff,
    n_covered           = as.integer(n_covered),
    coverage            = coverage,
    nominal             = nominal,
    excess              = coverage - nominal,
    mean_width          = mean(upper - lower),
    mean_interval_score = mean(score),
    p_binom_eff         = p_binom,
    fpr_equipoise       = hd_fpr_equipoise(p_binom),
    verdict             = verdict
  )
}

# ── 4. Block-bootstrap Sharpe interval ──────────────────────────────────────

#' Block-bootstrap confidence interval for the geometric Sharpe ratio
#'
#' Resamples contiguous blocks of returns with replacement and reports
#' percentile bounds on the Sharpe ratio.  The Sharpe is computed
#' geometrically — \code{CAGR / (sd(ret) * sqrt(periods_per_year))} — matching
#' the definition used in \code{R/plan_bootstrap_ci.R}.
#'
#' @section Contiguity assumption:
#' Blocks are drawn from row order, so this function assumes the supplied
#' series is **calendar-contiguous**.  Passing a series with gaps splices
#' non-adjacent periods into a single block and defeats the purpose of block
#' resampling.  See issue #603.
#'
#' @section Relationship to plan_bootstrap_ci.R:
#' This function reproduces the resampling in \code{R/plan_bootstrap_ci.R} so
#' that \code{qa_interval_coverage} tests the interval we actually publish
#' rather than a differently-specified one.  \code{plan_bootstrap_ci.R} has
#' not yet been migrated to call it — see issue #603 — so any change here must
#' be mirrored there until that migration lands.
#'
#' @param ret Numeric vector of periodic returns as decimals (0.01 = +1\%).
#' @param n_draws Integer.  Number of bootstrap draws.  Default \code{1000L}.
#' @param block_size Integer.  Periods per block.  Default \code{3L}.
#' @param ci_lo,ci_hi Numeric.  Percentile bounds.  Defaults \code{0.05} and
#'   \code{0.95}, giving a 90\% interval.
#' @param seed Integer or \code{NULL}.  If supplied, the RNG is seeded and the
#'   caller's RNG state is restored on exit.
#' @param periods_per_year Integer.  Annualisation factor.  Default \code{12L}
#'   (monthly).
#'
#' @return A one-row tibble with \code{sharpe_mean}, \code{sharpe_lo},
#'   \code{sharpe_hi}, \code{n_obs}, \code{n_draws} and \code{block_size}.
#'
#' @examples
#' set.seed(1)
#' hd_block_boot_sharpe_ci(stats::rnorm(60, 0.008, 0.04), n_draws = 100L, seed = 42L)
#'
#' @family calibration
#' @export
hd_block_boot_sharpe_ci <- function(ret, n_draws = 1000L, block_size = 3L,
                                    ci_lo = 0.05, ci_hi = 0.95, seed = NULL,
                                    periods_per_year = 12L) {
  ret <- as.numeric(ret)
  ret <- ret[!is.na(ret)]
  n <- length(ret)

  if (n < block_size) {
    cli::cli_abort(c(
      "x" = "Series has {n} non-NA observation{?s} but {.arg block_size} is {block_size}.",
      "i" = "A block bootstrap needs at least one full block.",
      "i" = "Either lengthen the series or reduce {.arg block_size}."
    ))
  }
  if (n < 2L) {
    cli::cli_abort(c(
      "x" = "Series has {n} non-NA observation{?s}; need at least 2 to compute a standard deviation."
    ))
  }
  if (any(ret <= -1)) {
    bad <- which(ret <= -1)
    cli::cli_abort(c(
      "x" = "{length(bad)} return{?s} at or below -100% at index {bad[1]}{cli::qty(length(bad))}{?/ (and others)}.",
      "i" = "The geometric Sharpe is undefined once {.code prod(1 + ret)} is non-positive.",
      "i" = "This is a data defect - investigate the source series rather than filtering it."
    ))
  }

  if (!is.null(seed)) {
    if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
      old_seed <- get(".Random.seed", envir = globalenv(), inherits = FALSE)
      on.exit(assign(".Random.seed", old_seed, envir = globalenv()), add = TRUE)
    } else {
      on.exit(suppressWarnings(rm(".Random.seed", envir = globalenv())), add = TRUE)
    }
    set.seed(seed)
  }

  ann <- as.integer(periods_per_year)
  n_blocks <- ceiling(n / block_size)
  max_start <- n - block_size + 1L

  sharpe_calc <- function(x) {
    vol <- stats::sd(x) * sqrt(ann)
    if (!is.finite(vol) || vol <= 0) return(NA_real_)
    cagr <- prod(1 + x)^(ann / length(x)) - 1
    cagr / vol
  }

  draws <- vapply(seq_len(as.integer(n_draws)), function(i) {
    starts <- sample.int(max_start, n_blocks, replace = TRUE)
    idx <- unlist(lapply(starts, function(s) s:(s + block_size - 1L)))
    sharpe_calc(ret[idx[seq_len(n)]])
  }, numeric(1))

  tibble::tibble(
    sharpe_mean = mean(draws, na.rm = TRUE),
    sharpe_lo   = unname(stats::quantile(draws, ci_lo, na.rm = TRUE)),
    sharpe_hi   = unname(stats::quantile(draws, ci_hi, na.rm = TRUE)),
    n_obs       = as.integer(n),
    n_draws     = as.integer(n_draws),
    block_size  = as.integer(block_size)
  )
}
