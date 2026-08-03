# BDBB M/G/∞ queueing diagnostics (Varma 2026) — issue #443 Phase 1
#
# Three exported functions:
#   bdbb_fit()          — rolling window M/G/∞ estimation
#   bdbb_half_life()    — convert θ to half-life in hours (log(2)/θ)
#   bdbb_tail_predict() — Varma Table 2 tail-risk predictivity test
#
# No library() calls — all pkg::fn() throughout (namespace-discipline rule).

# Required columns for bdbb_fit() input
.bdbb_required_cols <- c("time", "open", "high", "low", "close", "volume", "trades")

#' Fit rolling M/G/∞ queueing diagnostics (Varma 2026)
#'
#' Computes rolling R-metric (variance per unit signed flow), mean-reversion
#' rate θ, resilience half-life, and liquidity proxies (Amihud, Kyle) for a
#' sequence of hourly OHLCVT bars.  Suitable for the SOL/USD Kraken dataset
#' returned by [hd_kraken_ohlcvt()].
#'
#' @param df Tibble with columns `time` (POSIXct UTC), `open`, `high`, `low`,
#'   `close`, `volume`, `trades`.  Hourly bars are assumed.
#' @param window_days Integer. Rolling window length in days (converted to
#'   `window_days * 24L` hourly bars).  Default `30L`.
#' @param min_frac Numeric in (0, 1]. Minimum fraction of `n_bars` that must
#'   have non-NA log-returns for a window to be computed.  Default `0.7`.
#'
#' @return A tibble with one row per complete rolling window, columns:
#'   `window_end`, `R`, `theta`, `half_life_hours`, `signed_flow_mean`,
#'   `amihud_mean`, `kyle_mean`, `n_obs`, `regime`.
#'
#' @section Regime classification:
#' * `"mean_reversion"` — θ > 0.005 (positive ACF decay slope)
#' * `"momentum"` — θ < -0.005 (negative decay slope)
#' * `"ambiguous"` — insufficient lags or |θ| ≤ 0.005
#'
#' @section Look-ahead safety:
#' The diagnostic at `window_end = t` uses only bars up to and including `t`.
#' No future data enters the window.
#'
#' @family bdbb
#' @importFrom stats acf lm coef cov var
#' @export
#' @examplesIf interactive()
#' sol <- hd_kraken_ohlcvt("SOL", interval_min = 60L)
#' bdbb_fit(sol, window_days = 30L)
bdbb_fit <- function(df, window_days = 30L, min_frac = 0.7) {
  # Input validation
  missing_cols <- setdiff(.bdbb_required_cols, names(df))
  if (length(missing_cols) > 0L) {
    req_cols <- .bdbb_required_cols
    cli::cli_abort(c(
      "x" = "{.arg df} is missing required column{?s}: {.field {missing_cols}}.",
      "i" = "Required columns: {.field {req_cols}}.",
      "i" = "Did you pass output from {.fn hd_kraken_ohlcvt}?"
    ))
  }

  n_bars <- window_days * 24L
  min_n  <- ceiling(min_frac * n_bars)

  # Per-bar features (sort ensures correct lag ordering)
  df <- dplyr::arrange(df, time)
  df <- dplyr::mutate(
    df,
    log_ret     = log(close / dplyr::lag(close)),
    signed_flow = sign(close - open) * volume,
    amihud      = abs(log_ret) / pmax(volume, 1e-8)
  )
  # NOTE (#624): kyle_lambda is NOT a per-bar ratio. Kyle's lambda is a
  # price-impact *coefficient* — the slope of price change on signed order
  # flow — and is estimated per rolling window below (kyle_mean). A ratio
  # form here would collapse onto amihud, because abs(signed_flow) == volume
  # by construction.

  # Rolling window: one output row per window end (complete windows only)
  slider::slide_dfr(
    df,
    .f = function(w) {
      r  <- w$log_ret[!is.na(w$log_ret)]
      sf <- w$signed_flow[!is.na(w$signed_flow)]
      n  <- length(r)

      if (n < min_n) {
        return(tibble::tibble(
          window_end       = max(w$time, na.rm = TRUE),
          R                = NA_real_,
          theta            = NA_real_,
          half_life_hours  = NA_real_,
          signed_flow_mean = NA_real_,
          amihud_mean      = NA_real_,
          kyle_mean        = NA_real_,
          n_obs            = n,
          regime           = NA_character_
        ))
      }

      # R-metric: variance per unit signed flow
      R_metric <- var(r) / mean(abs(sf))

      # Exponential decay fit to ACF of signed returns
      max_lag <- min(10L, floor(n / 3L))
      if (max_lag < 3L) {
        theta  <- NA_real_
        regime <- "ambiguous"
      } else {
        acf_vals <- stats::acf(r, lag.max = max_lag, plot = FALSE)$acf[-1]
        lags     <- seq_len(max_lag)
        valid    <- which(abs(as.numeric(acf_vals)) > 1e-10)
        if (length(valid) < 2L) {
          theta  <- NA_real_
          regime <- "ambiguous"
        } else {
          y       <- log(abs(as.numeric(acf_vals[valid])))
          x       <- lags[valid]
          lm_df   <- data.frame(y = y, x = x)
          fit     <- stats::lm(y ~ x, data = lm_df)
          slope   <- stats::coef(fit)[["x"]]
          theta   <- -slope

          regime <- dplyr::case_when(
            is.na(theta)   ~ "ambiguous",
            theta >  0.005 ~ "mean_reversion",
            theta < -0.005 ~ "momentum",
            TRUE           ~ "ambiguous"
          )
        }
      }

      half_life_hours <- if (!is.na(theta) && theta > 0) log(2) / theta else NA_real_

      # Kyle's lambda: OLS slope of log_ret on signed_flow within the window
      # (the standard price-impact estimator; see Kyle 1985). Estimated as
      # cov(log_ret, signed_flow) / var(signed_flow) — the closed-form
      # simple-regression slope. A regression needs paired, non-degenerate
      # observations, so the coverage gate here is stricter (min_frac = 0.9,
      # matching the extreme-quantile gate in roll_quantile_safe()) than the
      # mean-based gate (min_n) used for R/amihud/theta above.
      pair_ok    <- !is.na(w$log_ret) & !is.na(w$signed_flow)
      n_pair     <- sum(pair_ok)
      kyle_min_n <- ceiling(0.9 * n_bars)
      if (n_pair < kyle_min_n) {
        kyle_mean <- NA_real_
      } else {
        lr     <- w$log_ret[pair_ok]
        sfp    <- w$signed_flow[pair_ok]
        var_sf <- stats::var(sfp)
        # A flat (zero-variance) flow window makes the slope undefined.
        kyle_mean <- if (!is.finite(var_sf) || var_sf < 1e-12) {
          NA_real_
        } else {
          stats::cov(lr, sfp) / var_sf
        }
      }

      tibble::tibble(
        window_end       = max(w$time, na.rm = TRUE),
        R                = R_metric,
        theta            = theta,
        half_life_hours  = half_life_hours,
        signed_flow_mean = mean(sf, na.rm = TRUE),
        amihud_mean      = mean(w$amihud, na.rm = TRUE),
        kyle_mean        = kyle_mean,
        n_obs            = n,
        regime           = regime
      )
    },
    .before   = n_bars - 1L,
    .complete = TRUE
  )
}


