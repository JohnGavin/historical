# Risk contribution measurement (#624, #626)
#
# hd_risk_contribution() — Euler (marginal + component) decomposition of
# portfolio volatility. Measurement only: this function does NOT renormalise
# or reweight the input. It exists because the project's only concentration
# metrics (`mean_eff_n`, `max_abs_weight` in weight_stability.R) are computed
# on *weights*, not *risk* — a position can look diversified on weight-HHI
# while dominating portfolio variance because it is highly volatile or
# correlated with the rest of the book. This function is also the
# prerequisite for the volatility-normalised / equal-risk-contribution
# leverage allocator planned in #626: that allocator's target state is
# exactly `pct_contribution` equal across assets, which cannot be verified
# without computing it.

#' Component and marginal contribution to portfolio risk (Euler decomposition)
#'
#' @title Portfolio Risk Contribution (`hd_risk_contribution`)
#'
#' @description
#' Decomposes total portfolio volatility into each asset's marginal and
#' component contribution using the standard Euler decomposition:
#'
#' \deqn{\sigma_p = \sqrt{w^\top \Sigma w}}
#' \deqn{MCR_i = \frac{(\Sigma w)_i}{\sigma_p}}
#' \deqn{CR_i = w_i \cdot MCR_i}
#'
#' By Euler's theorem for the (positive-homogeneous-of-degree-1) portfolio
#' volatility function, the component contributions sum exactly to total
#' portfolio volatility: \eqn{\sum_i CR_i = \sigma_p}. This identity is the
#' correctness anchor for this function and is asserted directly in its
#' test suite.
#'
#' **Why this differs from weight concentration:** `mean_eff_n` and
#' `max_abs_weight` ([hd_weight_stability_diagnostic()]) summarise the
#' *weight* vector alone and treat every asset as equally risky and
#' uncorrelated. A 5%-weight position in a high-volatility asset, or a
#' cluster of mutually correlated positions, can dominate portfolio variance
#' while appearing well diversified on weights alone. `hd_risk_contribution()`
#' answers "where does the portfolio's *risk* actually come from," using the
#' full covariance structure rather than weights in isolation.
#'
#' **Negative weights and negative contributions are both intentional.**
#' This project routinely runs long/short books. A short position
#' (`w_i < 0`) can have a *negative* `pct_contribution` — meaning it reduces
#' rather than adds to total portfolio risk (a hedge). A negative
#' `pct_contribution` is a correct hedging signal, not a bug or a sign that
#' the computation has failed.
#'
#' **Rank-deficient covariance is supported.** Estimated covariance matrices
#' in this project are routinely rank-deficient or ill-conditioned (see
#' [hd_cov_estimate()] and its regularisation methods). The Euler
#' decomposition above is well-defined for any positive semi-definite `Sigma`
#' — this function does **not** require or check positive-definiteness.
#'
#' @param w A numeric vector of portfolio weights, length `p`. May contain
#'   negative values (short positions). May be named.
#' @param cov_mat A numeric `p x p` covariance matrix. Must be square,
#'   symmetric (within floating-point tolerance), and have `nrow(cov_mat)`
#'   equal to `length(w)`.
#'
#' @return A [tibble::tibble()] with one row per asset and columns:
#'   \describe{
#'     \item{`asset`}{Character. Taken from `names(w)` if present, else from
#'       `colnames(cov_mat)`, else `"asset_1"`, `"asset_2"`, ....}
#'     \item{`weight`}{Numeric. The input weight `w_i`.}
#'     \item{`mcr`}{Numeric. Marginal contribution to risk,
#'       `(Sigma %*% w)[i] / sigma_p`.}
#'     \item{`cr`}{Numeric. Component contribution to risk,
#'       `w_i * mcr_i`. `sum(cr)` equals portfolio volatility `sigma_p`
#'       (the Euler identity).}
#'     \item{`pct_contribution`}{Numeric. `cr_i / sigma_p`, the fraction of
#'       total portfolio risk attributable to asset `i`. Sums to 1 across
#'       assets. May be negative for a hedging short position.}
#'   }
#'   When `sigma_p` is numerically zero (e.g. an all-zero `w`, or a
#'   perfectly hedged degenerate case), `mcr`, `cr`, and `pct_contribution`
#'   are `NA_real_` for every asset rather than a division-by-zero result.
#'
#' @examples
#' # Three-asset example: equal weights, unequal variances + correlation
#' Sigma <- matrix(
#'   c(0.04, 0.01, 0.00,
#'     0.01, 0.09, 0.02,
#'     0.00, 0.02, 0.01),
#'   nrow = 3, dimnames = list(c("A", "B", "C"), c("A", "B", "C"))
#' )
#' w <- c(A = 1 / 3, B = 1 / 3, C = 1 / 3)
#' hd_risk_contribution(w, Sigma)
#'
#' # Long/short: the short leg (D) can show a negative pct_contribution,
#' # meaning it hedges rather than adds to total portfolio risk.
#' Sigma2 <- matrix(
#'   c(0.04, 0.03,
#'     0.03, 0.04),
#'   nrow = 2, dimnames = list(c("C_long", "D_short"), c("C_long", "D_short"))
#' )
#' hd_risk_contribution(c(C_long = 1, D_short = -0.5), Sigma2)
#'
#' @family risk_metrics
#' @export
hd_risk_contribution <- function(w, cov_mat) {
  if (!is.numeric(w)) {
    cli::cli_abort(
      c(
        "{.arg w} must be a numeric vector.",
        "x" = "Got {.cls {class(w)}}."
      )
    )
  }

  if (length(w) == 0L) {
    cli::cli_abort(
      c(
        "{.arg w} must have length >= 1.",
        "x" = "Got a zero-length vector."
      )
    )
  }

  if (anyNA(w)) {
    cli::cli_abort(
      c(
        "{.arg w} must not contain {.val NA} or {.val NaN}.",
        "i" = "Found {sum(is.na(w))} missing value{?s} at position{?s} {which(is.na(w))}.",
        "i" = "Resolve missingness upstream; {.fun hd_risk_contribution} does not {.code na.rm}."
      )
    )
  }

  if (!all(is.finite(w))) {
    cli::cli_abort(
      c(
        "{.arg w} must contain only finite values.",
        "x" = "Found non-finite value{?s} at position{?s} {which(!is.finite(w))}."
      )
    )
  }

  if (!is.matrix(cov_mat) || !is.numeric(cov_mat)) {
    cli::cli_abort(
      c(
        "{.arg cov_mat} must be a numeric matrix.",
        "x" = "Got {.cls {class(cov_mat)}}."
      )
    )
  }

  if (nrow(cov_mat) != ncol(cov_mat)) {
    cli::cli_abort(
      c(
        "{.arg cov_mat} must be square.",
        "x" = "Got {nrow(cov_mat)} row{?s} and {ncol(cov_mat)} column{?s}."
      )
    )
  }

  if (anyNA(cov_mat) || !all(is.finite(cov_mat))) {
    cli::cli_abort(
      "{.arg cov_mat} must contain only finite, non-missing values."
    )
  }

  if (!isTRUE(all.equal(cov_mat, t(cov_mat), tolerance = 1e-8))) {
    cli::cli_abort(
      c(
        "{.arg cov_mat} must be symmetric.",
        "x" = "Max asymmetry: {max(abs(cov_mat - t(cov_mat)))}."
      )
    )
  }

  p <- length(w)
  if (nrow(cov_mat) != p) {
    cli::cli_abort(
      c(
        "{.arg cov_mat} dimensions must match {.arg w}.",
        "x" = "{.arg w} has length {p}; {.arg cov_mat} is {nrow(cov_mat)} x {ncol(cov_mat)}."
      )
    )
  }

  w_names   <- names(w)
  cov_names <- colnames(cov_mat)

  if (!is.null(w_names) && !is.null(cov_names) && !identical(w_names, cov_names)) {
    cli::cli_abort(
      c(
        "{.arg w} and {.arg cov_mat} names disagree.",
        "x" = "{.code names(w)}: {.val {w_names}}.",
        "x" = "{.code colnames(cov_mat)}: {.val {cov_names}}.",
        "i" = "Reorder upstream so the two agree; this function will not guess the correct alignment."
      )
    )
  }

  asset_names <- if (!is.null(w_names)) {
    w_names
  } else if (!is.null(cov_names)) {
    cov_names
  } else {
    paste0("asset_", seq_len(p))
  }

  sigma_p_sq <- as.numeric(t(w) %*% cov_mat %*% w)
  sigma_p    <- sqrt(max(sigma_p_sq, 0))

  if (!is.finite(sigma_p) || sigma_p < .Machine$double.eps^0.5) {
    return(
      tibble::tibble(
        asset            = asset_names,
        weight           = as.numeric(w),
        mcr              = NA_real_,
        cr               = NA_real_,
        pct_contribution = NA_real_
      )
    )
  }

  sigma_w <- as.numeric(cov_mat %*% w)
  mcr     <- sigma_w / sigma_p
  cr      <- as.numeric(w) * mcr

  tibble::tibble(
    asset            = asset_names,
    weight           = as.numeric(w),
    mcr              = mcr,
    cr               = cr,
    pct_contribution = cr / sigma_p
  )
}
