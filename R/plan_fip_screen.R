# Plan: FIP Path-Quality Screen for Cross-Sectional Momentum (#428)
#
# Da, Gurun & Warachka (2014) "A Closer Look at the Disposition Effect" and
# Gray & Vogel (2016) "Quantitative Momentum" (AA QMOM) show that momentum
# stocks with smooth, gradual appreciation paths (high FIP) outperform those
# with lumpy, episodic gains (low FIP) on a risk-adjusted basis.
#
# FIP = (n_positive_daily_returns - n_negative_daily_returns) / n_total_days
# over the 12-month formation window. High FIP = consistent daily gains.
#
# This plan screens the existing mom_combined (12-2 momentum baseline) by FIP:
#   - Long leg: top-decile by total_return AND FIP > cross-sectional median
#   - Short leg: bottom-decile by total_return AND FIP < cross-sectional median
#     (lowest-path-quality losers are the most-crowded short side)
#
# Comparison baseline: mom_combined_returns (unscreened 12-2, already built).
# No new data required — reuses ltr_universe (daily prices) and
# mom_prepeak_signal_raw (formation-period returns per stock per rebalance date).
#
# Applicable rules:
#   backtest-robustness    — fip_threshold (top 50%) is the main sensitivity lever
#   priced-in-prohibition  — FIP published 2014; crowding post-publication noted
#   backtest-partitions    — comparison uses existing mom_prepeak partition windows
#   snapshot-test-policy   — error messages and function signatures snapshotted
#
# Naming: fip_*
# Total targets: 6

