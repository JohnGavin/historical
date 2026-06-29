#' Shrinkage estimator for expected returns in mean-variance optimisation
#'
#' @title Expected-Return Shrinkage Estimator (`hd_returns_shrink`)
#'
#' @description
#' Shrinks a vector of sample expected returns toward a lower-variance target,
#' addressing the well-known sensitivity of mean-variance optimisation (MVO) to
#' noisy plug-in sample means. Three methods are supported:
#'
#' * **`"grand_mean"`** — shrinks each asset's expected return toward the
#'   cross-sectional grand mean `mean(mu)`. Requires an explicit `intensity` δ
#'   or, when `n_obs` is supplied, derives a James-Stein-inspired data-driven δ
#'   without needing the covariance matrix. Default δ is 0.5 when neither
#'   `intensity` nor `n_obs` is supplied.
#'
#' * **`"james_stein"`** — Bayes-Stein shrinkage (Jorion 1986) toward the
#'   minimum-variance grand mean μ₀ = (1ᵀΣ⁻¹μ) / (1ᵀΣ⁻¹1). The shrinkage
#'   intensity φ is estimated from the data via
#'   φ = (p+2) / ((p+2) + T·(μ−μ₀·1)ᵀΣ⁻¹(μ−μ₀·1)), where p is the number
#'   of assets and T = `n_obs`. Requires `sigma` and `n_obs`.
#'
#' * **`"equilibrium"`** — shrinks toward the CAPM reverse-optimisation
#'   implied return Π = λ·Σ·w\_mkt, where λ is the market risk-aversion
#'   coefficient and w\_mkt are the market-cap weights. This is the
#'   Black-Litterman prior; the later BL PR will extend this standalone
#'   shrink toward a posterior. Requires `sigma`, `w_mkt`, and
#'   `risk_aversion`. Uses `intensity` (default 0.5) for the blend.
#'
#' **Look-ahead bias note:** all intensity parameters (δ, φ) must be estimated
#' on in-window/training data only. Passing a covariance matrix or `n_obs`
#' estimated on a hold-out period introduces look-ahead bias into the
#' optimised weights.
#'
#' @param mu Named numeric vector (or single-column numeric data frame) of
#'   length p containing the asset expected returns. Names are preserved on
#'   the output. A single-column data frame is coerced to a numeric vector
#'   using the column's names.
#' @param method Shrinkage method. One of `"james_stein"` (default),
#'   `"grand_mean"`, or `"equilibrium"`. Partial matching supported via
#'   [base::match.arg()].
#' @param sigma p × p positive-definite covariance matrix (same asset order
#'   as `mu`). Required for `"james_stein"` and `"equilibrium"`; ignored for
#'   `"grand_mean"`.
#' @param n_obs Positive integer — number of observations (T) used to estimate
#'   `mu`. Required for `"james_stein"`. For `"grand_mean"`, when supplied and
#'   `intensity` is `NULL`, a James-Stein-inspired data-driven δ is derived:
#'   δ = clamp((p−2) / (T · ‖μ − μ̄·1‖²), 0, 1). When `NULL` and `intensity`
#'   is also `NULL`, the default intensity 0.5 is used.
#' @param w_mkt Named numeric vector of p market-cap weights that sum to
#'   approximately 1 (tolerance 0.01). Required for `"equilibrium"`.
#' @param risk_aversion Positive scalar risk-aversion coefficient λ. Required
#'   for `"equilibrium"`. Represents the slope of the mean-variance frontier
#'   consistent with the market portfolio.
#' @param intensity Scalar in \[0, 1\] — the shrinkage blend weight δ. When
#'   non-`NULL`, overrides any data-driven derivation for `"grand_mean"` and
#'   sets the blend for `"equilibrium"`. Ignored for `"james_stein"` (which
#'   computes φ analytically). When `NULL` and no alternative applies, the
#'   default is 0.5.
#'
#' @return A named numeric vector of length p — the shrunk expected-return
#'   vector. The result is always a convex combination of `mu` and the
#'   method-specific target: result = (1−δ)·μ + δ·target. The following
#'   attributes are always set:
#'   \describe{
#'     \item{`method`}{Character scalar — the shrinkage method used.}
#'     \item{`target`}{Named numeric vector of length p — the shrinkage target
#'       (grand mean vector, JS minimum-variance mean, or equilibrium Π).}
#'     \item{`intensity`}{Numeric scalar in \[0, 1\] — the shrinkage intensity δ
#'       (or φ for `"james_stein"`) that was applied.}
#'   }
#'
#' @references
#' Jorion, P. (1986). Bayes-Stein Estimation for Portfolio Analysis.
#' *Journal of Financial and Quantitative Analysis*, 21(3), 279–292.
#' \doi{10.2307/2331042}
#'
#' Black, F. & Litterman, R. (1992). Global Portfolio Optimization.
#' *Financial Analysts Journal*, 48(5), 28–43.
#' \doi{10.2469/faj.v48.n5.28}
#'
#' Jorion, P. (1991). Bayesian and CAPM estimators of the means:
#' Implications for portfolio selection. *Journal of Banking & Finance*,
#' 15(3), 717–727. \doi{10.1016/0378-4266(91)90094-3}
#'
#' @family returns
#' @export
#'
#' @examples
#' # 5-asset example
#' mu <- c(A1 = 0.05, A2 = 0.08, A3 = 0.12, A4 = 0.07, A5 = 0.10)
#' set.seed(1L)
#' X     <- matrix(stats::rnorm(120L * 5L), nrow = 120L, ncol = 5L)
#' sigma <- stats::cov(X)
#' dimnames(sigma) <- list(names(mu), names(mu))
#' w_mkt <- c(A1 = 0.30, A2 = 0.20, A3 = 0.25, A4 = 0.15, A5 = 0.10)
#'
#' # Grand-mean shrinkage with explicit intensity
#' mu_gm <- hd_returns_shrink(mu, method = "grand_mean", intensity = 0.4)
#' attr(mu_gm, "target")     # the grand mean vector
#' attr(mu_gm, "intensity")  # 0.4
#'
#' # Bayes-Stein (Jorion 1986) — data-driven shrinkage intensity
#' mu_js <- hd_returns_shrink(mu, method = "james_stein",
#'                            sigma = sigma, n_obs = 120L)
#' attr(mu_js, "intensity")  # phi in [0,1]
#'
#' # Equilibrium (Black-Litterman prior) with 40% shrinkage toward CAPM
#' mu_eq <- hd_returns_shrink(mu, method = "equilibrium",
#'                            sigma = sigma, w_mkt = w_mkt,
#'                            risk_aversion = 2.5, intensity = 0.4)
#' attr(mu_eq, "target")     # Π = lambda * Sigma * w_mkt
hd_returns_shrink <- function(mu,
                              method = c("james_stein", "grand_mean",
                                         "equilibrium"),
                              sigma         = NULL,
                              n_obs         = NULL,
                              w_mkt         = NULL,
                              risk_aversion = NULL,
                              intensity     = NULL) {

  method <- match.arg(method)

  # ---- Coerce mu to a named numeric vector ---------------------------------
  if (is.data.frame(mu)) {
    if (ncol(mu) != 1L) {
      cli::cli_abort(
        c(
          "{.arg mu} data frame must have exactly 1 column; got {ncol(mu)}.",
          "i" = "Provide a named numeric vector or a single-column data frame."
        )
      )
    }
    nm_save <- rownames(mu)
    mu      <- mu[[1L]]
    names(mu) <- nm_save
  }

  if (!is.numeric(mu)) {
    cli::cli_abort(
      "{.arg mu} must be a numeric vector or single-column data frame; got {.cls {class(mu)}}."
    )
  }

  p <- length(mu)
  if (p < 2L) {
    cli::cli_abort(
      "{.arg mu} must have at least 2 elements; got {p}."
    )
  }

  # ---- Validate shared optional args ---------------------------------------
  if (!is.null(intensity)) {
    if (!is.numeric(intensity) || length(intensity) != 1L ||
        intensity < 0 || intensity > 1) {
      cli::cli_abort(
        "{.arg intensity} must be a single numeric value in [0, 1]; got {intensity}."
      )
    }
  }

  if (!is.null(n_obs)) {
    if (!is.numeric(n_obs) || length(n_obs) != 1L || n_obs < 1L) {
      cli::cli_abort(
        "{.arg n_obs} must be a positive integer; got {n_obs}."
      )
    }
    n_obs <- as.integer(n_obs)
  }

  if (!is.null(sigma)) {
    if (!is.matrix(sigma) || !is.numeric(sigma)) {
      cli::cli_abort(
        "{.arg sigma} must be a numeric matrix; got {.cls {class(sigma)}}."
      )
    }
    if (nrow(sigma) != p || ncol(sigma) != p) {
      cli::cli_abort(
        c(
          "{.arg sigma} must be a {p} × {p} matrix (matching {.arg mu} length {p}).",
          "x" = "Got a {nrow(sigma)} × {ncol(sigma)} matrix."
        )
      )
    }
  }

  if (!is.null(w_mkt)) {
    if (!is.numeric(w_mkt) || length(w_mkt) != p) {
      cli::cli_abort(
        c(
          "{.arg w_mkt} must be a numeric vector of length {p} (matching {.arg mu}).",
          "x" = "Got length {length(w_mkt)}."
        )
      )
    }
    if (abs(sum(w_mkt) - 1) > 0.01) {
      cli::cli_abort(
        "{.arg w_mkt} must sum to approximately 1; got {round(sum(w_mkt), 4)}."
      )
    }
  }

  if (!is.null(risk_aversion)) {
    if (!is.numeric(risk_aversion) || length(risk_aversion) != 1L ||
        risk_aversion <= 0) {
      cli::cli_abort(
        "{.arg risk_aversion} must be a positive scalar; got {risk_aversion}."
      )
    }
  }

  # ---- Method-level required-arg checks ------------------------------------
  if (method == "james_stein") {
    if (is.null(sigma)) {
      cli::cli_abort(
        c(
          "{.arg sigma} is required for {.code method = \"james_stein\"}.",
          "i" = "Provide a {p} × {p} positive-definite covariance matrix."
        )
      )
    }
    if (is.null(n_obs)) {
      cli::cli_abort(
        c(
          "{.arg n_obs} is required for {.code method = \"james_stein\"}.",
          "i" = "Provide the number of observations (T) used to estimate {.arg mu}."
        )
      )
    }
  }

  if (method == "equilibrium") {
    if (is.null(sigma)) {
      cli::cli_abort(
        c(
          "{.arg sigma} is required for {.code method = \"equilibrium\"}.",
          "i" = "Provide a {p} × {p} positive-definite covariance matrix."
        )
      )
    }
    if (is.null(w_mkt)) {
      cli::cli_abort(
        c(
          "{.arg w_mkt} is required for {.code method = \"equilibrium\"}.",
          "i" = "Provide market-cap weights that sum to 1."
        )
      )
    }
    if (is.null(risk_aversion)) {
      cli::cli_abort(
        c(
          "{.arg risk_aversion} is required for {.code method = \"equilibrium\"}.",
          "i" = "Provide the market risk-aversion coefficient λ > 0."
        )
      )
    }
  }

  # ---- Dispatch to method helpers ------------------------------------------
  result <- switch(method,
    grand_mean   = .rs_grand_mean(mu, p, n_obs, intensity),
    james_stein  = .rs_james_stein(mu, p, sigma, n_obs),
    equilibrium  = .rs_equilibrium(mu, sigma, w_mkt, risk_aversion, intensity)
  )

  # ---- Attach attributes ---------------------------------------------------
  mu_shrunk <- result$mu_shrunk
  names(mu_shrunk) <- names(mu)

  attr(mu_shrunk, "method")    <- method
  attr(mu_shrunk, "target")    <- result$target
  attr(mu_shrunk, "intensity") <- result$intensity

  mu_shrunk
}

