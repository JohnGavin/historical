# Plan: Falsification Vignette Targets
#
# Pre-computed plots, tables, and captions for docs/falsification.qmd.
# Depends on plan_falsification.R targets (fals_summary, fals_keff, etc.).
#
# Strategy names: single source of truth via fals_vig_names target.
# All tables/plots/captions reference this target for consistent naming.

plan_falsification_vignette <- function() {

  # GH repo base URL for source links
  gh_base <- "https://github.com/JohnGavin/historical/blob/main"

  list(

    # ── Strategy names: filtered view of unified strategy_names target ──
    targets::tar_target(fals_vig_names, {
      strategy_names |>
        dplyr::filter(
          code_name %in% c("avoid_worst", "drif", "fac_max", "rsc", "ltr")
        )
    }),


    # ── Scorecard table ──────────────────────────────────────────────
    targets::tar_target(fals_vig_scorecard, {
      library(dplyr)

      nms <- fals_vig_names
      summary <- fals_summary

      summary |>
        dplyr::mutate(
          Verdict = factor(
            dplyr::case_when(
              ff_alpha_tstat > 2.0 & ff_r_squared < 0.15 ~ "Genuine alpha",
              ff_alpha_tstat > 1.96 ~ "Borderline",
              TRUE ~ "No alpha (beta)"
            ),
            levels = c("Genuine alpha", "Borderline", "No alpha (beta)"),
            ordered = TRUE
          ),
          Strategy = nms$long_name,
          `HAC t` = round(hac_tstat, 2),
          `Naive Sharpe` = round(hac_sharpe, 2),
          `Alpha (%)` = round(ff_alpha_annual * 100, 0),
          `Alpha t` = round(ff_alpha_tstat, 2),
          `R² (%)` = round(ff_r_squared * 100, 1)
        ) |>
        dplyr::arrange(Verdict) |>
        dplyr::select(Verdict, Strategy, `HAC t`, `Naive Sharpe`,
                       `Alpha (%)`, `Alpha t`, `R² (%)`)
    }),

    targets::tar_target(fals_vig_scorecard_caption, {
      nms <- fals_vig_names
      summary <- fals_summary

      alpha_mask <- summary$ff_alpha_tstat > 2.0 & summary$ff_r_squared < 0.15
      alpha_names <- nms$long_name[alpha_mask]
      border_mask <- summary$ff_alpha_tstat > 1.96 & !alpha_mask
      border_names <- nms$long_name[border_mask]
      beta_names <- nms$long_name[!alpha_mask & !border_mask]

      gh <- "https://github.com/JohnGavin/historical/blob/main"

      parts <- c(
        "Strategy falsification scorecard. ",
        paste0(paste(alpha_names, collapse = " and "),
               " show genuine alpha (Alpha t > 2.0, R² < 15%). "),
        if (length(border_names) > 0) paste0(
          paste(border_names, collapse = " and "), " are borderline. "
        ) else NULL,
        if (length(beta_names) > 0) paste0(
          paste(beta_names, collapse = " and "),
          " are explained by factor exposure (no alpha). "
        ) else NULL,
        "Columns: HAC t = Newey-West corrected t-statistic; ",
        "Alpha (%) = annualised Fama-French 5-factor + Momentum intercept; ",
        "Alpha t = HAC t-statistic on the alpha; ",
        "R² (%) = variance explained by known factors. ",
        "Source: [plan_falsification.R](", gh, "/R/plan_falsification.R), ",
        "M = ", fals_params$M, " null simulations per environment."
      )
      paste0(parts, collapse = "")
    }),


    # ── Null rejection rate heatmap ──────────────────────────────────
    targets::tar_target(fals_vig_null_heatmap, {
      library(dplyr)
      library(tidyr)
      library(ggplot2)

      nms <- fals_vig_names
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
            levels = nms$code_name,
            labels = nms$short_name
          ),
          pct = rejection_rate * 100
        )

      # Text colour: black on light fills, white on dark fills
      rej_long$text_col <- ifelse(rej_long$pct > 4 & rej_long$pct < 15,
                                   "#000000", "#ffffff")

      ggplot(rej_long, aes(x = null_env, y = strategy, fill = pct)) +
        geom_tile(color = "#333") +
        geom_text(aes(label = round(pct, 0), colour = text_col),
                  size = 4.5, fontface = "bold", show.legend = FALSE) +
        scale_colour_identity() +
        scale_fill_gradient2(
          low = "#1a9850", mid = "#ffffbf", high = "#d73027",
          midpoint = 8, limits = c(0, 100),
          name = "Rejection (%)"
        ) +
        labs(
          title = "Null Environment Rejection Rates",
          subtitle = "Green (low) = replicable under null. Red (high) = genuine signal.",
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

      gh <- "https://github.com/JohnGavin/historical/blob/main"

      paste0(
        "Rejection rates across 6 null environments (M = ",
        fals_params$M, " simulations each). ",
        "Values show rejection rate (%). ",
        "A low rate (<8%) means the strategy's t-statistic is easily replicated under ",
        "the null. A high rate means the null cannot explain the returns. ",
        "Range: ", round(min_rej * 100, 0), "%-", round(max_rej * 100, 0), "%. ",
        "Null environments: White Noise (iid), Regime Vol (high/low vol switching), ",
        "MA(1) (autocorrelation friction), Factor Null (random factor exposure), ",
        "GARCH(1,1) (volatility clustering), GJR-GARCH (asymmetric leverage). ",
        "Source: [hd_null_rejection_rate()](", gh,
        "/packages/historicaldata/R/falsification.R), alpha = ",
        fals_params$alpha_level, "."
      )
    }),


    # ── Null rejection rate table ────────────────────────────────────
    targets::tar_target(fals_vig_null_table, {
      library(dplyr)

      nms <- fals_vig_names
      summary <- fals_summary
      summary |>
        dplyr::mutate(
          Strategy = nms$long_name,
          `White Noise (%)` = round(rej_rate_wn * 100, 0),
          `Regime Vol (%)` = round(rej_rate_rv * 100, 0),
          `MA(1) (%)` = round(rej_rate_ma1 * 100, 0),
          `Factor (%)` = round(rej_rate_fn * 100, 0),
          `GARCH (%)` = round(rej_rate_garch * 100, 0),
          `GJR (%)` = round(rej_rate_gjr * 100, 0)
        ) |>
        dplyr::select(Strategy, `White Noise (%)`, `Regime Vol (%)`, `MA(1) (%)`,
                       `Factor (%)`, `GARCH (%)`, `GJR (%)`)
    }),


    # ── HAC vs Naive comparison ──────────────────────────────────────
    targets::tar_target(fals_vig_hac_comparison, {
      library(dplyr)

      nms <- fals_vig_names
      hac_results <- list(
        fals_hac_avoid_worst, fals_hac_drif, fals_hac_fac_max,
        fals_hac_rsc, fals_hac_ltr
      )

      # Naive t-stat = naive_sharpe * sqrt(T / ann_factor)
      naive_t <- sapply(seq_along(hac_results), function(i) {
        hac_results[[i]]$naive_sharpe * sqrt(hac_results[[i]]$T / nms$ann_factor[i])
      })

      tibble::tibble(
        Strategy = nms$long_name,
        `Naive Sharpe` = round(sapply(hac_results, `[[`, "naive_sharpe"), 2),
        `Ann Mean (%)` = round(sapply(hac_results, `[[`, "annualised_mean") * 100, 1),
        `Ann Vol (%)` = round(sapply(hac_results, `[[`, "annualised_vol") * 100, 1),
        `Naive t` = round(naive_t, 2),
        `HAC t` = round(sapply(hac_results, `[[`, "hac_tstat"), 2),
        `NW Lag` = as.integer(sapply(hac_results, `[[`, "lag_nw")),
        `T (obs)` = as.integer(sapply(hac_results, `[[`, "T"))
      )
    }),

    targets::tar_target(fals_vig_hac_caption, {
      nms <- fals_vig_names
      hac_results <- list(
        fals_hac_avoid_worst, fals_hac_drif, fals_hac_fac_max,
        fals_hac_rsc, fals_hac_ltr
      )
      hac_t <- sapply(hac_results, `[[`, "hac_tstat")
      all_pass <- all(hac_t > 2.0)
      min_t <- round(min(hac_t), 2)
      min_name <- nms$long_name[which.min(hac_t)]
      max_t <- round(max(hac_t), 2)
      max_name <- nms$long_name[which.max(hac_t)]
      avg_lag <- round(mean(sapply(hac_results, `[[`, "lag_nw")), 1)

      gh <- "https://github.com/JohnGavin/historical/blob/main"

      paste0(
        "Strategy performance with Newey-West HAC correction. ",
        "Columns: Naive Sharpe = uncorrected annualised Sharpe; ",
        "Ann Mean/Vol (%) = annualised return and volatility; ",
        "Naive t = t-statistic assuming iid returns; ",
        "HAC t = t-statistic corrected for serial correlation (GARCH persistence); ",
        "NW Lag = Newey-West bandwidth (Bartlett kernel, auto: ",
        "floor(4*(T/100)^(2/9))), average lag: ", avg_lag, ". ",
        if (all_pass) paste0(
          "All 5 strategies exceed the HAC t > 2.0 threshold, ",
          "ranging from ", min_name, " (t = ", min_t, ") to ",
          max_name, " (t = ", max_t, "). "
        ) else paste0(
          "HAC t ranges from ", min_t, " to ", max_t, ". "
        ),
        "Source: [hd_hac_sharpe()](", gh,
        "/packages/historicaldata/R/falsification.R#L80), ",
        "[Ken French Data Library](https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/data_library.html)."
      )
    }),


    # ── Factor regression details ────────────────────────────────────
    targets::tar_target(fals_vig_ff_table, {
      library(dplyr)

      nms <- fals_vig_names
      ff_results <- list(
        fals_ff_avoid_worst, fals_ff_drif, fals_ff_fac_max,
        fals_ff_rsc, fals_ff_ltr
      )

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
          Strategy = nms$long_name[i],
          `Alpha (%)` = round(ff$alpha_annual * 100, 1),
          `Alpha t` = round(ff$alpha_tstat_hac, 2),
          `R² (%)` = round(ff$r_squared * 100, 1),
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
      nms <- fals_vig_names
      ff_results <- list(
        fals_ff_avoid_worst, fals_ff_drif, fals_ff_fac_max,
        fals_ff_rsc, fals_ff_ltr
      )

      r2_vals <- sapply(ff_results, `[[`, "r_squared")
      highest_r2_idx <- which.max(r2_vals)
      highest_r2_name <- nms$long_name[highest_r2_idx]
      highest_r2_pct <- round(r2_vals[highest_r2_idx] * 100, 1)

      alpha_t <- sapply(ff_results, `[[`, "alpha_tstat_hac")
      best_alpha_idx <- which.max(alpha_t)
      best_alpha_name <- nms$long_name[best_alpha_idx]
      best_alpha_t <- round(alpha_t[best_alpha_idx], 2)

      gh <- "https://github.com/JohnGavin/historical/blob/main"

      paste0(
        "Fama-French 5-Factor + Momentum regression: ",
        "r_excess = Alpha + beta_Mkt-RF + beta_SMB + beta_HML + ",
        "beta_RMW + beta_CMA + beta_Mom + epsilon. ",
        "Columns: Alpha (%) = annualised intercept; Alpha t = HAC t-statistic; ",
        "R² (%) = variance explained by the 6 factors; ",
        "Mkt-RF through Mom = factor betas. ",
        highest_r2_name, " has the highest factor exposure (R² = ", highest_r2_pct, "%). ",
        best_alpha_name, " has the strongest alpha (t = ", best_alpha_t, "). ",
        "Source: [hd_factor_null_test()](", gh,
        "/packages/historicaldata/R/falsification.R), ",
        "daily factor data from ",
        "[Ken French Data Library](https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/data_library.html)."
      )
    }),


    # ── K_eff_frob and Delta-Z ────────────────────────────────────────────
    targets::tar_target(fals_vig_multiplicity, {
      harvey_t <- round(sqrt(2 * log(fals_keff$K_eff_frob)), 2)

      tibble::tibble(
        Metric = c(
          "K (strategies tested)", "K_eff_frob (independent strategies)",
          "Independence ratio (K_eff_frob/K)",
          "Best IS t-stat", "Best OOS t-stat",
          "Delta-Z (IS-OOS gap)",
          "Harvey threshold (sqrt(2*log(K_eff_frob)))"
        ),
        Value = as.character(c(
          5,
          round(fals_keff$K_eff_frob, 2),
          round(fals_keff$K_eff_frob / 5, 2),
          round(fals_delta_z$z_star_is, 2),
          round(fals_delta_z$z_star_oos, 2),
          round(fals_delta_z$delta_z, 2),
          harvey_t
        ))
      )
    }),

    targets::tar_target(fals_vig_multiplicity_caption, {
      keff <- round(fals_keff$K_eff_frob, 2)
      dz   <- round(fals_delta_z$delta_z, 2)
      harvey_t <- round(sqrt(2 * log(fals_keff$K_eff_frob)), 2)

      gh <- "https://github.com/JohnGavin/historical/blob/main"

      paste0(
        "Multiple testing adjustment. ",
        "K_eff_frob = ", keff,
        " (spectral participation ratio from pairwise correlation matrix) ",
        "measures how many truly independent strategies exist among the 5 tested. ",
        "Delta-Z = ", dz, " measures the gap between the best in-sample and best ",
        "out-of-sample t-statistics. ",
        "Harvey et al. (2016) threshold = sqrt(2*log(K_eff_frob)) = ", harvey_t,
        ". A strategy's HAC t must exceed this to survive multiplicity correction. ",
        "Source: [hd_keff_frob()](", gh,
        "/packages/historicaldata/R/falsification.R), ",
        "[hd_delta_z()](", gh,
        "/packages/historicaldata/R/falsification.R)."
      )
    }),


    # ── HAC dot chart (Cleveland style) ─────────────────────────────
    targets::tar_target(fals_vig_hac_plot, {
      library(ggplot2)

      nms <- fals_vig_names
      hac_results <- list(
        fals_hac_avoid_worst, fals_hac_drif, fals_hac_fac_max,
        fals_hac_rsc, fals_hac_ltr
      )

      naive_t <- sapply(seq_along(hac_results), function(i) {
        hac_results[[i]]$naive_sharpe * sqrt(hac_results[[i]]$T / nms$ann_factor[i])
      })
      hac_t <- sapply(hac_results, `[[`, "hac_tstat")

      df_long <- data.frame(
        strategy = factor(rep(nms$short_name, 2), levels = rev(nms$short_name)),
        type = factor(rep(c("Naive t", "HAC t"), each = 5),
                      levels = c("Naive t", "HAC t")),
        t_stat = c(naive_t, hac_t)
      )

      ggplot(df_long, aes(x = t_stat, y = strategy, colour = type, shape = type)) +
        geom_vline(xintercept = 2.0, color = "#e74c3c", linetype = "dashed",
                   linewidth = 0.8) +
        geom_vline(xintercept = 0, color = "#666", linewidth = 0.5) +
        geom_point(size = 5, position = position_dodge(width = 0.5)) +
        annotate("text", x = 2.2, y = 0.5, label = "t = 2.0",
                 color = "#e74c3c", hjust = 0, size = 4) +
        scale_colour_manual(values = c("Naive t" = "#4a90d9", "HAC t" = "#2ecc71")) +
        scale_shape_manual(values = c("Naive t" = 16, "HAC t" = 17)) +
        labs(
          title = "Naive vs HAC t-Statistics (Cleveland Dot Plot)",
          subtitle = "HAC correction accounts for GARCH persistence in returns",
          x = "t-statistic", y = NULL, colour = NULL, shape = NULL
        ) +
        theme_minimal(base_size = 14) +
        theme(
          plot.background = element_rect(fill = "black", color = NA),
          panel.background = element_rect(fill = "black", color = NA),
          text = element_text(color = "#e0e0e0"),
          axis.text = element_text(color = "#e0e0e0", size = 13),
          legend.position = "top",
          legend.background = element_rect(fill = "black"),
          legend.text = element_text(color = "#e0e0e0"),
          panel.grid.major.x = element_line(color = "#333"),
          panel.grid.minor = element_blank(),
          panel.grid.major.y = element_line(color = "#222")
        )
    }),


    # ── FF alpha scatter plot ────────────────────────────────────────
    targets::tar_target(fals_vig_ff_alpha_plot, {
      library(ggplot2)

      nms <- fals_vig_names
      ff_results <- list(
        fals_ff_avoid_worst, fals_ff_drif, fals_ff_fac_max,
        fals_ff_rsc, fals_ff_ltr
      )

      df <- data.frame(
        strategy = factor(nms$short_name, levels = nms$short_name),
        alpha_annual = sapply(ff_results, `[[`, "alpha_annual") * 100,
        alpha_t      = sapply(ff_results, `[[`, "alpha_tstat_hac"),
        r_squared    = sapply(ff_results, `[[`, "r_squared") * 100
      )

      df$verdict <- ifelse(df$alpha_t > 2.0, "Genuine alpha", "No alpha (beta)")

      ggplot(df, aes(x = r_squared, y = alpha_annual, color = verdict)) +
        geom_point(size = 6) +
        geom_text(aes(label = strategy), vjust = -1.2, size = 4, color = "#e0e0e0") +
        geom_hline(yintercept = 0, color = "#666", linetype = "dashed") +
        geom_vline(xintercept = 15, color = "#666", linetype = "dashed") +
        scale_color_manual(values = c("Genuine alpha" = "#2ecc71",
                                       "No alpha (beta)" = "#e74c3c")) +
        labs(
          title = "Alpha (%) vs Factor Exposure R² (%)",
          subtitle = "Genuine alpha = top-left (low R², positive Alpha). Beta = right (high R²).",
          x = "R² (%)", y = "Alpha (%)",
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
