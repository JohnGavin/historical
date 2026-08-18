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
    # #667: test_end wired from bt_partitions so rsc_metrics can bound its
    # Testing window instead of leaving it open above oos_start. RSC is a
    # VIX/VVIX-driven regime-timing overlay -- the same macro-signal family
    # as Managed Futures (plan_managed_futures.R) -- so bt_partitions$macro
    # is the matching partition set, even though the instrument it trades is
    # SPY (an equity ticker). oos_start is unchanged (2020-01-01 already
    # equals bt_partitions$macro$test_start).
    targets::tar_target(rsc_params, {
      p <- bt_partitions$macro
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
        oos_start = p$test_start,
        test_start = p$test_start,
        test_end   = p$test_end,         # #667: bounds rsc_metrics' Testing window
        # #673: bounds rsc_subperiod's trailing slice. Holdout, not test_end --
        # that target deliberately spans Testing AND Holdout; only Validation
        # must stay out. See the comment above rsc_subperiod.
        holdout_end = p$holdout_end,
        # Cost model (#425): SPY-level trades; 5 bps one-way
        # Applied only on regime-switch days (exposure changes)
        cost_per_trade = 0.0005
      )
    }),


    # ── Data: fetch and join all signals ─────────────────────────
    targets::tar_target(rsc_data, {
      library(dplyr)

      # SPY daily returns
      spy <- hd_ohlcv("SPY") |>
        arrange(date) |>
        mutate(spy_ret = adjusted_close / lag(adjusted_close) - 1) |>
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
        arrange(date) |>
        dplyr::mutate(date = as.Date(date, tz = "UTC"))
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

      # Cost model (#425): deduct cost only on days when exposure changes
      # (regime switches). cost = cost_per_trade * |delta_exposure| * 2
      # (round-trip: sell old SPY allocation + buy/sell new allocation).
      rsc_regime |>
        filter(!is.na(spy_ret), !is.na(exposure)) |>
        mutate(
          rf_daily        = ifelse(is.na(rf_lag), 0, rf_lag),
          # Switch indicator: exposure changed vs previous day
          exposure_change = abs(exposure - dplyr::lag(exposure, default = exposure[1L])),
          trade_cost      = rsc_params$cost_per_trade * exposure_change * 2.0,
          gross_ret_strategy = exposure * spy_ret + (1 - exposure) * rf_daily,
          ret_strategy    = gross_ret_strategy - trade_cost,
          ret_buyhold     = spy_ret,
          cum_strategy    = cumprod(1 + ret_strategy),
          cum_buyhold     = cumprod(1 + ret_buyhold)
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

      # #677 slice 2: carry drif_portfolio's own monthly rf_ret column through
      # so rsc_metrics can compute a real (non-NA) Sharpe for the DRIF_raw/
      # DRIF_overlay rows below -- see R/plan_drif.R's drif_portfolio target,
      # which already joins RF (from the same FF5+Mom daily pull used to
      # build drif_ret) onto each ym at construction time. No additional join
      # is needed here: rf_ret already lives on the same rows as drif_ret.
      drif_ret <- drif_portfolio |>
        select(date, drif_ret = portfolio_ret, rf_ret)

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

      # #677 slice 2: carry fm_portfolio's own monthly rf_ret column through --
      # same reasoning as rsc_overlay_drif above. fm_portfolio (R/plan_factormax.R)
      # already joins RF (from fm_monthly, the same FF5+Mom daily pull used to
      # build fm_ret) onto each ym, so rf_ret already lives on the same rows.
      fm_ret <- fm_portfolio |>
        select(date, fm_ret = portfolio_ret, rf_ret)

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
    # #667: Testing is bounded at rsc_params$test_end (bt_partitions$macro)
    # so it no longer silently extends past the sealed Validation partition
    # on every tar_make(). window_start/window_end columns added so gate S11
    # (check_metric_window_bounds()) can assert the bound.
    targets::tar_target(rsc_metrics, {
      library(dplyr)

      # #677 slice 2: rf_vec is OPTIONAL here (unlike sharpe_ratio_rf() itself,
      # which aborts on a NULL rf per fail-loud-not-null.md) so calc_metrics()
      # keeps working for any future row that genuinely has no rf series --
      # but as of this change every row DOES have one wired: SPY_buyhold/
      # SPY_overlay via rsc_portfolio$rf_daily (daily FF3 RF -- see rsc_data/
      # rsc_signals above), DRIF_raw/DRIF_overlay/FacMAX_raw/FacMAX_overlay
      # via drif_portfolio$rf_ret / fm_portfolio$rf_ret (monthly FF5+Mom RF,
      # already joined at construction time -- see rsc_overlay_drif /
      # rsc_overlay_fac_max above). `hac_sharpe` (HAC-adjusted, no rf) is
      # retained for all rows as a separate, non-rf-adjusted statistic.
      #
      # periods_per_year is now a parameter, not hardcoded 252. Discovered
      # while wiring the above: rsc_portfolio (SPY) is DAILY, but
      # rsc_overlay_drif/rsc_overlay_fac_max are MONTHLY (one row per ym --
      # see drif_portfolio/fm_portfolio, R/plan_drif.R, R/plan_factormax.R).
      # `years`/`vol` and hd_hac_sharpe()'s ann_factor were previously
      # hardcoded to 252 for EVERY row including the monthly DRIF/FacMAX
      # ones -- inflating `years` ~21x (so `cagr` was wildly wrong) and `vol`/
      # `hac_sharpe` ~4.6x (sqrt(252/12)). This was invisible because these 4
      # rows never reach the leaderboard (.norm_rsc() in R/plan_leaderboard.R
      # filters to "SPY_overlay" only) and no test asserted their magnitude
      # (only NA-ness). Per fail-loud-not-null.md: shipping a real, non-NA
      # Sharpe on the wrong annualisation basis would be exactly the
      # "plausible-looking wrong number" that rule prohibits, one level
      # deeper than the NA it replaces -- so it is fixed alongside the rf
      # wiring rather than left for a future session to discover by
      # accident. Every other calc_metrics() call site in this file passes
      # daily data and is unaffected (periods_per_year defaults to 252L).
      calc_metrics <- function(ret_vec, date_vec, label, strategy_name, rf_vec = NULL,
                                periods_per_year = 252L) {
        keep     <- !is.na(ret_vec)
        ret_vec  <- ret_vec[keep]
        date_vec <- date_vec[keep]
        if (!is.null(rf_vec)) rf_vec <- rf_vec[keep]
        if (length(ret_vec) < 20) return(NULL)
        years <- length(ret_vec) / periods_per_year
        cum <- prod(1 + ret_vec)
        cum_dd <- cumprod(1 + ret_vec)
        hac <- hd_hac_sharpe(ret_vec, ann_factor = periods_per_year)
        # Canonical, risk-free-adjusted Sharpe (#677) -- see
        # R/utils_metrics.R::sharpe_ratio_rf(). Distinct from hac_sharpe.
        sharpe_val <- if (!is.null(rf_vec)) {
          sharpe_ratio_rf(ret_vec, rf_vec, periods_per_year = periods_per_year)$sharpe
        } else {
          NA_real_
        }
        tibble::tibble(
          strategy  = strategy_name,
          period    = label,
          cagr      = round((cum^(1 / years) - 1) * 100, 2),
          vol       = round(sd(ret_vec) * sqrt(periods_per_year) * 100, 2),
          sharpe    = round(sharpe_val, 3),
          max_dd    = round(min((cum_dd - cummax(cum_dd)) /
                                  cummax(cum_dd)) * 100, 2),
          hac_tstat = round(hac$hac_tstat, 3),
          hac_sharpe = round(hac$naive_sharpe, 3),
          window_start = min(date_vec),
          window_end   = max(date_vec)
        )
      }

      oos      <- rsc_params$oos_start
      test_end <- rsc_params$test_end
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

      is_train <- port$date < oos
      is_test  <- port$date >= oos & port$date <= test_end

      # SPY buy-and-hold, SPY with overlay
      # rf_vec = port$rf_daily: FF3 daily RF, already lagged (t+1) and
      # zero-filled for leading NAs at rsc_portfolio construction time
      # (R/plan_risk_state.R rsc_portfolio target) -- safe to pass directly.
      spy_bh_full  <- calc_metrics(port$ret_buyhold,  port$date,  "Full Period", "SPY_buyhold",
                                   rf_vec = port$rf_daily)
      spy_ov_full  <- calc_metrics(port$ret_strategy, port$date,  "Full Period", "SPY_overlay",
                                   rf_vec = port$rf_daily)
      spy_bh_train <- calc_metrics(port$ret_buyhold[is_train],  port$date[is_train],
                                   "Training", "SPY_buyhold", rf_vec = port$rf_daily[is_train])
      spy_ov_train <- calc_metrics(port$ret_strategy[is_train], port$date[is_train],
                                   "Training", "SPY_overlay", rf_vec = port$rf_daily[is_train])
      spy_bh_test  <- calc_metrics(port$ret_buyhold[is_test],  port$date[is_test],
                                   "Testing", "SPY_buyhold", rf_vec = port$rf_daily[is_test])
      spy_ov_test  <- calc_metrics(port$ret_strategy[is_test], port$date[is_test],
                                   "Testing", "SPY_overlay", rf_vec = port$rf_daily[is_test])

      # DRIF raw vs overlaid (#677 slice 2: rf_vec = drif$rf_ret, monthly FF5+
      # Mom RF already joined onto drif_portfolio -- see rsc_overlay_drif
      # above; periods_per_year = 12L because this is a monthly series, not
      # daily -- see the calc_metrics() comment above)
      drif_raw_full <- calc_metrics(drif$ret_raw,     drif$date, "Full Period", "DRIF_raw",
                                    rf_vec = drif$rf_ret, periods_per_year = 12L)
      drif_ov_full  <- calc_metrics(drif$ret_overlay, drif$date, "Full Period", "DRIF_overlay",
                                    rf_vec = drif$rf_ret, periods_per_year = 12L)

      # FacMAX raw vs overlaid (#677 slice 2: rf_vec = facmx$rf_ret, monthly
      # FF5+Mom RF already joined onto fm_portfolio -- see
      # rsc_overlay_fac_max above; periods_per_year = 12L, same reasoning)
      fm_raw_full   <- calc_metrics(facmx$ret_raw,     facmx$date, "Full Period", "FacMAX_raw",
                                    rf_vec = facmx$rf_ret, periods_per_year = 12L)
      fm_ov_full    <- calc_metrics(facmx$ret_overlay, facmx$date, "Full Period", "FacMAX_overlay",
                                    rf_vec = facmx$rf_ret, periods_per_year = 12L)

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
    # #667 audit / #673 fix. The trailing slice was `date >= 2020-01-01` with
    # no upper bound. That is a DIFFERENT shape from #667's core defect -- the
    # labels here are explicit custom date ranges, not the canonical
    # Training/Testing/Holdout/Validation vocabulary, so no reader mistakes
    # this for the bounded canonical Testing window -- which is why #667/PR
    # #672 correctly left it alone. But unbounded is unbounded: #673 measured
    # equity_daily's boundary at 2026-04-13, below val_start (2026-05-01), so
    # the slice held no sealed data at that moment. It held none only because
    # equity_daily has NO SCHEDULED REFRESH (#673): the boundary is stationary
    # because the fetcher is unscheduled, not because it has yet to catch up.
    # The first run of scripts/fetch_equity.py would have carried it past
    # val_start and pulled sealed Validation returns in here, unlabelled, on
    # the next tar_make() -- and that fetch is the PREREQUISITE for the
    # one-shot evaluation in scripts/evaluate_validation.R. The protection
    # would have vanished in the same action that needed it. Now bounded at
    # holdout_end so the refresh is safe whenever it happens.
    #
    # Bound is holdout_end (2026-04-30), NOT test_end (2023-12-31): this is a
    # descriptive breakdown that spans Testing and Holdout on purpose, and
    # Holdout is observed-not-sealed per backtest-partitions.md. Validation is
    # the only line that must not be crossed. Bounding at test_end would
    # amputate two years of legitimate data.
    #
    # Do NOT add rsc_subperiod to S11_METRICS_REGISTRY (R/plan_qa_gates.R).
    # S11 asserts window_end <= test_end; this target's window legitimately
    # runs to holdout_end, so registering it would make the gate reject a
    # correct target. Its bespoke date-range labels are also outside the
    # canonical vocabulary S11's exempt_periods list assumes. Different shape,
    # deliberately unregistered.
    targets::tar_target(rsc_subperiod, {
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

      # #673: inclusive [start, end] slice whose label is DERIVED from its own
      # bounds, so the label cannot drift out of sync with the window when
      # partition dates move (the "2020-2026" string was previously hardcoded
      # next to a window that is now parameterised by holdout_end).
      slice_years <- function(data, start, end) {
        start <- as.Date(start)
        end   <- as.Date(end)
        calc_sp(
          data |> filter(as.Date(date) >= start, as.Date(date) <= end),
          paste0(format(start, "%Y"), "-", format(end, "%Y"))
        )
      }

      dplyr::bind_rows(
        slice_years(port, "2009-01-01", "2014-12-31"),
        slice_years(port, "2015-01-01", "2019-12-31"),
        slice_years(port, "2020-01-01", rsc_params$holdout_end),
        calc_sp(port, "Full Period")
      )
    }),

    # ── Registry sentinel (#442 Tier 1) ─────────────────────────────────────
    # Upserts bt.strategy row for "rsc", records one bt.run + bt.metric rows
    # (SPY_overlay / Full Period slice of rsc_metrics).
    # Returns tibble(strategy_id, run_uuid).
    # Guard: returns empty tibble if DBI / duckdb are unavailable.
    targets::tar_target(rsc_register_runs, {
      .rsc_register_runs(
        strategy_names = strategy_names,
        rsc_metrics    = rsc_metrics,
        rsc_portfolio  = rsc_portfolio
      )
    })

  )
}


# ── Internal helper ────────────────────────────────────────────────────────────
# Prefixed .rsc_* (private; not exported from the package).
# Mirrors .mom_prepeak_register_runs() from plan_mom_prepeak.R.

#' Register Risk State (VIX Overlay) backtest run in the strategy registry
#'
#' @param strategy_names Tibble from the `strategy_names` target.
#' @param rsc_metrics Tibble from the `rsc_metrics` target. The SPY_overlay /
#'   Full Period row is used for the bt.metric insert.
#' @param rsc_portfolio Tibble from the `rsc_portfolio` target; used to
#'   extract daily returns for SSR/top5pct stability metrics.
#'
#' @return Tibble with columns: strategy_id, run_uuid.
#' @noRd
.rsc_register_runs <- function(strategy_names, rsc_metrics, rsc_portfolio) {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("duckdb", quietly = TRUE)) {
    return(tibble::tibble(
      strategy_id = character(),
      run_uuid    = character()
    ))
  }

  path <- historicaldata::hd_registry_path()
  historicaldata::hd_registry_init(path)
  con <- historicaldata::hd_registry_open(path, read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  strat_row <- strategy_names |>
    dplyr::filter(.data$code_name == "rsc") |>
    dplyr::transmute(
      strategy_id        = .data$code_name,
      short_name         = .data$short_name,
      long_name          = .data$long_name,
      asset_class        = .data$asset_class,
      frequency          = .data$frequency,
      ann_factor         = as.integer(.data$ann_factor),
      directionality     = as.character(.data$directionality),
      liquidity_tier     = as.character(.data$liquidity_tier),
      time_horizon_days  = as.integer(.data$time_horizon_days_avg),
      trades_per_year    = as.numeric(.data$trades_per_year_avg),
      turnover_pct       = as.numeric(.data$turnover_pct_per_period_avg),
      tags               = .data$tags,
      research_paper_doi = .data$research_paper_doi
    )

  historicaldata::hd_strategy_upsert(con, strat_row)

  uu <- historicaldata::hd_run_upsert(
    con,
    strategy_id      = "rsc",
    partition        = "phase1",
    pipeline_version = "phase1"
  )

  # Record SPY_overlay / Full Period metrics row (the primary RSC result)
  # Units (#640): rsc_metrics stores cagr/vol/max_dd as PERCENT
  # (round(x*100, ...) in calc_metrics() above); sharpe/hac_tstat/hac_sharpe
  # are scale-free ratios (#677: `sharpe` is the new canonical,
  # risk-free-adjusted column added alongside the pre-existing `hac_sharpe`
  # -- both need a unit or hd_metric_record() aborts loud per #640).
  full_row <- rsc_metrics[
    rsc_metrics$strategy == "SPY_overlay" & rsc_metrics$period == "Full Period",
    , drop = FALSE
  ]
  if (nrow(full_row) == 1L) {
    metric_cols <- setdiff(names(full_row), c("strategy", "period"))
    rsc_units <- c(
      cagr = "percent", vol = "percent", max_dd = "percent",
      sharpe = "ratio", hac_tstat = "ratio", hac_sharpe = "ratio"
    )
    historicaldata::hd_metric_record(
      con, uu, full_row[, metric_cols, drop = FALSE], units = rsc_units
    )
  }

  # Record SSR + top5pct stability metrics (#400). Daily: w=252, ann_factor=252.
  rets <- rsc_portfolio$ret_strategy
  rets <- rets[!is.na(rets)]
  if (length(rets) > 0L) {
    historicaldata::hd_record_stability_metrics(
      con        = con,
      run_uuid   = uu,
      returns    = rets,
      w          = 252L,
      ann_factor = 252L
    )
  }

  tibble::tibble(strategy_id = "rsc", run_uuid = uu)
}
