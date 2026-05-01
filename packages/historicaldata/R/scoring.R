# Distributional forecast evaluation: CRPS, Brier score, horizon analysis
#
# All scoring rules follow the "lower is better" convention:
#   CRPS = 0 for a perfect point forecast, higher = worse
#   Brier score = 0 for perfect probability forecast, 0.25 = random (50/50)
#
# Reference: Gneiting & Raftery (2007), "Strictly Proper Scoring Rules,
# Prediction, and Estimation", JASA 102(477).


# ── 1. CRPS – empirical forecast distribution ─────────────────────────────────

#' CRPS for an empirical forecast distribution
#'
#' Computes the Continuous Ranked Probability Score for a forecast given as a
#' sample of draws from the predictive distribution. The energy score
#' decomposition is used:
#' \deqn{CRPS = E|X - y| - 0.5 \cdot E|X - X'|}
#' where X and X' are iid draws from the forecast distribution and y is the
#' observation. Memory is bounded by limiting the outer product to
#' `max_samples` draws.
#'
#' @param observed Scalar numeric. The realised observation.
#' @param forecast_samples Numeric vector of simulated values from the predictive
#'   distribution. At least 2 elements required; capped internally at
#'   `max_samples`.
#' @param max_samples Integer. Maximum number of samples used for the pairwise
#'   spread term. Defaults to 1000L. Reduces memory use for large forecasts.
#'
#' @return Scalar numeric CRPS value (non-negative). Returns `NA_real_` if
#'   `length(forecast_samples) < 2` or if `observed` is NA.
#'
#' @family scoring
#' @export
hd_crps_empirical <- function(observed, forecast_samples, max_samples = 1000L) {
  if (is.na(observed)) return(NA_real_)
  forecast_samples <- forecast_samples[!is.na(forecast_samples)]
  if (length(forecast_samples) < 2L) return(NA_real_)

  # Cap sample size to limit memory for outer product
  if (length(forecast_samples) > max_samples) {
    set.seed(NULL)  # use current RNG state (caller should set seed)
    forecast_samples <- sample(forecast_samples, max_samples, replace = FALSE)
  }

  bias_term   <- mean(abs(forecast_samples - observed))
  spread_term <- mean(abs(outer(forecast_samples, forecast_samples, "-")))
  bias_term - 0.5 * spread_term
}


# ── 2. CRPS – Gaussian (closed form) ─────────────────────────────────────────

#' CRPS for a Gaussian forecast distribution (closed form)
#'
#' Evaluates the exact CRPS for a forecast \eqn{N(\mu, \sigma^2)}:
#' \deqn{CRPS = \sigma \left[ z(2\Phi(z) - 1) + 2\phi(z) - \pi^{-1/2} \right]}
#' where \eqn{z = (y - \mu)/\sigma}, \eqn{\Phi} is the standard normal CDF,
#' and \eqn{\phi} is the standard normal PDF.
#'
#' @param observed Scalar numeric. The realised observation.
#' @param mu Scalar numeric. Forecast mean.
#' @param sigma Scalar numeric. Forecast standard deviation (must be > 0).
#'
#' @return Scalar numeric CRPS value (non-negative). Returns `NA_real_` if any
#'   input is NA or if `sigma <= 0`.
#'
#' @family scoring
#' @export
hd_crps_normal <- function(observed, mu, sigma) {
  if (any(is.na(c(observed, mu, sigma)))) return(NA_real_)
  if (sigma <= 0) return(NA_real_)

  z    <- (observed - mu) / sigma
  crps <- sigma * (z * (2 * stats::pnorm(z) - 1) +
                   2 * stats::dnorm(z) -
                   1 / sqrt(pi))
  crps
}


# ── 3. CRPS skill score ───────────────────────────────────────────────────────

#' CRPS skill score
#'
#' Computes the skill score measuring improvement of a model forecast over a
#' naive (climatological) benchmark:
#' \deqn{SS_{CRPS} = 1 - CRPS_{model} / CRPS_{naive}}
#' A score of 0 means no improvement over the naive forecast; positive values
#' indicate skill; negative values indicate the model is worse than naive.
#'
#' @param crps_model Numeric scalar or vector. CRPS values for the model.
#' @param crps_naive Numeric scalar or vector. CRPS values for the naive benchmark.
#'
#' @return Scalar numeric skill score. Returns `NA_real_` if either input is NA
#'   or if `crps_naive` is zero.
#'
#' @family scoring
#' @export
hd_crps_skill <- function(crps_model, crps_naive) {
  crps_model <- mean(crps_model, na.rm = TRUE)
  crps_naive <- mean(crps_naive, na.rm = TRUE)
  if (is.na(crps_model) || is.na(crps_naive)) return(NA_real_)
  if (abs(crps_naive) < .Machine$double.eps) return(NA_real_)
  1 - crps_model / crps_naive
}