# ---------------------------------------------------------------------------
# Internal helpers (not exported)
# ---------------------------------------------------------------------------

# Grand-mean shrinkage: target = mean(mu) * 1_p
#
# Intensity selection priority:
#   1. `intensity` supplied explicitly → use it (clamped to [0,1])
#   2. `n_obs` supplied, `intensity` = NULL → James-Stein-inspired
#      δ = clamp((p-2) / (n_obs * ||mu - mean(mu)||²), 0, 1)
#      (if all mu equal, ||mu - mean(mu)||² = 0; δ = 0 — no-op since
#       target == mu in that case)
#   3. Both NULL → documented default 0.5
.rs_grand_mean <- function(mu, p, n_obs, intensity) {
  gm     <- mean(mu)
  target <- rep(gm, p)
  names(target) <- names(mu)

  if (!is.null(intensity)) {
    delta <- intensity  # already validated in [0,1]
  } else if (!is.null(n_obs)) {
    ss <- sum((mu - gm)^2)
    if (ss < .Machine$double.eps) {
      delta <- 0  # degenerate: target == mu, so any delta gives mu
    } else {
      delta <- max(0, min(1, (p - 2) / (n_obs * ss)))
    }
  } else {
    delta <- 0.5  # documented default when neither arg is supplied
  }

  list(
    mu_shrunk = (1 - delta) * mu + delta * target,
    target    = target,
    intensity = delta
  )
}

