# Falsification framework: HAC inference + null-environment rejection rates
#
# Exports tools for testing whether a strategy's alpha survives under
# statistically rigorous null distributions.  All sigma parameters are
# ANNUAL; functions convert to daily via /sqrt(252) internally.
#
# Each null generator creates T_obs+1 values and discards the first
# observation to enforce t+1 execution.  The GARCH family adds 500 warmup
# observations.

# ── 1. HAC t-statistic ────────────────────────────────────────────────────────

#' Newey-West HAC t-statistic for mean(r) == 0
#'
#' Computes a heteroskedasticity- and autocorrelation-consistent t-statistic
#' for the hypothesis that the population mean return is zero, using the
#' Bartlett kernel with automatic bandwidth selection.
#'
#' @param r Numeric vector of returns.
#'
#' @return Named list with components:
#'   \describe{
#'     \item{t_stat}{HAC t-statistic (NA if \code{length(r) < 10}).}
#'     \item{se_hac}{HAC standard error.}
#'     \item{mean_r}{Sample mean of \code{r}.}
#'     \item{T}{Number of observations after removing NAs.}
#'     \item{lag_nw}{Newey-West bandwidth (number of lags).}
#'   }
#'
#' @family falsification
#' @export
hd_hac_tstat <- function(r) {
  r <- r[!is.na(r)]
  T <- length(r)

  na_result <- list(t_stat = NA_real_, se_hac = NA_real_,
                    mean_r = NA_real_, T = T, lag_nw = NA_integer_)
  if (T < 10L) return(na_result)

  lag_nw <- floor(4 * (T / 100)^(2 / 9))
  lag_nw <- max(lag_nw, 1L)

  mu <- mean(r)
  e  <- r - mu

  # Variance estimate (lag 0)
  gamma0 <- sum(e^2) / T

  # Bartlett-weighted autocovariances
  nw_sum <- 0
  for (j in seq_len(lag_nw)) {
    w_j    <- 1 - j / (lag_nw + 1)
    gamma_j <- sum(e[(j + 1):T] * e[1:(T - j)]) / T
    nw_sum  <- nw_sum + 2 * w_j * gamma_j
  }

  v_hac  <- (gamma0 + nw_sum) / T
  se_hac <- sqrt(max(v_hac, .Machine$double.eps))
  t_stat <- mu / se_hac

  list(t_stat = t_stat, se_hac = se_hac, mean_r = mu, T = T, lag_nw = lag_nw)
}


# ── 2. HAC Sharpe wrapper ─────────────────────────────────────────────────────

#' HAC-adjusted Sharpe ratio for a return series
#'
#' A convenience wrapper around \code{\link{hd_hac_tstat}} that also reports
#' the annualised mean, annualised volatility, and naive Sharpe ratio.
#'
#' @param r Numeric vector of returns.
#' @param ann_factor Integer. Annualisation factor (default 252 for daily).
#'
#' @return Named list with components \code{hac_tstat}, \code{annualised_mean},
#'   \code{annualised_vol}, \code{naive_sharpe}, \code{lag_nw}, \code{T}.
#'
#' @family falsification
#' @export
hd_hac_sharpe <- function(r, ann_factor = 252) {
  r   <- r[!is.na(r)]
  hac <- hd_hac_tstat(r)

  ann_mean <- mean(r) * ann_factor
  ann_vol  <- stats::sd(r) * sqrt(ann_factor)
  naive_sr <- if (ann_vol > 0) ann_mean / ann_vol else NA_real_

  list(
    hac_tstat       = hac$t_stat,
    annualised_mean = ann_mean,
    annualised_vol  = ann_vol,
    naive_sharpe    = naive_sr,
    lag_nw          = hac$lag_nw,
    T               = hac$T
  )
}


# ── 3. White-noise null ───────────────────────────────────────────────────────

#' Generate iid N(0, sigma_daily) null series
#'
#' Produces \code{M} independent, identically distributed Gaussian return
#' series of length \code{T_obs}, enforcing t+1 execution by generating
#' one extra observation and discarding the first.
#'
#' @param T_obs Integer. Target series length (post-discard).
#' @param M Integer. Number of null series to generate (default 100).
#' @param sigma_annual Numeric. Annualised volatility (default 0.20).
#' @param seed Integer. Random seed for reproducibility (default 42).
#'
#' @return List of \code{M} numeric vectors each of length \code{T_obs}.
#'
#' @family falsification
#' @export
hd_null_env_white_noise <- function(T_obs, M = 100, sigma_annual = 0.20, seed = 42L) {
  set.seed(seed)
  sigma_daily <- sigma_annual / sqrt(252)
  lapply(seq_len(M), function(i) {
    x <- stats::rnorm(T_obs + 1L, mean = 0, sd = sigma_daily)
    x[-1L]  # discard first observation (t+1 execution)
  })
}


