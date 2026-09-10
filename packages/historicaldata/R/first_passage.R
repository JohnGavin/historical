# First-passage / gambler's-ruin barrier-crossing probability.
#
# Origin: issue #586 G1. Every risk metric this package computes -- max DD,
# CVaR 95%, vol, Sharpe, SSR -- is TERMINAL or full-sample. None answers the
# PATH question: what is the probability of touching a lower barrier (e.g. a
# drawdown floor) before an upper barrier (e.g. a profit target), given a
# strategy's drift and volatility. Two strategies with identical max
# drawdown and Sharpe can have very different breach probabilities, and
# nothing in this package could previously distinguish them.
#
# Scope note (dispatch for #586/#588, 2026-08): this implements the
# CLOSED-FORM drifted-Brownian-motion case only -- the general two-barrier
# gambler's-ruin formula, which reduces exactly to the article's symmetric
# simplification P(pass) = 1/(1+exp(-theta)), theta = 2*mu*T/sigma^2, when
# upper == lower. Explicitly DEFERRED, per #586's own proposed scope:
#   - simulation fallback for empirical (fat-tailed) return paths -- the
#     closed form assumes iid Gaussian increments and is optimistic under
#     fat tails, same caveat as hd_detection_power()'s Assumptions section;
#   - finite-horizon conditioning (P(breach within N months) as opposed to
#     P(breach ever)) -- requires the inverse-Gaussian first-passage-TIME
#     distribution (one-sided) or a Brownian-bridge simulation (two-sided),
#     neither of which is implemented here;
#   - the parameterised "prop-constrained view" (#586 second comment) that
#     re-ranks strategies by survivability under an arbitrary
#     (floor, daily_limit, horizon, target) tuple.
# Tracked as follow-up work; see the issue for the full proposed shape.

