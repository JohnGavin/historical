# Zero-alpha calibration surface for composite-book Sharpe inflation (#839)
#
# Source: Jonathan Kinlay, "A Sharpe of 2.1 From Nothing: The Second Number
# Your Agent Doesn't Log" (Sept 2 2026). Running a research agent against a
# zero-alpha (no true signal, by construction) synthetic panel, the
# reported in-sample Sharpe is explained to 88% by two integers: N (trials
# run -- the classic multiple-testing count `hd_strat_keff_vertox()` /
# `hd_deflated_sharpe()` already target) and k (correlated legs blended
# into the reported book). Blending inflates Sharpe via variance reduction
# on correlated legs -- mean stays near its selected-high value while
# variance shrinks by roughly sqrt(k / (1 + (k-1)*rho_bar)) -- and this
# aggregation axis is not captured by trial-count-based corrections at all.
#
# This file implements a minimal, real, tested version of that mechanism
# (selection + leg-blending inflates reported Sharpe) against a synthetic
# zero-alpha panel. It does NOT calibrate against the real strategy
# grammar/universe or fit rho_bar from data -- both are explicitly out of
# scope for this slice (see the PR body for #839).

#' Generate a cross-sectionally correlated zero-alpha candidate panel
#'
#' Internal generator supporting `hd_zero_alpha_calibration()`. Modelled on
#' the single-factor construction in `hd_null_env_factor_null()`
#' (`R/falsification.R`) -- same `sigma_annual / sqrt(252)` daily
#' conversion, same t+1-discard convention (generate `T_obs + 1`
#' observations, drop the first) -- but differs in the one respect a
#' leg-blending demonstration needs: `hd_null_env_factor_null()` draws a
#' fresh, independent factor realisation *per candidate* (by design -- it
#' targets single-signal-vs-market-factor significance testing, not
#' cross-sectional leg correlation), so its `M` output series are mutually
#' independent. This generator instead draws ONE common factor and shares
#' it across all `M` candidates, giving each pair of candidates a
#' population pairwise correlation of `rho_bar` while preserving each
#' candidate's own marginal variance (`rho_bar * sigma^2 + (1 - rho_bar) *
#' sigma^2 == sigma^2`, for any `rho_bar`).
#'
#' `rho_bar` is a SUPPLIED construction parameter here, not fitted from
#' data -- correlation-structure estimation against the real strategy
#' grammar is out of scope for this function (#839).
#'
#' @param T_obs Integer. Target series length (post-discard).
#' @param M Integer. Number of candidates to generate.
#' @param rho_bar Numeric in `[0, 1)`. Target pairwise correlation between
#'   any two candidates.
#' @param sigma_annual Numeric. Annualised volatility of each candidate.
#' @param seed Integer. Random seed.
#' @return List of `M` numeric vectors, each of length `T_obs`.
#' @noRd
.hd_null_panel_correlated <- function(T_obs, M, rho_bar = 0,
                                      sigma_annual = 0.20, seed = 42L) {
  set.seed(seed)
  sigma_daily <- sigma_annual / sqrt(252)
  n_gen <- T_obs + 1L

  f <- stats::rnorm(n_gen, mean = 0, sd = sigma_daily)
  lapply(seq_len(M), function(i) {
    e <- stats::rnorm(n_gen, mean = 0, sd = sigma_daily)
    r <- sqrt(rho_bar) * f + sqrt(1 - rho_bar) * e
    r[-1L]
  })
}

#' Naive (non-HAC) annualised Sharpe of a single return series
#'
#' @param x Numeric vector of returns.
#' @param ann_factor Annualisation factor.
#' @return Numeric scalar Sharpe, or `NA_real_` if `sd(x)` is zero or
#'   non-finite.
#' @noRd
.hd_series_sharpe <- function(x, ann_factor) {
  sd_x <- stats::sd(x)
  if (!is.finite(sd_x) || sd_x <= 0) {
    return(NA_real_)
  }
  mean(x) / sd_x * sqrt(ann_factor)
}

