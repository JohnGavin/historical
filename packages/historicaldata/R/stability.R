# Sharpe Stability Ratio primitives
#
# Rolling-window Sharpe series and the Sharpe Stability Ratio (SSR), which
# quantifies how *consistently* a strategy earns its risk-adjusted returns
# across time, not just on average.
#
# Methodology: overlapping rolling windows share w-1 observations, creating
# strong serial correlation in the derived Sharpe series.  HAC (Newey-West)
# correction is essential -- naive variance estimators understate uncertainty
# by orders of magnitude for overlapping windows.
#
# Reference:
#   Bajor Traver & Rodriguez Dominguez (2026), "The Sharpe Stability Ratio".
#   Brine & Sueppel (2026), Macrosynergy research post on SSR.
#   Newey & West (1987), Econometrica 55(3), 703-708.


# ── 1. Rolling Sharpe series ──────────────────────────────────────────────────

#' Rolling-window annualised Sharpe ratios
#'
#' Computes annualised Sharpe ratios over overlapping rolling windows.
#' Used by [hd_sharpe_stability_ratio()] to assess the temporal consistency
#' of risk-adjusted performance.
#'
#' Windows where the standard deviation is zero (e.g. a constant-return
#' series) yield `NA`.  The return vector is silently stripped of `NA`s
#' before processing.
#'
#' @param r Numeric vector of period returns (daily, monthly, etc.).
#'   `NA` values are removed before computation.
#' @param w Integer window length in periods.  Typical choices: 252 for
#'   daily returns (one trading year), 36 for monthly (three years).
#' @param ann_factor Annualisation factor matching the frequency of `r`
#'   (252 for daily, 12 for monthly, 4 for quarterly).
#'
#' @return Numeric vector of length `max(0L, length(r_clean) - w + 1L)`
#'   where `r_clean = r[!is.na(r)]`.  Each element is the annualised Sharpe
#'   ratio for the corresponding window.  Windows with zero variance yield
#'   `NA`.
#'
#' @family falsification
#' @export
hd_rolling_sharpe <- function(r, w, ann_factor = 252) {
  if (!is.numeric(r)) {
    cli::cli_abort(c("x" = "{.arg r} must be a numeric vector."))
  }
  if (!is.numeric(w) || length(w) != 1L || w < 1L || w != floor(w)) {
    cli::cli_abort(c("x" = "{.arg w} must be a positive integer scalar."))
  }
  if (!is.numeric(ann_factor) || length(ann_factor) != 1L || ann_factor <= 0) {
    cli::cli_abort(c("x" = "{.arg ann_factor} must be a positive numeric scalar."))
  }

  r_clean <- r[!is.na(r)]
  w       <- as.integer(w)
  n       <- length(r_clean)

  if (n < w) return(numeric(0L))

  # slider::slide_dbl with .complete = TRUE returns NA for partial windows
  # (the leading w-1 positions).  We keep only the complete-window values.
  mu  <- slider::slide_dbl(r_clean, mean,       .before = w - 1L, .after = 0L, .complete = TRUE)
  sd_ <- slider::slide_dbl(r_clean, stats::sd,  .before = w - 1L, .after = 0L, .complete = TRUE)

  sr_full <- ifelse(sd_ > 0, mu / sd_ * sqrt(ann_factor), NA_real_)

  # Drop the leading NAs from partial windows (.complete = TRUE inserts them).
  # The result has exactly n - w + 1 elements.
  sr_full[!is.na(sd_)]
}


# ── 2. Sharpe Stability Ratio ─────────────────────────────────────────────────