#' First-passage (gambler's-ruin) probability for a drifted Brownian motion
#'
#' Given a strategy's per-period drift and volatility, computes the
#' probability that a Brownian-motion approximation of its cumulative
#' return path hits an UPPER barrier (e.g. a profit target) before a LOWER
#' barrier (e.g. a drawdown floor). This is the path question none of this
#' package's other risk metrics answer -- they are all terminal/aggregate
#' (max drawdown, CVaR, vol, Sharpe), not path-dependent.
#'
#' @section Derivation:
#' For a Brownian motion \eqn{X_t = \mu t + \sigma W_t} started at
#' \eqn{X_0 = 0}, with an upper absorbing barrier at \eqn{+b} (\code{upper})
#' and a lower absorbing barrier at \eqn{-a} (\code{lower}), the classical
#' two-barrier gambler's-ruin result (Karlin & Taylor, \emph{A First Course
#' in Stochastic Processes}) gives the probability of hitting \eqn{+b}
#' before \eqn{-a} as:
#' \deqn{P(\text{hit } b \text{ first}) = \frac{1 - e^{2\mu a/\sigma^2}}{e^{-2\mu b/\sigma^2} - e^{2\mu a/\sigma^2}}}
#' When the barriers are SYMMETRIC (\code{upper == lower == T}), this
#' reduces algebraically to the logistic form quoted by the source article:
#' \deqn{P(\text{pass}) = \frac{1}{1 + e^{-\theta}}, \quad \theta = \frac{2\mu T}{\sigma^2}}
#' (substitute \eqn{a = b = T}: numerator and denominator each factor as
#' \eqn{\mp(e^\theta - 1)} and \eqn{\mp(e^\theta - e^{-\theta})}, and
#' \eqn{e^\theta - e^{-\theta} = (e^\theta-1)(1+e^{-\theta})} gives the
#' logistic identity directly). When \eqn{\mu = 0} (no drift), the formula
#' has a removable singularity and this function uses the driftless
#' gambler's-ruin limit \eqn{P = a / (a + b)} instead (linear interpolation
#' by distance to the OPPOSITE barrier -- the standard result for a
#' driftless random walk / martingale).
#'
#' @section Assumptions and limits:
#' \itemize{
#'   \item \strong{Infinite horizon.} This is \eqn{P(\text{ever hits } b
#'     \text{ before } -a)}, with no time limit. It does NOT answer "within
#'     N months" -- that needs the first-passage-TIME distribution, which
#'     this function does not compute (see the file-level scope note).
#'   \item \strong{Gaussian, iid increments assumed.} Real return paths have
#'     fat tails and autocorrelation; both make barrier breaches MORE likely
#'     than this closed form implies, i.e. \code{pass_prob} is an OPTIMISTIC
#'     (upper) bound on survivability, not a point estimate to trust exactly
#'     -- same caveat as \code{\link{hd_detection_power}}'s Gaussian
#'     assumption. A simulation-based fallback over empirical return paths
#'     (fat-tail-aware) is deferred -- see the file-level scope note.
#'   \item \code{mu} and \code{sigma} must be in the SAME return units as
#'     \code{upper}/\code{lower} (e.g. all four as PER-PERIOD fractions --
#'     do not mix an annualised \code{mu} with per-period \code{sigma}).
#' }
#'
#' @source Delphic Alpha, "Prop Firm Math: What the Rules Actually Cost
#'   You" (2026), whose reported closed form (in the symmetric case) is the
#'   \eqn{\theta}-logistic identity above.
#'   \url{https://delphicalpha.substack.com/p/prop-firm-math-what-the-rules-actually}
#'
#' @param mu Numeric scalar. Per-period drift (mean return), any sign.
#' @param sigma Numeric scalar, must be > 0. Per-period volatility.
#' @param upper Numeric scalar, must be > 0. Distance to the upper barrier
#'   (e.g. a profit target), in the same units as \code{mu}/\code{sigma}
#'   (e.g. \code{0.10} for a +10% target).
#' @param lower Numeric scalar, must be > 0. Distance to the lower barrier
#'   (e.g. a drawdown floor), same units. Default \code{upper} (the
#'   symmetric case the source article's closed form describes).
#'
#' @return Named list:
#'   \describe{
#'     \item{pass_prob}{Probability of hitting the upper barrier before the
#'       lower barrier (infinite horizon). \code{NA_real_} if the closed
#'       form is not finite (extreme parameter combinations -- see
#'       Assumptions).}
#'     \item{theta}{\eqn{2\mu T/\sigma^2} when \code{upper == lower == T}
#'       (matches the source article's symmetric-case parameter exactly).
#'       \code{NA_real_} for asymmetric barriers, where no single
#'       \eqn{\theta} exists.}
#'     \item{mu, sigma, upper, lower}{Echoed inputs.}
#'   }
#'
#' @references
#' Karlin, S. and Taylor, H. M. (1975). \emph{A First Course in Stochastic
#' Processes}, 2nd ed. Academic Press. (Two-barrier gambler's-ruin exit
#' probability for Brownian motion with drift.)
#'
#' @examples
#' # Symmetric +/-10% barriers, matching the source article's convention
#' hd_first_passage(mu = 0.001, sigma = 0.02, upper = 0.10)
#'
#' # Verify the logistic identity directly for the symmetric case
#' theta <- 2 * 0.001 * 0.10 / 0.02^2
#' 1 / (1 + exp(-theta))
#'
#' @family risk_metrics
#' @export
hd_first_passage <- function(mu, sigma, upper, lower = upper) {
  if (!is.numeric(mu) || length(mu) != 1L || is.na(mu)) {
    cli::cli_abort(c(
      "x" = "{.arg mu} must be a single non-missing number.",
      "i" = "Got {.val {mu}}."
    ))
  }
  if (!is.numeric(sigma) || length(sigma) != 1L || is.na(sigma) || sigma <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg sigma} must be a single positive number.",
      "i" = "Got {.val {sigma}}."
    ))
  }
  if (!is.numeric(upper) || length(upper) != 1L || is.na(upper) || upper <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg upper} must be a single positive number.",
      "i" = "Got {.val {upper}}."
    ))
  }
  if (!is.numeric(lower) || length(lower) != 1L || is.na(lower) || lower <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg lower} must be a single positive number.",
      "i" = "Got {.val {lower}}."
    ))
  }

  symmetric <- isTRUE(all.equal(upper, lower))
  theta <- if (symmetric) 2 * mu * upper / sigma^2 else NA_real_

  if (abs(mu) < 1e-12) {
    # Driftless limit: standard gambler's-ruin result for a martingale --
    # probability of hitting +upper first is proportional to the distance
    # to the OPPOSITE barrier.
    pass_prob <- lower / (lower + upper)
  } else {
    theta_a <- 2 * mu * lower / sigma^2
    theta_b <- 2 * mu * upper / sigma^2
    num <- -expm1(theta_a)              # 1 - exp(theta_a), numerically stable near 0
    den <- exp(-theta_b) - exp(theta_a)
    pass_prob <- num / den
    if (!is.finite(pass_prob)) pass_prob <- NA_real_
  }

  list(
    pass_prob = pass_prob,
    theta     = theta,
    mu        = mu,
    sigma     = sigma,
    upper     = upper,
    lower     = lower
  )
}
