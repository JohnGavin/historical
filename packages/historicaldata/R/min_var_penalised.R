#' Penalised global minimum-variance portfolio weights (closed form)
#'
#' @title Penalised Global Minimum-Variance Weights (`hd_min_var_weights_penalised`)
#'
#' @description
#' Returns penalised global minimum-variance (GMV) portfolio weights via a
#' **single linear solve** — no quadratic-programming solver required.
#' Two closed-form penalties are supported simultaneously:
#'
#' * **Ridge (L2 on covariance):** adds \eqn{\lambda_{\text{ridge}} I} to the
#'   covariance matrix before inversion, shrinking extreme weights toward an
#'   equal-risk allocation and improving numerical conditioning.
#'
#' * **L2 turnover penalty toward prior weights:** minimises
#'   \deqn{w^\top (\Sigma + \lambda_r I + \lambda_t I) w - 2\lambda_t w_{\text{prev}}^\top w}
#'   subject to \eqn{\mathbf{1}^\top w = 1}. The KKT/Lagrange solution is:
#'   \deqn{w^* = \lambda_t A^{-1} w_{\text{prev}} +
#'               \frac{1 - \lambda_t \mathbf{1}^\top A^{-1} w_{\text{prev}}}
#'                    {\mathbf{1}^\top A^{-1} \mathbf{1}} \, A^{-1} \mathbf{1}}
#'   where \eqn{A = \Sigma + (\lambda_r + \lambda_t) I}. Both inverses are
#'   computed in a single `solve()` call.
#'
#' When both penalties are zero the function reduces exactly to
#' [hd_min_var_weights()].
#'
#' **Look-ahead-bias note:** penalty intensities (`lambda_ridge`,
#' `lambda_turnover`) and the prior weights `w_prev` must be determined from
#' in-window/training data only. Using hold-out data to calibrate these
#' parameters introduces look-ahead bias into the optimised weights.
#'
#' **Deferred (Phase 3b — requires a QP solver/new dependency):**
#' no-short constraints (\eqn{w \geq 0}), box constraints, L1 turnover
#' penalty, and robust/worst-case MVO. These will be implemented in a
#' follow-up PR once `quadprog` (or similar) is added to DESCRIPTION and
#' the Nix environment is regenerated.
#'
#' @param Sigma A \eqn{p \times p} symmetric, positive-definite numeric matrix.
#'   Must have `p >= 2`. Row names are used to name the returned weight vector.
#' @param lambda_ridge Non-negative scalar. Regularisation intensity for the
#'   ridge (L2) covariance penalty. `0` (default) means no ridge regularisation.
#'   Larger values shrink weights toward the equal-risk portfolio and improve
#'   the conditioning of the penalised matrix.
#' @param w_prev Named or unnamed numeric vector of length `p` — the prior
#'   portfolio weights toward which the L2 turnover penalty pulls the solution.
#'   Required when `lambda_turnover > 0`; ignored (and must be `NULL`) when
#'   `lambda_turnover == 0`. A warning is issued if `w_prev` does not sum to
#'   approximately 1 (tolerance 0.01).
#' @param lambda_turnover Non-negative scalar. Intensity of the L2 turnover
#'   penalty. `0` (default) disables the penalty. Requires `w_prev` when > 0.
#' @param normalize Logical scalar. If `TRUE` (default), the returned weights
#'   are normalised to sum exactly to 1. If `FALSE`, the raw solution of the
#'   linear system is returned (useful for diagnostics).
#'
#' @return A named numeric vector of length `p`. When `normalize = TRUE` the
#'   weights sum to 1. Names are taken from `dimnames(Sigma)[[1]]`; `NULL` if
#'   `Sigma` has no dimnames. The following attributes are always attached:
#'   \describe{
#'     \item{`lambda_ridge`}{The ridge penalty used.}
#'     \item{`lambda_turnover`}{The turnover penalty used.}
#'     \item{`condition_number`}{The 2-norm condition number of the penalised
#'       matrix \eqn{A = \Sigma + (\lambda_r + \lambda_t) I}, computed via
#'       [base::kappa()]. Lower values indicate better conditioning.}
#'     \item{`turnover`}{Sum of absolute weight changes
#'       \eqn{\sum |w^* - w_{\text{prev}}|}; set only when `w_prev` is
#'       supplied.}
#'   }
#'
#' @references
#' Markowitz, H. (1952). Portfolio selection. *Journal of Finance*, 7(1),
#' 77–91. \doi{10.2307/2975974}
#'
#' DeMiguel, V., Garlappi, L., & Uppal, R. (2009). Optimal versus naive
#' diversification: How inefficient is the 1/N portfolio strategy? *Review of
#' Financial Studies*, 22(5), 1915–1953. \doi{10.1093/rfs/hhm075}
#'
#' Ledoit, O. & Wolf, M. (2004). A well-conditioned estimator for
#' large-dimensional covariance matrices. *Journal of Multivariate Analysis*,
#' 88(2), 365–411. \doi{10.1016/S0047-259X(03)00096-4}
#'
#' @family covariance
#' @export
#'
#' @examples
#' # 3-asset well-conditioned covariance matrix
#' Sigma <- matrix(c(0.04, 0.01, 0.00,
#'                   0.01, 0.09, 0.02,
#'                   0.00, 0.02, 0.16),
#'                 nrow = 3, ncol = 3,
#'                 dimnames = list(c("A","B","C"), c("A","B","C")))
#'
#' # Plain GMV — identical to hd_min_var_weights(Sigma) when penalties are 0
#' w0 <- hd_min_var_weights_penalised(Sigma)
#' sum(w0)   # 1
#'
#' # Ridge-penalised GMV — better conditioning, moderate regularisation
#' w_ridge <- hd_min_var_weights_penalised(Sigma, lambda_ridge = 0.01)
#' attr(w_ridge, "condition_number")  # lower than attr(w0, "condition_number")
#'
#' # Turnover-damped GMV — pull weights toward a prior allocation
#' w_prev <- c(A = 0.5, B = 0.3, C = 0.2)
#' w_to   <- hd_min_var_weights_penalised(Sigma, w_prev = w_prev,
#'                                         lambda_turnover = 0.1)
#' attr(w_to, "turnover")  # sum(|w_to - w_prev|)
hd_min_var_weights_penalised <- function(Sigma,
                                          lambda_ridge    = 0,
                                          w_prev          = NULL,
                                          lambda_turnover = 0,
                                          normalize       = TRUE) {

  # ---- Input validation: Sigma ------------------------------------------
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

  # ---- Input validation: penalties -------------------------------------
  if (!is.numeric(lambda_ridge) || length(lambda_ridge) != 1L ||
      is.na(lambda_ridge) || lambda_ridge < 0) {
    cli::cli_abort(
      c(
        "{.arg lambda_ridge} must be a single non-negative numeric scalar.",
        "x" = "Got {.val {lambda_ridge}}."
      )
    )
  }

  if (!is.numeric(lambda_turnover) || length(lambda_turnover) != 1L ||
      is.na(lambda_turnover) || lambda_turnover < 0) {
    cli::cli_abort(
      c(
        "{.arg lambda_turnover} must be a single non-negative numeric scalar.",
        "x" = "Got {.val {lambda_turnover}}."
      )
    )
  }

  # ---- Input validation: w_prev ----------------------------------------
  if (lambda_turnover > 0 && is.null(w_prev)) {
    cli::cli_abort(
      c(
        "{.arg w_prev} must be supplied when {.arg lambda_turnover} > 0.",
        "i" = "Provide the prior portfolio weights as a numeric vector of length {p}."
      )
    )
  }

  if (!is.null(w_prev)) {
    if (!is.numeric(w_prev) || length(w_prev) != p) {
      cli::cli_abort(
        c(
          "{.arg w_prev} must be a numeric vector of length {p} (matching {.arg Sigma} dimension).",
          "x" = "Got {.cls {class(w_prev)}} of length {length(w_prev)}."
        )
      )
    }
    w_sum <- sum(w_prev)
    if (abs(w_sum - 1) > 0.01) {
      cli::cli_warn(
        c(
          "{.arg w_prev} does not sum to 1.",
          "!" = "Sum is {round(w_sum, 4)}. L2 turnover penalty assumes a budget-feasible prior."
        )
      )
    }
  }

  # ---- Input validation: normalize -------------------------------------
  if (!is.logical(normalize) || length(normalize) != 1L || is.na(normalize)) {
    cli::cli_abort(
      "{.arg normalize} must be a single non-NA logical value."
    )
  }

  # ---- Build penalised matrix A = Sigma + (lambda_ridge + lambda_turn) I ---
  A <- Sigma + (lambda_ridge + lambda_turnover) * diag(p)

  ones <- rep(1, p)

  # ---- Solve A^{-1} [ones | w_prev] in one shot -------------------------
  has_turnover <- !is.null(w_prev) && lambda_turnover > 0
  rhs <- if (has_turnover) cbind(ones, w_prev) else matrix(ones, ncol = 1L)

  sol <- tryCatch(
    solve(A, rhs),
    error = function(e) {
      cli::cli_abort(
        c(
          paste0(
            "Cannot compute penalised minimum-variance weights: ",
            "the penalised matrix is singular or numerically ill-conditioned."
          ),
          "i" = paste0(
            "Increase {.arg lambda_ridge} to improve conditioning, or supply a ",
            "well-conditioned covariance estimate via {.fun hd_cov_estimate}."
          )
        )
      )
    }
  )

  a1    <- sol[, 1L]            # A^{-1} ones
  alpha <- as.numeric(t(ones) %*% a1)   # 1^T A^{-1} 1

  # ---- Compute raw GMV weights ------------------------------------------
  if (has_turnover) {
    aw    <- sol[, 2L]                        # A^{-1} w_prev
    beta  <- as.numeric(t(ones) %*% aw)      # 1^T A^{-1} w_prev
    # KKT solution — inherently satisfies 1^T w = 1
    w_raw <- lambda_turnover * aw +
             ((1 - lambda_turnover * beta) / alpha) * a1
  } else {
    # Ridge-only (or plain GMV when lambda_ridge = 0): raw = A^{-1} ones
    w_raw <- a1
  }

  # ---- Normalise -------------------------------------------------------
  if (normalize) {
    denom <- sum(w_raw)
    if (!is.finite(denom) || abs(denom) < .Machine$double.eps^0.5) {
      cli::cli_abort(
        c(
          "Normalisation failed: sum of raw weights is zero or non-finite.",
          "x" = "Sum of raw weights: {denom}.",
          "i" = "This may indicate a near-singular or ill-scaled {.arg Sigma}."
        )
      )
    }
    w <- w_raw / denom
  } else {
    w <- w_raw
  }

  # ---- Names -----------------------------------------------------------
  names(w) <- dimnames(Sigma)[[1]]

  # ---- Attributes ------------------------------------------------------
  attr(w, "lambda_ridge")    <- lambda_ridge
  attr(w, "lambda_turnover") <- lambda_turnover
  attr(w, "condition_number") <- kappa(A)

  if (!is.null(w_prev)) {
    attr(w, "turnover") <- sum(abs(w - w_prev))
  }

  w
}