# ── 4. Two-state Markov-switching volatility null ─────────────────────────────

#' Generate two-state Markov regime-switching null series
#'
#' Simulates returns under a two-state volatility regime model with no alpha.
#' Transitions follow a first-order Markov chain.
#'
#' @param T_obs Integer. Target series length (post-discard).
#' @param M Integer. Number of null series (default 100).
#' @param p_stay Numeric. Probability of remaining in the current regime
#'   (default 0.98).
#' @param sigma_low Numeric. Annualised volatility in the low-vol regime
#'   (default 0.10).
#' @param sigma_high Numeric. Annualised volatility in the high-vol regime
#'   (default 0.30).
#' @param seed Integer. Random seed (default 42).
#'
#' @return List of \code{M} numeric vectors each of length \code{T_obs}.
#'
#' @family falsification
#' @export
hd_null_env_regime_vol <- function(T_obs, M = 100, p_stay = 0.98,
                                    sigma_low = 0.10, sigma_high = 0.30,
                                    seed = 42L) {
  set.seed(seed)
  n_gen  <- T_obs + 1L
  sig_lo <- sigma_low  / sqrt(252)
  sig_hi <- sigma_high / sqrt(252)

  lapply(seq_len(M), function(i) {
    state  <- 1L  # start in low-vol regime
    r      <- numeric(n_gen)
    for (t in seq_len(n_gen)) {
      sigma_t <- if (state == 1L) sig_lo else sig_hi
      r[t]    <- stats::rnorm(1L, mean = 0, sd = sigma_t)
      # Transition
      state <- if (stats::runif(1) < p_stay) state else (3L - state)  # 1->2 or 2->1
    }
    r[-1L]
  })
}


# ── 5. MA(1) bid-ask bounce null ──────────────────────────────────────────────

#' Generate MA(1) bid-ask bounce null series
#'
#' Simulates the well-known bid-ask microstructure effect where observed
#' returns exhibit negative first-order autocorrelation.
#'
#' @param T_obs Integer. Target series length (post-discard).
#' @param M Integer. Number of null series (default 100).
#' @param theta Numeric. MA(1) parameter (default \code{-0.5}).
#' @param sigma_annual Numeric. Annualised innovation volatility (default 0.20).
#' @param seed Integer. Random seed (default 42).
#'
#' @return List of \code{M} numeric vectors each of length \code{T_obs}.
#'
#' @family falsification
#' @export
hd_null_env_ma1 <- function(T_obs, M = 100, theta = -0.5,
                              sigma_annual = 0.20, seed = 42L) {
  set.seed(seed)
  sigma_daily <- sigma_annual / sqrt(252)
  n_gen       <- T_obs + 1L

  lapply(seq_len(M), function(i) {
    eps <- stats::rnorm(n_gen + 1L, mean = 0, sd = sigma_daily)
    r   <- eps[-1L] + theta * eps[-(n_gen + 1L)]  # r_t = eps_t + theta*eps_{t-1}
    r[-1L]  # discard first (t+1 execution)
  })
}


# ── 6. Factor null environment (zero alpha) ───────────────────────────────────

#' Generate factor null series with zero alpha
#'
#' Simulates \code{r = beta * f + epsilon} where \code{f} is an iid Gaussian
#' factor and \code{epsilon} is idiosyncratic noise.  By construction, alpha
#' is zero.
#'
#' @param T_obs Integer. Target series length (post-discard).
#' @param M Integer. Number of null series (default 100).
#' @param beta Numeric. Factor loading (default 1.0).
#' @param sigma_f Numeric. Annualised factor volatility (default 0.20).
#' @param sigma_e Numeric. Annualised idiosyncratic volatility (default 0.10).
#' @param seed Integer. Random seed (default 42).
#'
#' @return List of \code{M} numeric vectors each of length \code{T_obs}.
#'
#' @family falsification
#' @export
hd_null_env_factor_null <- function(T_obs, M = 100, beta = 1.0,
                                     sigma_f = 0.20, sigma_e = 0.10,
                                     seed = 42L) {
  set.seed(seed)
  sf_d <- sigma_f / sqrt(252)
  se_d <- sigma_e / sqrt(252)
  n_gen <- T_obs + 1L

  lapply(seq_len(M), function(i) {
    f <- stats::rnorm(n_gen, mean = 0, sd = sf_d)
    e <- stats::rnorm(n_gen, mean = 0, sd = se_d)
    r <- beta * f + e
    r[-1L]
  })
}


