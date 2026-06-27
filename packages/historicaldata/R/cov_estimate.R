#' Regularised covariance estimator for wide financial data
#'
#' @title Regularised Covariance Estimator (`hd_cov_estimate`)
#'
#' @description
#' Computes a regularised covariance matrix from a returns matrix or
#' data frame using one of four methods suited to the *p >> n* (wide-data)
#' regime common in portfolio construction:
#'
#' * **`"sample"`** — classical n−1 sample covariance (baseline; singular
#'   when p > n).
#' * **`"ledoit_wolf"`** — linear shrinkage toward a structured target
#'   (Ledoit & Wolf 2004). Guaranteed positive-definite for any n, p.
#' * **`"rmt_denoise"`** — Marchenko-Pastur eigenvalue clipping. Noise
#'   eigenvalues (below the MP upper edge) are collapsed to their mean so
#'   the trace is preserved, then the matrix is reconstructed.
#' * **`"threshold"`** — soft or hard thresholding of off-diagonal
#'   correlations. Simple but can break positive-definiteness; a warning is
#'   issued when that occurs.
#'
#' Missing values are handled by dropping rows with any `NA` (complete
#' cases). A `date` column, if present in a data frame input, is silently
#' dropped before estimation.
#'
#' @param returns A numeric matrix or data frame with rows = observations
#'   (n) and columns = assets (p). Data frames are coerced to a numeric
#'   matrix; a `date` column (any column whose name equals `"date"`,
#'   case-insensitively) is dropped first. Column names are preserved as
#'   `dimnames` on the output.
#' @param method Estimator to use. One of `"sample"`, `"ledoit_wolf"`,
#'   `"rmt_denoise"`, `"threshold"`. Partial matching is supported via
#'   [base::match.arg()].
#' @param lw_target Structured target for Ledoit-Wolf shrinkage. One of
#'   `"const_cor"` (constant-correlation target, Ledoit & Wolf 2004 "Honey,
#'   I Shrunk…") or `"identity"` (scaled-identity target). Ignored unless
#'   `method = "ledoit_wolf"`.
#' @param threshold Off-diagonal correlation threshold for `method =
#'   "threshold"`. Must be in \[0, 1). Default `0.1`.
#' @param threshold_type Type of thresholding. One of `"soft"` or `"hard"`.
#'   Ignored unless `method = "threshold"`.
#' @param assume_centered Logical. If `TRUE`, the data are treated as
#'   already demeaned and the column means are not subtracted before
#'   estimation. Default `FALSE`.
#'
#' @return A symmetric p × p numeric matrix with the same `dimnames` as the
#'   columns of `returns`. The following attributes are always set:
#'   \describe{
#'     \item{`method`}{Character scalar — the estimator used.}
#'     \item{`n_obs`}{Integer — number of complete-case rows used.}
#'     \item{`n_assets`}{Integer — number of assets (columns) p.}
#'     \item{`condition_number`}{Numeric — ratio of the largest to the
#'       smallest eigenvalue (a measure of numerical ill-conditioning).}
#'   }
#'   Additional attributes for specific methods:
#'   \describe{
#'     \item{`shrinkage`}{(`ledoit_wolf` only) Optimal shrinkage intensity
#'       δ* in \[0, 1].}
#'     \item{`n_clipped`}{(`rmt_denoise` only) Number of eigenvalues below
#'       the Marchenko-Pastur upper edge that were clipped to their mean.}
#'   }
#'
#' @references
#' Ledoit, O. & Wolf, M. (2004). A well-conditioned estimator for
#' large-dimensional covariance matrices. *Journal of Multivariate
#' Analysis*, 88(2), 365–411. \doi{10.1016/S0047-259X(03)00096-4}
#'
#' Ledoit, O. & Wolf, M. (2004). Honey, I Shrunk the Sample Covariance
#' Matrix. *Journal of Portfolio Management*, 30(4), 110–119.
#' \doi{10.3905/jpm.2004.110}
#'
#' Laloux, L., Cizeau, P., Bouchaud, J.-P. & Potters, M. (1999). Noise
#' Dressing of Financial Correlation Matrices. *Physical Review Letters*,
#' 83(7), 1467–1470. \doi{10.1103/PhysRevLett.83.1467}
#'
#' Raviv, E. (2026). Covariance Estimation for Wide Data. *WIREs
#' Computational Statistics*, 18(2). \doi{10.1002/wics.70068}
#'
#' @family covariance
#' @export
#'
#' @examples
#' set.seed(42)
#' X <- matrix(rnorm(60 * 10), nrow = 60, ncol = 10)
#' colnames(X) <- paste0("A", seq_len(10))
#'
#' # baseline — singular when p > n
#' S_sample <- hd_cov_estimate(X, method = "sample")
#'
#' # Ledoit-Wolf shrinkage (constant-correlation target)
#' S_lw <- hd_cov_estimate(X, method = "ledoit_wolf", lw_target = "const_cor")
#' attr(S_lw, "shrinkage")   # optimal delta*
#'
#' # RMT denoising
#' S_rmt <- hd_cov_estimate(X, method = "rmt_denoise")
#' attr(S_rmt, "n_clipped")  # how many eigenvalues were noise
#'
#' # hard thresholding at 0.2
#' S_thr <- hd_cov_estimate(X, method = "threshold", threshold = 0.2,
#'                          threshold_type = "hard")
hd_cov_estimate <- function(returns,
                            method = c("sample", "ledoit_wolf",
                                       "rmt_denoise", "threshold"),
                            lw_target = c("const_cor", "identity"),
                            threshold = 0.1,
                            threshold_type = c("soft", "hard"),
                            assume_centered = FALSE) {

  method         <- match.arg(method)
  lw_target      <- match.arg(lw_target)
  threshold_type <- match.arg(threshold_type)

  # ---- Input validation -----------------------------------------------
  if (!is.matrix(returns) && !is.data.frame(returns)) {
    cli::cli_abort(
      "{.arg returns} must be a numeric matrix or data frame; got {.cls {class(returns)}}."
    )
  }

  # Coerce data frame to matrix, dropping a date column if present
  if (is.data.frame(returns)) {
    date_col <- which(tolower(names(returns)) == "date")
    if (length(date_col) > 0L) {
      returns <- returns[, -date_col, drop = FALSE]
    }
    asset_names <- names(returns)
    returns <- as.matrix(returns)
    colnames(returns) <- asset_names
  }

  if (!is.numeric(returns)) {
    cli::cli_abort(
      "{.arg returns} must be numeric after coercion; got {.cls {typeof(returns)}}."
    )
  }

  p <- ncol(returns)
  if (is.null(p) || p < 2L) {
    cli::cli_abort(
      "{.arg returns} must have at least 2 columns (assets); got {p %||% 0L}."
    )
  }

  if (!is.logical(assume_centered) || length(assume_centered) != 1L) {
    cli::cli_abort(
      "{.arg assume_centered} must be a single logical value."
    )
  }

  if (!is.numeric(threshold) || length(threshold) != 1L ||
      threshold < 0 || threshold >= 1) {
    cli::cli_abort(
      "{.arg threshold} must be a single numeric value in [0, 1); got {threshold}."
    )
  }

  # ---- Complete cases --------------------------------------------------
  complete <- stats::complete.cases(returns)
  n_dropped <- sum(!complete)
  if (n_dropped > 0L) {
    cli::cli_warn(
      "Dropped {n_dropped} row{?s} containing NA from {.arg returns}."
    )
  }
  X <- returns[complete, , drop = FALSE]
  n <- nrow(X)

  if (n == 0L) {
    cli::cli_abort(
      "No complete cases remain in {.arg returns} after dropping NA rows."
    )
  }

  # Preserve column names
  asset_names <- colnames(X)

  # ---- Dispatch to method helpers -------------------------------------
  result <- switch(method,
    sample      = .cov_sample(X, assume_centered),
    ledoit_wolf = .cov_ledoit_wolf(X, lw_target, assume_centered),
    rmt_denoise = .cov_rmt_denoise(X, assume_centered),
    threshold   = .cov_threshold(X, threshold, threshold_type, assume_centered)
  )

  Sigma <- result$Sigma

  # ---- Symmetrise (numerical) -----------------------------------------
  Sigma <- (Sigma + t(Sigma)) / 2

  # ---- Dimnames --------------------------------------------------------
  if (!is.null(asset_names)) {
    dimnames(Sigma) <- list(asset_names, asset_names)
  }

  # ---- Common attributes ----------------------------------------------
  evals <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
  cond  <- max(evals) / max(min(evals), .Machine$double.eps)

  attr(Sigma, "method")           <- method
  attr(Sigma, "n_obs")            <- n
  attr(Sigma, "n_assets")         <- p
  attr(Sigma, "condition_number") <- cond

  # ---- Method-specific attributes -------------------------------------
  if (!is.null(result$shrinkage)) {
    attr(Sigma, "shrinkage") <- result$shrinkage
  }
  if (!is.null(result$n_clipped)) {
    attr(Sigma, "n_clipped") <- result$n_clipped
  }

  Sigma
}

