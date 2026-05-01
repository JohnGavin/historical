# Plan: Commodity / Strategy Forecast Evaluation (#66)
#
# Applies distributional forecast evaluation metrics — CRPS, Brier score, and
# horizon analysis — to the three main monthly strategies: DRIF, Factor MAX,
# and LambdaMART CS Momentum (LTR).
#
# Inputs (from plan_falsification.R):
#   fals_drif_input   — tibble(date, strategy_ret), monthly
#   fals_fac_max_input — tibble(date, strategy_ret), monthly
#   fals_ltr_input    — tibble(date, strategy_ret), monthly
#
# For the CRPS/Brier targets we treat each strategy's monthly return as a
# "forecast" of the market: the naive baseline is the unconditional return
# distribution (all observed returns pooled).  This gives a meaningful
# comparison: does the strategy concentrate predictive mass in the right tail?
#
# For horizon analysis we need daily data.  We use SPY daily returns from
# hd_ohlcv() and compare the (month-end) strategy signal against realised
# forward SPY returns at 1–21 trading day horizons.
#
# Total targets: 6

plan_forecast_eval <- function() {
  list(

    # ── Parameters ─────────────────────────────────────────────────────────
    targets::tar_target(fe_params, {
      list(
        horizons    = c(1L, 2L, 3L, 5L, 10L, 21L),  # trading days
        strategies  = c("drif", "fac_max", "ltr"),
        roll_months = 12L,   # rolling window for empirical forecast distribution
        seed        = 42L
      )
    }),


    # ── CRPS per strategy ───────────────────────────────────────────────────
    # For each monthly observation t, the "empirical forecast" is the rolling
    # window of the *previous* roll_months returns.  This ensures no look-ahead:
    # the forecast distribution at time t only uses data up to t-1.
    #
    # CRPS_naive uses the full-sample unconditional distribution (all returns
    # except the current one) — a constant reference that ignores timing.
    targets::tar_target(fe_crps, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      set.seed(fe_params$seed)

      strategy_list <- list(
        drif    = fals_drif_input,
        fac_max = fals_fac_max_input,
        ltr     = fals_ltr_input
      )

      results <- lapply(names(strategy_list), function(name) {
        df <- strategy_list[[name]] |>
          dplyr::mutate(date = as.Date(date)) |>
          dplyr::arrange(date)

        rets <- df$strategy_ret
        n    <- length(rets)
        k    <- fe_params$roll_months

        if (n < k + 2L) {
          return(tibble::tibble(
            strategy     = name,
            crps_model   = NA_real_,
            crps_naive   = NA_real_,
            skill_score  = NA_real_,
            n_obs        = n
          ))
        }

        # Per-observation CRPS using rolling k-period empirical forecast
        crps_model_vec <- vapply(seq(k + 1L, n), function(i) {
          forecast_samples <- rets[(i - k):(i - 1L)]
          hd_crps_empirical(
            observed         = rets[i],
            forecast_samples = forecast_samples,
            max_samples      = 1000L
          )
        }, numeric(1))

        # Naive: unconditional distribution (all other observations)
        crps_naive_vec <- vapply(seq(k + 1L, n), function(i) {
          all_other <- rets[-i]
          hd_crps_empirical(
            observed         = rets[i],
            forecast_samples = all_other,
            max_samples      = 1000L
          )
        }, numeric(1))

        crps_model_mean <- mean(crps_model_vec, na.rm = TRUE)
        crps_naive_mean <- mean(crps_naive_vec, na.rm = TRUE)

        tibble::tibble(
          strategy    = name,
          crps_model  = crps_model_mean,
          crps_naive  = crps_naive_mean,
          skill_score = hd_crps_skill(crps_model_mean, crps_naive_mean),
          n_obs       = as.integer(length(crps_model_vec))
        )
      })

      dplyr::bind_rows(results)
    }),


    # ── Brier score per strategy ────────────────────────────────────────────
    # Binary outcome: did the strategy produce a positive return in period t?
    # Forecast probability: rolling win rate over the previous roll_months periods.
    # Naive baseline: unconditional win rate over the full sample.
    targets::tar_target(fe_brier, {
      library(dplyr)

      strategy_list <- list(
        drif    = fals_drif_input,
        fac_max = fals_fac_max_input,
        ltr     = fals_ltr_input
      )

      results <- lapply(names(strategy_list), function(name) {
        df <- strategy_list[[name]] |>
          dplyr::mutate(date = as.Date(date)) |>
          dplyr::arrange(date)

        rets <- df$strategy_ret
        n    <- length(rets)
        k    <- fe_params$roll_months

        if (n < k + 2L) {
          return(tibble::tibble(
            strategy       = name,
            brier_model    = NA_real_,
            brier_naive    = NA_real_,
            brier_skill    = NA_real_,
            win_rate       = NA_real_,
            n_obs          = n
          ))
        }

        # Binary outcomes
        binary <- as.integer(rets > 0)

        # Rolling win rate as forecast probability (strictly prior to current obs)
        forecast_prob <- vapply(seq(k + 1L, n), function(i) {
          mean(binary[(i - k):(i - 1L)], na.rm = TRUE)
        }, numeric(1))

        obs_binary <- binary[(k + 1L):n]

        # Naive forecast: constant unconditional win rate
        unconditional_wr <- mean(binary[seq_len(k)], na.rm = TRUE)
        naive_prob       <- rep(unconditional_wr, length(obs_binary))

        bs_model <- hd_brier_score(obs_binary, forecast_prob)
        bs_naive <- hd_brier_score(obs_binary, naive_prob)

        # Brier skill score (1 - model/naive; higher = better)
        skill <- if (!is.na(bs_naive) && abs(bs_naive) > .Machine$double.eps) {
          1 - bs_model / bs_naive
        } else {
          NA_real_
        }

        tibble::tibble(
          strategy    = name,
          brier_model = bs_model,
          brier_naive = bs_naive,
          brier_skill = skill,
          win_rate    = mean(binary, na.rm = TRUE),
          n_obs       = as.integer(length(obs_binary))
        )
      })

      dplyr::bind_rows(results)
    }),


    # ── Horizon analysis ────────────────────────────────────────────────────
    # SPY daily returns from hd_ohlcv().
    # Strategy signal = lagged monthly return (last available value before
    # each trading day, treated as the "signal" available to the investor).
    # We measure how well this signal predicts actual forward SPY returns at
    # horizons 1, 2, 3, 5, 10, 21 trading days.
    targets::tar_target(fe_horizon, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      # Daily SPY returns
      spy_daily <- hd_ohlcv("SPY") |>
        dplyr::mutate(date = as.Date(date)) |>
        dplyr::arrange(date) |>
        dplyr::mutate(
          daily_ret = (close - dplyr::lag(close)) / dplyr::lag(close)
        ) |>
        dplyr::filter(!is.na(daily_ret))

      strategy_list <- list(
        drif    = fals_drif_input,
        fac_max = fals_fac_max_input,
        ltr     = fals_ltr_input
      )

      results <- lapply(names(strategy_list), function(name) {
        monthly <- strategy_list[[name]] |>
          dplyr::mutate(date = as.Date(date)) |>
          dplyr::arrange(date)

        # Merge: for each SPY trading day, find the most recent monthly
        # strategy return (last available as of that trading day).
        # This is a last-observation-carried-forward join.
        daily_with_signal <- spy_daily |>
          dplyr::left_join(
            monthly |> dplyr::rename(signal = strategy_ret),
            by = "date"
          ) |>
          # Fill signal forward (carry last known monthly return)
          dplyr::mutate(
            signal = zoo_locf(signal)
          ) |>
          dplyr::filter(!is.na(signal))

        if (nrow(daily_with_signal) < 30L) {
          return(tibble::tibble(
            strategy    = character(0),
            horizon     = integer(0),
            rmse        = numeric(0),
            correlation = numeric(0),
            n_obs       = integer(0)
          ))
        }

        skill_tbl <- hd_horizon_skill(
          returns    = daily_with_signal$daily_ret,
          signal     = daily_with_signal$signal,
          horizons   = fe_params$horizons,
          ann_factor = 252L
        )

        dplyr::bind_cols(
          tibble::tibble(strategy = name),
          skill_tbl
        )
      })

      dplyr::bind_rows(results)
    }),


    # ── Summary table ───────────────────────────────────────────────────────
    targets::tar_target(fe_summary, {
      library(dplyr)

      crps_wide <- fe_crps |>
        dplyr::select(strategy, crps_model, crps_naive, skill_score, n_obs) |>
        dplyr::rename(
          crps_model_val  = crps_model,
          crps_naive_val  = crps_naive,
          crps_skill      = skill_score,
          n_crps          = n_obs
        )

      brier_wide <- fe_brier |>
        dplyr::select(strategy, brier_model, brier_naive, brier_skill, win_rate, n_obs) |>
        dplyr::rename(n_brier = n_obs)

      crps_wide |>
        dplyr::left_join(brier_wide, by = "strategy") |>
        dplyr::arrange(dplyr::desc(crps_skill))
    }),


    # ── Dynamic caption ─────────────────────────────────────────────────────
    targets::tar_target(fe_caption, {
      best_strat <- fe_summary$strategy[which.max(fe_summary$crps_skill)]
      best_skill <- round(fe_summary$crps_skill[which.max(fe_summary$crps_skill)], 3)
      min_n      <- min(fe_summary$n_crps, na.rm = TRUE)

      paste0(
        "Forecast evaluation for ", length(fe_params$strategies),
        " strategies (DRIF, Factor MAX, LTR) using CRPS and Brier score. ",
        "Rolling ", fe_params$roll_months, "-month window used as empirical ",
        "forecast distribution; naive baseline is the unconditional return ",
        "distribution. Best CRPS skill: ", best_strat,
        " (skill = ", best_skill, "). ",
        "Minimum observations: ", min_n, " months. ",
        "Sources: fals_drif_input, fals_fac_max_input, fals_ltr_input targets; ",
        "SPY daily OHLCV via hd_ohlcv(). ",
        "See falsification.qmd for strategy construction details."
      )
    })

  )
}


# ── Internal helper: last-observation-carried-forward ─────────────────────────
# This is not exported; it replicates zoo::na.locf without the zoo dependency.
zoo_locf <- function(x) {
  non_na <- which(!is.na(x))
  if (length(non_na) == 0L) return(x)
  # For each position, the fill value is the last non-NA before or at it
  filled <- x
  for (i in seq_along(x)) {
    candidates <- non_na[non_na <= i]
    if (length(candidates) > 0L) {
      filled[i] <- x[max(candidates)]
    }
  }
  filled
}
