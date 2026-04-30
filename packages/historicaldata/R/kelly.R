# Kelly criterion variants: Bayesian, rolling window, and bounded sizing
#
# Three exported helpers for enhanced Kelly position sizing beyond the
# standard fractional Kelly (f* = edge / variance × fraction).
#
# All functions return conservative estimates suitable for live use:
# - Bayesian: posterior mean via Beta-Binomial update
# - Rolling: time-varying f* clipped to [0, 1]
# - Bounded: survival-constrained f* preventing ruin from worst single return

# ── 1. Bayesian Kelly ──────────────────────────────────────────────────────────

#' Bayesian Kelly criterion via Beta-Binomial posterior
#'
#' Estimates the Kelly fraction using a Beta-Binomial conjugate model.
#' Each return is classified as a win (>0) or loss (<=0). The posterior
#' mean win probability is used in the classic discrete Kelly formula
#' f* = (p*b - q) / b, where b = mean(wins) / |mean(losses)|.
#'
#' @param returns Numeric vector of returns (e.g., monthly log-returns).
#'   NAs are silently dropped.
#' @param prior_a Positive scalar. Alpha parameter of the Beta prior
#'   (pseudo-wins). Default 1 = flat (uniform) prior.
#' @param prior_b Positive scalar. Beta parameter of the Beta prior
#'   (pseudo-losses). Default 1 = flat (uniform) prior.
#' @param fraction Scalar in (0, 1]. Fractional Kelly multiplier applied
#'   to f*. Default 1.0 retains the full Bayesian estimate; use 0.25 for
#'   quarter-Kelly.
#'
#' @return A named list with components:
#'   \describe{
#'     \item{f_star}{Kelly fraction after applying \code{fraction} multiplier.
#'       Clipped to [0, Inf) — negative values (negative edge) return 0.}
#'     \item{p_posterior}{Posterior mean win probability.}
#'     \item{a_posterior}{Final alpha parameter of posterior Beta distribution.}
#'     \item{b_posterior}{Final beta parameter of posterior Beta distribution.}
#'     \item{n_obs}{Number of non-NA returns used.}
#'   }
#'
#' @family kelly
#' @export
#'
#' @examples
#' set.seed(42)
#' ret <- rnorm(120, mean = 0.005, sd = 0.04)
#' hd_kelly_bayesian(ret)
hd_kelly_bayesian <- function(returns, prior_a = 1, prior_b = 1,
                               fraction = 1.0) {
  returns <- returns[!is.na(returns)]
  n_obs <- length(returns)
  if (n_obs < 2L) {
    return(list(f_star = 0, p_posterior = NA_real_,
                a_posterior = prior_a, b_posterior = prior_b,
                n_obs = n_obs))
  }

  wins   <- returns[returns > 0]
  losses <- returns[returns <= 0]
  n_wins   <- length(wins)
  n_losses <- length(losses)

  a_posterior <- prior_a + n_wins
  b_posterior <- prior_b + n_losses
  p_posterior <- a_posterior / (a_posterior + b_posterior)

  # Avoid division by zero when all returns are positive
  if (n_losses == 0L || mean(abs(losses)) < .Machine$double.eps) {
    f_star <- fraction   # edge is infinite — cap at fraction
  } else {
    b_ratio <- mean(wins) / mean(abs(losses))  # win/loss odds ratio
    q       <- 1 - p_posterior
    f_raw   <- (p_posterior * b_ratio - q) / b_ratio
    f_star  <- max(0, f_raw * fraction)
  }

  list(
    f_star      = f_star,
    p_posterior = p_posterior,
    a_posterior = a_posterior,
    b_posterior = b_posterior,
    n_obs       = n_obs
  )
}

# ── 2. Rolling Kelly ───────────────────────────────────────────────────────────

