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


# ── 8b. Merton jump-diffusion null ────────────────────────────────────────────

#' Generate Merton jump-diffusion null series
#'
#' Simulates returns under a jump-diffusion model: continuous GBM + compound
#' Poisson jumps.  No alpha — the drift is zero.
#'
#' @param T_obs Integer. Target series length (post-discard).
#' @param M Integer. Number of null series (default 100).
#' @param lambda_annual Numeric. Expected number of jumps per year (default 5).
#' @param mu_jump Numeric. Mean log jump size (default 0).
#' @param sigma_jump_annual Numeric. Annualised jump size volatility
#'   (default 0.10).
#' @param sigma_annual Numeric. Annualised diffusion volatility (default 0.20).
#' @param seed Integer. Random seed (default 42).
#'
#' @return List of \code{M} numeric vectors each of length \code{T_obs}.
#'
#' @family falsification
#' @export
hd_null_env_jump_diffusion <- function(T_obs, M = 100, lambda_annual = 5,
                                         mu_jump = 0, sigma_jump_annual = 0.10,
                                         sigma_annual = 0.20, seed = 42L) {
  set.seed(seed)
  sigma_daily <- sigma_annual / sqrt(252)
  sigma_j     <- sigma_jump_annual / sqrt(252)
  lambda_daily <- lambda_annual / 252

  lapply(seq_len(M), function(i) {
    # Diffusion component
    diffusion <- stats::rnorm(T_obs + 1L, mean = 0, sd = sigma_daily)
    # Jump component: number of jumps per day ~ Poisson
    n_jumps <- stats::rpois(T_obs + 1L, lambda = lambda_daily)
    # Jump sizes: sum of n_jumps Gaussian jumps per day
    jumps <- vapply(n_jumps, function(nj) {
      if (nj == 0L) 0 else sum(stats::rnorm(nj, mean = mu_jump, sd = sigma_j))
    }, double(1L))
    r <- diffusion + jumps
    r[-1L]  # discard first observation (t+1 execution)
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

#' Effective number of independent strategies (K_eff_frob)
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
#'     \item{K_eff_frob}{Effective number of independent strategies.}
#'     \item{K}{Total number of strategies (columns).}
#'     \item{frobenius_norm_sq}{Squared Frobenius norm of the correlation
#'       matrix.}
#'   }
#'
#' @family falsification
#' @export
hd_keff_frob <- function(returns_mat) {
  if (!is.matrix(returns_mat)) returns_mat <- as.matrix(returns_mat)
  K     <- ncol(returns_mat)
  sigma <- stats::cor(returns_mat, use = "pairwise.complete.obs")
  # Replace NA correlations with 0 (unknown = assume independent)
  sigma[is.na(sigma)] <- 0
  diag(sigma) <- 1  # ensure diagonal is 1
  frob2 <- sum(sigma^2)
  K_eff_frob <- K^2 / frob2

  list(K_eff_frob = K_eff_frob, K = K, frobenius_norm_sq = frob2)
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
#' @param k_eff_count Numeric. Effective number of independent strategies from
#'   any K_eff method, e.g. \code{\link{hd_keff_frob}} (Frobenius-norm) or
#'   \code{\link{hd_strat_keff_vertox}} (Vertox correlation-aware count).
#'   Bare `K_eff` is reserved — always pass a method-suffixed value.
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
hd_delta_z <- function(z_is, z_oos, k_eff_count, n_sim = 5000L, seed = 42L) {
  set.seed(seed)
  K_int   <- max(1L, round(k_eff_count))
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


# ── 11b. Tail-weighted regime-conditional K_eff_frob ───────────────────────────────

#' Tail-weighted regime-conditional independence test
#'
#' Partitions the returns matrix into \emph{crisis} and \emph{calm} regimes
#' and computes K_eff_frob separately for each.  A strategy portfolio that claims
#' diversification must show that K_eff_frob does not collapse in the crisis regime
#' (i.e., strategies remain independent precisely when it matters most).
#'
#' The crisis subset is defined as any row where at least one strategy's return
#' falls below its empirical \code{q}-quantile.  The calm subset is the
#' complement.
#'
#' @param returns_mat Numeric matrix where columns are strategy return series
#'   and rows are time periods.  Must have complete cases (no NA rows).
#' @param q Numeric scalar in (0, 1).  Quantile threshold defining the
#'   lower tail (default 0.05 = bottom 5\%).
#'
#' @return Named list with components:
#'   \describe{
#'     \item{K_eff_frob_crisis}{Effective number of independent strategies in the
#'       crisis regime (lower = more correlated = less diversification).}
#'     \item{K_eff_frob_calm}{Effective number of independent strategies in the
#'       calm regime.}
#'     \item{n_crisis_days}{Number of crisis-regime observations.}
#'     \item{n_calm_days}{Number of calm-regime observations.}
#'     \item{correlation_crisis}{Correlation matrix estimated from crisis days.}
#'     \item{correlation_calm}{Correlation matrix estimated from calm days.}
#'   }
#'
#' @family falsification
#' @export
hd_tail_keff_frob <- function(returns_mat, q = 0.05) {
  if (!is.matrix(returns_mat)) returns_mat <- as.matrix(returns_mat)
  returns_mat <- returns_mat[stats::complete.cases(returns_mat), , drop = FALSE]

  K <- ncol(returns_mat)
  n <- nrow(returns_mat)

  # Compute per-column q-quantile thresholds
  thresholds <- apply(returns_mat, 2, stats::quantile, probs = q, na.rm = TRUE)

  # Crisis day: any strategy return falls below its q-quantile
  in_crisis <- apply(
    sweep(returns_mat, 2, thresholds, FUN = "<"),
    1,
    any
  )

  crisis_mat <- returns_mat[in_crisis,  , drop = FALSE]
  calm_mat   <- returns_mat[!in_crisis, , drop = FALSE]

  compute_keff <- function(mat) {
    if (nrow(mat) < (K + 1L)) return(NA_real_)
    sigma <- stats::cor(mat, use = "pairwise.complete.obs")
    sigma[is.na(sigma)] <- 0
    diag(sigma) <- 1
    K^2 / sum(sigma^2)
  }

  cor_mat <- function(mat) {
    if (nrow(mat) < (K + 1L)) {
      m <- matrix(NA_real_, nrow = K, ncol = K)
      dimnames(m) <- list(colnames(returns_mat), colnames(returns_mat))
      return(m)
    }
    sigma <- stats::cor(mat, use = "pairwise.complete.obs")
    sigma[is.na(sigma)] <- 0
    diag(sigma) <- 1
    sigma
  }

  list(
    K_eff_frob_crisis       = compute_keff(crisis_mat),
    K_eff_frob_calm         = compute_keff(calm_mat),
    n_crisis_days      = nrow(crisis_mat),
    n_calm_days        = nrow(calm_mat),
    correlation_crisis = cor_mat(crisis_mat),
    correlation_calm   = cor_mat(calm_mat)
  )
}


# ── 11c. Empirical lower tail dependence ────────────────────────────────────

#' Empirical lower tail dependence coefficient
#'
#' Estimates the lower tail dependence coefficient (lambda_L) for a pair of
#' return series: the conditional probability that Y falls below its
#' \code{q}-quantile given that X falls below its \code{q}-quantile.
#'
#' Under independence, lambda_L converges to \code{q} as the sample grows.
#' Values substantially above \code{q} indicate tail co-movement —
#' strategies tend to lose simultaneously in the worst periods.
#'
#' @param x Numeric vector of returns for the first strategy.
#' @param y Numeric vector of returns for the second strategy.
#' @param q Numeric scalar in (0, 1).  Quantile threshold for the lower tail
#'   (default 0.05 = bottom 5\%).
#'
#' @return Named list with components:
#'   \describe{
#'     \item{lambda_L}{Empirical lower tail dependence coefficient,
#'       \eqn{P(Y < Q_Y(q) \mid X < Q_X(q))}.  Under independence this
#'       equals \code{q}.}
#'     \item{q}{The quantile threshold used.}
#'     \item{n_pairs}{Number of joint tail observations
#'       (days where both X and Y are below their respective quantiles).}
#'   }
#'
#' @family falsification
#' @export
hd_tail_dependence <- function(x, y, q = 0.05) {
  keep <- !is.na(x) & !is.na(y)
  x <- x[keep]
  y <- y[keep]

  qx <- stats::quantile(x, probs = q)
  qy <- stats::quantile(y, probs = q)

  in_x_tail <- x < qx
  n_x_tail  <- sum(in_x_tail)

  if (n_x_tail == 0L) {
    return(list(lambda_L = NA_real_, q = q, n_pairs = 0L))
  }

  n_joint <- sum(in_x_tail & (y < qy))

  list(
    lambda_L = n_joint / n_x_tail,
    q        = q,
    n_pairs  = n_joint
  )
}


# ── 11d. Pairwise drawdown overlap ──────────────────────────────────────────

#' Pairwise drawdown overlap matrix
#'
#' For each strategy in \code{returns_mat}, identifies drawdown periods —
#' contiguous stretches where the cumulative return is below the running
#' maximum (underwater).  For each pair of strategies, computes the fraction
#' of days that are simultaneously in a drawdown.
#'
#' A high overlap fraction indicates that strategies tend to be underwater at
#' the same time, reducing the practical diversification benefit.
#'
#' @param returns_mat Numeric matrix where columns are strategy return series
#'   and rows are time periods.  Rows with any NA are removed before
#'   computing cumulative returns.
#'
#' @return Symmetric numeric matrix of dimension \code{K × K} (where K is the
#'   number of strategies / columns).  Element \code{[i, j]} is the fraction
#'   of days that both strategy \code{i} and strategy \code{j} are
#'   simultaneously in a drawdown.  The diagonal is the fraction of days each
#'   strategy is in its own drawdown.
#'
#' @family falsification
#' @export
hd_drawdown_overlap <- function(returns_mat) {
  if (!is.matrix(returns_mat)) returns_mat <- as.matrix(returns_mat)
  returns_mat <- returns_mat[stats::complete.cases(returns_mat), , drop = FALSE]

  K   <- ncol(returns_mat)
  nms <- colnames(returns_mat)
  n   <- nrow(returns_mat)

  # Identify drawdown days (cumulative return below running max)
  is_drawdown <- function(r) {
    cum_r   <- cumprod(1 + r) - 1          # cumulative return (approximate)
    run_max <- cummax(cum_r)
    cum_r < run_max                        # TRUE on every underwater day
  }

  dd_flags <- apply(returns_mat, 2, is_drawdown)  # n × K logical matrix

  # Pairwise overlap fractions
  overlap <- matrix(NA_real_, nrow = K, ncol = K,
                    dimnames = list(nms, nms))

  for (i in seq_len(K)) {
    for (j in seq_len(K)) {
      overlap[i, j] <- sum(dd_flags[, i] & dd_flags[, j]) / n
    }
  }

  overlap
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


# ── 13. Deflated Sharpe Ratio (DSR) ─────────────────────────────────────────

#' Deflated Sharpe Ratio
#'
#' Adjusts the Sharpe ratio for non-normality (skewness, kurtosis) and
#' multiple testing (number of strategies tried).  Based on Lopez de Prado
#' (2018), "The Deflated Sharpe Ratio".
#'
#' The DSR tests H0: true Sharpe <= 0, accounting for the fact that:
#' (1) returns are non-normal (fat tails inflate naive Sharpe), and
#' (2) the best of K strategies has an inflated expected Sharpe
#' even under pure noise (the "haircut").
#'
#' @param r Numeric vector of returns (daily or monthly).
#' @param K_trials Integer. Number of strategies tested (default 1 = no
#'   multiple-testing adjustment).
#' @param ann_factor Integer. Annualisation factor (252 for daily, 12 for
#'   monthly). Default 252.
#'
#' @return Named list:
#'   \describe{
#'     \item{dsr}{Deflated Sharpe Ratio (annualised).}
#'     \item{dsr_pvalue}{p-value for H0: true Sharpe <= 0.}
#'     \item{naive_sharpe}{Uncorrected annualised Sharpe.}
#'     \item{haircut_pct}{Percentage reduction from naive to deflated.}
#'     \item{skewness}{Sample skewness of returns.}
#'     \item{kurtosis}{Sample excess kurtosis of returns.}
#'     \item{K_trials}{Number of strategies tested.}
#'     \item{T}{Number of observations.}
#'   }
#'
#' @references
#' Lopez de Prado, M. (2018). "The Deflated Sharpe Ratio: Correcting for
#' Selection Bias, Backtest Overfitting, and Non-Normality."
#' \emph{Journal of Portfolio Management}, 40(5), 94-107.
#'
#' @family falsification
#' @export
hd_deflated_sharpe <- function(r, K_trials = 1L, ann_factor = 252L) {
  r <- r[!is.na(r)]
  T_obs <- length(r)
  if (T_obs < 10L) {
    return(list(dsr = NA_real_, dsr_pvalue = NA_real_,
                naive_sharpe = NA_real_, haircut_pct = NA_real_,
                skewness = NA_real_, kurtosis = NA_real_,
                K_trials = K_trials, T = T_obs))
  }

  mu    <- mean(r)
  sigma <- stats::sd(r)
  sr    <- if (sigma > 0) mu / sigma else 0

  # Annualised naive Sharpe
  naive_sr <- sr * sqrt(ann_factor)

  # Sample moments
  n   <- T_obs
  m3  <- sum((r - mu)^3) / n / sigma^3  # skewness
  m4  <- sum((r - mu)^4) / n / sigma^4  # kurtosis (not excess)
  ek  <- m4 - 3  # excess kurtosis

  # Variance of the Sharpe ratio estimator (Lo, 2002):
  # Var(SR) ≈ (1 - m3*SR + (m4-1)/4 * SR^2) / T
  var_sr <- (1 - m3 * sr + (m4 - 1) / 4 * sr^2) / T_obs

  # Expected maximum Sharpe under K independent trials (Euler-Mascheroni):
  # E[max(SR)] ≈ sqrt(2*log(K)) - (gamma + log(pi/2)) / (2*sqrt(2*log(K)))
  # For K=1: E[max] = 0
  if (K_trials > 1L) {
    z <- sqrt(2 * log(K_trials))
    euler_mascheroni <- 0.5772156649
    e_max_sr <- z - (euler_mascheroni + log(pi / 2)) / (2 * z)
    # Scale to per-period SR (not annualised)
    e_max_sr <- e_max_sr / sqrt(T_obs)
  } else {
    e_max_sr <- 0
  }

  # Deflated SR: test H0: SR <= E[max(SR)]
  # DSR = (SR - E[max]) / sqrt(Var(SR))
  se_sr <- sqrt(max(var_sr, .Machine$double.eps))
  dsr_stat <- (sr - e_max_sr) / se_sr

  # p-value (one-sided)
  dsr_pvalue <- 1 - stats::pnorm(dsr_stat)

  # Annualised DSR
  dsr_ann <- dsr_stat * sqrt(ann_factor / T_obs)

  # Haircut
  haircut <- if (abs(naive_sr) > 0.001) {
    (1 - dsr_ann / naive_sr) * 100
  } else NA_real_

  list(
    dsr           = dsr_ann,
    dsr_pvalue    = dsr_pvalue,
    naive_sharpe  = naive_sr,
    haircut_pct   = haircut,
    skewness      = m3,
    kurtosis      = ek,
    K_trials      = K_trials,
    T             = T_obs
  )
}
