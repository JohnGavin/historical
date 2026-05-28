# Walk-Forward Correlation (WFC) core function
#
# Computes the IS↔OOS Pearson and Spearman correlation across the full
# parameter grid for a strategy, following Tinsley (2026), SSRN 6324079.
#
# Usage: compute grid_tbl with columns theta_id, theta_label, IS_metric,
# OOS_metric (one row per parameter tuple), then call hd_wf_correlation().
#
# Reference: knowledge/wiki/walk-forward-correlation.md
# Issue: #297

# ── 1. Core WFC function ──────────────────────────────────────────────────────

#' Walk-Forward Correlation diagnostic across a full parameter grid
#'
#' Evaluates the predictive consistency of in-sample optimisation by computing
#' the Pearson and Spearman correlation between IS and OOS metric values across
#' every parameter combination in the supplied grid.  This quantifies whether
#' the optimisation surface has structural predictive power or merely overfits
#' in-sample noise.
#'
#' High WFC with positive OOS performance indicates structural edge.
#' High WFC with negative OOS performance indicates a consistently
#' loss-making strategy.  Low WFC (≤ 0.234, the paper's calibration for
#' "low") indicates over-fitting or noise regardless of OOS sign.
#'
#' Calibration thresholds (from Tinsley's Figure 4 worked example):
#' \itemize{
#'   \item High WFC: ≥ 0.70 (paper's clean-edge example ≈ 0.881)
#'   \item Moderate WFC: 0.40 – 0.70 (paper's moderate example ≈ 0.581)
#'   \item Low WFC: < 0.40 (paper's no-edge example ≈ 0.234)
#' }
#' The cutoff of 0.70 for "high" is our project's working threshold, sitting
#' midway between the paper's moderate (0.581) and high (0.881) calibration
#' points.  See \code{wfc_threshold_high} parameter to override.
#'
#' @param grid_tbl A data frame with at minimum the columns:
#'   \describe{
#'     \item{theta_id}{Integer or character. Unique identifier for each
#'       parameter combination (row).}
#'     \item{theta_label}{Character. Human-readable label, e.g. \code{"alpha=0.5,lambda=0.01"}.}
#'     \item{IS_metric}{Numeric. In-sample Sharpe ratio (or other metric) for
#'       this parameter combination.  Must be computed on the train partition
#'       only — no IS/OOS overlap.}
#'     \item{OOS_metric}{Numeric. Out-of-sample Sharpe ratio on the test
#'       partition.}
#'   }
#' @param wfc_threshold_high Numeric. WFC value above which the strategy is
#'   classified as "high correlation".  Default 0.70.  See Details for the
#'   paper calibration.
#' @param oos_median_ref Numeric or \code{NULL}.  Reference median used to
#'   classify OOS performance as positive or negative.  If \code{NULL}
#'   (default), the median of \code{OOS_metric} across the grid is used.
#'
#' @return A named list with components:
#'   \describe{
#'     \item{pearson}{Numeric. Pearson correlation between IS_metric and OOS_metric.}
#'     \item{spearman}{Numeric. Spearman (rank) correlation.}
#'     \item{n_points}{Integer. Number of complete-case grid points used.}
#'     \item{classification}{Character. One of
#'       \code{"structural_edge"} (high WFC, positive median OOS),
#'       \code{"consistently_loss_making"} (high WFC, negative median OOS),
#'       \code{"spurious_luck"} (low WFC, positive median OOS), or
#'       \code{"noise"} (low WFC, negative median OOS).}
#'     \item{wfc_category}{Character. \code{"high"}, \code{"moderate"}, or
#'       \code{"low"} based on the Pearson ρ and the calibration thresholds.}
#'     \item{median_oos}{Numeric. Median OOS_metric across the grid.}
#'     \item{pct_positive_oos}{Numeric. Fraction of grid points with
#'       OOS_metric > 0.}
#'   }
#'
#' @family falsification
#' @export
#'
#' @examples
#' # Perfectly correlated IS and OOS (ideal structural edge)
#' grid <- data.frame(
#'   theta_id    = 1:5,
#'   theta_label = paste0("p", 1:5),
#'   IS_metric   = c(0.5, 0.8, 1.2, 1.5, 1.8),
#'   OOS_metric  = c(0.4, 0.7, 1.1, 1.4, 1.7)
#' )
#' hd_wf_correlation(grid)
hd_wf_correlation <- function(grid_tbl,
                               wfc_threshold_high = 0.70,
                               oos_median_ref     = NULL) {

  # ── Input validation ───────────────────────────────────────────────────────
  required_cols <- c("theta_id", "theta_label", "IS_metric", "OOS_metric")
  missing_cols  <- setdiff(required_cols, names(grid_tbl))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "grid_tbl is missing required columns: {.val {missing_cols}}",
      "i" = "Required: {.val {required_cols}}"
    ))
  }

  # Remove rows where either metric is NA
  complete <- grid_tbl[
    !is.na(grid_tbl$IS_metric) & !is.na(grid_tbl$OOS_metric),
  ]

  n_points <- nrow(complete)

  if (n_points < 2L) {
    cli::cli_abort(c(
      "x" = "grid_tbl has only {n_points} complete-case row{?s} after removing NAs.",
      "i" = "Need at least 2 rows to compute a correlation.",
      "i" = "Check that IS_metric and OOS_metric are populated for each parameter combination."
    ))
  }

  # ── Correlations ───────────────────────────────────────────────────────────
  pearson_rho  <- stats::cor(complete$IS_metric, complete$OOS_metric,
                              method = "pearson")
  spearman_rho <- stats::cor(complete$IS_metric, complete$OOS_metric,
                              method = "spearman")

  # ── OOS summary ────────────────────────────────────────────────────────────
  median_oos     <- stats::median(complete$OOS_metric)
  pct_pos_oos    <- mean(complete$OOS_metric > 0)

  oos_ref <- if (!is.null(oos_median_ref)) oos_median_ref else median_oos
  oos_positive   <- oos_ref >= 0

  # ── WFC category (Pearson-based, using project thresholds) ─────────────────
  # Thresholds: high >= 0.70, moderate [0.40, 0.70), low < 0.40
  # Cutoffs chosen to straddle the paper's empirical calibration points
  # (high ≈ 0.881, moderate ≈ 0.581, low ≈ 0.234).
  wfc_category <- dplyr::case_when(
    pearson_rho >= wfc_threshold_high ~ "high",
    pearson_rho >= 0.40               ~ "moderate",
    TRUE                              ~ "low"
  )

  wfc_high <- pearson_rho >= wfc_threshold_high

  # ── 2×2 classification (Tinsley p.4 diagnostic matrix) ─────────────────────
  classification <- dplyr::case_when(
    wfc_high  &  oos_positive ~ "structural_edge",
    wfc_high  & !oos_positive ~ "consistently_loss_making",
    !wfc_high &  oos_positive ~ "spurious_luck",
    TRUE                      ~ "noise"
  )

  list(
    pearson         = pearson_rho,
    spearman        = spearman_rho,
    n_points        = n_points,
    classification  = classification,
    wfc_category    = wfc_category,
    median_oos      = median_oos,
    pct_positive_oos = pct_pos_oos
  )
}