# ── 4. Brier score ────────────────────────────────────────────────────────────

#' Brier score for probabilistic directional forecasts
#'
#' Computes the mean squared error between forecast probabilities and binary
#' outcomes:
#' \deqn{BS = \frac{1}{N} \sum (p_i - o_i)^2}
#' where \eqn{p_i \in [0,1]} is the forecast probability and \eqn{o_i \in \{0,1\}}
#' is the binary outcome. A perfect forecast scores 0; a random 50/50 forecast
#' scores 0.25.
#'
#' @param observed_binary Integer or numeric vector of binary outcomes (0 or 1).
#' @param forecast_prob Numeric vector of probabilities in the unit interval.
#'
#' @return Scalar numeric Brier score (range 0 to 1). Returns `NA_real_` if
#'   fewer than 2 complete pairs remain after removing NAs.
#'
#' @family scoring
#' @export
hd_brier_score <- function(observed_binary, forecast_prob) {
  complete <- !is.na(observed_binary) & !is.na(forecast_prob)
  obs  <- observed_binary[complete]
  prob <- forecast_prob[complete]
  if (length(obs) < 2L) return(NA_real_)
  mean((prob - obs)^2)
}


# ── 5. Horizon skill analysis ─────────────────────────────────────────────────

#' Forecast skill by horizon
#'
#' For each horizon \eqn{h} in `horizons`, computes the forward \eqn{h}-period
#' return and measures forecast accuracy (RMSE and correlation) of a signal
#' against those realised returns. Useful for identifying the useful forecast
#' range of a strategy signal before alpha decays.
#'
#' @param returns Numeric vector of period returns (e.g., daily), ordered
#'   chronologically. NAs are propagated.
#' @param signal Numeric vector of the same length as `returns`, representing
#'   the forecast signal at each time point.
#' @param horizons Integer vector of forecast horizons in periods.
#'   Defaults to `1:10`.
#' @param ann_factor Integer. Annualisation factor for normalising RMSE.
#'   Defaults to `252L` (trading days). Set to `12L` for monthly data.
#'
#' @return A [tibble][tibble::tibble] with columns:
#'   \describe{
#'     \item{horizon}{Forecast horizon (integer).}
#'     \item{rmse}{Root mean squared error of signal vs h-period forward return.}
#'     \item{correlation}{Pearson correlation of signal with h-period forward return.}
#'     \item{n_obs}{Number of complete observation pairs used.}
#'   }
#'
#' @family scoring
#' @export
hd_horizon_skill <- function(returns, signal,
                              horizons = 1:10,
                              ann_factor = 252L) {
  n <- length(returns)
  if (n < 2L || length(signal) != n) {
    return(tibble::tibble(
      horizon     = integer(0),
      rmse        = numeric(0),
      correlation = numeric(0),
      n_obs       = integer(0)
    ))
  }

  results <- lapply(horizons, function(h) {
    # Forward h-period cumulative return: product of (1 + r) over next h periods
    fwd <- vapply(seq_len(n - h), function(i) {
      window <- returns[(i + 1L):(i + h)]
      if (any(is.na(window))) NA_real_ else prod(1 + window) - 1
    }, numeric(1))

    sig_trimmed <- signal[seq_len(n - h)]
    complete    <- !is.na(fwd) & !is.na(sig_trimmed)
    f <- fwd[complete]
    s <- sig_trimmed[complete]
    n_obs <- length(f)

    if (n_obs < 5L) {
      return(list(horizon = h, rmse = NA_real_,
                  correlation = NA_real_, n_obs = n_obs))
    }

    rmse <- sqrt(mean((s - f)^2))
    cor_val <- if (stats::sd(s) < .Machine$double.eps ||
                   stats::sd(f) < .Machine$double.eps) {
      NA_real_
    } else {
      stats::cor(s, f, method = "pearson")
    }

    list(horizon = h, rmse = rmse, correlation = cor_val, n_obs = n_obs)
  })

  tibble::tibble(
    horizon     = vapply(results, `[[`, integer(1), "horizon"),
    rmse        = vapply(results, `[[`, numeric(1), "rmse"),
    correlation = vapply(results, `[[`, numeric(1), "correlation"),
    n_obs       = vapply(results, `[[`, integer(1), "n_obs")
  )
}