# James-Stein (Jorion 1986) shrinkage toward the minimum-variance grand mean.
#
# Target: μ₀ = (1ᵀΣ⁻¹μ) / (1ᵀΣ⁻¹1)   (scalar; the min-var portfolio mean)
# Intensity: φ = (p+2) / ((p+2) + T·dᵀΣ⁻¹d), d = μ − μ₀·1
# Result: (1−φ)·μ + φ·μ₀·1
.rs_james_stein <- function(mu, p, sigma, n_obs) {
  T     <- n_obs
  ones  <- rep(1, p)

  # Solve Σ⁻¹ · [mu, ones] simultaneously — avoids two separate solves
  rhs       <- cbind(mu, ones)
  Si_rhs    <- tryCatch(
    solve(sigma, rhs),
    error = function(e) {
      cli::cli_abort(
        c(
          "Could not invert {.arg sigma} for {.code method = \"james_stein\"}.",
          "x" = "Matrix is likely singular or ill-conditioned.",
          "i" = "Consider regularising {.arg sigma} with {.fn hd_cov_estimate}."
        )
      )
    }
  )
  Si_mu   <- Si_rhs[, 1L]
  Si_ones <- Si_rhs[, 2L]

  mu_0   <- as.numeric(t(ones)  %*% Si_mu) /
             as.numeric(t(ones) %*% Si_ones)
  target <- mu_0 * ones
  names(target) <- names(mu)

  diff   <- mu - target
  quad   <- as.numeric(t(diff) %*% Si_mu - t(diff) %*% (Si_rhs[, 1L] - Si_mu))
  # Re-derive cleanly: quad = diff' Σ⁻¹ diff
  Si_diff <- tryCatch(
    solve(sigma, diff),
    error = function(e) {
      cli::cli_abort(
        c(
          "Could not compute Mahalanobis form for {.code method = \"james_stein\"}.",
          "x" = "Matrix solve failed; {.arg sigma} may be singular."
        )
      )
    }
  )
  quad <- as.numeric(t(diff) %*% Si_diff)

  # Clamp numerically to [0, 1] (should be automatic, but guard against
  # floating-point degenerate case where quad is tiny negative due to FP noise)
  phi <- if (quad < .Machine$double.eps) {
    1  # mu == target exactly; full shrinkage is the limiting result
  } else {
    max(0, min(1, (p + 2) / ((p + 2) + T * quad)))
  }

  list(
    mu_shrunk = (1 - phi) * mu + phi * target,
    target    = target,
    intensity = phi
  )
}

# Equilibrium (CAPM reverse-optimisation) shrinkage.
#
# Target: Π = λ·Σ·w_mkt
# Blend:  (1−δ)·μ + δ·Π   for δ = intensity %||% 0.5
.rs_equilibrium <- function(mu, sigma, w_mkt, risk_aversion, intensity) {
  Pi  <- as.numeric(risk_aversion * sigma %*% w_mkt)
  names(Pi) <- names(mu)

  delta <- intensity %||% 0.5
  delta <- max(0, min(1, delta))

  list(
    mu_shrunk = (1 - delta) * mu + delta * Pi,
    target    = Pi,
    intensity = delta
  )
}
