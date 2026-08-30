# Risk architecture metrics (Tinsley Pillar 8)
#
# hd_dd_duration()     — drawdown duration statistics (avg, max, count)
# hd_loss_clustering() — Wald-Wolfowitz runs test + lag-1 ACF clustering signal
# hd_cdap()            — Coherent Drawdown-Adjusted Performance (fixes Calmar
#                         sign-inversion for negative returns, issue #588)

# ── 1. Drawdown duration ─────────────────────────────────────────────────────

#' Drawdown duration statistics using high-water mark definition
#'
#' Identifies contiguous drawdown periods using the cumulative high-water mark
#' (HWM).  A drawdown begins when the cumulative return falls below the prior
#' peak and ends when it recovers to within 0.1% of that peak.  Durations are
#' returned in the same units as the input dates (calendar days when dates are
#' provided, observations otherwise).
#'
#' @param returns Numeric vector of returns (NAs removed automatically).
#' @param dates Optional Date or POSIXct vector of the same length as
#'   \code{returns}.  When supplied, durations are in calendar days; when
#'   \code{NULL} (default), durations are in observations.
#'
#' @return A named list with three components:
#'   \describe{
#'     \item{avg_dd_duration}{Average drawdown duration (days or obs).
#'       \code{NA} if no qualifying drawdown was found.}
#'     \item{max_dd_duration}{Maximum drawdown duration (days or obs).
#'       \code{NA} if no qualifying drawdown was found.}
#'     \item{n_drawdowns}{Integer count of distinct drawdown events (HWM
#'       definition, threshold -1%).}
#'   }
#'
#' @examples
#' set.seed(1)
#' r <- rnorm(120, 0.001, 0.02)
#' hd_dd_duration(r)
#'
#' @family risk_metrics
#' @export
hd_dd_duration <- function(returns, dates = NULL) {
  returns <- as.numeric(returns)
  if (!is.null(dates)) {
    keep    <- !is.na(returns) & !is.na(dates)
    dates   <- as.Date(dates[keep])
    returns <- returns[keep]
  } else {
    returns <- returns[!is.na(returns)]
  }

  n <- length(returns)
  na_list <- list(avg_dd_duration = NA_real_,
                  max_dd_duration = NA_real_,
                  n_drawdowns     = 0L)
  if (n < 2L) return(na_list)

  cum  <- cumprod(1 + returns)
  peak <- cummax(cum)
  dd   <- (cum - peak) / peak          # <= 0 throughout

  # Drawdown event: contiguous run below -1% threshold
  in_dd <- dd < -0.01

  if (!any(in_dd)) {
    return(list(avg_dd_duration = NA_real_,
                max_dd_duration = NA_real_,
                n_drawdowns     = 0L))
  }

  # Identify start and end indices of each drawdown run
  rle_dd <- rle(in_dd)
  ends   <- cumsum(rle_dd$lengths)
  starts <- c(1L, ends[-length(ends)] + 1L)

  durations <- numeric(0)
  event_count <- 0L

  for (k in seq_along(rle_dd$values)) {
    if (!rle_dd$values[k]) next
    event_count <- event_count + 1L
    s <- starts[k]
    e <- ends[k]

    if (!is.null(dates)) {
      # Calendar duration from start of drawdown run to end
      dur <- as.numeric(difftime(dates[e], dates[s], units = "days")) + 1
    } else {
      dur <- rle_dd$lengths[k]
    }
    durations <- c(durations, dur)
  }

  if (length(durations) == 0L) return(na_list)

  list(
    avg_dd_duration = mean(durations),
    max_dd_duration = max(durations),
    n_drawdowns     = event_count
  )
}


# ── 2. Loss clustering ───────────────────────────────────────────────────────