# ── 7. GARCH(1,1) null ────────────────────────────────────────────────────────

#' Generate GARCH(1,1) null series with zero mean
#'
#' Simulates a GARCH(1,1) process with 500 warmup observations.  The
#' unconditional variance is determined by the GARCH parameters and
#' \code{sigma_annual}.  Alpha is zero by construction.
#'
#' @param T_obs Integer. Target series length (post-discard).
#' @param M Integer. Number of null series (default 100).
#' @param alpha_arch Numeric. ARCH parameter (default 0.10).
#' @param beta_garch Numeric. GARCH parameter (default 0.85).
#' @param sigma_annual Numeric. Annualised unconditional volatility (default 0.20).
#' @param seed Integer. Random seed (default 42).
#'
#' @return List of \code{M} numeric vectors each of length \code{T_obs}.
#'
#' @family falsification
#' @export
hd_null_env_garch11 <- function(T_obs, M = 100, alpha_arch = 0.10,
                                  beta_garch = 0.85, sigma_annual = 0.20,
                                  seed = 42L) {
  set.seed(seed)
  n_warmup <- 500L
  n_total  <- T_obs + 1L + n_warmup

  # omega from unconditional variance: var = omega / (1 - alpha - beta)
  var_unc <- (sigma_annual / sqrt(252))^2
  omega   <- var_unc * (1 - alpha_arch - beta_garch)
  if (omega <= 0) omega <- 1e-8

  lapply(seq_len(M), function(i) {
    h <- rep(var_unc, n_total)
    z <- stats::rnorm(n_total)
    r <- numeric(n_total)
    r[1] <- sqrt(h[1]) * z[1]
    for (t in 2:n_total) {
      h[t] <- omega + alpha_arch * r[t - 1]^2 + beta_garch * h[t - 1]
      r[t] <- sqrt(max(h[t], .Machine$double.eps)) * z[t]
    }
    # Discard warmup and first post-warmup observation (t+1 execution)
    r[(n_warmup + 2L):n_total]  # length = T_obs
  })
}


# ── 8. GJR-GARCH null ─────────────────────────────────────────────────────────

#' Generate GJR-GARCH null series with asymmetric leverage effect
#'
#' Extends GARCH(1,1) with a leverage effect: negative innovations increase
#' next-period conditional variance more than positive innovations of equal
#' magnitude.  Alpha is zero by construction.
#'
#' Variance equation:
#' \deqn{h_t = \omega + (\alpha + \gamma \cdot I(e_{t-1} < 0)) e_{t-1}^2 + \beta h_{t-1}}
#'
#' @param T_obs Integer. Target series length (post-discard).
#' @param M Integer. Number of null series (default 100).
#' @param alpha_arch Numeric. ARCH parameter (default 0.05).
#' @param beta_garch Numeric. GARCH parameter (default 0.85).
#' @param gamma_gjr Numeric. Leverage parameter (default 0.10).
#' @param sigma_annual Numeric. Annualised unconditional volatility (default 0.20).
#' @param seed Integer. Random seed (default 42).
#'
#' @return List of \code{M} numeric vectors each of length \code{T_obs}.
#'
#' @family falsification
#' @export
hd_null_env_gjr_garch <- function(T_obs, M = 100, alpha_arch = 0.05,
                                    beta_garch = 0.85, gamma_gjr = 0.10,
                                    sigma_annual = 0.20, seed = 42L) {
  set.seed(seed)
  n_warmup <- 500L
  n_total  <- T_obs + 1L + n_warmup

  # Unconditional variance: E[h] = omega / (1 - alpha - gamma/2 - beta)
  # (since E[I(e<0)] = 0.5 for symmetric z)
  eff_alpha <- alpha_arch + gamma_gjr / 2
  var_unc   <- (sigma_annual / sqrt(252))^2
  omega     <- var_unc * (1 - eff_alpha - beta_garch)
  if (omega <= 0) omega <- 1e-8

  lapply(seq_len(M), function(i) {
    h <- rep(var_unc, n_total)
    z <- stats::rnorm(n_total)
    r <- numeric(n_total)
    r[1] <- sqrt(h[1]) * z[1]
    for (t in 2:n_total) {
      lev   <- if (r[t - 1] < 0) gamma_gjr else 0
      h[t]  <- omega + (alpha_arch + lev) * r[t - 1]^2 + beta_garch * h[t - 1]
      r[t]  <- sqrt(max(h[t], .Machine$double.eps)) * z[t]
    }
    r[(n_warmup + 2L):n_total]
  })
}