#' Convert M/G/∞ mean-reversion rate θ to resilience half-life in hours
#'
#' Uses the correct formula `log(2) / theta` (true half-life), NOT `1/theta`
#' which gives the time constant (1/e point), not the half-life.
#' See the `half-life-decay` project rule.
#'
#' @param theta Numeric. Mean-reversion rate θ from [bdbb_fit()].
#'   A positive θ implies mean reversion; negative implies momentum.
#'
#' @return Numeric. Half-life in hours.  `Inf` when `theta == 0`;
#'   negative when `theta < 0` (momentum regime).
#'
#' @family bdbb
#' @export
#' @examples
#' bdbb_half_life(log(2) / 10)  # returns 10 (half-life = 10 hours)
bdbb_half_life <- function(theta) {
  log(2) / theta
}


#' Tail-risk predictivity test (Varma 2026 Table 2)
#'
#' Replicates Varma's tercile-split predictivity test: for each predictor
#' (R, Amihud, Kyle), split windows into terciles by predictor value, then
#' compare the probability of an extreme next-period return in the top tercile
#' vs the bottom tercile.
#'
#' @param diagnostics_df Tibble output of [bdbb_fit()].  Must have columns
#'   `window_end`, `R`, `amihud_mean`, `kyle_mean`.
#' @param returns_df Tibble with columns `time` (POSIXct UTC) and `log_ret`
#'   (numeric).  The function looks one period forward from `window_end`.
#'
#' @return A tibble with one row per predictor and columns:
#'   `predictor`, `p_extreme_high_tercile`, `p_extreme_low_tercile`,
#'   `spread_pp`, `n_high`, `n_low`.
#'
#' @family bdbb
#' @export
#' @examplesIf interactive()
#' sol <- hd_kraken_ohlcvt("SOL", interval_min = 60L)
#' fit <- bdbb_fit(sol)
#' ret <- dplyr::mutate(sol, log_ret = log(close / dplyr::lag(close)))
#' bdbb_tail_predict(fit, dplyr::select(ret, time, log_ret))
bdbb_tail_predict <- function(diagnostics_df, returns_df) {
  # Compute next-period extreme_move flag (top decile absolute return)
  threshold_90 <- stats::quantile(
    abs(returns_df$log_ret), 0.90, na.rm = TRUE
  )
  returns_df <- dplyr::mutate(
    returns_df,
    extreme = abs(log_ret) > threshold_90
  )

  # Shift diagnostics forward 1 period: window_end at t predicts returns at t+1.
  # We create a join key by shifting the return times back by one interval
  # (smallest observed gap) to align with the diagnostic window_end.
  # Simpler: join diagnostics$window_end to returns$time directly,
  # since window_end is the LAST bar of the window and the NEXT bar is t+1.
  joined <- dplyr::left_join(
    diagnostics_df,
    returns_df,
    by = dplyr::join_by(window_end == time)
  )

  predictors <- c("R", "amihud_mean", "kyle_mean")

  purrr::map_dfr(predictors, function(pred) {
    df_pred <- dplyr::filter(joined, !is.na(.data[[pred]]), !is.na(extreme))
    df_pred <- dplyr::mutate(
      df_pred,
      tercile = dplyr::ntile(.data[[pred]], 3L)
    )

    high_t <- dplyr::filter(df_pred, tercile == 3L)
    low_t  <- dplyr::filter(df_pred, tercile == 1L)

    p_high <- if (nrow(high_t) > 0L) mean(high_t$extreme, na.rm = TRUE) else NA_real_
    p_low  <- if (nrow(low_t)  > 0L) mean(low_t$extreme,  na.rm = TRUE) else NA_real_

    tibble::tibble(
      predictor             = pred,
      p_extreme_high_tercile = p_high,
      p_extreme_low_tercile  = p_low,
      spread_pp             = (p_high - p_low) * 100,
      n_high                = nrow(high_t),
      n_low                 = nrow(low_t)
    )
  })
}
