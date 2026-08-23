# Prospective statistical power: is the sample long enough to detect the
# effect being claimed?
#
# Origin: issue #711 Gap 1. Every multiple-testing tool this package already
# has (hd_deflated_sharpe(), hd_strat_keff_vertox(), hd_hac_sharpe(), the
# null environments in falsification.R) is RETROSPECTIVE -- given a
# backtest, how likely is the observed result under a null. None of them is
# PROSPECTIVE: before trusting a backtest, was the sample even long enough
# to detect an effect of the size being claimed, or is the study
# underpowered regardless of what it found. hd_detection_power() answers
# that question.
#
# The constants in issue #711 (~2500 bars for SNR 2, quoting a third-party
# article read only in summarised form) are DELIBERATELY NOT used here --
# see the issue's own method caveat. The formula below is derived from the
# same Lo (2002) / Mertens (2002) asymptotic Sharpe-ratio variance already
# used by hd_deflated_sharpe() (see that function's `var_sr` line), applied
# to a standard one-sided power calculation. It is independently checkable
# against `stats::qnorm()`/`stats::pnorm()` -- see the roxygen derivation
# and packages/historicaldata/tests/testthat/test-hd-detection-power.R.

#' Prospective statistical power to detect a claimed Sharpe ratio
#'
#' Answers a question none of this package's other multiple-testing tools
#' answer: is the sample long enough to detect an effect of the size being
#' claimed, or is the result underpowered regardless of what it found. Given
#' a claimed annualised Sharpe ratio, this computes (a) the power of a
#' one-sided test to distinguish it from zero at a given sample length, and
#' (b) the minimum sample length needed to reach a target power -- both from
#' the same closed-form derivation, so a caller can ask either question
#' without duplicating the effect-size/variance machinery.
#'
#' @section Derivation:
#' For a sample Sharpe ratio \eqn{\widehat{SR} = \bar r / \hat\sigma}
#' estimated from \eqn{T} (approximately) iid returns, the asymptotic
#' sampling variance is (Lo, 2002; Mertens, 2002):
#' \deqn{Var(\widehat{SR}) \approx \frac{1 - \gamma_3 \cdot SR + \frac{\gamma_4 - 1}{4} SR^2}{T}}
#' where \eqn{\gamma_3} is skewness and \eqn{\gamma_4} is (non-excess)
#' kurtosis. This is the SAME formula already implemented by
#' \code{\link{hd_deflated_sharpe}} (see its \code{var_sr} line). Under the
#' normal-returns simplification (\eqn{\gamma_3 = 0}, \eqn{\gamma_4 = 3}) it
#' reduces to:
#' \deqn{Var(\widehat{SR}) \approx \frac{1 + SR^2/2}{T}}
#'
#' A one-sided test of \eqn{H_0: SR = 0} against \eqn{H_1: SR = SR_1 > 0} at
#' level \eqn{\alpha} rejects when \eqn{\widehat{SR} > z_{1-\alpha} \cdot SE_0}
#' where \eqn{SE_0 = \sqrt{1/T}} is the standard error UNDER THE NULL
#' (\eqn{SR = 0}, so the \eqn{SR^2/2} term vanishes). Writing
#' \eqn{SE_1 = \sqrt{(1 + SR_1^2/2)/T}} for the standard error under the
#' alternative, the power of this test is the standard unequal-variance
#' z-test result:
#' \deqn{\text{power} = \Phi\left(\frac{SR_1 - z_{1-\alpha} \cdot SE_0}{SE_1}\right)}
#'
#' Both \eqn{SE_0} and \eqn{SE_1} scale as \eqn{c/\sqrt{T}} for constants
#' \eqn{c_0 = 1} and \eqn{c_1 = \sqrt{1 + SR_1^2/2}} that do not depend on
#' \eqn{T}. Substituting and solving the same power equation for \eqn{T} at
#' a target power \eqn{1 - \beta} therefore has an EXACT closed form (no
#' root-finding, no numerical optimisation):
#' \deqn{T_{min} = \left(\frac{z_{1-\beta} \cdot c_1 + z_{1-\alpha} \cdot c_0}{SR_1}\right)^2}
#'
#' \eqn{SR_1} above is the PER-PERIOD Sharpe ratio. \code{sharpe_annual} is
#' converted via \eqn{SR_1 = sharpe\_annual / \sqrt{ann\_factor}}, the same
#' \eqn{\sqrt{T}}-scaling convention used throughout this package (e.g.
#' \code{hd_hac_sharpe()}'s \code{annualised_vol <- stats::sd(r) * sqrt(ann_factor)}).
#'
#' A useful special case for verifying the implementation independently:
#' at \code{target_power = 0.5}, \eqn{z_{1-\beta} = 0} and the \eqn{c_1}
#' term drops out entirely, giving the parameter-free
#' \eqn{T_{min} = (z_{1-\alpha} / SR_1)^2} exactly.
#'
#' @section Assumptions and limits:
#' \itemize{
#'   \item \strong{NOT HAC-aware.} The variance formula assumes (in
#'     expectation) iid returns. Positive autocorrelation inflates the true
#'     sampling variance beyond this formula, so \code{min_n_periods} here
#'     is a LOWER BOUND on the sample actually needed -- an autocorrelated
#'     series needs strictly more observations than this function reports.
#'     For inference on an ALREADY-COLLECTED sample, use
#'     \code{\link{hd_hac_tstat}} / \code{\link{hd_hac_sharpe}}, which
#'     correct for autocorrelation directly using the observed data; this
#'     function answers a different, PROSPECTIVE question (how much data
#'     would be needed) for which no HAC correction is possible without
#'     already knowing the autocorrelation structure being planned for.
#'   \item Assumes (approximately) normally distributed returns. Fat tails
#'     (excess kurtosis) or skew inflate \eqn{Var(\widehat{SR})} beyond this
#'     formula -- the general formula above shows exactly how; this function
#'     uses the normal-returns case because, prospectively, no data exists
#'     yet from which to estimate skew/kurtosis (the same reason
#'     \code{\link{hd_deflated_sharpe}} must estimate them from data it
#'     already has, which this function does not).
#'   \item One-sided test only (\eqn{H_1: SR > 0}). \code{sharpe_annual}
#'     must be positive -- see Details.
#'   \item Does not itself apply a multiple-testing correction. Combine with
#'     \code{\link{hd_strat_keff_vertox}} by tightening \code{alpha} (e.g.
#'     Bonferroni: \code{alpha / k_eff_leaderboard}) if testing several
#'     strategies.
#' }
#'
#' @param sharpe_annual Numeric scalar, must be > 0. The annualised Sharpe
#'   ratio being claimed (the effect size to detect). Use the same
#'   annualised-Sharpe convention as the rest of this package (e.g.
#'   \code{\link{hd_hac_sharpe}}'s \code{naive_sharpe}, or a leaderboard
#'   row's \code{sharpe} column).
#' @param n_obs \code{NULL}, or a numeric scalar >= 2. The ACTUAL number of
#'   return observations in the sample, in the SAME periodicity as
#'   \code{ann_factor} (e.g. months of monthly returns when
#'   \code{ann_factor = 12}; days of daily returns when
#'   \code{ann_factor = 252}). When supplied, \code{power} and
#'   \code{underpowered} are computed against it. When \code{NULL} (the
#'   default), only the minimum-sample-size fields are returned and
#'   \code{power}/\code{underpowered} are \code{NA}.
#' @param ann_factor Numeric scalar, must be > 0. Periods per year for the
#'   return series (12 = monthly, 252 = daily, 52 = weekly). Default `12`.
#' @param alpha Numeric scalar in `(0, 1)`. One-sided significance level for
#'   the test \eqn{H_0: SR = 0} vs \eqn{H_1: SR = sharpe\_annual > 0}.
#'   Default `0.05`.
#' @param target_power Numeric scalar in `(0, 1)`. Target power used to
#'   compute \code{min_n_periods}/\code{min_n_years}. Default `0.80`.
#'
#' @return Named list:
#'   \describe{
#'     \item{power}{Power of the test at \code{n_obs} periods (`NA` if
#'       \code{n_obs} is `NULL`).}
#'     \item{underpowered}{Logical: is \code{n_obs} below \code{min_n_periods}?
#'       (`NA` if \code{n_obs} is `NULL`).}
#'     \item{min_n_periods}{Minimum sample length, in periods matching
#'       \code{ann_factor}, for \code{target_power} at \code{alpha}.}
#'     \item{min_n_years}{\code{min_n_periods / ann_factor} -- comparable
#'       across strategies of different periodicity, unlike
#'       \code{min_n_periods}.}
#'     \item{n_obs, sharpe_annual, sharpe_period, ann_factor, alpha,
#'       target_power}{Echoed inputs (\code{n_obs} as \code{NA_real_} if
#'       \code{NULL}; \code{sharpe_period} is the per-period conversion of
#'       \code{sharpe_annual} used internally).}
#'   }
#'
#' @references
#' Lo, A. W. (2002). "The Statistics of Sharpe Ratios." \emph{Financial
#' Analysts Journal}, 58(4), 36-52.
#'
#' Mertens, E. (2002). "Comments on variance of the IID estimator in Lo
#' (2002)." Unpublished working note (the correction to Lo's original
#' variance formula that \code{\link{hd_deflated_sharpe}}'s \code{var_sr}
#' line also implements).
#'
#' @examples
#' # Power to detect an annualised Sharpe of 0.5 with 3 years of monthly data
#' hd_detection_power(sharpe_annual = 0.5, n_obs = 36, ann_factor = 12)
#'
#' # How many months of data would be needed for 80% power?
#' hd_detection_power(sharpe_annual = 0.5, ann_factor = 12)$min_n_periods
#'
#' @family falsification
#' @export
hd_detection_power <- function(sharpe_annual, n_obs = NULL, ann_factor = 12,
                                alpha = 0.05, target_power = 0.80) {
  if (!is.numeric(sharpe_annual) || length(sharpe_annual) != 1L ||
      is.na(sharpe_annual) || sharpe_annual <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg sharpe_annual} must be a single positive number.",
      "i" = "Got {.val {sharpe_annual}}.",
      "i" = paste0(
        "hd_detection_power() tests a one-sided H1: SR > 0 -- a non-positive ",
        "or missing claimed effect has no power to compute."
      )
    ))
  }
  if (!is.numeric(ann_factor) || length(ann_factor) != 1L ||
      is.na(ann_factor) || ann_factor <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg ann_factor} must be a single positive number.",
      "i" = "Got {.val {ann_factor}}."
    ))
  }
  if (!is.numeric(alpha) || length(alpha) != 1L || is.na(alpha) ||
      alpha <= 0 || alpha >= 1) {
    cli::cli_abort(c(
      "x" = "{.arg alpha} must be a single number strictly between 0 and 1.",
      "i" = "Got {.val {alpha}}."
    ))
  }
  if (!is.numeric(target_power) || length(target_power) != 1L ||
      is.na(target_power) || target_power <= 0 || target_power >= 1) {
    cli::cli_abort(c(
      "x" = "{.arg target_power} must be a single number strictly between 0 and 1.",
      "i" = "Got {.val {target_power}}."
    ))
  }
  if (!is.null(n_obs)) {
    if (!is.numeric(n_obs) || length(n_obs) != 1L || is.na(n_obs) || n_obs < 2) {
      cli::cli_abort(c(
        "x" = "{.arg n_obs} must be NULL or a single number >= 2.",
        "i" = "Got {.val {n_obs}}."
      ))
    }
  }

  sr_period <- sharpe_annual / sqrt(ann_factor)

  z_alpha <- stats::qnorm(1 - alpha)
  z_beta  <- stats::qnorm(target_power)
  c0 <- 1
  c1 <- sqrt(1 + 0.5 * sr_period^2)

  min_n_periods <- ((z_beta * c1 + z_alpha * c0) / sr_period)^2
  min_n_years   <- min_n_periods / ann_factor

  if (is.null(n_obs)) {
    power        <- NA_real_
    underpowered <- NA
  } else {
    se_h0 <- c0 / sqrt(n_obs)
    se_h1 <- c1 / sqrt(n_obs)
    power        <- stats::pnorm((sr_period - z_alpha * se_h0) / se_h1)
    underpowered <- n_obs < min_n_periods
  }

  list(
    power         = power,
    underpowered  = underpowered,
    min_n_periods = min_n_periods,
    min_n_years   = min_n_years,
    n_obs         = if (is.null(n_obs)) NA_real_ else n_obs,
    sharpe_annual = sharpe_annual,
    sharpe_period = sr_period,
    ann_factor    = ann_factor,
    alpha         = alpha,
    target_power  = target_power
  )
}
