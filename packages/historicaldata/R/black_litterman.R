#' Black-Litterman equilibrium-anchored posterior expected returns
#'
#' @title Black-Litterman Posterior (`hd_black_litterman`)
#'
#' @description
#' Computes the Black-Litterman (1992) posterior expected-return vector and
#' posterior covariance matrix by blending a CAPM reverse-optimisation prior
#' with investor views expressed through the pick matrix P and view-return
#' vector Q.
#'
#' **The master formula (He & Litterman 1999, eq. 2):**
#' \deqn{
#'   \hat{\mu} = \left[(\tau\Sigma)^{-1} + P^\top \Omega^{-1} P\right]^{-1}
#'               \left[(\tau\Sigma)^{-1} \Pi + P^\top \Omega^{-1} Q\right]
#' }
#' where the **equilibrium prior** is Π = λ·Σ·w_mkt (reverse-optimisation
#' of the market portfolio under risk aversion λ) and the **posterior
#' covariance of the mean** is
#' \deqn{M = \left[(\tau\Sigma)^{-1} + P^\top \Omega^{-1} P\right]^{-1}.}
#' The full posterior covariance (used for portfolio construction) is
#' Σ\_BL = Σ + M.
#'
#' **No-views case:** when `P` is `NULL` (or has 0 rows), the posterior
#' collapses to the prior exactly:
#' * posterior μ̂ = Π
#' * posterior Σ\_BL = Σ + τΣ = (1 + τ)·Σ
#'
#' This is the mathematically consistent limit as the view-observation matrix
#' P vanishes (M → τΣ), verified in Test 1 of the accompanying test file.
#'
#' **Default view uncertainty (Ω):** when `omega` is `NULL`, the standard
#' He & Litterman (1999) diagonal default is used:
#' Ω = diag(P (τΣ) Pᵀ), which sets view-portfolio uncertainty proportional
#' to the prior covariance of the view portfolio.
#'
#' **Look-ahead bias note:** the calibration parameters τ, Ω, w\_mkt, and
#' view returns Q must all be determined using in-window/training data only.
#' Passing any of these from a hold-out period introduces look-ahead bias into
#' optimised portfolio weights.
#'
#' **Priced-in signal note (see `priced-in-prohibition` rule):** views in Q
#' must provide *incremental* predictive power over and above what is already
#' reflected in current prices (i.e. the equilibrium prior Π). Views derived
#' from publicly available consensus macro forecasts carry no such edge and
#' merely tilt the portfolio toward an already-priced risk.
#'
#' @param sigma A p × p numeric, positive-definite covariance matrix (asset
#'   names preserved as `dimnames`). Use [hd_cov_estimate()] to regularise
#'   near-singular matrices before calling this function.
#' @param w_mkt Named numeric vector of p market-cap weights that sum to
#'   approximately 1 (tolerance 0.01). Defines the equilibrium portfolio
#'   whose implied returns seed the prior Π = λ·Σ·w\_mkt.
#' @param P Optional k × p numeric pick matrix encoding k investor views over
#'   p assets. Row i of P defines the view portfolio; `P[i, j]` is the weight
#'   on asset j in view i. A relative (long-short) view uses signed weights
#'   (e.g. long A, short B: `c(1, -1, rep(0, p-2))`). An absolute view uses
#'   a unit row (e.g. `c(1, 0, ..., 0)`). When `NULL` (the default), the
#'   posterior collapses to the equilibrium prior.
#' @param Q Numeric vector of length k — the expected return for each view
#'   portfolio in the same units as `sigma` (typically annualised decimals,
#'   e.g. `0.05` for 5%). Required when `P` is supplied.
#' @param tau Positive scalar — the scalar controlling the uncertainty of the
#'   prior distribution. Typically small (e.g. `0.025` to `0.10`); a common
#'   practitioner default is `0.05`. Larger τ means more weight on views
#'   relative to the prior. Default `0.05`.
#' @param omega Optional k × k positive-definite matrix of view uncertainties.
#'   When `NULL` (default), the He & Litterman (1999) diagonal default is
#'   used: Ω = diag(P (τΣ) Pᵀ), which scales uncertainty proportional to the
#'   prior variance of each view portfolio. Ignored when `P` is `NULL`.
#' @param risk_aversion Positive scalar — the market risk-aversion coefficient
#'   λ, used to compute the equilibrium prior Π = λ·Σ·w\_mkt. A common
#'   empirical estimate for global equity markets is `2.5`; callers should
#'   supply their own estimate based on their investment universe (e.g.
#'   Merton 1980 or calibration from the Sharpe ratio of the market). When
#'   `NULL`, defaults to `2.5` with a diagnostic message. Default `NULL`.
#'
#' @return A named list with the following components:
#'   \describe{
#'     \item{`posterior_mu`}{Named numeric vector of length p — the
#'       Black-Litterman posterior expected returns. Names match the column
#'       names of `sigma`. This is μ̂ in the master formula.}
#'     \item{`posterior_sigma`}{Numeric p × p matrix — the posterior
#'       covariance Σ\_BL = Σ + M. Numerically symmetrised. Use this for
#'       portfolio construction in place of the sample covariance.}
#'     \item{`prior_mu`}{Named numeric vector of length p — the CAPM
#'       reverse-optimisation equilibrium prior Π = λ·Σ·w\_mkt.}
#'   }
#'   The following attributes are always set on the returned list:
#'   \describe{
#'     \item{`tau`}{Numeric scalar — the τ used.}
#'     \item{`risk_aversion`}{Numeric scalar — the λ used.}
#'     \item{`n_views`}{Integer — number of views (k), or 0 when `P` is
#'       `NULL`.}
#'   }
#'
#' @references
#' Black, F. & Litterman, R. (1992). Global Portfolio Optimization.
#' *Financial Analysts Journal*, 48(5), 28–43.
#' \doi{10.2469/faj.v48.n5.28}
#'
#' He, G. & Litterman, R. (1999). The Intuition Behind Black-Litterman
#' Model Portfolios. Goldman Sachs Investment Management Series.
#' \url{https://papers.ssrn.com/sol3/papers.cfm?abstract_id=334304}
#'
#' Idzorek, T. (2007). A Step-By-Step Guide to the Black-Litterman Model.
#' In S. Satchell (Ed.), *Forecasting Expected Returns in the Financial
#' Markets*. Elsevier. \doi{10.1016/B978-075068321-0.50011-1}
#'
#' Merton, R.C. (1980). On estimating the expected return on the market.
#' *Journal of Financial Economics*, 8(4), 323–361.
#' \doi{10.1016/0304-405X(80)90007-0}
#'
#' @family returns
#' @export
#'
#' @examples
#' # 5-asset example
#' set.seed(1L)
#' X     <- matrix(stats::rnorm(120L * 5L), nrow = 120L, ncol = 5L)
#' sigma <- stats::cov(X)
#' dimnames(sigma) <- list(paste0("A", seq_len(5L)), paste0("A", seq_len(5L)))
#' w_mkt <- c(A1 = 0.30, A2 = 0.20, A3 = 0.25, A4 = 0.15, A5 = 0.10)
#'
#' # No views: posterior collapses to equilibrium prior
#' bl_noviews <- hd_black_litterman(sigma, w_mkt, risk_aversion = 2.5)
#' bl_noviews$posterior_mu   # == risk_aversion * sigma %*% w_mkt
#' bl_noviews$prior_mu       # same as posterior_mu in the no-views case
#'
#' # Two views: A1 will return 6%, A2 will outperform A3 by 2%
#' P <- rbind(
#'   c(1,  0, 0, 0, 0),   # absolute view on A1
#'   c(0,  1, -1, 0, 0)   # relative view: A2 outperforms A3
#' )
#' colnames(P) <- paste0("A", seq_len(5L))
#' Q <- c(0.06, 0.02)
#'
#' bl <- hd_black_litterman(sigma, w_mkt, P = P, Q = Q,
#'                          tau = 0.05, risk_aversion = 2.5)
#' bl$posterior_mu     # view-adjusted expected returns
#' bl$posterior_sigma  # posterior covariance for portfolio construction
#' attr(bl, "n_views") # 2
hd_black_litterman <- function(sigma,
                               w_mkt,
                               P             = NULL,
                               Q             = NULL,
                               tau           = 0.05,
                               omega         = NULL,
                               risk_aversion = NULL) {

  # ---- Validate sigma (N × N, numeric, square) ----------------------------
  if (!is.matrix(sigma) || !is.numeric(sigma)) {
    cli::cli_abort(
      "{.arg sigma} must be a numeric matrix; got {.cls {class(sigma)}}."
    )
  }
  if (nrow(sigma) != ncol(sigma)) {
    cli::cli_abort(
      c(
        "{.arg sigma} must be a square matrix.",
        "x" = "Got a {nrow(sigma)} × {ncol(sigma)} matrix."
      )
    )
  }
  N <- nrow(sigma)
  if (N < 2L) {
    cli::cli_abort(
      "{.arg sigma} must be at least 2 × 2; got {N} × {N}."
    )
  }
  asset_names <- rownames(sigma)

  # ---- Validate tau -------------------------------------------------------
  if (!is.numeric(tau) || length(tau) != 1L || tau <= 0) {
    cli::cli_abort(
      "{.arg tau} must be a single positive scalar; got {tau}."
    )
  }

  # ---- Validate / default risk_aversion -----------------------------------
  if (is.null(risk_aversion)) {
    risk_aversion <- 2.5
  } else {
    if (!is.numeric(risk_aversion) || length(risk_aversion) != 1L ||
        risk_aversion <= 0) {
      cli::cli_abort(
        "{.arg risk_aversion} must be a positive scalar; got {risk_aversion}."
      )
    }
  }

  # ---- Validate w_mkt -----------------------------------------------------
  if (!is.numeric(w_mkt) || length(w_mkt) != N) {
    cli::cli_abort(
      c(
        "{.arg w_mkt} must be a numeric vector of length {N} (matching {.arg sigma}).",
        "x" = "Got length {length(w_mkt)}."
      )
    )
  }
  if (abs(sum(w_mkt) - 1) > 0.01) {
    cli::cli_abort(
      "{.arg w_mkt} must sum to approximately 1; got {round(sum(w_mkt), 4)}."
    )
  }

  # ---- Compute equilibrium prior Π = λ·Σ·w_mkt ---------------------------
  Pi <- as.numeric(risk_aversion * sigma %*% w_mkt)
  if (!is.null(asset_names)) names(Pi) <- asset_names

  # ---- Determine number of views ------------------------------------------
  k <- if (is.null(P)) 0L else nrow(P)

  # ---- No-views case: posterior collapses to prior ------------------------
  if (k == 0L) {
    tau_sigma      <- tau * sigma
    posterior_mu   <- Pi
    posterior_sigma <- (sigma + tau_sigma)
    if (!is.null(asset_names)) {
      dimnames(posterior_sigma) <- list(asset_names, asset_names)
    }
    # Symmetrise (numerical guard)
    posterior_sigma <- (posterior_sigma + t(posterior_sigma)) / 2

    result <- list(
      posterior_mu    = posterior_mu,
      posterior_sigma = posterior_sigma,
      prior_mu        = Pi
    )
    attr(result, "tau")           <- tau
    attr(result, "risk_aversion") <- risk_aversion
    attr(result, "n_views")       <- 0L
    return(result)
  }

  # ---- Validate P ---------------------------------------------------------
  if (!is.matrix(P) || !is.numeric(P)) {
    cli::cli_abort(
      "{.arg P} must be a numeric matrix; got {.cls {class(P)}}."
    )
  }
  if (ncol(P) != N) {
    cli::cli_abort(
      c(
        "{.arg P} must have {N} columns (one per asset), matching {.arg sigma}.",
        "x" = "Got {ncol(P)} columns."
      )
    )
  }

  # ---- Validate Q ---------------------------------------------------------
  if (is.null(Q)) {
    cli::cli_abort(
      c(
        "{.arg Q} is required when {.arg P} is supplied.",
        "i" = "Provide a numeric vector of length {k} — one expected return per view."
      )
    )
  }
  Q <- as.numeric(Q)
  if (length(Q) != k) {
    cli::cli_abort(
      c(
        "{.arg Q} must have length {k} (one return per view row of {.arg P}).",
        "x" = "Got length {length(Q)}."
      )
    )
  }

  # ---- Validate omega (if supplied) ----------------------------------------
  if (!is.null(omega)) {
    if (!is.matrix(omega) || !is.numeric(omega)) {
      cli::cli_abort(
        "{.arg omega} must be a numeric matrix; got {.cls {class(omega)}}."
      )
    }
    if (nrow(omega) != k || ncol(omega) != k) {
      cli::cli_abort(
        c(
          "{.arg omega} must be a {k} × {k} matrix (one row/col per view).",
          "x" = "Got a {nrow(omega)} × {ncol(omega)} matrix."
        )
      )
    }
  }

  # ---- τΣ -----------------------------------------------------------------
  tau_sigma <- tau * sigma

  # ---- Default Ω = diag(P (τΣ) Pᵀ) (He & Litterman 1999) -----------------
  if (is.null(omega)) {
    diag_vals <- as.numeric(diag(P %*% tau_sigma %*% t(P)))
    omega     <- diag(diag_vals, nrow = k, ncol = k)
  }

  # ---- BL master formula --------------------------------------------------
  # All solves wrapped in tryCatch to give informative errors on singularity.

  # (τΣ)⁻¹  — used twice; solve once
  inv_tau_sigma <- tryCatch(
    solve(tau_sigma),
    error = function(e) {
      cli::cli_abort(
        c(
          "Could not invert {.arg tau} * {.arg sigma} (τΣ).",
          "x" = "The matrix is likely singular or ill-conditioned.",
          "i" = "Consider regularising {.arg sigma} with {.fn hd_cov_estimate}."
        )
      )
    }
  )

  # Ω⁻¹ P  — used twice
  inv_omega_P <- tryCatch(
    solve(omega, P),
    error = function(e) {
      cli::cli_abort(
        c(
          "Could not invert {.arg omega}.",
          "x" = "The view-uncertainty matrix is likely singular or ill-conditioned.",
          "i" = "Supply a positive-definite {k} × {k} {.arg omega}."
        )
      )
    }
  )

  # A = (τΣ)⁻¹ + Pᵀ Ω⁻¹ P
  A_mat <- inv_tau_sigma + t(P) %*% inv_omega_P

  # M = A⁻¹  (posterior covariance of the mean)
  M <- tryCatch(
    solve(A_mat),
    error = function(e) {
      cli::cli_abort(
        c(
          "Could not invert [(τΣ)⁻¹ + Pᵀ Ω⁻¹ P] in the BL master formula.",
          "x" = "The combined precision matrix is singular or ill-conditioned.",
          "i" = "Regularise {.arg sigma} with {.fn hd_cov_estimate} or reduce the",
          "i" = "number of views so they are not collinear."
        )
      )
    }
  )

  # RHS: (τΣ)⁻¹ Π + Pᵀ Ω⁻¹ Q
  rhs <- inv_tau_sigma %*% Pi + t(inv_omega_P) %*% Q

  # Posterior μ̂
  posterior_mu <- as.numeric(M %*% rhs)
  if (!is.null(asset_names)) names(posterior_mu) <- asset_names

  # Posterior Σ_BL = Σ + M
  posterior_sigma <- sigma + M
  if (!is.null(asset_names)) {
    dimnames(posterior_sigma) <- list(asset_names, asset_names)
  }
  # Symmetrise (numerical guard)
  posterior_sigma <- (posterior_sigma + t(posterior_sigma)) / 2

  # ---- Assemble result ----------------------------------------------------
  result <- list(
    posterior_mu    = posterior_mu,
    posterior_sigma = posterior_sigma,
    prior_mu        = Pi
  )
  attr(result, "tau")           <- tau
  attr(result, "risk_aversion") <- risk_aversion
  attr(result, "n_views")       <- k

  result
}