#' Rolling window Kelly criterion
#'
#' Computes a time-varying Kelly fraction using rolling mean and variance
#' estimates: f*_t = mu_t / sigma2_t. Useful for detecting regime changes
#' in the sizing signal over time.
#'
#' @param returns Numeric vector of returns. NAs are silently dropped before
#'   the rolling calculation.
#' @param window Positive integer. Width of the rolling window in periods.
#'   Default 252L (approximately one trading year of monthly data if
#'   the series is daily; adjust for your sampling frequency).
#' @param fraction Scalar in (0, 1]. Fractional Kelly multiplier. Default
#'   0.25 (quarter-Kelly).
#'
#' @return A [tibble::tibble()] with one row per period starting at
#'   \code{window + 1} and columns:
#'   \describe{
#'     \item{period}{Integer index of the return in the original vector,
#'       starting from \code{window + 1}.}
#'     \item{f_star}{Rolling Kelly fraction, clipped to \code{[0, 1]}.}
#'     \item{mu_rolling}{Rolling mean of returns in the window.}
#'     \item{sigma2_rolling}{Rolling variance of returns in the window.}
#'   }
#'
#' @family kelly
#' @export
#'
#' @examples
#' set.seed(42)
#' ret <- rnorm(300, mean = 0.005, sd = 0.04)
#' kv <- hd_kelly_rolling(ret, window = 60L, fraction = 0.25)
#' head(kv)
hd_kelly_rolling <- function(returns, window = 252L, fraction = 0.25) {
  returns <- returns[!is.na(returns)]
  n <- length(returns)
  window <- as.integer(window)

  if (n <= window) {
    return(tibble::tibble(
      period       = integer(0),
      f_star       = numeric(0),
      mu_rolling   = numeric(0),
      sigma2_rolling = numeric(0)
    ))
  }

  periods        <- seq.int(window + 1L, n)
  mu_rolling     <- vapply(periods, function(i) {
    mean(returns[(i - window):(i - 1L)])
  }, numeric(1))
  sigma2_rolling <- vapply(periods, function(i) {
    var(returns[(i - window):(i - 1L)])
  }, numeric(1))

  # Avoid division by near-zero variance
  safe_denom <- ifelse(sigma2_rolling < .Machine$double.eps, NA_real_, sigma2_rolling)
  f_raw      <- mu_rolling / safe_denom * fraction
  f_star     <- pmax(0, pmin(1, f_raw))

  tibble::tibble(
    period         = periods,
    f_star         = f_star,
    mu_rolling     = mu_rolling,
    sigma2_rolling = sigma2_rolling
  )
}

# ── 3. Bounded Kelly ───────────────────────────────────────────────────────────

#' Survival-constrained (bounded) Kelly criterion
#'
#' Enforces the hard survival constraint 1 + f * min(returns) > 0, which
#' prevents a single worst-case return from wiping out the portfolio. The
#' final f* is the minimum of the standard fractional Kelly estimate and
#' the maximum survivable fraction.
#'
#' @param returns Numeric vector of returns. NAs are silently dropped.
#' @param fraction Scalar in (0, 1]. Fractional Kelly multiplier applied
#'   to the standard estimate before taking the minimum with the survival
#'   bound. Default 0.25.
#'
#' @return A named list with components:
#'   \describe{
#'     \item{f_star}{Final Kelly fraction: \code{min(f_standard, f_bounded)}.}
#'     \item{f_standard}{Standard fractional Kelly estimate
#'       (mean / var × fraction), clipped to [0, Inf).}
#'     \item{f_bounded}{Maximum fraction satisfying the survival constraint.
#'       Computed as \code{(1 - epsilon) / abs(min_return)} where epsilon
#'       is a small safety margin.}
#'     \item{min_return}{Minimum observed return.}
#'     \item{binding}{Logical. TRUE if the survival constraint is tighter
#'       than the standard fractional Kelly estimate.}
#'   }
#'
#' @family kelly
#' @export
#'
#' @examples
#' set.seed(42)
#' ret <- rnorm(120, mean = 0.005, sd = 0.04)
#' hd_kelly_bounded(ret)
hd_kelly_bounded <- function(returns, fraction = 0.25) {
  returns <- returns[!is.na(returns)]
  if (length(returns) < 2L) {
    return(list(f_star = 0, f_standard = 0, f_bounded = Inf,
                min_return = NA_real_, binding = FALSE))
  }

  min_return <- min(returns)
  mu         <- mean(returns)
  vr         <- var(returns)

  # Standard fractional Kelly (non-negative)
  f_standard <- if (vr > .Machine$double.eps && mu > 0) {
    max(0, mu / vr * fraction)
  } else {
    0
  }

  # Survival constraint: f * |min_return| < 1 - epsilon
  epsilon <- 1e-6
  f_bounded <- if (min_return < 0) {
    (1 - epsilon) / abs(min_return)
  } else {
    Inf  # No negative returns: constraint is non-binding
  }

  f_star <- min(f_standard, f_bounded)

  list(
    f_star     = f_star,
    f_standard = f_standard,
    f_bounded  = f_bounded,
    min_return = min_return,
    binding    = f_bounded < f_standard
  )
}
