#' Global minimum-variance portfolio weights (unconstrained, closed form)
#'
#' @title Global Minimum-Variance Weights (`hd_min_var_weights`)
#'
#' @description
#' Returns the unconstrained global minimum-variance (GMV) portfolio weights for
#' a given covariance matrix `Sigma`. The GMV solution is the unique vector of
#' portfolio weights that minimises portfolio variance subject only to the
#' budget constraint (\eqn{\mathbf{1}^\top w = 1}):
#'
#' \deqn{w^* = \frac{\Sigma^{-1} \mathbf{1}}{\mathbf{1}^\top \Sigma^{-1} \mathbf{1}}}
#'
#' Implemented via `solve(Sigma, rep(1, p))` followed by normalisation, which
#' is numerically equivalent and avoids explicit matrix inversion.
#'
#' **Singularity:** the sample covariance matrix is singular when the number of
#' assets \eqn{p} exceeds the number of observations \eqn{n}. When `Sigma` is
#' singular or numerically ill-conditioned, `solve()` will fail and
#' `hd_min_var_weights()` aborts with an informative error suggesting the caller
#' use a regularised estimator (see [hd_cov_estimate()]). This failure is the
#' *intended* demonstration that plain sample covariance breaks in the wide
#' (\eqn{p \geq n}) regime — the diagnostic function [hd_cov_oos_diagnostic()]
#' counts these failures per method.
#'
#' @param Sigma A \eqn{p \times p} symmetric, positive-definite numeric matrix.
#'   Must have `p >= 2`. Column names (or row names) are used to name the
#'   returned weight vector.
#' @param normalize Logical scalar. If `TRUE` (default), weights are
#'   normalised so they sum to exactly 1. If `FALSE`, the raw
#'   `solve(Sigma, rep(1, p))` solution is returned (useful for diagnostics).
#'
#' @return A named numeric vector of length `p`. When `normalize = TRUE`, the
#'   weights sum to 1. Names are taken from `dimnames(Sigma)[[1]]` (row names
#'   of the covariance matrix); `NULL` if `Sigma` has no dimnames.
#'
#' @references
#' Markowitz, H. (1952). Portfolio selection. *Journal of Finance*, 7(1),
#' 77–91. \doi{10.2307/2975974}
#'
#' Merton, R. C. (1972). An analytic derivation of the efficient portfolio
#' frontier. *Journal of Financial and Quantitative Analysis*, 7(4),
#' 1851–1872. \doi{10.2307/2329621}
#'
#' @family covariance
#' @export
#'
#' @examples
#' # 3-asset example with a known covariance matrix
#' Sigma <- matrix(c(0.04, 0.01, 0.00,
#'                   0.01, 0.09, 0.02,
#'                   0.00, 0.02, 0.16),
#'                 nrow = 3, ncol = 3,
#'                 dimnames = list(c("A","B","C"), c("A","B","C")))
#'
#' w <- hd_min_var_weights(Sigma)
#' sum(w)       # 1
#' names(w)     # "A" "B" "C"
#'
#' # GMV variance is lower than equal-weight variance
#' p <- nrow(Sigma)
#' w_eq <- rep(1/p, p)
#' var_gmv <- as.numeric(t(w) %*% Sigma %*% w)
#' var_eq  <- as.numeric(t(w_eq) %*% Sigma %*% w_eq)
#' var_gmv <= var_eq  # TRUE
hd_min_var_weights <- function(Sigma, normalize = TRUE) {

  # ---- Input validation -----------------------------------------------
  if (!is.matrix(Sigma) || !is.numeric(Sigma)) {
    cli::cli_abort(
      c(
        "{.arg Sigma} must be a numeric matrix.",
        "x" = "Got {.cls {class(Sigma)}}."
      )
    )
  }

  p <- nrow(Sigma)
  if (ncol(Sigma) != p) {
    cli::cli_abort(
      c(
        "{.arg Sigma} must be square.",
        "x" = "Got {p} rows and {ncol(Sigma)} columns."
      )
    )
  }

  if (p < 2L) {
    cli::cli_abort(
      c(
        "{.arg Sigma} must have at least 2 rows/columns.",
        "x" = "Got {p}."
      )
    )
  }

  # Symmetry check (tolerance 1e-8)
  max_asym <- max(abs(Sigma - t(Sigma)))
  if (max_asym > 1e-8) {
    cli::cli_abort(
      c(
        "{.arg Sigma} must be symmetric.",
        "x" = "Maximum asymmetry: {round(max_asym, 10)}.",
        "i" = "Enforce symmetry with {.code (Sigma + t(Sigma)) / 2} before calling."
      )
    )
  }

  if (!is.logical(normalize) || length(normalize) != 1L || is.na(normalize)) {
    cli::cli_abort(
      "{.arg normalize} must be a single non-NA logical value."
    )
  }

  # ---- Solve for raw GMV weights --------------------------------------
  ones <- rep(1, p)
  raw_w <- tryCatch(
    solve(Sigma, ones),
    error = function(e) {
      cli::cli_abort(
        c(
          "Cannot compute minimum-variance weights: {.arg Sigma} is singular or numerically ill-conditioned.",
          "i" = paste0(
            "In the wide regime (p >= n) the sample covariance is rank-deficient. ",
            "Use a regularised estimator via {.fun hd_cov_estimate} with ",
            "{.code method = \"ledoit_wolf\"} or {.code method = \"rmt_denoise\"}."
          )
        )
      )
    }
  )

  # ---- Normalise -------------------------------------------------------
  if (normalize) {
    denom <- sum(raw_w)
    if (!is.finite(denom) || abs(denom) < .Machine$double.eps^0.5) {
      cli::cli_abort(
        c(
          "Normalisation failed: sum of raw weights is zero or non-finite.",
          "x" = "Sum of raw weights: {denom}.",
          "i" = "This may indicate a near-singular or ill-scaled {.arg Sigma}."
        )
      )
    }
    w <- raw_w / denom
  } else {
    w <- raw_w
  }

  # ---- Names -----------------------------------------------------------
  names(w) <- dimnames(Sigma)[[1]]

  w
}