#' Zero-alpha calibration surface for composite-book Sharpe inflation
#'
#' Estimates how much of a reported in-sample Sharpe ratio is
#' *manufactured* by the combination of (a) selecting the best-looking
#' result out of many zero-alpha trials (multiple testing -- the axis
#' `hd_strat_keff_vertox()` / `hd_deflated_sharpe()` already correct for)
#' and (b) equal-weight blending several selected results into one
#' reported "book" (variance reduction on correlated legs -- an axis
#' neither of those functions targets). See the file header (`R/zero_
#' alpha_calibration.R`) for the motivating citation and #839.
#'
#' At each `(n_trials, n_legs)` grid point, this function repeatedly: (1)
#' draws `n_trials` zero-alpha (no true signal, by construction) candidate
#' return series from `.hd_null_panel_correlated()` with target pairwise
#' correlation `rho_bar`; (2) ranks them by in-sample Sharpe and keeps the
#' top `n_legs`; (3) equal-weights the selected legs into one book; (4)
#' computes the book's in-sample Sharpe. The result is the *distribution*,
#' across `n_reps` repetitions, of the Sharpe ratio a genuinely-zero-alpha
#' pipeline would report at that operating point.
#'
#' @section Manufactured-Sharpe estimate, NOT an out-of-sample forecast:
#' The Sharpe values this function returns describe how much apparent edge
#' the trial-count + leg-blending mechanism *manufactures on its own*, on
#' data with no true signal. They are a haircut estimate for a reported
#' in-sample Sharpe -- NOT a prediction of what any real strategy will earn
#' going forward, and regime effects or genuine structural change can
#' dominate this correction in either direction (the article's own
#' section 5 finding). In particular:
#' \itemize{
#'   \item Do NOT use a shrinking gap between a reported Sharpe and its
#'     calibrated-null Sharpe as grounds to revise or abandon a strategy --
#'     see `.claude/rules/resulting-prohibition.md` (judge process, not
#'     outcome).
#'   \item Do NOT treat multi-year underperformance following a strategy's
#'     launch as evidence this calibration was "wrong" -- see
#'     `.claude/rules/underperformance-prior.md` (historically normal
#'     drawdown durations are long, sometimes decades).
#' }
#' This function calibrates a search/aggregation artefact. It is not a
#' return forecast, and it must never be used as one.
#'
#' @param grid A data frame with integer columns `n_trials` and `n_legs`.
#'   `n_legs` must satisfy `1 <= n_legs <= n_trials` in every row (aborts
#'   otherwise, naming the offending row indices).
#' @param T_obs Integer. Length of each candidate return series. Default
#'   `60L` (5 years of monthly data).
#' @param n_reps Integer. Monte Carlo repetitions per grid point. Default
#'   `200L`.
#' @param rho_bar Numeric in `[0, 1)`. Target pairwise correlation among
#'   the `n_trials` candidates within a repetition -- see
#'   `.hd_null_panel_correlated()`. Default `0` (independent candidates).
#'   This is a SUPPLIED parameter, not fitted from data; correlation-
#'   structure estimation against the real strategy grammar is explicitly
#'   out of scope for this function (#839).
#' @param sigma_annual Numeric. Annualised volatility of each candidate.
#'   Default `0.20`.
#' @param ann_factor Integer. Annualisation factor for the Sharpe
#'   computation (e.g. `12` for monthly, `252` for daily). Default `12`.
#' @param seed Integer. Base random seed; every grid point / repetition
#'   uses a deterministic seed derived from this, so the whole surface is
#'   reproducible. Default `42L`.
#'
#' @return A tibble, one row per grid point, with columns `n_trials`,
#'   `n_legs`, `rho_bar`, `n_reps`, `mean_sharpe`, `median_sharpe`,
#'   `sd_sharpe`, `q05_sharpe`, `q95_sharpe` -- the manufactured-Sharpe
#'   distribution's summary statistics at that operating point, computed
#'   entirely on data with zero true alpha by construction.
#'
#' @seealso [hd_detection_power()] for the sibling first-class-metric
#'   precedent (#726); [hd_strat_keff_vertox()] and [hd_deflated_sharpe()]
#'   for the trial-count multiple-testing correction this function
#'   complements (it targets the leg-blending axis, which those do not).
#' @family falsification
#' @export
hd_zero_alpha_calibration <- function(grid,
                                      T_obs = 60L,
                                      n_reps = 200L,
                                      rho_bar = 0,
                                      sigma_annual = 0.20,
                                      ann_factor = 12,
                                      seed = 42L) {
  if (!is.data.frame(grid) || !all(c("n_trials", "n_legs") %in% names(grid))) {
    cli::cli_abort(c(
      "x" = "{.arg grid} must be a data frame with columns {.field n_trials} and {.field n_legs}.",
      "i" = "Got columns: {.val {names(grid)}}."
    ))
  }
  if (nrow(grid) == 0L) {
    cli::cli_abort("{.arg grid} must have at least one row.")
  }
  if (rho_bar < 0 || rho_bar >= 1) {
    cli::cli_abort("{.arg rho_bar} must be in [0, 1); got {rho_bar}.")
  }

  bad <- which(grid$n_legs < 1L | grid$n_trials < 1L | grid$n_legs > grid$n_trials)
  if (length(bad) > 0L) {
    cli::cli_abort(c(
      "x" = "{.arg grid} has {length(bad)} row(s) that violate 1 <= n_legs <= n_trials: {bad}.",
      "i" = "n_trials: {.val {grid$n_trials[bad]}}; n_legs: {.val {grid$n_legs[bad]}}."
    ))
  }

  rows <- vector("list", nrow(grid))
  for (i in seq_len(nrow(grid))) {
    n_trials <- as.integer(grid$n_trials[i])
    n_legs   <- as.integer(grid$n_legs[i])

    rep_sharpes <- vapply(seq_len(n_reps), function(r) {
      rep_seed <- seed + i * 100000L + r
      candidates <- .hd_null_panel_correlated(
        T_obs, M = n_trials, rho_bar = rho_bar,
        sigma_annual = sigma_annual, seed = rep_seed
      )
      cand_sharpes <- vapply(
        candidates, .hd_series_sharpe, numeric(1), ann_factor = ann_factor
      )
      top_idx <- order(cand_sharpes, decreasing = TRUE)[seq_len(n_legs)]
      book <- Reduce(`+`, candidates[top_idx]) / n_legs
      .hd_series_sharpe(book, ann_factor = ann_factor)
    }, numeric(1))

    rows[[i]] <- tibble::tibble(
      n_trials      = n_trials,
      n_legs        = n_legs,
      rho_bar       = rho_bar,
      n_reps        = as.integer(n_reps),
      mean_sharpe   = mean(rep_sharpes, na.rm = TRUE),
      median_sharpe = stats::median(rep_sharpes, na.rm = TRUE),
      sd_sharpe     = stats::sd(rep_sharpes, na.rm = TRUE),
      q05_sharpe    = unname(stats::quantile(rep_sharpes, 0.05, na.rm = TRUE)),
      q95_sharpe    = unname(stats::quantile(rep_sharpes, 0.95, na.rm = TRUE))
    )
  }
  dplyr::bind_rows(rows)
}
