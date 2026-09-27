# Probabilistic Sharpe Ratio: given the sample we have, how confident are we
# the TRUE Sharpe exceeds a benchmark?
#
# Origin: issue #851, prompted by StratProof's "I built the paper-spec
# crypto momentum strategy on 5.8 years of data. It has lost money every
# year since 2024." (Patrick Mortenson, Sep 2 2026), which reports
# "Probability the true Sharpe is greater than zero: 81% (need 95%+ to call
# this signal, not noise)" as its actual accept/reject bar.
#
# This is a DIFFERENT statistical object from hd_detection_power()'s T_min/
# power -- see that function's own header comment and
# .claude/rules/detection-power-required.md. hd_detection_power() asks "is
# the sample long enough to detect this effect if it's real" (PROSPECTIVE,
# frequentist power). hd_prob_sharpe_positive() asks "given the sample we
# have, how confident are we the sign is actually positive"
# (RETROSPECTIVE, a Bailey & Lopez de Prado "Probabilistic Sharpe Ratio",
# PSR). A strategy can be adequately sampled (power-sufficient) and still
# have a low P(SR > 0) if the point estimate is weak, and vice versa -- the
# two are complementary, not redundant (#851 proposed work item 1).
#
# REUSE, NOT RE-DERIVATION (per this repo's own premise check before
# building this): hd_deflated_sharpe() (R/falsification.R) already computes
# EXACTLY this quantity as a byproduct of its own hurdle test -- at
# K_trials = 1 (its default), its benchmark E[max SR] is 0, so
# `1 - hd_deflated_sharpe(r, K_trials = 1)$dsr_pvalue` IS P(true SR > 0),
# computed from the identical Lo (2002) / Mertens (2002) `var_sr` line this
# function reuses (see hd_deflated_sharpe()'s "Variance-aware hurdle" roxygen
# section and its `var_sr <- (1 - m3 * sr + (m4 - 1) / 4 * sr^2) / T_obs`
# line). This function is NOT a re-derivation of that formula -- it is the
# SAME formula, exposed as a standalone, documented, tested function that
# (a) takes summary statistics (sharpe/n_obs/skewness/kurtosis) rather than
# raw returns, for callers such as R/plan_leaderboard.R that do not have a
# raw return series at the row being computed (mirroring
# hd_detection_power()'s own summary-statistic API), and (b) offers a
# Bonferroni-style n_tests/correction argument pair consistent with
# hd_detection_power()'s #903 API, rather than hd_deflated_sharpe()'s
# different (also legitimate, already-implemented, already-tested)
# trial-count benchmark-shift mechanism -- see the "Multiple-testing
# correction" section below for why a DIFFERENT mechanism was chosen here
# despite the similar-looking argument names.