# ── 9. Null rejection rate ────────────────────────────────────────────────────

#' Compute rejection rate of a strategy function under a null environment
#'
#' Applies \code{strategy_fn} to each series in \code{null_series} and
#' counts how often the returned t-statistic exceeds the critical value
#' implied by \code{alpha_level} under the standard normal.
#'
#' @param strategy_fn Function taking a numeric vector and returning a
#'   numeric t-statistic (or \code{NA}).
#' @param null_series List of numeric vectors (from any \code{hd_null_env_*}
#'   function).
#' @param alpha_level Numeric. One-sided significance level (default 0.05).
#'
#' @return Named list:
#'   \describe{
#'     \item{rejection_rate}{Fraction of null series that reject H0.}
#'     \item{n_valid}{Number of series with non-NA t-statistics.}
#'     \item{threshold_binomial}{Exact binomial 95th-percentile threshold for
#'       the number of rejections under H0 (used to flag inflated Type I error).}
#'     \item{passes}{Logical: is the rejection rate <= \code{alpha_level * 1.5}?}
#'     \item{t_stats}{Numeric vector of all t-statistics.}
#'   }
#'
#' @family falsification
#' @export
hd_null_rejection_rate <- function(strategy_fn, null_series, alpha_level = 0.05) {
  t_stats <- vapply(null_series, function(r) {
    tryCatch(strategy_fn(r), error = function(e) NA_real_)
  }, numeric(1L))

  crit    <- stats::qnorm(1 - alpha_level)
  valid   <- t_stats[!is.na(t_stats)]
  n_valid <- length(valid)

  if (n_valid == 0L) {
    return(list(rejection_rate = NA_real_, n_valid = 0L,
                threshold_binomial = NA_integer_, passes = NA,
                t_stats = t_stats))
  }

  n_reject   <- sum(valid > crit)
  rej_rate   <- n_reject / n_valid
  # Binomial 95th percentile: how many rejections to expect at most by chance
  threshold  <- stats::qbinom(0.95, n_valid, alpha_level)

  list(
    rejection_rate     = rej_rate,
    n_valid            = n_valid,
    threshold_binomial = threshold,
    passes             = rej_rate <= alpha_level * 1.5,
    t_stats            = t_stats
  )
}


# ── 10. Effective number of independent tests ─────────────────────────────────

#' Effective number of independent strategies (K_eff)
#'
#' Estimates the effective number of independent tests from a correlation
#' matrix of strategy returns using the eigenvalue-based formula:
#' \deqn{K_{\text{eff}} = K^2 / \|\Sigma\|_F^2}
#' where \eqn{\|\Sigma\|_F^2} is the squared Frobenius norm of the
#' correlation matrix.
#'
#' @param returns_mat Numeric matrix where columns are strategy return series
#'   (rows are time periods).
#'
#' @return Named list:
#'   \describe{
#'     \item{K_eff}{Effective number of independent strategies.}
#'     \item{K}{Total number of strategies (columns).}
#'     \item{frobenius_norm_sq}{Squared Frobenius norm of the correlation
#'       matrix.}
#'   }
#'
#' @family falsification
#' @export
hd_keff <- function(returns_mat) {
  if (!is.matrix(returns_mat)) returns_mat <- as.matrix(returns_mat)
  K     <- ncol(returns_mat)
  sigma <- stats::cor(returns_mat, use = "pairwise.complete.obs")
  # Replace NA correlations with 0 (unknown = assume independent)
  sigma[is.na(sigma)] <- 0
  diag(sigma) <- 1  # ensure diagonal is 1
  frob2 <- sum(sigma^2)
  K_eff <- K^2 / frob2

  list(K_eff = K_eff, K = K, frobenius_norm_sq = frob2)
}


# ── 11. Delta-Z over-fitting test ─────────────────────────────────────────────

