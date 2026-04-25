# Plan: Falsification Vignette Targets
#
# Pre-computed plots, tables, and captions for docs/falsification.qmd.
# Depends on plan_falsification.R targets (fals_summary, fals_keff, etc.).

plan_falsification_vignette <- function() {
  list(

    # ── Scorecard table ──────────────────────────────────────────────
    targets::tar_target(fals_vig_scorecard, {
      library(dplyr)

      summary <- fals_summary
      summary |>
        dplyr::mutate(
          Strategy = c(
            "Avoid Worst Days (VIX)", "DRIF (Factor Rotation)",
            "Factor MAX (Momentum)", "Risk State (VIX Overlay)",
            "LTR (CS Momentum)"
          ),
          `HAC t` = round(hac_tstat, 2),
          `Naive Sharpe` = round(hac_sharpe, 2),
          `FF Alpha (ann)` = paste0(round(ff_alpha_annual * 100, 2), "%"),
          `FF Alpha t` = round(ff_alpha_tstat, 2),
          `FF R²` = paste0(round(ff_r_squared * 100, 1), "%"),
          Verdict = dplyr::case_when(
            ff_alpha_tstat > 2.0 & ff_r_squared < 0.15 ~ "Genuine alpha",
            ff_alpha_tstat > 1.96 ~ "Borderline",
            TRUE ~ "No alpha (beta)"
          )
        ) |>
        dplyr::select(Strategy, `HAC t`, `Naive Sharpe`,
                       `FF Alpha (ann)`, `FF Alpha t`, `FF R²`, Verdict)
    }),

    targets::tar_target(fals_vig_scorecard_caption, {
      summary <- fals_summary
      n_alpha <- sum(summary$ff_alpha_tstat > 2.0)
      n_beta  <- sum(summary$ff_alpha_tstat <= 1.96)
      best    <- summary$strategy[which.max(summary$ff_alpha_tstat)]
      best_t  <- round(max(summary$ff_alpha_tstat), 2)

      paste0(
        "Strategy falsification scorecard. ",
        n_alpha, " of ", nrow(summary),
        " strategies show genuine alpha (FF5+Mom alpha t > 2.0); ",
        n_beta, " are explained by factor exposure. ",
        "Best: ", best, " (t = ", best_t, "). ",
        "HAC t-statistics use Newey-West correction. ",
        "Source: plan_falsification.R, M = ",
        fals_params$M, " null simulations per environment."
      )
    }),


    # ── Null rejection rate heatmap ──────────────────────────────────
    targets::tar_target(fals_vig_null_heatmap, {
      library(dplyr)
      library(tidyr)
      library(ggplot2)

      summary <- fals_summary

      rej_long <- summary |>
        dplyr::select(strategy, starts_with("rej_rate_")) |>
        tidyr::pivot_longer(-strategy, names_to = "null_env", values_to = "rejection_rate") |>
        dplyr::mutate(
          null_env = gsub("rej_rate_", "", null_env),
          null_env = factor(null_env,
            levels = c("wn", "rv", "ma1", "fn", "garch", "gjr"),
            labels = c("White Noise", "Regime Vol", "MA(1)", "Factor Null",
                       "GARCH(1,1)", "GJR-GARCH")
          ),
          strategy = factor(strategy,
            levels = c("avoid_worst", "drif", "fac_max", "rsc", "ltr"),
            labels = c("Avoid Worst", "DRIF", "Factor MAX", "RSC Overlay", "LTR")
          ),
          pct = rejection_rate * 100
        )

      ggplot(rej_long, aes(x = null_env, y = strategy, fill = pct)) +
        geom_tile(color = "#333") +
        geom_text(aes(label = paste0(round(pct, 0), "%")),
                  color = "white", size = 4.5, fontface = "bold") +
        scale_fill_gradient2(
          low = "#1a9850", mid = "#fee08b", high = "#d73027",
          midpoint = 8, limits = c(0, 100),
          name = "Rejection %"
        ) +
        labs(
          title = "Null Environment Rejection Rates",
          subtitle = "Green (low) = strategy replicable under null. Red (high) = genuine signal.",
          x = "Null Environment", y = NULL
        ) +
        theme_minimal(base_size = 14) +
        theme(
          plot.background = element_rect(fill = "black", color = NA),
          panel.background = element_rect(fill = "black", color = NA),
          text = element_text(color = "#e0e0e0"),
          axis.text = element_text(color = "#e0e0e0"),
          axis.text.x = element_text(angle = 30, hjust = 1),
          legend.position = "right",
          legend.background = element_rect(fill = "black"),
          legend.text = element_text(color = "#e0e0e0"),
          panel.grid = element_blank()
        )
    }),

    targets::tar_target(fals_vig_null_heatmap_caption, {
      summary <- fals_summary
      max_rej <- max(unlist(summary[, grep("rej_rate_", names(summary))]))
      min_rej <- min(unlist(summary[, grep("rej_rate_", names(summary))]))

      paste0(
        "Rejection rates across 6 null environments (M = ",
        fals_params$M, " simulations each). ",
        "A low rate (<8%) means the strategy's t-statistic is easily replicated under ",
        "the null — no genuine signal. A high rate means the null cannot explain the returns. ",
        "Range: ", round(min_rej * 100, 0), "%-", round(max_rej * 100, 0), "%. ",
        "Null environments: White Noise (iid), Regime Vol (high/low vol switching), ",
        "MA(1) (autocorrelation friction), Factor Null (random factor exposure), ",
        "GARCH(1,1) (volatility clustering), GJR-GARCH (asymmetric leverage). ",
        "Source: hd_null_rejection_rate(), alpha = ",
        fals_params$alpha_level, "."
      )
    }),


    # ── Null rejection rate table ────────────────────────────────────
    targets::tar_target(fals_vig_null_table, {
      library(dplyr)

      summary <- fals_summary
      summary |>
        dplyr::mutate(
          Strategy = c("Avoid Worst", "DRIF", "Factor MAX", "RSC Overlay", "LTR"),
          `White Noise` = paste0(round(rej_rate_wn * 100, 0), "%"),
          `Regime Vol` = paste0(round(rej_rate_rv * 100, 0), "%"),
          `MA(1)` = paste0(round(rej_rate_ma1 * 100, 0), "%"),
          `Factor` = paste0(round(rej_rate_fn * 100, 0), "%"),
          `GARCH` = paste0(round(rej_rate_garch * 100, 0), "%"),
          `GJR` = paste0(round(rej_rate_gjr * 100, 0), "%")
        ) |>
        dplyr::select(Strategy, `White Noise`, `Regime Vol`, `MA(1)`,
                       Factor, GARCH, GJR)
    }),


    # ── HAC vs Naive comparison ──────────────────────────────────────
    targets::tar_target(fals_vig_hac_comparison, {
      library(dplyr)

      hac_results <- list(
        fals_hac_avoid_worst, fals_hac_drif, fals_hac_fac_max,
        fals_hac_rsc, fals_hac_ltr
      )
      names_vec <- c("Avoid Worst", "DRIF", "Factor MAX", "RSC Overlay", "LTR")

      # Naive t-stat = naive_sharpe * sqrt(T / ann_factor)
      ann_factors <- c(252, 12, 12, 252, 12)
      naive_t <- sapply(seq_along(hac_results), function(i) {
        hac_results[[i]]$naive_sharpe * sqrt(hac_results[[i]]$T / ann_factors[i])
      })

      tibble::tibble(
        Strategy = names_vec,
        `Naive Sharpe` = round(sapply(hac_results, `[[`, "naive_sharpe"), 3),
        `Ann Mean` = paste0(round(sapply(hac_results, `[[`, "annualised_mean") * 100, 2), "%"),
        `Ann Vol` = paste0(round(sapply(hac_results, `[[`, "annualised_vol") * 100, 2), "%"),
        `Naive t` = round(naive_t, 2),
        `HAC t` = round(sapply(hac_results, `[[`, "hac_tstat"), 2),
        `NW Lag` = as.integer(sapply(hac_results, `[[`, "lag_nw")),
        `T (obs)` = as.integer(sapply(hac_results, `[[`, "T"))
      )
    }),

    targets::tar_target(fals_vig_hac_caption, {
      hac_results <- list(
        fals_hac_avoid_worst, fals_hac_drif, fals_hac_fac_max,
        fals_hac_rsc, fals_hac_ltr
      )
      avg_lag <- round(mean(sapply(hac_results, `[[`, "lag_nw")), 1)

      paste0(
        "Strategy performance with Newey-West HAC correction. ",
        "Naive Sharpe assumes iid returns; HAC t-stat corrects for ",
        "serial correlation (GARCH persistence). ",
        "NW Lag = Newey-West bandwidth (Bartlett kernel, auto: ",
        "floor(4*(T/100)^(2/9))). Average lag: ", avg_lag, ". ",
        "HAC t > 2.0 indicates robust risk-adjusted returns after ",
        "accounting for volatility clustering. ",
        "Source: hd_hac_sharpe()."
      )
    }),


    # ── Factor regression details ────────────────────────────────────
    targets::tar_target(fals_vig_ff_table, {
      library(dplyr)

      ff_results <- list(
        fals_ff_avoid_worst, fals_ff_drif, fals_ff_fac_max,
        fals_ff_rsc, fals_ff_ltr
      )
      names_vec <- c("Avoid Worst", "DRIF", "Factor MAX", "RSC Overlay", "LTR")

      # Extract betas for each factor
      factor_names <- c("Mkt_RF", "SMB", "HML", "RMW", "CMA", "Mom")

      rows <- lapply(seq_along(ff_results), function(i) {
        ff <- ff_results[[i]]
        betas <- setNames(
          sapply(paste0("beta_", factor_names), function(b) {
            if (b %in% names(ff)) round(ff[[b]][[1]], 3) else NA_real_
          }),
          factor_names
        )
        tibble::tibble(
          Strategy = names_vec[i],
          `Alpha (ann %)` = round(ff$alpha_annual * 100, 2),
          `Alpha t` = round(ff$alpha_tstat_hac, 2),
          `R²` = round(ff$r_squared * 100, 1),
          `Mkt-RF` = betas["Mkt_RF"],
          SMB = betas["SMB"],
          HML = betas["HML"],
          RMW = betas["RMW"],
          CMA = betas["CMA"],
          Mom = betas["Mom"]
        )
      })
      dplyr::bind_rows(rows)
    }),

    targets::tar_target(fals_vig_ff_caption, {
      ff_results <- list(
        fals_ff_avoid_worst, fals_ff_drif, fals_ff_fac_max,
        fals_ff_rsc, fals_ff_ltr
      )
      names_vec <- c("Avoid Worst", "DRIF", "Factor MAX", "RSC Overlay", "LTR")

      # Find highest R² strategy
      r2_vals <- sapply(ff_results, `[[`, "r_squared")
      highest_r2_idx <- which.max(r2_vals)
      highest_r2_name <- names_vec[highest_r2_idx]
      highest_r2_pct <- round(r2_vals[highest_r2_idx] * 100, 1)

      # Find best alpha
      alpha_t <- sapply(ff_results, `[[`, "alpha_tstat_hac")
      best_alpha_idx <- which.max(alpha_t)
      best_alpha_name <- names_vec[best_alpha_idx]
      best_alpha_t <- round(alpha_t[best_alpha_idx], 2)

      paste0(
        "Fama-French 5-Factor + Momentum regression (r_excess = alpha + sum(beta_k * F_k) + epsilon). ",
        "Alpha is annualised; t-statistic uses HAC standard errors. ",
        "R-squared measures how much of the strategy's variance is explained by known factors. ",
        "High R-squared (>20%) with low alpha t = disguised beta. ",
        "Low R-squared (<10%) with high alpha t = genuine alpha. ",
        highest_r2_name, " has the highest factor exposure (R² = ", highest_r2_pct, "%). ",
        best_alpha_name, " has the strongest alpha (t = ", best_alpha_t, "). ",
        "Source: hd_factor_null_test(), daily factor data from Ken French Data Library."
      )
    }),


    # ── K_eff and Delta-Z ────────────────────────────────────────────
    targets::tar_target(fals_vig_multiplicity, {
      harvey_t <- round(sqrt(2 * log(fals_keff$K_eff)), 2)

      tibble::tibble(
        Metric = c(
          "K (strategies tested)", "K_eff (independent strategies)",
          "Independence ratio (K_eff/K)",
          "Best IS t-stat", "Best OOS t-stat",
          "Delta-Z (IS-OOS gap)",
          "Harvey threshold (sqrt(2*log(K_eff)))"
        ),
        Value = as.character(c(
          5,
          round(fals_keff$K_eff, 2),
          round(fals_keff$K_eff / 5, 2),
          round(fals_delta_z$z_star_is, 2),
          round(fals_delta_z$z_star_oos, 2),
          round(fals_delta_z$delta_z, 2),
          harvey_t
        ))
      )
    }),

    targets::tar_target(fals_vig_multiplicity_caption, {
      keff <- round(fals_keff$K_eff, 2)
      dz   <- round(fals_delta_z$delta_z, 2)
      harvey_t <- round(sqrt(2 * log(fals_keff$K_eff)), 2)

      paste0(
        "Multiple testing adjustment. K_eff = ", keff,
        " (spectral participation ratio from pairwise correlation matrix) ",
        "measures how many truly independent strategies exist among the 5 tested. ",
        "Delta-Z = ", dz, " measures the gap between the best in-sample and best ",
        "out-of-sample t-statistics. ",
        "Harvey et al. (2016) threshold = sqrt(2*log(K_eff)) = ", harvey_t,
        ". A strategy's t-stat must exceed this to survive multiplicity correction. ",
        "Source: hd_keff(), hd_delta_z()."
      )
    }),


    # ── HAC bar chart ────────────────────────────────────────────────
    targets::tar_target(fals_vig_hac_plot, {
      library(ggplot2)

      hac_results <- list(
        fals_hac_avoid_worst, fals_hac_drif, fals_hac_fac_max,
        fals_hac_rsc, fals_hac_ltr
      )

      # Compute naive t-stats for comparison
      ann_factors <- c(252, 12, 12, 252, 12)
      strat_names <- c("Avoid Worst", "DRIF", "Factor MAX", "RSC Overlay", "LTR")

      naive_t <- sapply(seq_along(hac_results), function(i) {
        hac_results[[i]]$naive_sharpe * sqrt(hac_results[[i]]$T / ann_factors[i])
      })
      hac_t <- sapply(hac_results, `[[`, "hac_tstat")

      df_long <- data.frame(
        strategy = factor(rep(strat_names, 2), levels = strat_names),
        type = rep(c("Naive t", "HAC t"), each = 5),
        t_stat = c(naive_t, hac_t)
      )

      ggplot(df_long, aes(x = strategy, y = t_stat, fill = type)) +
        geom_col(position = "dodge", width = 0.7) +
        geom_hline(yintercept = 2.0, color = "#e74c3c", linetype = "dashed",
                   linewidth = 0.8) +
        geom_hline(yintercept = 0, color = "#666", linewidth = 0.5) +
        annotate("text", x = 0.5, y = 2.2, label = "t = 2.0 threshold",
                 color = "#e74c3c", hjust = 0, size = 3.5) +
        scale_fill_manual(values = c("Naive t" = "#4a90d9", "HAC t" = "#2ecc71")) +
        labs(
          title = "Naive vs HAC t-Statistics",
          subtitle = "HAC correction accounts for GARCH persistence in returns",
          x = NULL, y = "t-statistic", fill = NULL
        ) +
        theme_minimal(base_size = 14) +
        theme(
          plot.background = element_rect(fill = "black", color = NA),
          panel.background = element_rect(fill = "black", color = NA),
          text = element_text(color = "#e0e0e0"),
          axis.text = element_text(color = "#e0e0e0"),
          axis.text.x = element_text(angle = 20, hjust = 1),
          legend.position = "top",
          legend.background = element_rect(fill = "black"),
          legend.text = element_text(color = "#e0e0e0"),
          panel.grid.major.y = element_line(color = "#333"),
          panel.grid.minor = element_blank(),
          panel.grid.major.x = element_blank()
        )
    }),


    # ── FF alpha bar chart ───────────────────────────────────────────
    targets::tar_target(fals_vig_ff_alpha_plot, {
      library(ggplot2)

      ff_results <- list(
        fals_ff_avoid_worst, fals_ff_drif, fals_ff_fac_max,
        fals_ff_rsc, fals_ff_ltr
      )

      df <- data.frame(
        strategy = factor(
          c("Avoid Worst", "DRIF", "Factor MAX", "RSC Overlay", "LTR"),
          levels = c("Avoid Worst", "DRIF", "Factor MAX", "RSC Overlay", "LTR")
        ),
        alpha_annual = sapply(ff_results, `[[`, "alpha_annual") * 100,
        alpha_t      = sapply(ff_results, `[[`, "alpha_tstat_hac"),
        r_squared    = sapply(ff_results, `[[`, "r_squared") * 100
      )

      df$verdict <- ifelse(df$alpha_t > 2.0, "Alpha", "Beta")

      ggplot(df, aes(x = r_squared, y = alpha_annual, color = verdict)) +
        geom_point(size = 6) +
        geom_text(aes(label = strategy), vjust = -1.2, size = 4, color = "#e0e0e0") +
        geom_hline(yintercept = 0, color = "#666", linetype = "dashed") +
        geom_vline(xintercept = 15, color = "#666", linetype = "dashed") +
        scale_color_manual(values = c("Alpha" = "#2ecc71", "Beta" = "#e74c3c")) +
        scale_x_continuous(labels = function(x) paste0(x, "%")) +
        scale_y_continuous(labels = function(x) paste0(x, "%")) +
        labs(
          title = "Alpha vs Factor Exposure",
          subtitle = "Genuine alpha = top-left (low R², positive alpha). Beta = right (high R²).",
          x = "FF5+Mom R² (factor exposure)", y = "Annualised Alpha",
          color = "Verdict"
        ) +
        theme_minimal(base_size = 14) +
        theme(
          plot.background = element_rect(fill = "black", color = NA),
          panel.background = element_rect(fill = "black", color = NA),
          text = element_text(color = "#e0e0e0"),
          axis.text = element_text(color = "#e0e0e0"),
          legend.position = "top",
          legend.background = element_rect(fill = "black"),
          legend.text = element_text(color = "#e0e0e0"),
          panel.grid.major = element_line(color = "#333"),
          panel.grid.minor = element_blank()
        )
    })

  )
}
