#' Effective number of tested strategies (Vertox K_eff_strat)
#'
#' Computes the correlation-aware effective count of tested strategies
#' `K_eff_strat`, as defined in
#' \href{https://www.vertoxquant.com/p/the-effective-number-of-tested-strategies}{VertoxQuant (2026)}.
#' This is the foundation for any correct multiple-testing correction
#' (Deflated Sharpe, Bonferroni, FDR, Harvey/Liu) applied to a *portfolio of
#' correlated strategies*. See issue #160 for the audit + 4-PR plan.
#'
#' Defined implicitly via:
#' \deqn{E[\max_i Z_i^2 \mid \Sigma] = E[\max_i Z_i^2 \mid I_{K}]}
#' where the left side is evaluated under the actual strategy-return
#' correlation \eqn{\Sigma} (size \eqn{M}), the right side under
#' \eqn{K} independent standard normals, and `K_eff_strat` is the
#' \eqn{K} that makes the two equal.
#'
#' Boundary behaviour (axioms from the article):
#' \itemize{
#'   \item \eqn{\Sigma = I_M} → `K_eff_strat = M` (no correlation, no shrinkage)
#'   \item \eqn{\Sigma = \mathbf{1}\mathbf{1}^\top} → `K_eff_strat = 1` (perfect correlation collapses to 1)
#'   \item Adding a new strategy weakly increases `K_eff_strat` (monotonicity)
#' }
#'
#' This implementation uses Monte Carlo simulation for the correlated side
#' (cheap and trivially correct for any PSD \eqn{\Sigma}) and analytic
#' integration for the iid side. Stochasticity is controlled via the `seed`
#' argument for reproducible pipeline targets.
#'
#' @section Companion quantity:
#' This is distinct from `K_eff_acf` (autocorrelation-adjusted effective
#' sample size *per series*, Newey-West) computed by
#' [calculate_keff()] in `R/tail_keff.R`. Bare `K_eff` (no suffix) is
#' reserved — always use the suffixed name.
#'
#' @param sigma Strategy-return correlation matrix (\eqn{M \times M},
#'   symmetric, positive semi-definite, unit diagonal). Typically computed
#'   from a leaderboard's strategy return-series.
#' @param n_sim Monte Carlo sample size for E[max Z² | Σ]. Default 20,000 —
#'   enough that the MC standard error on `K_eff_strat` is below 0.05 for
#'   typical leaderboards. Raise for tighter convergence; lower for speed.
#' @param seed Optional integer for reproducibility. `NULL` leaves the
#'   global RNG state alone.
#' @param tol Numerical tolerance for the Brent root-finder. Default 1e-3
#'   (i.e. `K_eff_strat` accurate to ~0.001 of a strategy).
#'
#' @return Scalar `K_eff_strat` in `[1, M]`. Never `NA`; boundary cases
#'   return exact `1` or `M` (see Details).
#'
#' @references VertoxQuant (2026), \emph{The Effective Number of Tested
#'   Strategies}. \url{https://www.vertoxquant.com/p/the-effective-number-of-tested-strategies}
#' @family multiple-testing
#' @export
hd_strat_keff_vertox <- function(sigma, n_sim = 20000L, seed = NULL, tol = 1e-3) {
  rlang::check_installed("stats")

  if (!is.matrix(sigma)) {
    cli::cli_abort("{.arg sigma} must be a matrix; got {.cls {class(sigma)}}.")
  }
  M <- nrow(sigma)
  if (ncol(sigma) != M) {
    cli::cli_abort("{.arg sigma} must be square; got {nrow(sigma)} x {ncol(sigma)}.")
  }
  if (M < 1L) {
    cli::cli_abort("{.arg sigma} must have at least one row/column.")
  }
  if (M == 1L) {
    return(1)
  }
  if (max(abs(sigma - t(sigma))) > 1e-8) {
    cli::cli_abort("{.arg sigma} must be symmetric.")
  }
  if (max(abs(diag(sigma) - 1)) > 1e-6) {
    cli::cli_warn("{.arg sigma} does not have unit diagonal; treating as correlation matrix anyway.")
  }

  sigma_rank <- qr(sigma, tol = 1e-10)$rank
  if (sigma_rank < M) {
    return(as.numeric(sigma_rank))
  }

  L <- tryCatch(
    chol(sigma),
    error = function(e) {
      cli::cli_warn("Cholesky failed despite rank = M; jittering diagonal by 1e-10.")
      chol(sigma + diag(1e-10, M))
    }
  )

  if (!is.null(seed)) {
    old_seed <- if (exists(".Random.seed", envir = .GlobalEnv)) {
      get(".Random.seed", envir = .GlobalEnv)
    } else {
      NULL
    }
    on.exit({
      if (!is.null(old_seed)) {
        assign(".Random.seed", old_seed, envir = .GlobalEnv)
      } else {
        rm(".Random.seed", envir = .GlobalEnv)
      }
    }, add = TRUE)
    set.seed(seed)
  }

  Z_indep <- matrix(stats::rnorm(n_sim * M), nrow = n_sim, ncol = M)
  Z_corr <- Z_indep %*% L
  e_max_corr <- mean(do.call(pmax, c(as.data.frame(Z_corr^2))))

  e_max_indep_K <- function(K) {
    integrand <- function(z) 2 * z * (1 - (2 * stats::pnorm(z) - 1)^K)
    stats::integrate(integrand, lower = 0, upper = Inf)$value
  }

  f_at_1 <- e_max_indep_K(1) - e_max_corr
  if (f_at_1 >= 0) return(1)
  f_at_M <- e_max_indep_K(M) - e_max_corr
  if (f_at_M <= 0) return(M)

  result <- stats::uniroot(
    function(K) e_max_indep_K(K) - e_max_corr,
    interval = c(1, M),
    tol = tol
  )
  result$root
}