# -------------------------------------------------------------------------
# Internal helpers (not exported)
# -------------------------------------------------------------------------

# Demean the matrix (or leave centred if assume_centered = TRUE)
.cov_demean <- function(X, assume_centered) {
  if (assume_centered) return(X)
  sweep(X, 2L, colMeans(X), "-")
}

# Sample covariance (n-1 denominator)
.cov_sample <- function(X, assume_centered) {
  Sigma <- stats::cov(X)
  list(Sigma = Sigma, shrinkage = NULL, n_clipped = NULL)
}

# Ledoit-Wolf linear shrinkage
.cov_ledoit_wolf <- function(X, lw_target, assume_centered) {
  n <- nrow(X)
  p <- ncol(X)
  Xc <- .cov_demean(X, assume_centered)

  # MLE sample covariance (1/n denominator) for LW shrinkage formulas
  S <- crossprod(Xc) / n

  if (lw_target == "const_cor") {
    result <- .lw_const_cor(Xc, S, n, p)
  } else {
    result <- .lw_identity(Xc, S, n, p)
  }
  result
}

# Ledoit-Wolf constant-correlation target
.lw_const_cor <- function(Xc, S, n, p) {
  s_ii  <- diag(S)
  sd_i  <- sqrt(s_ii)

  # Sample correlation matrix
  R    <- S / outer(sd_i, sd_i)
  # Mean off-diagonal correlation
  rbar <- (sum(R) - p) / (p * (p - 1L))

  # Target F: constant-correlation matrix in covariance units
  F_mat         <- rbar * outer(sd_i, sd_i)
  diag(F_mat)   <- s_ii

  # pi_hat: asymptotic variance of the sample cov elements
  pi_mat <- matrix(0, p, p)
  for (t in seq_len(n)) {
    diff <- outer(Xc[t, ], Xc[t, ]) - S
    pi_mat <- pi_mat + diff^2
  }
  pi_mat  <- pi_mat / n
  pi_hat  <- sum(pi_mat)

  # rho_hat: covariance between S and F
  rho_diag <- sum(diag(pi_mat))

  rho_off <- 0
  for (i in seq_len(p)) {
    for (j in seq_len(p)) {
      if (i == j) next
      # theta_ii_ij and theta_jj_ij
      theta_ii_ij <- (1 / n) * sum((Xc[, i]^2 - s_ii[i]) *
                                   (Xc[, i] * Xc[, j] - S[i, j]))
      theta_jj_ij <- (1 / n) * sum((Xc[, j]^2 - s_ii[j]) *
                                   (Xc[, i] * Xc[, j] - S[i, j]))
      rho_off <- rho_off +
        (rbar / 2) * (sqrt(s_ii[j] / s_ii[i]) * theta_ii_ij +
                      sqrt(s_ii[i] / s_ii[j]) * theta_jj_ij)
    }
  }
  rho_hat <- rho_diag + rho_off

  # gamma_hat: squared Frobenius misspecification
  gamma_hat <- sum((F_mat - S)^2)

  # Optimal shrinkage
  kappa <- (pi_hat - rho_hat) / gamma_hat
  delta <- max(0, min(1, kappa / n))

  Sigma <- delta * F_mat + (1 - delta) * S

  list(Sigma = Sigma, shrinkage = delta, n_clipped = NULL)
}

