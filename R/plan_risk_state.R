# Plan: Risk State Classification Overlay (#51)
#
# A reusable exposure-scaling overlay that classifies market regime as
# benign/cautious/hostile using three signals from VIX options data,
# then scales any strategy's exposure.  NOT a standalone strategy.
#
# Three signals (all use PREVIOUS-day values — t+1 execution):
#   1. VVIX (vol-of-vol, earliest warning): percentile thresholds
#   2. Term structure change: 5-day Δ in VIX3M/VIX1M ratio
#   3. Term structure level: VIX3M/VIX1M ratio percentile
#
# Regime = worst of the three signals.
# Exposure: benign = 100%, cautious = 50%, hostile = 10%.
# Cash earns RF rate.
#
# Naming convention: rsc_*
# Total targets: ~16

plan_risk_state <- function() {
  list(

    # ── Parameters ──────────────────────────────────────────────
    targets::tar_target(rsc_params, {
      list(
        vvix_hostile_pct       = 0.95,   # VVIX percentile threshold
        vvix_cautious_pct      = 0.80,
        slope_change_hostile   = -0.08,  # 5-day Δ VIX3M/VIX1M threshold
        slope_change_cautious  = -0.04,
        slope_level_hostile_pct  = 0.05, # VIX3M/VIX1M ratio percentile
        slope_level_cautious_pct = 0.10,
        exposure_benign   = 1.00,
        exposure_cautious = 0.50,
        exposure_hostile  = 0.10,
        slope_change_window = 5L,        # days for delta computation
        oos_start = as.Date("2020-01-01")
      )
    }),


    # ── Data: fetch and join all signals ─────────────────────────
    targets::tar_target(rsc_data, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      # SPY daily returns
      spy <- hd_ohlcv("SPY") |>
        arrange(date) |>
        mutate(spy_ret = adjusted / lag(adjusted) - 1) |>
        filter(!is.na(spy_ret)) |>
        select(date, spy_ret)

      # VIX1M (VIXCLS = 30-day implied vol, from 1990)
      vix1m <- hd_macro("VIXCLS") |>
        select(date, vix1m = value) |>
        arrange(date)

      # VIX3M (3-month implied vol, from 2009)
      vix3m <- hd_macro("VIX3M") |>
        select(date, vix3m = value) |>
        arrange(date)

      # VVIX (vol-of-vol, from 2006)
      vvix <- hd_macro("VVIX") |>
        select(date, vvix = value) |>
        arrange(date)

      # RF from FF3 daily factors
      rf <- hd_factors(dataset = "FF3", frequency = "daily") |>
        filter(factor_name == "RF") |>
        mutate(rf = value / 100) |>
        select(date, rf)

      # Join all on date
      spy |>
        left_join(vix1m, by = "date") |>
        left_join(vix3m, by = "date") |>
        left_join(vvix,  by = "date") |>
        left_join(rf,    by = "date") |>
        arrange(date)
    }),


    # ── Signals: lagged (ALL use PREVIOUS day for t+1 execution) ─
    targets::tar_target(rsc_signals, {
      library(dplyr)

      rsc_data |>
        arrange(date) |>
        mutate(
          # All signals use PREVIOUS day (t+1 execution)
          vvix_lag  = lag(vvix),
          vix1m_lag = lag(vix1m),
          vix3m_lag = lag(vix3m),
          # Term structure ratio (using lagged values)
          slope_ratio = vix3m_lag / vix1m_lag,
          # 5-day change in slope ratio
          slope_change = slope_ratio - lag(slope_ratio,
                                           rsc_params$slope_change_window),
          # RF for cash return
          rf_lag = lag(rf)
        )
    }),


    # ── Thresholds: computed from TRAINING data only ──────────────
    # (date < oos_start to avoid look-ahead bias)
    targets::tar_target(rsc_thresholds, {
      library(dplyr)

      train <- rsc_signals |>
        filter(date < rsc_params$oos_start)

      list(
        vvix_hostile  = quantile(train$vvix_lag,
                                 rsc_params$vvix_hostile_pct,
                                 na.rm = TRUE),
        vvix_cautious = quantile(train$vvix_lag,
                                 rsc_params$vvix_cautious_pct,
                                 na.rm = TRUE),
        slope_level_hostile  = quantile(train$slope_ratio,
                                        rsc_params$slope_level_hostile_pct,
                                        na.rm = TRUE),
        slope_level_cautious = quantile(train$slope_ratio,
                                        rsc_params$slope_level_cautious_pct,
                                        na.rm = TRUE)
      )
    }),


    # ── Regime: classify each day ────────────────────────────────
    targets::tar_target(rsc_regime, {
      library(dplyr)

      rsc_signals |>
        mutate(
          # Signal 1: VVIX (earliest warning)
          sig_vvix = dplyr::case_when(
            is.na(vvix_lag)                              ~ "benign",
            vvix_lag > rsc_thresholds$vvix_hostile       ~ "hostile",
            vvix_lag > rsc_thresholds$vvix_cautious      ~ "cautious",
            TRUE                                         ~ "benign"
          ),
          # Signal 2: Term structure change (early warning)
          sig_change = dplyr::case_when(
            is.na(slope_change)                                    ~ "benign",
            slope_change < rsc_params$slope_change_hostile         ~ "hostile",
            slope_change < rsc_params$slope_change_cautious        ~ "cautious",
            TRUE                                                   ~ "benign"
          ),
          # Signal 3: Term structure level (confirming)
          sig_level = dplyr::case_when(
            is.na(slope_ratio)                                      ~ "benign",
            slope_ratio < rsc_thresholds$slope_level_hostile        ~ "hostile",
            slope_ratio < rsc_thresholds$slope_level_cautious       ~ "cautious",
            TRUE                                                    ~ "benign"
          ),
          # Combined: worst of three signals
          regime = dplyr::case_when(
            sig_vvix == "hostile" |
              sig_change == "hostile" |
              sig_level == "hostile"  ~ "hostile",
            sig_vvix == "cautious" |
              sig_change == "cautious" |
              sig_level == "cautious" ~ "cautious",
            TRUE                     ~ "benign"
          ),
          regime = factor(regime, levels = c("benign", "cautious", "hostile")),
          # Exposure scaling
          exposure = dplyr::case_when(
            regime == "hostile"  ~ rsc_params$exposure_hostile,
            regime == "cautious" ~ rsc_params$exposure_cautious,
            TRUE                 ~ rsc_params$exposure_benign
          )
        )
    }),


    # ── Portfolio: apply exposure to SPY (standalone baseline) ───
    targets::tar_target(rsc_portfolio, {
      library(dplyr)

      rsc_regime |>
        filter(!is.na(spy_ret), !is.na(exposure)) |>
        mutate(
          rf_daily     = ifelse(is.na(rf_lag), 0, rf_lag),
          ret_strategy = exposure * spy_ret + (1 - exposure) * rf_daily,
          ret_buyhold  = spy_ret,
          cum_strategy = cumprod(1 + ret_strategy),
          cum_buyhold  = cumprod(1 + ret_buyhold)
        )
    }),


    # ── Overlay: apply to DRIF ────────────────────────────────────
    targets::tar_target(rsc_overlay_drif, {
      library(dplyr)

      # Last trading day of each month from regime series
      rsc_regime_monthly <- rsc_regime |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(ym) |>
        filter(date == max(date)) |>
        ungroup() |>
        select(ym, regime, exposure)

      drif_ret <- drif_portfolio |>
        select(date, drif_ret = portfolio_ret)

      drif_ret |>
        mutate(ym = format(date, "%Y-%m")) |>
        left_join(rsc_regime_monthly, by = "ym") |>
        mutate(
          exposure   = ifelse(is.na(exposure), 1, exposure),
          ret_overlay = exposure * drif_ret,
          ret_raw     = drif_ret
        )
    }),


    # ── Overlay: apply to Factor MAX ─────────────────────────────
    targets::tar_target(rsc_overlay_fac_max, {
      library(dplyr)

      # Last trading day of each month from regime series
      rsc_regime_monthly <- rsc_regime |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(ym) |>
        filter(date == max(date)) |>
        ungroup() |>
        select(ym, regime, exposure)

      fm_ret <- fm_portfolio |>
        select(date, fm_ret = portfolio_ret)

      fm_ret |>
        mutate(ym = format(date, "%Y-%m")) |>
        left_join(rsc_regime_monthly, by = "ym") |>
        mutate(
          exposure    = ifelse(is.na(exposure), 1, exposure),
          ret_overlay = exposure * fm_ret,
          ret_raw     = fm_ret
        )
    }),


    # ── Metrics: summary per partition for all strategy variants ──
    targets::tar_target(rsc_metrics, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      calc_metrics <- function(ret_vec, label, strategy_name) {
        ret_vec <- ret_vec[!is.na(ret_vec)]
        if (length(ret_vec) < 20) return(NULL)
        years <- length(ret_vec) / 252
        cum <- prod(1 + ret_vec)
        cum_dd <- cumprod(1 + ret_vec)
        hac <- hd_hac_sharpe(ret_vec)
        tibble::tibble(
          strategy  = strategy_name,
          period    = label,
          cagr      = round((cum^(1 / years) - 1) * 100, 2),
          vol       = round(sd(ret_vec) * sqrt(252) * 100, 2),
          max_dd    = round(min((cum_dd - cummax(cum_dd)) /
                                  cummax(cum_dd)) * 100, 2),
          hac_tstat = round(hac$hac_tstat, 3),
          hac_sharpe = round(hac$naive_sharpe, 3)
        )
      }

      oos   <- rsc_params$oos_start
      port  <- rsc_portfolio
      drif  <- rsc_overlay_drif
      facmx <- rsc_overlay_fac_max

      # Regime distribution for SPY portfolio
      regime_dist <- function(d) {
        n <- nrow(d)
        c(
          pct_benign   = round(sum(d$regime == "benign",   na.rm = TRUE) / n * 100, 1),
          pct_cautious = round(sum(d$regime == "cautious", na.rm = TRUE) / n * 100, 1),
          pct_hostile  = round(sum(d$regime == "hostile",  na.rm = TRUE) / n * 100, 1)
        )
      }

      # SPY buy-and-hold, SPY with overlay
      spy_bh_full  <- calc_metrics(port$ret_buyhold,   "Full Period", "SPY_buyhold")
      spy_ov_full  <- calc_metrics(port$ret_strategy,  "Full Period", "SPY_overlay")
      spy_bh_train <- calc_metrics(port$ret_buyhold[port$date < oos],
                                   "Training", "SPY_buyhold")
      spy_ov_train <- calc_metrics(port$ret_strategy[port$date < oos],
                                   "Training", "SPY_overlay")
      spy_bh_test  <- calc_metrics(port$ret_buyhold[port$date >= oos],
                                   "Testing", "SPY_buyhold")
      spy_ov_test  <- calc_metrics(port$ret_strategy[port$date >= oos],
                                   "Testing", "SPY_overlay")

      # DRIF raw vs overlaid
      drif_raw_full <- calc_metrics(drif$ret_raw,     "Full Period", "DRIF_raw")
      drif_ov_full  <- calc_metrics(drif$ret_overlay, "Full Period", "DRIF_overlay")

      # FacMAX raw vs overlaid
      fm_raw_full   <- calc_metrics(facmx$ret_raw,     "Full Period", "FacMAX_raw")
      fm_ov_full    <- calc_metrics(facmx$ret_overlay, "Full Period", "FacMAX_overlay")

      dplyr::bind_rows(
        spy_bh_full, spy_ov_full,
        spy_bh_train, spy_ov_train,
        spy_bh_test, spy_ov_test,
        drif_raw_full, drif_ov_full,
        fm_raw_full, fm_ov_full
      )
    }),


    # ── Plot: equity curve SPY buy-and-hold vs SPY with overlay ──
    targets::tar_target(rsc_plot, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(ggplot2)
      library(dplyr)

      port <- rsc_portfolio |> filter(!is.na(cum_strategy))

      # Build regime shading rectangles
      regimes <- port |>
        mutate(
          regime_grp = cumsum(c(TRUE, diff(as.integer(regime)) != 0))
        ) |>
        group_by(regime_grp) |>
        summarise(
          xmin   = min(date),
          xmax   = max(date),
          regime = first(regime),
          .groups = "drop"
        ) |>
        mutate(
          fill_col = dplyr::case_when(
            regime == "benign"   ~ "#27ae60",  # green
            regime == "cautious" ~ "#f39c12",  # amber
            TRUE                 ~ "#e74c3c"   # red (hostile)
          )
        )

      plot_data <- port |>
        select(date,
               `SPY Buy & Hold` = cum_buyhold,
               `SPY + RSC Overlay` = cum_strategy) |>
        tidyr::pivot_longer(-date, names_to = "strategy", values_to = "growth")

      ggplot() +
        geom_rect(data = regimes,
                  aes(xmin = xmin, xmax = xmax,
                      ymin = -Inf, ymax = Inf,
                      fill = fill_col),
                  alpha = 0.15, inherit.aes = FALSE) +
        scale_fill_identity() +
        geom_line(data = plot_data,
                  aes(date, growth, colour = strategy),
                  linewidth = 0.6) +
        geom_vline(xintercept = rsc_params$oos_start,
                   linetype = "dashed", colour = "grey50", linewidth = 0.4) +
        scale_y_log10(labels = scales::dollar) +
        scale_colour_manual(values = hd_palette(2)) +
        labs(x = NULL,
             y = "Growth of $1 (log scale)",
             colour = NULL,
             title = "Risk State Classification: SPY Overlay vs Buy & Hold",
             subtitle = "Green = benign, amber = cautious, red = hostile") +
        hd_theme()
    }),


    # ── Plot: three-panel signal chart ───────────────────────────
    targets::tar_target(rsc_plot_signals, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(ggplot2)
      library(dplyr)

      sig_data <- rsc_signals |>
        filter(!is.na(vvix_lag)) |>
        select(date, vvix_lag, slope_ratio, slope_change)

      # Panel 1: VVIX
      p1 <- ggplot(sig_data, aes(date, vvix_lag)) +
        geom_line(linewidth = 0.4, colour = hd_palette(1)) +
        geom_hline(yintercept = rsc_thresholds$vvix_cautious,
                   linetype = "dashed", colour = "#f39c12") +
        geom_hline(yintercept = rsc_thresholds$vvix_hostile,
                   linetype = "dashed", colour = "#e74c3c") +
        labs(x = NULL, y = "VVIX",
             title = "Signal 1: VVIX (vol-of-vol)") +
        hd_theme()

      # Panel 2: slope ratio
      p2 <- ggplot(sig_data |> filter(!is.na(slope_ratio)),
                   aes(date, slope_ratio)) +
        geom_line(linewidth = 0.4, colour = hd_palette(2)[2]) +
        geom_hline(yintercept = rsc_thresholds$slope_level_cautious,
                   linetype = "dashed", colour = "#f39c12") +
        geom_hline(yintercept = rsc_thresholds$slope_level_hostile,
                   linetype = "dashed", colour = "#e74c3c") +
        labs(x = NULL, y = "VIX3M / VIX1M",
             title = "Signal 3: Term Structure Level") +
        hd_theme()

      # Panel 3: slope change
      p3 <- ggplot(sig_data |> filter(!is.na(slope_change)),
                   aes(date, slope_change)) +
        geom_line(linewidth = 0.4, colour = hd_palette(3)[3]) +
        geom_hline(yintercept = rsc_params$slope_change_cautious,
                   linetype = "dashed", colour = "#f39c12") +
        geom_hline(yintercept = rsc_params$slope_change_hostile,
                   linetype = "dashed", colour = "#e74c3c") +
        geom_hline(yintercept = 0, colour = "grey70", linewidth = 0.3) +
        labs(x = NULL, y = "5-day \u0394 ratio",
             title = "Signal 2: 5-Day Change in Term Structure") +
        hd_theme()

      patchwork::wrap_plots(p1, p2, p3, ncol = 1)
    }),


    # ── Plot: overlay comparison DRIF and Factor MAX ──────────────
    targets::tar_target(rsc_overlay_comparison, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(ggplot2)
      library(dplyr)

      make_cum <- function(ret) cumprod(1 + ret)

      drif_data <- rsc_overlay_drif |>
        filter(!is.na(ret_raw), !is.na(ret_overlay)) |>
        arrange(date) |>
        mutate(
          cum_raw     = make_cum(ret_raw),
          cum_overlay = make_cum(ret_overlay)
        )

      fm_data <- rsc_overlay_fac_max |>
        filter(!is.na(ret_raw), !is.na(ret_overlay)) |>
        arrange(date) |>
        mutate(
          cum_raw     = make_cum(ret_raw),
          cum_overlay = make_cum(ret_overlay)
        )

      plot_df <- dplyr::bind_rows(
        drif_data |> select(date, cum_raw, cum_overlay) |>
          tidyr::pivot_longer(-date) |>
          mutate(strategy = "DRIF",
                 label = ifelse(name == "cum_raw", "DRIF (raw)",
                                "DRIF + RSC")),
        fm_data |> select(date, cum_raw, cum_overlay) |>
          tidyr::pivot_longer(-date) |>
          mutate(strategy = "FacMAX",
                 label = ifelse(name == "cum_raw", "FacMAX (raw)",
                                "FacMAX + RSC"))
      )

      ggplot(plot_df, aes(date, value, colour = label)) +
        geom_line(linewidth = 0.6) +
        facet_wrap(~strategy, scales = "free_y") +
        scale_y_log10(labels = scales::dollar) +
        scale_colour_manual(values = hd_palette(4)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = "RSC Overlay Applied to DRIF and Factor MAX") +
        hd_theme()
    }),


    # ── Caption: dynamic for the equity curve plot ───────────────
    targets::tar_target(rsc_caption, {
      library(dplyr)

      port  <- rsc_portfolio
      n     <- nrow(port)
      years <- n / 252

      cum_bh   <- tail(port$cum_buyhold,  1)
      cum_strat <- tail(port$cum_strategy, 1)
      cagr_bh   <- round((cum_bh^(1 / years)   - 1) * 100, 1)
      cagr_strat <- round((cum_strat^(1 / years) - 1) * 100, 1)

      pct_benign   <- round(mean(port$regime == "benign",   na.rm = TRUE) * 100, 1)
      pct_cautious <- round(mean(port$regime == "cautious", na.rm = TRUE) * 100, 1)
      pct_hostile  <- round(mean(port$regime == "hostile",  na.rm = TRUE) * 100, 1)

      paste0(
        "**Risk State Classification overlay applied to SPY.** ",
        "Growth of $1, log scale. ",
        format(min(port$date), "%Y"), "\u2013",
        format(max(port$date), "%Y"),
        " (", format(n, big.mark = ","), " trading days). ",
        "SPY buy-and-hold CAGR: ", cagr_bh, "%. ",
        "SPY + RSC overlay CAGR: ", cagr_strat, "%. ",
        "Regime distribution: benign ", pct_benign,
        "%, cautious ", pct_cautious,
        "%, hostile ", pct_hostile, "%. ",
        "Thresholds estimated from training data (before ",
        format(rsc_params$oos_start, "%Y"), ") to avoid look-ahead bias. ",
        "Dashed line = OOS start."
      )
    }),


    # ── Alpha decay: delay signals 1-10 days ─────────────────────
    targets::tar_target(rsc_alpha_decay, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      # Re-run SPY overlay with signals delayed by d additional days
      # Baseline (d=1) = already built into rsc_portfolio (t+1 minimum)
      base_data <- rsc_data |> arrange(date) |>
        mutate(
          vvix_d  = vvix,
          vix1m_d = vix1m,
          vix3m_d = vix3m
        )

      run_delayed <- function(d) {
        sig <- base_data |>
          arrange(date) |>
          mutate(
            vvix_lag    = lag(vvix,  d),
            vix1m_lag   = lag(vix1m, d),
            vix3m_lag   = lag(vix3m, d),
            slope_ratio  = vix3m_lag / vix1m_lag,
            slope_change = slope_ratio - lag(slope_ratio,
                                             rsc_params$slope_change_window),
            rf_lag       = lag(rf, d),

            sig_vvix = dplyr::case_when(
              is.na(vvix_lag)                               ~ "benign",
              vvix_lag > rsc_thresholds$vvix_hostile        ~ "hostile",
              vvix_lag > rsc_thresholds$vvix_cautious       ~ "cautious",
              TRUE                                          ~ "benign"
            ),
            sig_change = dplyr::case_when(
              is.na(slope_change)                                   ~ "benign",
              slope_change < rsc_params$slope_change_hostile        ~ "hostile",
              slope_change < rsc_params$slope_change_cautious       ~ "cautious",
              TRUE                                                  ~ "benign"
            ),
            sig_level = dplyr::case_when(
              is.na(slope_ratio)                                     ~ "benign",
              slope_ratio < rsc_thresholds$slope_level_hostile       ~ "hostile",
              slope_ratio < rsc_thresholds$slope_level_cautious      ~ "cautious",
              TRUE                                                   ~ "benign"
            ),
            regime = dplyr::case_when(
              sig_vvix == "hostile"  | sig_change == "hostile"  |
                sig_level == "hostile"  ~ "hostile",
              sig_vvix == "cautious" | sig_change == "cautious" |
                sig_level == "cautious" ~ "cautious",
              TRUE                     ~ "benign"
            ),
            exposure = dplyr::case_when(
              regime == "hostile"  ~ rsc_params$exposure_hostile,
              regime == "cautious" ~ rsc_params$exposure_cautious,
              TRUE                 ~ rsc_params$exposure_benign
            )
          ) |>
          filter(!is.na(spy_ret), !is.na(exposure)) |>
          mutate(
            rf_use = ifelse(is.na(rf_lag), 0, rf_lag),
            ret_strat = exposure * spy_ret + (1 - exposure) * rf_use
          )

        ret <- sig$ret_strat
        if (length(ret) < 20) return(NULL)
        years <- length(ret) / 252
        cum <- prod(1 + ret)
        cum_dd <- cumprod(1 + ret)
        hac <- hd_hac_sharpe(ret)
        tibble::tibble(
          delay_days = d,
          cagr       = round((cum^(1 / years) - 1) * 100, 1),
          vol        = round(sd(ret) * sqrt(252) * 100, 1),
          max_dd     = round(min((cum_dd - cummax(cum_dd)) /
                                   cummax(cum_dd)) * 100, 1),
          hac_tstat  = round(hac$hac_tstat, 3),
          hac_sharpe = round(hac$naive_sharpe, 3)
        )
      }

      # t+1 to t+10 (t+0 is impossible; t+1 is the minimum)
      purrr::map_dfr(1:10, run_delayed)
    }),


    # ── Subperiod analysis: three sub-periods ────────────────────
    targets::tar_target(rsc_subperiod, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      calc_sp <- function(data, label) {
        ret <- data$ret_strategy
        ret_bh <- data$ret_buyhold
        if (length(ret[!is.na(ret)]) < 20) return(NULL)
        hac <- hd_hac_sharpe(ret[!is.na(ret)])
        years <- sum(!is.na(ret)) / 252
        cum_s <- prod(1 + ret[!is.na(ret)])
        cum_b <- prod(1 + ret_bh[!is.na(ret_bh)])
        cum_dd_s <- cumprod(1 + ret[!is.na(ret)])
        cum_dd_b <- cumprod(1 + ret_bh[!is.na(ret_bh)])
        pct_b  <- round(mean(data$regime == "benign",   na.rm = TRUE) * 100, 1)
        pct_c  <- round(mean(data$regime == "cautious", na.rm = TRUE) * 100, 1)
        pct_h  <- round(mean(data$regime == "hostile",  na.rm = TRUE) * 100, 1)
        tibble::tibble(
          period       = label,
          cagr_overlay = round((cum_s^(1 / years) - 1) * 100, 1),
          cagr_buyhold = round((cum_b^(1 / years) - 1) * 100, 1),
          vol          = round(sd(ret, na.rm = TRUE) * sqrt(252) * 100, 1),
          max_dd       = round(min((cum_dd_s - cummax(cum_dd_s)) /
                                     cummax(cum_dd_s)) * 100, 1),
          hac_tstat    = round(hac$hac_tstat, 3),
          pct_benign   = pct_b,
          pct_cautious = pct_c,
          pct_hostile  = pct_h
        )
      }

      port <- rsc_portfolio
      dplyr::bind_rows(
        calc_sp(port |> filter(date >= as.Date("2009-01-01"),
                               date <  as.Date("2015-01-01")),
                "2009-2014"),
        calc_sp(port |> filter(date >= as.Date("2015-01-01"),
                               date <  as.Date("2020-01-01")),
                "2015-2019"),
        calc_sp(port |> filter(date >= as.Date("2020-01-01")),
                "2020-2026"),
        calc_sp(port, "Full Period")
      )
    })

  )
}