#' Test for in-sample over-fitting via ΔZ
#'
#' Computes ΔZ = max(z_IS) - max(z_OOS) and compares it against the null
#' distribution of the same quantity when there is no true alpha.  A large
#' positive ΔZ suggests the in-sample best strategy was selected by luck.
#'
#' @param z_is Numeric vector of in-sample HAC t-statistics across strategies.
#' @param z_oos Numeric vector of out-of-sample HAC t-statistics (same order
#'   as \code{z_is}).
#' @param K_eff Numeric. Effective number of independent strategies from
#'   \code{\link{hd_keff}}.
#' @param n_sim Integer. Number of simulations for the null distribution
#'   (default 5000).
#' @param seed Integer. Random seed (default 42).
#'
#' @return Named list:
#'   \describe{
#'     \item{delta_z}{Observed ΔZ = max(z_IS) - max(z_OOS).}
#'     \item{z_star_is}{max(z_IS).}
#'     \item{z_star_oos}{max(z_OOS).}
#'     \item{threshold_99}{99th-percentile of simulated ΔZ under H0.}
#'     \item{is_overfit}{Logical: is delta_z > threshold_99?}
#'   }
#'
#' @family falsification
#' @export
hd_delta_z <- function(z_is, z_oos, K_eff, n_sim = 5000L, seed = 42L) {
  set.seed(seed)
  K_int   <- max(1L, round(K_eff))
  z_star_is  <- max(z_is,  na.rm = TRUE)
  z_star_oos <- max(z_oos, na.rm = TRUE)
  delta_z    <- z_star_is - z_star_oos

  # Null: simulate max(z_IS) - max(z_OOS) when both are iid standard normal
  null_deltas <- replicate(n_sim, {
    sim_is  <- max(stats::rnorm(K_int))
    sim_oos <- max(stats::rnorm(K_int))
    sim_is - sim_oos
  })

  threshold_99 <- stats::quantile(null_deltas, 0.99)

  list(
    delta_z      = delta_z,
    z_star_is    = z_star_is,
    z_star_oos   = z_star_oos,
    threshold_99 = as.numeric(threshold_99),
    is_overfit   = delta_z > threshold_99
  )
}


# ── 12. Factor null regression (FF alpha) ────────────────────────────────────

#' OLS factor regression with HAC t-statistic on alpha
#'
#' Regresses excess strategy returns on Fama-French factors and estimates
#' alpha with a Newey-West HAC standard error.
#'
#' @param strategy_daily Data frame with columns \code{date} and
#'   \code{strategy_ret}.
#' @param rf_daily Data frame with columns \code{date} and \code{rf}
#'   (risk-free rate, same frequency as \code{strategy_daily}).
#' @param factors_daily Data frame with columns \code{date},
#'   \code{factor_name}, \code{value} (already in decimal form).
#'
#' @return A \code{\link[tibble]{tibble}} with one row containing:
#'   \code{alpha_annual}, \code{alpha_tstat_hac}, \code{r_squared}, and
#'   one column per factor named \code{beta_<factor>}.
#'
#' @family falsification
#' @export
hd_factor_null_test <- function(strategy_daily, rf_daily, factors_daily) {
  # Pivot factors wide
  factors_wide <- tidyr::pivot_wider(
    factors_daily,
    id_cols    = "date",
    names_from  = "factor_name",
    values_from = "value"
  )

  # Join strategy, rf, factors
  d <- dplyr::inner_join(strategy_daily, rf_daily, by = "date") |>
    dplyr::inner_join(factors_wide, by = "date") |>
    dplyr::filter(!is.na(strategy_ret), !is.na(rf))

  factor_names <- setdiff(names(d), c("date", "strategy_ret", "rf"))
  # Sanitise column names: Mkt-RF -> Mkt_RF (hyphens break R formulas)
  clean_names <- gsub("-", "_", factor_names)
  names(d)[match(factor_names, names(d))] <- clean_names
  factor_names <- clean_names
  d[["excess_ret"]] <- d[["strategy_ret"]] - d[["rf"]]

  # Build and fit OLS model
  fmla_str <- paste("excess_ret ~", paste(factor_names, collapse = " + "))
  fit      <- stats::lm(stats::as.formula(fmla_str), data = d)
  resid_v  <- stats::residuals(fit)
  alpha_ols <- stats::coef(fit)[["(Intercept)"]]

  # HAC t-stat on alpha: treat intercept residuals = residuals + alpha,
  # then test mean of that series == 0 (equivalent to H0: alpha == 0)
  alpha_series <- resid_v + alpha_ols
  hac          <- hd_hac_tstat(alpha_series)

  alpha_annual <- alpha_ols * 252
  r_squared    <- summary(fit)$r.squared

  betas <- stats::coef(fit)[factor_names]
  names(betas) <- paste0("beta_", factor_names)

  out <- tibble::tibble(
    alpha_annual      = alpha_annual,
    alpha_tstat_hac   = hac$t_stat,
    r_squared         = r_squared
  )
  for (nm in names(betas)) out[[nm]] <- betas[[nm]]
  out
}