#' Sharpe Stability Ratio (SSR)
#'
#' Quantifies the temporal stability and statistical significance of a
#' strategy's risk-adjusted performance.  Defined as the mean of rolling
#' Sharpe ratios divided by their Newey-West HAC standard error.
#'
#' The SSR approximates a t-statistic for the population Sharpe being
#' non-zero after accounting for the serial correlation induced by
#' overlapping windows:
#'
#' * SSR = 1.00 → ~68% confidence (1 SD)
#' * SSR = 1.64 → ~90% confidence
#' * SSR = 1.96 → ~95% confidence
#' * SSR = 2.58 → ~99% confidence
#'
#' Methodological note: overlapping rolling windows share `w-1`
#' observations, creating strong serial correlation in the derived Sharpe
#' series.  HAC (Newey-West) correction is essential -- naive variance
#' estimators understate uncertainty by orders of magnitude.
#'
#' Calibration anchors from published research: S&P 500 daily returns since
#' 1995 yield a naive Sharpe ~0.5 and SSR ~5.3.  A purely episodic return
#' series (a single large gain in an otherwise flat series) has positive
#' full-sample Sharpe but SSR near zero, correctly diagnosing instability.
#'
#' @param r Numeric vector of period returns.  `NA` values are removed.
#' @param w Window length in periods.  Typical 252 (daily) or 36 (monthly).
#' @param ann_factor Annualisation factor (252 daily, 12 monthly).
#' @param lag_nw Newey-West bandwidth (number of lags).  `NULL` (default)
#'   uses the standard automatic rule `floor(4 * (T / 100)^(2/9))` where
#'   `T` is the number of rolling-window observations, with a minimum of 1.
#'
#' @return Named list with components:
#'   \describe{
#'     \item{ssr}{Sharpe Stability Ratio.  `NA` if fewer than 2 complete
#'       windows are available.}
#'     \item{mean_sharpe}{Mean of the rolling Sharpe series.}
#'     \item{se}{Newey-West HAC standard error of the rolling Sharpe series.}
#'     \item{n_windows}{Number of complete rolling windows used.}
#'     \item{w}{Window length (echoed from input).}
#'     \item{lag_nw}{Bandwidth actually used (integer).}
#'     \item{ann_factor}{Annualisation factor (echoed from input).}
#'   }
#'
#' @references
#' Bajor Traver & Rodriguez Dominguez (2026),
#'   "The Sharpe Stability Ratio".
#' Brine & Sueppel (2026),
#'   Macrosynergy research post on SSR.
#' Newey & West (1987),
#'   "A Simple, Positive Semi-Definite, Heteroskedasticity and
#'   Autocorrelation Consistent Covariance Matrix",
#'   *Econometrica* **55**(3), 703-708.
#'
#' @family falsification
#' @export
hd_sharpe_stability_ratio <- function(r, w, ann_factor = 252, lag_nw = NULL) {
  if (!is.numeric(r)) {
    cli::cli_abort(c("x" = "{.arg r} must be a numeric vector."))
  }
  if (!is.numeric(w) || length(w) != 1L || w < 1L || w != floor(w)) {
    cli::cli_abort(c("x" = "{.arg w} must be a positive integer scalar."))
  }
  if (!is.numeric(ann_factor) || length(ann_factor) != 1L || ann_factor <= 0) {
    cli::cli_abort(c("x" = "{.arg ann_factor} must be a positive numeric scalar."))
  }
  if (!is.null(lag_nw)) {
    if (!is.numeric(lag_nw) || length(lag_nw) != 1L ||
        lag_nw < 0L || lag_nw != floor(lag_nw)) {
      cli::cli_abort(c("x" = "{.arg lag_nw} must be NULL or a non-negative integer scalar."))
    }
    lag_nw <- as.integer(lag_nw)
  }

  sr <- hd_rolling_sharpe(r, w, ann_factor)
  n  <- length(sr)

  na_result <- list(
    ssr         = NA_real_,
    mean_sharpe = NA_real_,
    se          = NA_real_,
    n_windows   = n,
    w           = as.integer(w),
    lag_nw      = NA_integer_,
    ann_factor  = as.double(ann_factor)
  )

  if (n < 2L) return(na_result)

  # Automatic bandwidth if not supplied: standard rule from hd_hac_tstat.
  if (is.null(lag_nw)) {
    lag_nw <- max(1L, as.integer(floor(4 * (n / 100)^(2 / 9))))
  }

  # Newey-West long-run variance of the rolling Sharpe series.
  # We apply the Bartlett kernel (same as hd_hac_tstat) to the demeaned series.
  sr_mean   <- mean(sr, na.rm = TRUE)
  sr_demean <- sr - sr_mean

  gamma0  <- sum(sr_demean^2, na.rm = TRUE) / n
  hac_var <- gamma0
  for (l in seq_len(lag_nw)) {
    gamma_l <- sum(
      sr_demean[seq_len(n - l)] * sr_demean[(l + 1L):n],
      na.rm = TRUE
    ) / n
    weight  <- 1 - l / (lag_nw + 1L)
    hac_var <- hac_var + 2 * weight * gamma_l
  }

  # Guard against rounding to slightly below zero.
  hac_var <- max(hac_var, 0)
  se      <- sqrt(hac_var / n)
  ssr     <- if (se > 0) sr_mean / se else NA_real_

  list(
    ssr         = ssr,
    mean_sharpe = sr_mean,
    se          = se,
    n_windows   = n,
    w           = as.integer(w),
    lag_nw      = lag_nw,
    ann_factor  = as.double(ann_factor)
  )
}