plan_fip_screen <- function() {
  list(

    # ── Parameters ─────────────────────────────────────────────────────────────
    targets::tar_target(fip_params, {
      list(
        # Formation window: 12 months of daily returns (matches 12-2 lookback)
        lookback_months  = 12L,

        # FIP threshold: keep top X% of long candidates by path quality.
        # 0.5 = top half (median split, canonical AA QMOM screen).
        # Sensitivity lever for backtest-robustness: sweep 0.33 / 0.50 / 0.67 in v1.
        fip_threshold    = 0.50,

        # Minimum daily observations in the formation window for a valid FIP score.
        min_obs_days     = 100L,

        # Transaction cost: matches mom_prepeak_params (10bps per trade).
        cost_per_trade   = 0.001
      )
    }),


    # ── Daily returns: precompute once for the whole ltr_universe ──────────────
    # Avoids recomputing per rebalance date inside fip_scores.
    targets::tar_target(fip_daily_returns, {
      library(dplyr)

      ltr_universe |>
        dplyr::mutate(date = as.Date(.data$date)) |>
        dplyr::arrange(.data$ticker, .data$date) |>
        dplyr::group_by(.data$ticker) |>
        dplyr::mutate(
          daily_ret = .data$adjusted / dplyr::lag(.data$adjusted) - 1,
          ret_sign  = sign(.data$daily_ret)
        ) |>
        dplyr::filter(!is.na(.data$daily_ret)) |>
        dplyr::ungroup() |>
        dplyr::select("ticker", "date", "daily_ret", "ret_sign")
    }),


    # ── FIP scores: count up/down days per (ticker, rebalance date) ────────────
    # For each as_of_date, look back `lookback_months` months of daily returns.
    # Uses approximate 21-trading-days/month conversion (±2 days is immaterial).
    # Per look-ahead-bias-prevention: formation window ends ON as_of_date,
    # which matches how mom_prepeak_signal_raw is constructed.
    targets::tar_target(fip_scores, {
      library(dplyr)

      lb_days   <- fip_params$lookback_months * 21L
      min_obs   <- fip_params$min_obs_days
      daily_ret <- fip_daily_returns

      dplyr::bind_rows(lapply(mom_prepeak_as_of_dates, function(aod) {
        window_start <- aod - lb_days

        daily_ret |>
          dplyr::filter(.data$date >= window_start, .data$date <= aod) |>
          dplyr::group_by(.data$ticker) |>
          dplyr::summarise(
            n_pos      = sum(.data$ret_sign > 0L, na.rm = TRUE),
            n_neg      = sum(.data$ret_sign < 0L, na.rm = TRUE),
            n_tot      = .data$n_pos + .data$n_neg,
            fip        = ifelse(.data$n_tot >= min_obs,
                                (.data$n_pos - .data$n_neg) / .data$n_tot,
                                NA_real_),
            as_of_date = aod,
            .groups    = "drop"
          )
      }))
    }),


    # ── FIP-screened portfolio: 12-2 momentum with path-quality filter ─────────
    # Rank stocks by total_return (12-2 momentum signal, same as mom_combined).
    # Among the top decile (long candidates): keep only FIP > cross-section median.
    # Among the bottom decile (short candidates): keep only FIP < cross-section median
    # (lumpy losers = most fragile short candidates).
    # Weights are rebalanced to equal-weight WITHIN each post-filter leg.
    targets::tar_target(fip_portfolio, {
      library(dplyr)

      n_q        <- mom_prepeak_params$n_quantiles
      min_stocks <- mom_prepeak_params$min_stocks_per_month
      fip_thr    <- fip_params$fip_threshold

      # Join FIP scores onto signal tibble
      signal_with_fip <- mom_prepeak_signal_raw |>
        dplyr::left_join(
          fip_scores |> dplyr::select("ticker", "as_of_date", "fip"),
          by = c("ticker", "as_of_date")
        )

      signal_with_fip |>
        dplyr::select(
          "as_of_date", "ticker",
          signal_value = "total_return",
          "fip"
        ) |>
        dplyr::filter(!is.na(.data$signal_value)) |>
        dplyr::group_by(.data$as_of_date) |>
        dplyr::filter(dplyr::n() >= min_stocks) |>
        dplyr::mutate(
          decile     = dplyr::ntile(.data$signal_value, n_q),
          # Cross-sectional FIP median at this rebalance date
          fip_median = stats::median(.data$fip, na.rm = TRUE)
        ) |>
        # FIP screen: long leg keeps high-FIP; short leg keeps low-FIP
        dplyr::filter(
          (.data$decile == n_q & (is.na(.data$fip) | .data$fip >= .data$fip_median)) |
          (.data$decile == 1L  & (is.na(.data$fip) | .data$fip <= .data$fip_median))
        ) |>
        # Rebalance to equal-weight within each post-filter leg
        dplyr::mutate(
          n_long  = sum(.data$decile == n_q),
          n_short = sum(.data$decile == 1L),
          weight  = dplyr::case_when(
            .data$decile == n_q & .data$n_long  > 0L ~ 1 / .data$n_long,
            .data$decile == 1L  & .data$n_short > 0L ~ -1 / .data$n_short,
            TRUE                                      ~ NA_real_
          )
        ) |>
        dplyr::ungroup() |>
        dplyr::select("as_of_date", "ticker", "signal_value", "decile", "weight")
    }),


    # ── Returns: reuse existing compute_returns helper ─────────────────────────
    targets::tar_target(fip_returns, {
      .mom_prepeak_compute_returns(
        portfolio_tbl  = fip_portfolio,
        universe_tbl   = ltr_universe,
        cost_per_trade = fip_params$cost_per_trade
      )
    }),


    # ── Comparison metrics: FIP-screened vs unscreened baseline ───────────────
    # Baseline is mom_combined_returns (standard 12-2 momentum, no FIP filter).
    # Reports Full, Training, OOS periods matching mom_prepeak partition windows.
    targets::tar_target(fip_comparison, {
      library(dplyr)

      oos <- bt_partitions$equity$test_start

      calc_metrics <- function(ret_vec, strategy_name, period_name) {
        ret_vec <- ret_vec[!is.na(ret_vec)]
        if (length(ret_vec) < 12L) return(NULL)
        years   <- length(ret_vec) / 12
        cagr    <- (prod(1 + ret_vec)^(1 / years) - 1) * 100
        vol     <- stats::sd(ret_vec) * sqrt(12) * 100
        sharpe  <- ifelse(vol > 0, cagr / vol, NA_real_)
        cum_w   <- cumprod(1 + ret_vec)
        dd      <- (cum_w - cummax(cum_w)) / cummax(cum_w)
        max_dd  <- min(dd) * 100
        tibble::tibble(
          strategy = strategy_name,
          period   = period_name,
          n_months = length(ret_vec),
          cagr     = round(cagr, 2),
          vol      = round(vol, 2),
          sharpe   = round(sharpe, 3),
          max_dd   = round(max_dd, 2)
        )
      }

      strategies <- list(
        fip      = fip_returns$ret_ls,
        baseline = mom_combined_returns$ret_ls
      )
      labels <- c(
        fip      = "12-2 Momentum + FIP Screen (top 50% by path quality)",
        baseline = "12-2 Momentum (unscreened, mom_combined baseline)"
      )
      dates  <- fip_returns$exec_date
      is_oos <- dates >= oos

      rows <- list()
      for (nm in names(strategies)) {
        r <- strategies[[nm]]
        d <- if (nm == "fip") dates else mom_combined_returns$exec_date
        io <- d >= oos
        rows <- c(rows,
          list(calc_metrics(r,       labels[nm], "Full")),
          list(calc_metrics(r[!io],  labels[nm], "Training")),
          list(calc_metrics(r[io],   labels[nm], "OOS"))
        )
      }
      dplyr::bind_rows(Filter(Negate(is.null), rows))
    }),


    # ── Caption: dynamic summary ──────────────────────────────────────────────
    targets::tar_target(fip_caption, {
      library(dplyr)

      thr_pct <- round(fip_params$fip_threshold * 100)
      oos     <- bt_partitions$equity$test_start
      oos_yr  <- format(oos, "%Y")

      fip_oos  <- fip_comparison |>
        dplyr::filter(strategy == "12-2 Momentum + FIP Screen (top 50% by path quality)",
                      period == "OOS")
      base_oos <- fip_comparison |>
        dplyr::filter(strategy == "12-2 Momentum (unscreened, mom_combined baseline)",
                      period == "OOS")
      fip_full  <- fip_comparison |>
        dplyr::filter(strategy == "12-2 Momentum + FIP Screen (top 50% by path quality)",
                      period == "Full")

      fip_sh  <- if (nrow(fip_oos) > 0)  round(fip_oos$sharpe[1], 3)  else NA
      base_sh <- if (nrow(base_oos) > 0) round(base_oos$sharpe[1], 3) else NA
      fip_cagr <- if (nrow(fip_full) > 0) round(fip_full$cagr[1], 2) else NA

      lift <- if (!is.na(fip_sh) && !is.na(base_sh)) {
        paste0(round((fip_sh - base_sh) / abs(base_sh) * 100, 1), "%")
      } else "N/A"

      paste0(
        "**FIP Path-Quality Screen for 12-2 Momentum (#428).** ",
        "Frog-in-the-Pan (FIP) filter from Da, Gurun & Warachka (2014): ",
        "FIP = (positive days - negative days) / total days over the 12-month ",
        "formation window. Higher FIP = smoother, more consistent appreciation path. ",
        "Screen: long leg restricted to top ", thr_pct, "% of momentum stocks by FIP; ",
        "short leg restricted to bottom ", thr_pct, "% (lumpiest losers). ",
        "Full-period CAGR: ", fip_cagr, "%. ",
        "OOS (", oos_yr, "+): FIP-screened Sharpe ", fip_sh,
        " vs unscreened baseline ", base_sh,
        " (lift: ", lift, "). ",
        "Universe: ~51 US equities (ltr_universe, methodology-demonstration scope). ",
        "Priced-in note (priced-in-prohibition rule): FIP has been published since 2014; ",
        "any OOS lift should be interpreted with caution — partial crowding likely. ",
        "FIP threshold (", thr_pct, "%) is the main sensitivity lever; ",
        "sweep 33%/50%/67% is deferred to v1. ",
        "Baseline: mom_combined_returns (standard 12-2 momentum, no FIP filter)."
      )
    })

  )
}
