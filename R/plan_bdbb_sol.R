# Plan: BDBB queueing diagnostics on SOL/USD (#443 Phase 1)
#
# Varma (2026) M/G/∞ queueing model on Kraken hourly OHLCVT.
# Data source: hd_kraken_ohlcvt("SOL") — 39,743 hourly bars from 2021-06.
#
# Look-ahead safety: diagnostics at window_end t predict returns at t+1.
# No future data enters the window_end diagnostic.

plan_bdbb_sol <- function() {
  list(

    targets::tar_target(bdbb_sol_params, {
      list(
        ticker       = "SOL",
        interval_min = 60L,
        window_days  = 30L,
        min_frac     = 0.7,
        from         = as.POSIXct("2021-06-01", tz = "UTC")
      )
    }),

    targets::tar_target(bdbb_sol_data, {
      hd_kraken_ohlcvt(
        ticker       = bdbb_sol_params$ticker,
        interval_min = bdbb_sol_params$interval_min,
        from         = bdbb_sol_params$from
      )
    }),

    # Basic data validation: row count + date range
    targets::tar_target(bdbb_sol_dv, {
      n        <- nrow(bdbb_sol_data)
      date_min <- min(bdbb_sol_data$time, na.rm = TRUE)
      date_max <- max(bdbb_sol_data$time, na.rm = TRUE)
      if (n < 5000L) {
        cli::cli_abort(c(
          "x" = "bdbb_sol_data has only {n} rows; expected >= 5,000 for SOL hourly.",
          "i" = "Check hd_kraken_ohlcvt() and the HF parquet."
        ))
      }
      tibble::tibble(
        ticker     = bdbb_sol_params$ticker,
        n_rows     = n,
        date_min   = date_min,
        date_max   = date_max,
        n_na_close = sum(is.na(bdbb_sol_data$close))
      )
    }),

    targets::tar_target(bdbb_sol_fit, {
      historicaldata::bdbb_fit(
        bdbb_sol_data,
        window_days = bdbb_sol_params$window_days,
        min_frac    = bdbb_sol_params$min_frac
      )
    }),

    targets::tar_target(bdbb_sol_tail_predict, {
      returns_df <- bdbb_sol_data |>
        dplyr::arrange(time) |>
        dplyr::mutate(log_ret = log(close / dplyr::lag(close))) |>
        dplyr::select(time, log_ret)

      historicaldata::bdbb_tail_predict(bdbb_sol_fit, returns_df)
    }),

    targets::tar_target(bdbb_sol_metrics, {
      fit   <- bdbb_sol_fit
      total <- nrow(fit)
      if (total == 0L) cli::cli_abort("bdbb_sol_fit is empty.")

      regime_pct <- fit |>
        dplyr::count(regime) |>
        dplyr::mutate(pct = round(n / total * 100, 1))

      mr_pct <- regime_pct |>
        dplyr::filter(regime == "mean_reversion") |>
        dplyr::pull(pct)
      mr_pct <- if (length(mr_pct) == 0L) 0 else mr_pct

      med_hl   <- stats::median(fit$half_life_hours, na.rm = TRUE)
      r_spread <- bdbb_sol_tail_predict |>
        dplyr::filter(predictor == "R") |>
        dplyr::pull(spread_pp)

      tibble::tibble(
        ticker               = bdbb_sol_params$ticker,
        n_windows            = total,
        pct_mean_reversion   = mr_pct,
        median_half_life_hrs = round(med_hl, 1),
        r_spread_pp          = round(r_spread, 2),
        varma_r_spread_pp    = 8.6  # paper benchmark for BTC
      )
    }),

    targets::tar_target(bdbb_sol_caption, {
      m <- bdbb_sol_metrics
      paste0(
        "BDBB M/G/infinity queueing diagnostics on SOL/USD (Varma 2026). ",
        "Kraken hourly OHLCVT, ",
        format(min(bdbb_sol_data$time), "%Y-%m"), " to ",
        format(max(bdbb_sol_data$time), "%Y-%m"), ". ",
        "Rolling ", bdbb_sol_params$window_days, "-day windows: ",
        m$n_windows, " total. ",
        "Regime: ", m$pct_mean_reversion, "% mean-reversion ",
        "(Varma BTC benchmark: ~39%). ",
        "Median resilience half-life: ", m$median_half_life_hrs, " hrs ",
        "(Varma BTC benchmark: 10-25 hrs). ",
        "R-metric tail predictivity spread: ", m$r_spread_pp, " pp ",
        "(Varma BTC benchmark: 8.6 pp)."
      )
    })

  )
}