#' Loss clustering signal: Wald-Wolfowitz runs test + lag-1 ACF
#'
#' Tests whether losses are clustered (non-random) using two complementary
#' signals:
#'
#' \enumerate{
#'   \item **Wald-Wolfowitz runs test** on the sign of returns.  Under the null
#'         that successive return signs are independent, the number of runs
#'         follows an approximately normal distribution.  A small p-value
#'         indicates the sign sequence is non-random (too few runs = clustered
#'         losses/wins; too many = alternating).
#'   \item **Lag-1 autocorrelation** of raw monthly returns.  Positive ACF(1)
#'         indicates momentum / persistence; negative indicates mean-reversion.
#' }
#'
#' The composite \code{clustered} flag is \code{TRUE} only when \emph{both}
#' signals agree: \code{runs_test_p < 0.05} AND \code{acf_lag1 > 0.2}.
#'
#' @param returns Numeric vector of returns.  NAs are removed.
#'
#' @return A named list with three components:
#'   \describe{
#'     \item{runs_test_p}{Two-sided p-value from the Wald-Wolfowitz runs test
#'       on \code{sign(returns)}.  \code{NA} if fewer than 10 observations
#'       remain after removing NAs.}
#'     \item{acf_lag1}{Lag-1 autocorrelation of \code{returns}.  \code{NA} if
#'       fewer than 3 observations.}
#'     \item{clustered}{Logical.  \code{TRUE} if \code{runs_test_p < 0.05} AND
#'       \code{acf_lag1 > 0.2}; \code{FALSE} otherwise; \code{NA} if either
#'       input is \code{NA}.}
#'   }
#'
#' @examples
#' set.seed(42)
#' hd_loss_clustering(rnorm(100))        # iid noise -> clustered = FALSE
#'
#' @family risk_metrics
#' @export
hd_loss_clustering <- function(returns) {
  returns <- as.numeric(returns)
  returns <- returns[!is.na(returns)]

  na_list <- list(runs_test_p = NA_real_, acf_lag1 = NA_real_,
                  clustered   = NA)

  n <- length(returns)
  if (n < 3L) return(na_list)

  # ── Lag-1 ACF ────────────────────────────────────────────────────────────
  acf_lag1 <- stats::cor(returns[-n], returns[-1L], use = "complete.obs")
  if (is.na(acf_lag1)) acf_lag1 <- NA_real_

  if (n < 10L) {
    return(list(runs_test_p = NA_real_, acf_lag1 = acf_lag1, clustered = NA))
  }

  # ── Wald-Wolfowitz runs test on sign(returns) ────────────────────────────
  # Ties (zero returns) are dropped: sign=0 is excluded.
  signs <- sign(returns)
  signs <- signs[signs != 0L]
  n_eff <- length(signs)

  if (n_eff < 10L) {
    return(list(runs_test_p = NA_real_, acf_lag1 = acf_lag1, clustered = NA))
  }

  n_pos <- sum(signs > 0L)
  n_neg <- n_eff - n_pos

  # Count runs
  n_runs <- 1L + sum(signs[-1L] != signs[-n_eff])

  # Under H0, expected runs and variance (exact formula):
  #   E[R] = 1 + 2*n1*n2 / (n1+n2)
  #   Var[R] = 2*n1*n2*(2*n1*n2 - n1 - n2) / ((n1+n2)^2*(n1+n2-1))
  n1 <- n_pos
  n2 <- n_neg
  N  <- n1 + n2

  mu_r  <- 1 + 2 * n1 * n2 / N
  var_r <- if (N > 1L) {
    (2 * n1 * n2 * (2 * n1 * n2 - N)) / (N^2 * (N - 1))
  } else {
    NA_real_
  }

  if (is.na(var_r) || var_r <= 0) {
    # Degenerate case: all same sign -> exactly 1 run, much fewer than expected.
    # Treat as strongly significant clustering (p ~= 0).
    if (n1 == 0L || n2 == 0L) {
      runs_test_p <- 0
    } else {
      runs_test_p <- NA_real_
    }
  } else {
    z <- (n_runs - mu_r) / sqrt(var_r)
    runs_test_p <- 2 * stats::pnorm(-abs(z))   # two-sided
  }

  # Composite flag
  clustered <- if (is.na(runs_test_p) || is.na(acf_lag1)) {
    NA
  } else {
    runs_test_p < 0.05 && acf_lag1 > 0.2
  }

  list(
    runs_test_p = runs_test_p,
    acf_lag1    = acf_lag1,
    clustered   = clustered
  )
}


# ── 3. Coherent Drawdown-Adjusted Performance (CDAP) ────────────────────────

