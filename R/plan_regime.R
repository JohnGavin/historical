# Regime-aware portfolio reweighting (#34)
#
# Classifies each month as low/medium/high risk based on realised vol
# (or VIX if available in consolidated_macro), then scales strategy
# exposure down in high-risk regimes.
#
# Consumes: port_returns, port_optimal_weights, stk_rf, stk_params
# Produces: regime_params, regime_vol, regime_classification,
#           regime_weights, regime_portfolio, regime_metrics, regime_plot

plan_regime <- function() {
  list(
    # ── Parameters ────────────────────────────────────────────────
    targets::tar_target(regime_params, {
      list(
        vol_window     = 12L,            # rolling months for realised vol
        q_low          = 0.33,           # quantile boundary low/med
        q_high         = 0.80,           # quantile boundary med/high
        scale_low      = 1.0,            # full exposure in low-risk
        scale_medium   = 0.7,            # reduced in medium-risk
        scale_high     = 0.4             # minimal in high-risk
      )
    }),

    # ── Rolling realised volatility of the combined portfolio ─────
    targets::tar_target(regime_vol, {
      library(dplyr)

      strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif")
      w <- port_optimal_weights

      # Compute weighted portfolio return for each month
      ret_matrix <- as.matrix(port_returns[, strat_cols])
      combined_ret <- as.numeric(ret_matrix %*% w)

      vol_df <- port_returns |>
        mutate(combined_ret = combined_ret) |>
        arrange(date) |>
        mutate(
          # Rolling 12-month SD annualised
          roll_vol = zoo::rollapply(
            combined_ret,
            width = regime_params$vol_window,
            FUN   = function(x) sd(x, na.rm = TRUE) * sqrt(12),
            fill  = NA,
            align = "right"
          )
        ) |>
        select(ym, date, combined_ret, roll_vol)

      # Try to augment with VIX if available
      vix_available <- tryCatch({
        "VIXCLS" %in% names(consolidated_macro) ||
          (is.data.frame(consolidated_macro) &&
             "series_id" %in% names(consolidated_macro) &&
             "VIXCLS" %in% consolidated_macro$series_id)
      }, error = function(e) FALSE)

      if (vix_available) {
        vix_monthly <- tryCatch({
          if ("VIXCLS" %in% names(consolidated_macro)) {
            # Wide format
            consolidated_macro |>
              select(ym = any_of(c("ym", "date")), vix = VIXCLS) |>
              mutate(ym = if (inherits(ym, "Date")) format(ym, "%Y-%m") else as.character(ym))
          } else {
            # Long format with series_id column
            consolidated_macro |>
              filter(series_id == "VIXCLS") |>
              mutate(ym = format(date, "%Y-%m")) |>
              group_by(ym) |>
              summarise(vix = mean(value, na.rm = TRUE), .groups = "drop")
          }
        }, error = function(e) NULL)

        if (!is.null(vix_monthly) && nrow(vix_monthly) > 0) {
          vol_df <- vol_df |>
            left_join(vix_monthly, by = "ym") |>
            # Normalise VIX to annualised vol scale (VIX is already annualised %)
            mutate(
              vix_vol = vix / 100,
              # Use VIX where available, otherwise fall back to realised vol
              risk_signal = dplyr::coalesce(vix_vol, roll_vol)
            )
        } else {
          vol_df <- vol_df |> mutate(risk_signal = roll_vol)
        }
      } else {
        vol_df <- vol_df |> mutate(risk_signal = roll_vol)
      }

      vol_df
    }),

    # ── Classify months as low/medium/high risk ───────────────────
    targets::tar_target(regime_classification, {
      library(dplyr)

      # Use TRAINING-period quantiles to avoid look-ahead bias
      train_signal <- regime_vol |>
        filter(date <= stk_params$is_end, !is.na(risk_signal)) |>
        pull(risk_signal)

      if (length(train_signal) < 12) {
        cli::cli_warn("Fewer than 12 training months for regime classification — using full-period quantiles")
        train_signal <- regime_vol |> filter(!is.na(risk_signal)) |> pull(risk_signal)
      }

      q_low  <- quantile(train_signal, probs = regime_params$q_low,  na.rm = TRUE)
      q_high <- quantile(train_signal, probs = regime_params$q_high, na.rm = TRUE)

      regime_vol |>
        mutate(
          regime = dplyr::case_when(
            is.na(risk_signal)        ~ NA_character_,
            risk_signal <= q_low      ~ "low_risk",
            risk_signal <= q_high     ~ "medium_risk",
            TRUE                      ~ "high_risk"
          ),
          regime = factor(regime, levels = c("low_risk", "medium_risk", "high_risk")),
          q_low_threshold  = q_low,
          q_high_threshold = q_high
        )
    }),

    # ── Exposure multipliers per month ────────────────────────────
    targets::tar_target(regime_weights, {
      library(dplyr)

      regime_classification |>
        mutate(
          exposure = dplyr::case_when(
            regime == "low_risk"    ~ regime_params$scale_low,
            regime == "medium_risk" ~ regime_params$scale_medium,
            regime == "high_risk"   ~ regime_params$scale_high,
            TRUE                    ~ 1.0   # NA regime: full exposure
          )
        ) |>
        select(ym, date, regime, risk_signal, exposure)
    }),

    # ── Regime-adjusted portfolio returns ─────────────────────────
    targets::tar_target(regime_portfolio, {
      library(dplyr)

      strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif")
      w <- port_optimal_weights

      # Base weighted portfolio return
      ret_matrix <- as.matrix(port_returns[, strat_cols])
      base_ret   <- as.numeric(ret_matrix %*% w)

      port_with_base <- port_returns |>
        mutate(base_ret = base_ret) |>
        left_join(regime_weights |> select(ym, regime, exposure), by = "ym") |>
        mutate(
          # Scale risky exposure; remainder sits in cash (rf_ret)
          exposure     = dplyr::coalesce(exposure, 1.0),
          regime_ret   = exposure * base_ret + (1 - exposure) * rf_ret,
          # Cumulative growth
          base_cum     = cumprod(1 + base_ret),
          regime_cum   = cumprod(1 + regime_ret)
        )

      port_with_base
    }),

    # ── Regime metrics per period ─────────────────────────────────
    targets::tar_target(regime_metrics, {
      library(dplyr)

      calc_regime_metrics <- function(df, label) {
        # Drop rows with NA returns
        df <- df |> filter(!is.na(regime_ret), !is.na(base_ret))
        n <- nrow(df)
        if (n < 12) return(NULL)

        calc_one <- function(ret_col, name_prefix) {
          r  <- df[[ret_col]]
          rf <- if ("rf_ret" %in% names(df)) df$rf_ret else rep(0, n)
          rf[is.na(rf)] <- 0
          ann_ret  <- prod(1 + r)^(12/n) - 1
          ann_vol  <- sd(r) * sqrt(12)
          rf_ann   <- mean(rf, na.rm = TRUE) * 12
          sharpe   <- if (ann_vol < 1e-8) NA_real_ else (ann_ret - rf_ann) / ann_vol
          cum      <- cumprod(1 + r)
          max_dd   <- min(cum / cummax(cum) - 1)
          tibble(
            period   = label,
            strategy = name_prefix,
            months   = n,
            cagr     = ann_ret,
            vol      = ann_vol,
            sharpe   = sharpe,
            max_dd   = max_dd
          )
        }

        bind_rows(
          calc_one("regime_ret", "Regime-Adjusted"),
          calc_one("base_ret",   "Base Portfolio")
        )
      }

      bind_rows(
        calc_regime_metrics(regime_portfolio |> filter(date <= stk_params$is_end), "Training"),
        calc_regime_metrics(regime_portfolio |> filter(date >= stk_params$test_start, date <= stk_params$test_end), "Testing"),
        calc_regime_metrics(regime_portfolio, "Full Period")
      )
    }),

    # ── Cumulative return plot with shaded regime bands ───────────
    targets::tar_target(regime_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)

      # Build shading rectangles for high-risk periods
      high_risk_periods <- regime_portfolio |>
        filter(!is.na(regime), regime == "high_risk") |>
        arrange(date) |>
        mutate(
          grp = cumsum(c(1, diff(as.numeric(date)) > 45))
        ) |>
        group_by(grp) |>
        summarise(xmin = min(date), xmax = max(date), .groups = "drop")

      plot_data <- regime_portfolio |>
        select(
          date,
          `Regime-Adjusted` = regime_cum,
          `Base Portfolio`  = base_cum
        ) |>
        tidyr::pivot_longer(-date, names_to = "strategy", values_to = "growth")

      p <- ggplot(plot_data, aes(date, growth, colour = strategy)) +
        geom_line(linewidth = 0.6)

      # Add high-risk shading if any periods exist
      if (nrow(high_risk_periods) > 0) {
        p <- p +
          geom_rect(
            data    = high_risk_periods,
            inherit.aes = FALSE,
            aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
            fill    = "#e74c3c",
            alpha   = 0.12
          )
      }

      p +
        geom_vline(xintercept = stk_params$oos_start, linetype = "dashed",
                   colour = "grey50", linewidth = 0.4) +
        annotate("text", x = stk_params$oos_start,
                 y = max(plot_data$growth, na.rm = TRUE) * 0.92,
                 label = "OOS", colour = "grey60", hjust = -0.1, size = 3) +
        scale_y_log10(labels = dollar) +
        scale_colour_manual(values = hd_palette(2)) +
        labs(
          x        = NULL,
          y        = "Growth of $1 (log scale)",
          colour   = NULL,
          title    = "Regime-Aware Portfolio (shaded = high-risk months)",
          subtitle = paste0(
            "Scale: low=", regime_params$scale_low,
            " / med=",    regime_params$scale_medium,
            " / high=",   regime_params$scale_high
          )
        ) +
        hd_theme()
    })
  )
}
