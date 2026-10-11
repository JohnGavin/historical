#' Expected maximum of K independent standard normals
#'
#' Exact (deterministic quadrature) value of \eqn{E[\max(Z_1,\dots,Z_K)]}
#' for \eqn{Z_i} iid \eqn{N(0,1)}. It is the multiple-testing benchmark used
#' by [hd_deflated_sharpe()]: the Sharpe ratio one expects to see from the
#' best of `K` null trials, in units of the trial-population standard
#' deviation.
#'
#' @details
#' The density of the maximum of `K` iid normals is
#' \eqn{K \phi(x) \Phi(x)^{K-1}}, so
#' \deqn{E[\max] = K \int_{-\infty}^{\infty} x\,\phi(x)\,\Phi(x)^{K-1}\,dx.}
#' The integral is evaluated with [stats::integrate()] (relative tolerance
#' `1e-12`). `K` need not be an integer: effective trial counts (for
#' example `K_eff_strat`) are real, and the integrand is well defined for any
#' real `K >= 1`. The integral is split at the mode (near
#' `qnorm(1 - 1/K)`) so the narrow peak at large `K` is never skipped, and
#' \eqn{\Phi^{K-1}} is evaluated as `exp((K - 1) * log1p(-upper_tail))` to
#' stay accurate in the upper tail.
#'
#' This replaces the earlier closed-form approximation
#' \eqn{z - (\gamma + \log(\pi/2)) / (2z)}, \eqn{z = \sqrt{2\log K}}, which
#' overstated the exact value by 9-31% for K between 2 and 5000 (#931).
#'
#' @param K Single finite number, `K >= 1` (number of independent trials;
#'   non-integer allowed).
#'
#' @return Single numeric: `0` for `K = 1`, otherwise the expected maximum.
#'
#' @examples
#' # Worked check: E[max of 2 N(0,1)] = 1/sqrt(pi)
#' hd_expected_max_normal(2)
#' 1 / sqrt(pi)
#' hd_expected_max_normal(10)  # 1.538753
#'
#' @references
#' Bailey, D. H. and Lopez de Prado, M. (2014). "The Deflated Sharpe Ratio:
#' Correcting for Selection Bias, Backtest Overfitting and Non-Normality."
#' \emph{Journal of Portfolio Management}, 40(5), 94-107.
#'
#' @family falsification
#' @export
hd_expected_max_normal <- function(K) {
  if (!is.numeric(K) || length(K) != 1L || is.na(K) || !is.finite(K)) {
    cli::cli_abort(c(
      "x" = "{.arg K} must be a single finite number.",
      "i" = "Got {.val {K}}."
    ))
  }
  if (K < 1) {
    cli::cli_abort(c(
      "x" = "{.arg K} must be at least 1.",
      "i" = "Got {.val {K}}."
    ))
  }
  if (K == 1) {
    return(0)
  }

  integrand <- function(x) {
    # K * x * phi(x) * Phi(x)^(K - 1), with Phi^(K-1) computed in log space
    upper <- stats::pnorm(x, lower.tail = FALSE)
    K * x * stats::dnorm(x) * exp((K - 1) * log1p(-upper))
  }

  mode_x <- stats::qnorm(1 - 1 / K)
  lo <- -12
  hi <- max(12, mode_x + 8)
  breaks <- sort(unique(c(lo, mode_x - 3, mode_x, mode_x + 3, hi)))
  breaks <- breaks[breaks >= lo & breaks <= hi]

  total <- 0
  for (i in seq_len(length(breaks) - 1L)) {
    total <- total + stats::integrate(
      integrand, lower = breaks[i], upper = breaks[i + 1L],
      rel.tol = 1e-12, subdivisions = 2000L
    )$value
  }
  total
}
