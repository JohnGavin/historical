# ADF stationarity + ACF/Ljung-Box clustering diagnostics.
#
# Origin: issue #838. The aligrithm article runs an ADF stationarity check
# and an ACF-decay diagnostic on its rolling log-volatility series before
# trusting the regime classification built on top of it, and explicitly
# treats this as a precondition, not an afterthought. `grep -rn
# "adf.test|acf(|Box.test"` across R/ and packages/historicaldata/R/ (as of
# #838) found no ADF/Box.test usage anywhere in this repo -- this file fills
# that gap.

#' ADF stationarity test and ACF/Ljung-Box clustering diagnostics
#'
#' Runs an augmented Dickey-Fuller (ADF) unit-root test (drift, no trend
#' case) plus an ACF/Ljung-Box autocorrelation summary on a numeric series
#' -- the two checks the aligrithm article (Borrego Roldan 2024, issue #838)
#' runs on its log-volatility input before trusting the regime
#' classification built on top of it.
#'
#' @section ADF implementation note:
#' No unit-root-test package (`tseries`, `urca`) is available in this
#' project's Nix environment (see `flake.nix`), and per
#' `.claude/rules/external-code-zero-trust.md` this is NOT worked around by
#' copying one of those packages' implementations. Instead, the standard
#' textbook augmented Dickey-Fuller regression (Dickey & Fuller, 1979) is
#' implemented directly with `stats::lm()`:
#' \deqn{\Delta y_t = \alpha + \beta y_{t-1} + \sum_{i=1}^{p} \gamma_i \Delta y_{t-i} + \varepsilon_t}
#' testing \eqn{H_0: \beta = 0} (unit root) against \eqn{H_1: \beta < 0}
#' (stationary) -- the "drift, no trend" case, appropriate for a
#' log-volatility series with no obvious deterministic trend. The
#' augmenting lag order defaults to \code{trunc((n - 1)^(1/3))} (the
#' rule-of-thumb default also used by `tseries::adf.test()`) when
#' \code{adf_lag_order} is \code{NULL}.
#'
#' The test statistic is compared against the ASYMPTOTIC (\eqn{T \to
#' \infty}) Dickey-Fuller critical values for the drift-only case (Fuller,
#' 1976; Hamilton, 1994, Table B.6): \eqn{-3.43} (1\%), \eqn{-2.86} (5\%),
#' \eqn{-2.57} (10\%). This is DELIBERATELY NOT a finite-sample-interpolated
#' p-value the way `tseries::adf.test()` computes one -- for a small sample
#' the true critical value is somewhat less negative than the asymptotic
#' figure, so \code{stationary_5pct} is a slightly conservative
#' (harder-to-pass) flag, not a precise p-value. Treat it as a diagnostic
#' signal, not a publication-grade test statistic.
#'
#' @param x Numeric vector, in time order (e.g. rolling log-volatility).
#'   Non-finite values (`NA`, `NaN`, `Inf`) are dropped before the checks
#'   run; the count dropped is reported via `cli::cli_warn()`
#'   (`fail-loud-not-null.md` Required Pattern 4) and returned as
#'   `n_dropped`. Dropping compacts the series rather than reindexing around
#'   the gap -- the same accepted limitation as this package's other rolling
#'   diagnostics (see the `na-propagation-rolling-stats` project memory).
#'   Must have at least 20 finite observations after dropping.
#' @param acf_lags Integer >= 1, and `< ` the number of finite observations.
#'   Number of lags for the ACF summary and the Ljung-Box test. Default
#'   `10L`.
#' @param adf_lag_order `NULL` (default, uses `trunc((n - 1)^(1/3))`), or a
#'   single non-negative integer overriding the number of augmenting lags
#'   in the ADF regression.
#'
#' @return Named list:
#'   \describe{
#'     \item{adf_statistic}{The ADF test statistic (\eqn{\hat\beta / SE(\hat\beta)}
#'       on the \eqn{y_{t-1}} coefficient).}
#'     \item{adf_lag_order}{Augmenting lag order actually used.}
#'     \item{adf_critical_values}{Named numeric vector, asymptotic critical
#'       values at `1%`/`5%`/`10%` (drift, no trend case).}
#'     \item{stationary_5pct}{Logical: is `adf_statistic` more negative than
#'       the 5% critical value (i.e. reject the unit-root null at 5%)?}
#'     \item{acf_values}{Numeric vector of length `acf_lags`, the sample ACF
#'       at lags `1:acf_lags` (lag 0 excluded).}
#'     \item{ljung_box_stat, ljung_box_p_value}{The Ljung-Box \eqn{Q}
#'       statistic and p-value (`stats::Box.test(type = "Ljung-Box")`) --
#'       jointly tests whether the first `acf_lags` autocorrelations differ
#'       from white noise (evidence of clustering).}
#'     \item{n_obs, n_dropped}{Finite observations used, and how many were
#'       dropped for non-finiteness.}
#'   }
#'
#' @references
#' Dickey, D. A., & Fuller, W. A. (1979). "Distribution of the Estimators
#' for Autoregressive Time Series with a Unit Root." \emph{Journal of the
#' American Statistical Association}, 74(366), 427-431.
#'
#' Fuller, W. A. (1976). \emph{Introduction to Statistical Time Series}.
#' Wiley. (Asymptotic critical values, drift-only case.)
#'
#' Ljung, G. M., & Box, G. E. P. (1978). "On a Measure of Lack of Fit in
#' Time Series Models." \emph{Biometrika}, 65(2), 297-303.
#'
#' @examples
#' set.seed(1)
#' # Stationary AR(1) series
#' x <- as.numeric(stats::arima.sim(list(ar = 0.5), n = 200))
#' out <- hd_stationarity_diagnostics(x)
#' out$stationary_5pct
#'
#' @family regime-diagnostics
#' @export
hd_stationarity_diagnostics <- function(x, acf_lags = 10L, adf_lag_order = NULL) {
  if (!is.numeric(x)) {
    cli::cli_abort(c(
      "x" = "{.arg x} must be a numeric vector.",
      "i" = "Got class {.cls {class(x)}}."
    ))
  }
  if (!is.numeric(acf_lags) || length(acf_lags) != 1L || is.na(acf_lags) ||
      acf_lags < 1L || acf_lags != round(acf_lags)) {
    cli::cli_abort(c(
      "x" = "{.arg acf_lags} must be a single positive integer.",
      "i" = "Got {.val {acf_lags}}."
    ))
  }
  acf_lags <- as.integer(acf_lags)
  if (!is.null(adf_lag_order)) {
    if (!is.numeric(adf_lag_order) || length(adf_lag_order) != 1L ||
        is.na(adf_lag_order) || adf_lag_order < 0L ||
        adf_lag_order != round(adf_lag_order)) {
      cli::cli_abort(c(
        "x" = "{.arg adf_lag_order} must be NULL or a single non-negative integer.",
        "i" = "Got {.val {adf_lag_order}}."
      ))
    }
    adf_lag_order <- as.integer(adf_lag_order)
  }

  n_raw <- length(x)
  finite <- is.finite(x)
  n_dropped <- sum(!finite)
  if (n_dropped > 0L) {
    cli::cli_warn(c(
      "!" = "Dropped {n_dropped} non-finite value{?s} (NA/NaN/Inf) from {.arg x}.",
      "i" = "hd_stationarity_diagnostics() compacts around gaps rather than reindexing -- see roxygen limitation note."
    ))
  }
  x <- x[finite]
  n_obs <- length(x)

  if (n_obs < 20L) {
    cli::cli_abort(c(
      "x" = "{.arg x} has only {n_obs} finite observation{?s} after dropping non-finite values.",
      "i" = "hd_stationarity_diagnostics() requires at least 20 to fit the ADF regression and compute ACF lags.",
      "i" = "Raw input length was {n_raw}."
    ))
  }
  if (acf_lags >= n_obs) {
    cli::cli_abort(c(
      "x" = "{.arg acf_lags} ({acf_lags}) must be less than the number of finite observations ({n_obs}).",
      "i" = "Reduce {.arg acf_lags} or supply a longer {.arg x}."
    ))
  }

  p <- if (is.null(adf_lag_order)) trunc((n_obs - 1)^(1 / 3)) else adf_lag_order

  dy <- diff(x)
  n_dy <- length(dy)
  used_rows <- n_dy - p
  n_params  <- p + 2L  # intercept + y_lag1 + p augmenting lags
  if (used_rows - n_params < 5L) {
    cli::cli_abort(c(
      "x" = "ADF augmenting lag order {p} leaves too few usable observations to fit the regression.",
      "i" = "{n_obs} finite observations yield only {max(used_rows, 0L)} usable row{?s} for {n_params} parameters.",
      "i" = "Supply a smaller {.arg adf_lag_order} or a longer {.arg x}."
    ))
  }

  y_lag1 <- x[-length(x)]  # length n_dy, aligned with dy
  start_row <- p + 1L
  reg_rows  <- start_row:n_dy
  resp      <- dy[reg_rows]
  y_lag1_r  <- y_lag1[reg_rows]

  lag_mat <- if (p > 0L) {
    m <- vapply(seq_len(p), function(i) dy[reg_rows - i], numeric(length(reg_rows)))
    colnames(m) <- paste0("dy_lag", seq_len(p))
    m
  } else {
    NULL
  }

  fit_df <- data.frame(resp = resp, y_lag1 = y_lag1_r)
  if (!is.null(lag_mat)) {
    fit_df <- cbind(fit_df, as.data.frame(lag_mat))
  }

  fit  <- stats::lm(resp ~ ., data = fit_df)
  smry <- summary(fit)
  coefs <- smry$coefficients
  if (!("y_lag1" %in% rownames(coefs)) ||
      anyNA(coefs["y_lag1", c("Estimate", "Std. Error")])) {
    cli::cli_abort(c(
      "x" = "ADF regression could not estimate the y_lag1 coefficient (collinear or degenerate design).",
      "i" = "This can happen with a near-constant {.arg x} or too high {.arg adf_lag_order} for the sample."
    ))
  }
  adf_stat <- unname(coefs["y_lag1", "Estimate"] / coefs["y_lag1", "Std. Error"])

  adf_crit <- c(`1%` = -3.43, `5%` = -2.86, `10%` = -2.57)

  acf_obj  <- stats::acf(x, lag.max = acf_lags, plot = FALSE)
  acf_vals <- as.numeric(acf_obj$acf[-1])  # drop lag 0

  bt <- stats::Box.test(x, lag = acf_lags, type = "Ljung-Box")

  list(
    adf_statistic       = adf_stat,
    adf_lag_order       = p,
    adf_critical_values = adf_crit,
    stationary_5pct     = unname(adf_stat < adf_crit["5%"]),
    acf_values          = acf_vals,
    ljung_box_stat      = unname(bt$statistic),
    ljung_box_p_value   = unname(bt$p.value),
    n_obs               = n_obs,
    n_dropped           = as.integer(n_dropped)
  )
}