#' Probabilistic Sharpe Ratio: P(true Sharpe ratio > benchmark)
#'
#' Answers a RETROSPECTIVE question \code{\link{hd_detection_power}} does
#' not: given the observed Sharpe ratio, sample length, and return
#' distribution shape (skewness, kurtosis), what is the probability that the
#' TRUE (population) Sharpe ratio exceeds a benchmark (0 by default)? This is
#' the "Probabilistic Sharpe Ratio" (PSR) of Bailey & Lopez de Prado --
#' distinct from \code{\link{hd_detection_power}}'s PROSPECTIVE "is the
#' sample long enough to detect this effect if it's real" question. See
#' \code{.claude/rules/detection-power-required.md} and this function's
#' package source header comment for the full relationship.
#'
#' @section Derivation:
#' For a sample Sharpe ratio \eqn{\widehat{SR}} estimated from \eqn{T}
#' (approximately) iid returns, the asymptotic sampling variance (Lo, 2002;
#' Mertens, 2002) is
#' \deqn{\widehat{Var}(\widehat{SR}) = \frac{1 - \gamma_3 \widehat{SR} + \frac{\gamma_4 - 1}{4}\widehat{SR}^2}{T}}
#' where \eqn{\gamma_3} is skewness and \eqn{\gamma_4} is (non-excess)
#' kurtosis -- EXACTLY the formula already implemented by
#' \code{\link{hd_deflated_sharpe}}'s \code{var_sr} line (see that function's
#' "Variance-aware hurdle" roxygen section) and referenced in
#' \code{\link{hd_detection_power}}'s own "Derivation" section. This function
#' reuses it, not a re-derivation: \code{kurtosis} here is EXCESS kurtosis
#' (0 = normal), matching \code{hd_deflated_sharpe()}'s returned
#' \code{kurtosis} field, and \eqn{\gamma_4} is recovered internally as
#' \code{kurtosis + 3}.
#'
#' The Probabilistic Sharpe Ratio (Bailey & Lopez de Prado, 2012) is then
#' \deqn{PSR(SR^*) = \Phi\left(\frac{(\widehat{SR} - SR^*)}{\sqrt{\widehat{Var}(\widehat{SR})}}\right)}
#' where \eqn{SR^*} is the benchmark (\code{benchmark_annual}, 0 by default)
#' and \eqn{\Phi} is the standard normal CDF. \code{sharpe_annual} and
#' \code{benchmark_annual} are converted to per-period Sharpe via
#' \eqn{SR = sharpe\_annual / \sqrt{ann\_factor}}, the same convention used
#' throughout this package (e.g. \code{\link{hd_detection_power}}).
#'
#' @section Relationship to \code{hd_deflated_sharpe()}:
#' \code{hd_deflated_sharpe(r, K_trials = 1)$dsr_pvalue} is
#' \eqn{1 - PSR(0)} computed from raw returns \code{r} (which supplies its
#' own \code{skewness}/\code{kurtosis} from the sample). Passing the SAME
#' \code{sharpe_annual}, \code{n_obs}, \code{skewness}, \code{kurtosis} here
#' reproduces \code{1 - dsr_pvalue} to numerical precision -- see
#' \code{test-hd-prob-sharpe-positive.R}'s "reuses hd_deflated_sharpe()'s
#' variance formula exactly" test, which is this repository's falsification
#' of the reuse claim, not merely a shared citation. This function exists
#' as a standalone entry point because many callers (e.g.
#' \code{R/plan_leaderboard.R}, which computes this from summary statistics
#' per leaderboard row, mirroring \code{hd_detection_power}'s own call
#' pattern there) do not have a raw return series at hand, only
#' \code{sharpe}/\code{months}/\code{obs_ann_factor}.
#'
#' @section Multiple-testing correction:
#' \code{n_tests}/\code{correction} mirror \code{\link{hd_detection_power}}'s
#' #903 API in NAME and in the falsification contract (\code{n_tests = 1}
#' MUST reproduce the uncorrected figure exactly, for either
#' \code{correction} value -- verified by
#' \code{test-hd-prob-sharpe-positive.R}), but use a DIFFERENT mechanism,
#' deliberately: \code{hd_detection_power()}'s Bonferroni correction tightens
#' \strong{alpha} (a significance threshold feeding a sample-size
#' calculation); this function's Bonferroni correction rescales the
#' \strong{p-value itself} --
#' \eqn{p_{corrected} = \min(1, p \times n\_tests)}, the standard Bonferroni
#' p-value adjustment -- because the object this function reports IS a
#' probability, not a sample-size requirement, so there is no "alpha" to
#' tighten. \code{\link{hd_deflated_sharpe}} ALREADY implements a different,
#' also-legitimate multiple-testing correction for this same family of
#' statistics (shifting the benchmark itself via extreme-value theory over
#' \code{K_trials} trials, its \code{trial_sharpe_var}-aware hurdle) -- that
#' mechanism is reused, not duplicated, at the leaderboard's own
#' \code{strat_deflated_sharpe} target (\code{dsr_pvalue}), which already
#' has raw returns and a per-strategy \code{K_trials}. This function's
#' Bonferroni-p-value mechanism is the appropriate one specifically where
#' only summary statistics (no raw returns) are available, exactly the
#' \code{hd_detection_power()} call pattern it is designed to sit alongside.
#'
#' @section Non-computable inputs (fail-loud-not-null.md):
#' Two DIFFERENT failure modes are distinguished, per
#' \code{.claude/rules/fail-loud-not-null.md}: an invalid ARGUMENT (wrong
#' type, out-of-range, non-finite) aborts loudly via
#' \code{\link[cli]{cli_abort}} -- see Arguments below for each check. A
#' VALID argument combination that is nonetheless statistically
#' non-computable returns \code{NA} for every probability/p-value field,
#' with \code{reason} stating why -- NEVER \code{0.5} (which would silently
#' assert "no information", a substantive claim this function has not
#' earned) and never a silent fallback. The two non-computable paths are:
#' (a) \code{n_obs < 10} -- matching \code{\link{hd_deflated_sharpe}}'s own
#' \code{T_obs < 10} threshold for moment-estimator reliability, and (b) a
#' non-positive or non-finite estimated \eqn{\widehat{Var}(\widehat{SR})} --
#' an internally inconsistent \code{skewness}/\code{kurtosis}/
#' \code{sharpe_annual} combination that the Lo/Mertens formula itself
#' flags as invalid for a real sampling distribution.
#'
#' @param sharpe_annual Numeric scalar, finite. The OBSERVED annualised
#'   Sharpe ratio. Unlike \code{\link{hd_detection_power}} (which tests a
#'   one-sided \eqn{H_1: SR > 0} and therefore requires a positive claimed
#'   effect), this function answers a probability question that is
#'   meaningful for ANY observed Sharpe -- negative, zero, or positive --
#'   and does NOT require \code{sharpe_annual > 0}.
#' @param n_obs Numeric scalar >= 2. The number of return observations in
#'   the sample, in the SAME periodicity as \code{ann_factor}.
#'   \code{n_obs < 10} is a non-computable input (see above) -- returns NA
#'   with a stated reason rather than aborting, since it is a legitimate,
#'   if uninformative, sample size.
#' @param ann_factor Numeric scalar > 0. Periods per year (12 = monthly,
#'   252 = daily, 52 = weekly). Default `12`.
#' @param skewness Numeric scalar, finite. Sample skewness of returns
#'   (\eqn{\gamma_3} above). Default `0` (the normal-returns
#'   simplification -- the same simplification
#'   \code{\link{hd_detection_power}} uses when no raw returns are
#'   available to estimate this).
#' @param kurtosis Numeric scalar >= -2 (the theoretical floor for any real
#'   distribution), finite. Sample EXCESS kurtosis of returns (matching
#'   \code{\link{hd_deflated_sharpe}}'s returned \code{kurtosis} field --
#'   \eqn{\gamma_4} above is recovered as \code{kurtosis + 3}). Default `0`
#'   (normal).
#' @param benchmark_annual Numeric scalar, finite. The annualised Sharpe
#'   ratio benchmark to test against (\eqn{SR^*} above). Default `0` -- the
#'   StratProof article's benchmark, and the standard PSR test of
#'   \eqn{H_0: SR \le 0}.
#' @param n_tests Numeric scalar >= 1. The effective number of tests/
#'   strategies this claim is one of (e.g. a leaderboard's
#'   \code{k_eff_leaderboard}, \code{\link{hd_strat_keff_vertox}}). Default
#'   `1` (no correction). See "Multiple-testing correction" above.
#' @param correction One of `"none"` or `"bonferroni"` (partial matching via
#'   \code{\link[base]{match.arg}}). Default `"none"`.
#'
#' @return Named list:
#'   \describe{
#'     \item{prob_sharpe_positive}{\eqn{P(SR_{true} > benchmark)} -- `NA` if
#'       non-computable (see above), with \code{reason} stating why.}
#'     \item{pvalue}{\eqn{1 - }\code{prob_sharpe_positive} (\eqn{P(SR_{true} \le benchmark)}).}
#'     \item{reason}{\code{NA_character_} when computed; otherwise a string
#'       naming which non-computable path applied.}
#'     \item{n_obs, sharpe_annual, sharpe_period, ann_factor, skewness,
#'       kurtosis, benchmark_annual, benchmark_period}{Echoed/derived
#'       inputs.}
#'     \item{n_tests, correction}{Echoed inputs.}
#'     \item{pvalue_corrected}{\eqn{\min(1, pvalue \times n\_tests)} when
#'       \code{correction = "bonferroni"} and \code{n_tests > 1}; equal to
#'       \code{pvalue} otherwise (the falsification property -- see
#'       "Multiple-testing correction" above).}
#'     \item{prob_sharpe_positive_corrected}{\eqn{1 - }\code{pvalue_corrected}.
#'       Always \code{<= prob_sharpe_positive} (a Bonferroni p-value
#'       correction can only weakly increase the p-value, which can only
#'       weakly decrease the reported probability).}
#'   }
#'
#' @references
#' Bailey, D. H., & Lopez de Prado, M. (2012). "The Sharpe Ratio Efficient
#' Frontier." \emph{Journal of Risk}, 15(2), 3-44. (Probabilistic Sharpe
#' Ratio.)
#'
#' Lo, A. W. (2002). "The Statistics of Sharpe Ratios." \emph{Financial
#' Analysts Journal}, 58(4), 36-52.
#'
#' Mertens, E. (2002). "Comments on variance of the IID estimator in Lo
#' (2002)." Unpublished working note.
#'
#' @examples
#' # P(true Sharpe > 0) for an observed annualised Sharpe of 0.5 over 5 years
#' # of monthly data, assuming normal returns
#' hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, ann_factor = 12)
#'
#' # Same, but using the actual sample skewness/kurtosis from hd_deflated_sharpe()
#' d <- hd_deflated_sharpe(rnorm(120, 0.01, 0.05), ann_factor = 12)
#' hd_prob_sharpe_positive(
#'   sharpe_annual = d$naive_sharpe, n_obs = d$T, ann_factor = 12,
#'   skewness = d$skewness, kurtosis = d$kurtosis
#' )
#'
#' @family falsification
#' @export
hd_prob_sharpe_positive <- function(sharpe_annual, n_obs, ann_factor = 12,
                                     skewness = 0, kurtosis = 0,
                                     benchmark_annual = 0,
                                     n_tests = 1,
                                     correction = c("none", "bonferroni")) {
  correction <- match.arg(correction)

  if (!is.numeric(sharpe_annual) || length(sharpe_annual) != 1L ||
      is.na(sharpe_annual) || !is.finite(sharpe_annual)) {
    cli::cli_abort(c(
      "x" = "{.arg sharpe_annual} must be a single finite number.",
      "i" = "Got {.val {sharpe_annual}}.",
      "i" = paste0(
        "Unlike hd_detection_power(), hd_prob_sharpe_positive() does NOT ",
        "require a positive claimed effect -- P(SR_true > benchmark) is a ",
        "meaningful question for a negative or zero observed Sharpe too."
      )
    ))
  }
  if (!is.numeric(n_obs) || length(n_obs) != 1L || is.na(n_obs) || n_obs < 2) {
    cli::cli_abort(c(
      "x" = "{.arg n_obs} must be a single number >= 2.",
      "i" = "Got {.val {n_obs}}."
    ))
  }
  if (!is.numeric(ann_factor) || length(ann_factor) != 1L ||
      is.na(ann_factor) || ann_factor <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg ann_factor} must be a single positive number.",
      "i" = "Got {.val {ann_factor}}."
    ))
  }
  if (!is.numeric(skewness) || length(skewness) != 1L || is.na(skewness) ||
      !is.finite(skewness)) {
    cli::cli_abort(c(
      "x" = "{.arg skewness} must be a single finite number.",
      "i" = "Got {.val {skewness}}."
    ))
  }
  if (!is.numeric(kurtosis) || length(kurtosis) != 1L || is.na(kurtosis) ||
      !is.finite(kurtosis) || kurtosis < -2) {
    cli::cli_abort(c(
      "x" = "{.arg kurtosis} must be a single finite number >= -2.",
      "i" = "Got {.val {kurtosis}}.",
      "i" = paste0(
        "-2 is the theoretical floor for the EXCESS kurtosis of any real ",
        "distribution (raw kurtosis >= 1); a lower value cannot come from ",
        "a real sample."
      )
    ))
  }
  if (!is.numeric(benchmark_annual) || length(benchmark_annual) != 1L ||
      is.na(benchmark_annual) || !is.finite(benchmark_annual)) {
    cli::cli_abort(c(
      "x" = "{.arg benchmark_annual} must be a single finite number.",
      "i" = "Got {.val {benchmark_annual}}."
    ))
  }
  if (!is.numeric(n_tests) || length(n_tests) != 1L || is.na(n_tests) ||
      n_tests < 1) {
    cli::cli_abort(c(
      "x" = "{.arg n_tests} must be a single number >= 1.",
      "i" = "Got {.val {n_tests}}.",
      "i" = paste0(
        "n_tests is the effective number of tests this claim is one of -- ",
        "a value below 1 would SHRINK the corrected p-value, the opposite ",
        "of a correction."
      )
    ))
  }

  sr_period    <- sharpe_annual / sqrt(ann_factor)
  bench_period <- benchmark_annual / sqrt(ann_factor)

  na_out <- function(reason) {
    list(
      prob_sharpe_positive = NA_real_,
      pvalue                = NA_real_,
      reason                = reason,
      n_obs                 = n_obs,
      sharpe_annual         = sharpe_annual,
      sharpe_period         = sr_period,
      ann_factor            = ann_factor,
      skewness              = skewness,
      kurtosis              = kurtosis,
      benchmark_annual      = benchmark_annual,
      benchmark_period      = bench_period,
      n_tests               = n_tests,
      correction            = correction,
      pvalue_corrected                = NA_real_,
      prob_sharpe_positive_corrected  = NA_real_
    )
  }

  # ── Non-computable path (a): sample too short for a reliable moment-based
  # variance estimate -- matches hd_deflated_sharpe()'s own T_obs < 10
  # threshold exactly (see that function's early-return for the same reason).
  if (n_obs < 10) {
    return(na_out(paste0(
      "n_obs (", n_obs, ") < 10: sample too short for a reliable moment-",
      "based Sharpe-ratio variance estimate (matches hd_deflated_sharpe()'s ",
      "own T_obs < 10 threshold)."
    )))
  }

  # Lo (2002) / Mertens (2002) asymptotic variance of the Sharpe-ratio
  # estimator -- REUSED, not re-derived, from hd_deflated_sharpe()'s var_sr
  # line. kurtosis here is EXCESS kurtosis (0 = normal); m4 below is the
  # RAW (non-excess) kurtosis the formula itself uses.
  m4     <- kurtosis + 3
  var_sr <- (1 - skewness * sr_period + (m4 - 1) / 4 * sr_period^2) / n_obs

  # ── Non-computable path (b): the skewness/kurtosis/sharpe combination is
  # internally inconsistent with a real sampling distribution (negative
  # variance) -- the formula itself flags this; never coerce to |var_sr| or
  # a floor, which would silently manufacture a number for an invalid input.
  if (!is.finite(var_sr) || var_sr <= 0) {
    return(na_out(paste0(
      "Estimated Var(SR) is non-positive or non-finite (", format(var_sr, digits = 4),
      ") for sharpe_annual = ", format(sharpe_annual, digits = 4),
      ", skewness = ", format(skewness, digits = 4),
      ", kurtosis = ", format(kurtosis, digits = 4),
      " -- this skewness/kurtosis/Sharpe combination is inconsistent with a ",
      "real sampling distribution at this sample size."
    )))
  }

  se_sr  <- sqrt(var_sr)
  z      <- (sr_period - bench_period) / se_sr
  prob   <- stats::pnorm(z)
  pvalue <- 1 - prob

  # ── Multiple-testing correction (Bonferroni p-value adjustment; see the
  # "Multiple-testing correction" roxygen section above for why this differs
  # from hd_detection_power()'s alpha-tightening mechanism). n_tests = 1, or
  # correction = "none", leaves pvalue_corrected == pvalue EXACTLY -- the
  # falsification property test-hd-prob-sharpe-positive.R verifies for both
  # correction values.
  if (correction == "bonferroni" && n_tests > 1) {
    pvalue_corrected <- min(1, pvalue * n_tests)
  } else {
    pvalue_corrected <- pvalue
  }
  prob_corrected <- 1 - pvalue_corrected

  list(
    prob_sharpe_positive = prob,
    pvalue                = pvalue,
    reason                = NA_character_,
    n_obs                 = n_obs,
    sharpe_annual         = sharpe_annual,
    sharpe_period         = sr_period,
    ann_factor            = ann_factor,
    skewness              = skewness,
    kurtosis              = kurtosis,
    benchmark_annual      = benchmark_annual,
    benchmark_period      = bench_period,
    n_tests               = n_tests,
    correction            = correction,
    pvalue_corrected                = pvalue_corrected,
    prob_sharpe_positive_corrected  = prob_corrected
  )
}