# Ledoit-Wolf scaled-identity target
.lw_identity <- function(Xc, S, n, p) {
  mu <- mean(diag(S))

  # d2: squared Frobenius distance from scaled identity
  d2 <- sum((S - mu * diag(p))^2)

  # b2bar: average asymptotic variance of S elements
  b2bar <- 0
  for (t in seq_len(n)) {
    diff  <- outer(Xc[t, ], Xc[t, ]) - S
    b2bar <- b2bar + sum(diff^2)
  }
  b2bar <- b2bar / n^2

  b2 <- min(b2bar, d2)
  a2 <- d2 - b2

  # Shrinkage: toward mu * I
  if (d2 < .Machine$double.eps) {
    # S is already very close to scaled identity
    Sigma <- S
    delta <- 0
  } else {
    Sigma <- (b2 / d2) * mu * diag(p) + (a2 / d2) * S
    delta <- b2 / d2
  }

  list(Sigma = Sigma, shrinkage = delta, n_clipped = NULL)
}

# RMT denoising via Marchenko-Pastur clipping
.cov_rmt_denoise <- function(X, assume_centered) {
  n <- nrow(X)
  p <- ncol(X)

  # n-1 sample covariance for variance extraction
  S1 <- stats::cov(X)
  sd <- sqrt(diag(S1))

  # Correlation matrix (clip numerically to [-1, 1])
  C <- S1 / outer(sd, sd)
  C <- pmin(pmax(C, -1), 1)

  # Marchenko-Pastur upper edge
  q          <- p / n
  lambda_plus <- (1 + sqrt(q))^2

  # Eigendecompose correlation matrix
  e    <- eigen(C, symmetric = TRUE)
  vals <- e$values

  # Clip noise eigenvalues (below lambda_plus) to their mean
  noise_idx <- which(vals < lambda_plus)
  n_clipped <- length(noise_idx)
  if (n_clipped > 0L) {
    vals[noise_idx] <- mean(vals[noise_idx])
  }

  # Reconstruct and renormalise to unit diagonal
  C_clean <- e$vectors %*% diag(vals, nrow = length(vals)) %*% t(e$vectors)
  d       <- sqrt(diag(C_clean))
  d[d < .Machine$double.eps^0.5] <- 1  # guard against near-zero diagonal
  C_clean <- C_clean / outer(d, d)

  # Convert back to covariance
  Sigma <- C_clean * outer(sd, sd)

  list(Sigma = Sigma, shrinkage = NULL, n_clipped = n_clipped)
}