#' Coherent Drawdown-Adjusted Performance -- a sign-coherent Calmar ratio
#'
#' The conventional Calmar ratio (\code{cagr / abs(max_dd)}) is
#' mathematically incoherent when \code{cagr} is negative: dividing a
#' negative return by a LARGER drawdown magnitude yields a LESS negative
#' (better-ranked) ratio. Two strategies with identical CAGR but twice the
#' drawdown then rank the RISKIER one higher -- the metric inverts exactly
#' where risk assessment matters most. See issue #588 for the worked example
#' (\code{r = -0.10}: \code{d = -0.20} gives \code{-0.50}; \code{d = -0.40}
#' gives \code{-0.25}, ranking the deeper drawdown "better").
#'
#' CDAP resolves this by flipping the exponent on the drawdown term
#' according to the sign of the return:
#' \deqn{CDAP = r \times |d|^{-\mathrm{sign}(r)}}
#' For \code{r > 0} this is \code{r / |d|} -- identical to the conventional
#' Calmar ratio, so no existing positive-return ranking changes. For
#' \code{r < 0} this is \code{r \times |d|}, so a LARGER drawdown magnitude
#' now produces a MORE negative (worse-ranked) score -- the coherent
#' direction. For \code{r == 0}, \code{sign(r) == 0} in R, so the exponent
#' is 0 and \code{CDAP = r = 0} (no special-casing needed).
#'
#' @source Samir Varma, "The Stop-Loss That Stops Gains" (2026), summarising
#'   a Nov 2025 \emph{Journal of Portfolio Management} paper.
#'   \url{https://samirvarma.substack.com/p/the-stop-loss-that-stops-gains}
#'
#' @param r Numeric vector. Return (e.g. CAGR), any sign. \code{r} and
#'   \code{d} must use the SAME scale (both fractions, e.g. \code{-0.10}, or
#'   both percent, e.g. \code{-10}) -- CDAP is scale-consistent with its
#'   inputs, matching whatever convention the caller's \code{cagr}/\code{max_dd}
#'   already use (see \code{R/utils_metrics.R} unit-convention comment).
#' @param d Numeric vector. Maximum drawdown, same length as \code{r} (or
#'   length 1, recycled). May be signed (the conventional negative
#'   representation, e.g. \code{-0.20}) or already a non-negative magnitude
#'   -- \code{abs(d)} is taken internally either way.
#'
#' @return Numeric vector of CDAP values, same length as
#'   \code{max(length(r), length(d))}. \code{NA_real_} where \code{r} or
#'   \code{d} is \code{NA}, or where \code{d == 0} (no drawdown to divide
#'   by or multiply against) -- matching the prior Calmar convention of
#'   returning \code{NA} when \code{max_dd} is zero.
#'
#' @examples
#' # Positive return: identical to conventional Calmar
#' hd_cdap(0.10, -0.05)   # 0.10 / 0.05 = 2
#'
#' # Negative return: larger drawdown now ranks WORSE (more negative),
#' # unlike the conventional Calmar ratio it replaces (issue #588).
#' hd_cdap(-0.10, -0.20)  # -0.10 * 0.20 = -0.02
#' hd_cdap(-0.10, -0.40)  # -0.10 * 0.40 = -0.04 (worse, correctly)
#'
#' @family risk_metrics
#' @export
hd_cdap <- function(r, d) {
  if (!is.numeric(r)) {
    cli::cli_abort(c(
      "x" = "{.arg r} must be a numeric vector.",
      "i" = "Got {.cls {class(r)}}."
    ))
  }
  if (!is.numeric(d)) {
    cli::cli_abort(c(
      "x" = "{.arg d} must be a numeric vector.",
      "i" = "Got {.cls {class(d)}}."
    ))
  }

  n <- max(length(r), length(d))
  if (length(r) != n && length(r) != 1L) {
    cli::cli_abort(c(
      "x" = "{.arg r} and {.arg d} must be the same length (or length 1).",
      "i" = "Got length {length(r)} and {length(d)}."
    ))
  }
  if (length(d) != n && length(d) != 1L) {
    cli::cli_abort(c(
      "x" = "{.arg r} and {.arg d} must be the same length (or length 1).",
      "i" = "Got length {length(r)} and {length(d)}."
    ))
  }

  ad <- abs(d)
  ifelse(
    is.na(r) | is.na(d) | ad == 0,
    NA_real_,
    r * ad^(-sign(r))
  )
}