# Off-diagonal correlation thresholding
.cov_threshold <- function(X, threshold, threshold_type, assume_centered) {
  S1 <- stats::cov(X)
  sd <- sqrt(diag(S1))

  # Correlation matrix (clip to [-1, 1])
  C <- S1 / outer(sd, sd)
  C <- pmin(pmax(C, -1), 1)

  p <- ncol(C)

  # Apply threshold to off-diagonal elements
  for (i in seq_len(p)) {
    for (j in seq_len(p)) {
      if (i == j) next
      cij <- C[i, j]
      if (threshold_type == "hard") {
        C[i, j] <- if (abs(cij) > threshold) cij else 0
      } else {
        C[i, j] <- sign(cij) * max(abs(cij) - threshold, 0)
      }
    }
  }

  # Convert back to covariance
  Sigma <- C * outer(sd, sd)
  Sigma <- (Sigma + t(Sigma)) / 2

  # Warn if not positive-definite
  min_eval <- min(eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values)
  if (min_eval <= 0) {
    cli::cli_warn(
      c(
        "The thresholded covariance matrix is not positive-definite.",
        "i" = "Minimum eigenvalue: {round(min_eval, 6)}.",
        "i" = "Consider reducing {.arg threshold} or using {.arg method = \"ledoit_wolf\"}."
      )
    )
  }

  list(Sigma = Sigma, shrinkage = NULL, n_clipped = NULL)
}
