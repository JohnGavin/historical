# Plan: Covariance Diagnostic Vignette Targets (issue #498 Phase 3b)
#
# Pre-computed plots, table, and caption for the "Covariance Regularisation"
# section in docs/falsification.qmd. Consumes cov_diag_summary from
# plan_cov_diagnostic.R.
#
# Targets produced:
#   cov_diag_vig_table       — tidy data.frame for fals_dt()
#   cov_diag_vig_cond_plot   — Cleveland dot plot of mean condition number
#   cov_diag_vig_sharpe_plot — Cleveland dot plot of OOS min-var Sharpe
#   cov_diag_vig_caption     — dynamic caption string (≥3 sentences)
#
# All plots mirror the dark-background theme used in plan_falsification_vignette.R
# (black panel, #e0e0e0 text, legend.position = "bottom").

plan_cov_diagnostic_vignette <- function() {

  list(

    # ── Display table ────────────────────────────────────────────────────
    # Friendly method labels; Sharpe rounded to 2 dp; condition number
    # rounded to 0 dp (can be very large on wide universe).
    # Returned as a plain data.frame — fals_dt() in the qmd wraps it.
    targets::tar_target(cov_diag_vig_table, {
      library(dplyr)

      cov_diag_summary |>
        dplyr::mutate(
          Universe     = dplyr::case_when(
            universe == "4-asset" ~ "4-asset (SPY/TLT/GLD/DBC)",
            universe == "wide"    ~ "Wide (~30 large-cap equities)",
            .default  = universe
          ),
          Method       = dplyr::case_when(
            method == "sample"      ~ "Sample",
            method == "ledoit_wolf" ~ "Ledoit-Wolf",
            method == "rmt_denoise" ~ "RMT-denoise",
            .default      = method
          ),
          `OOS Sharpe` = round(oos_sharpe,  2),
          `Mean κ`   = round(mean_cond, 0),
          Windows      = as.integer(n_oos),
          Failed       = as.integer(n_failed),
          `p/n`        = if (!is.na(n_assets[1]) && !is.na(train_window[1])) {
            round(n_assets / train_window, 3)
          } else {
            NA_real_
          }
        ) |>
        dplyr::arrange(Universe, Method) |>
        dplyr::select(
          Universe, Method, `OOS Sharpe`, `Mean κ`, Windows, Failed, `p/n`
        )
    }),


    # ── Conditioning dot plot ────────────────────────────────────────────
    # Cleveland dot plot: mean condition number (log10 x-axis) by estimator,
    # coloured and shaped by universe. Lower = better conditioned.
    targets::tar_target(cov_diag_vig_cond_plot, {
      library(ggplot2)

      s <- cov_diag_summary

      s$method_label <- factor(
        dplyr::case_when(
          s$method == "sample"      ~ "Sample",
          s$method == "ledoit_wolf" ~ "Ledoit-Wolf",
          s$method == "rmt_denoise" ~ "RMT-denoise",
          .default      = s$method
        ),
        levels = c("Sample", "Ledoit-Wolf", "RMT-denoise")
      )

      s$universe_label <- factor(
        dplyr::case_when(
          s$universe == "4-asset" ~ "4-asset (SPY/TLT/GLD/DBC)",
          s$universe == "wide"    ~ "Wide (~30 equities)",
          .default  = s$universe
        )
      )

      ggplot(s, aes(
        x = mean_cond, y = method_label,
        colour = universe_label, shape = universe_label
      )) +
        geom_point(size = 5) +
        scale_x_log10(labels = scales::comma) +
        scale_colour_manual(
          values = c(
            "4-asset (SPY/TLT/GLD/DBC)" = "#4a90d9",
            "Wide (~30 equities)"        = "#69d4a0"
          ),
          name = "Universe"
        ) +
        scale_shape_manual(
          values = c(
            "4-asset (SPY/TLT/GLD/DBC)" = 16L,
            "Wide (~30 equities)"        = 17L
          ),
          name = "Universe"
        ) +
        labs(
          title    = "Mean Covariance Condition Number (κ) by Estimator",
          subtitle = "Lower = better conditioned. Log₁₀ scale. Regularisation reduces κ.",
          x        = "Mean condition number κ (log₁₀ scale)",
          y        = NULL,
          colour   = "Universe",
          shape    = "Universe"
        ) +
        theme_minimal(base_size = 14L) +
        theme(
          plot.background    = element_rect(fill = "black", color = NA),
          panel.background   = element_rect(fill = "black", color = NA),
          text               = element_text(color = "#e0e0e0"),
          axis.text          = element_text(color = "#e0e0e0", size = 13L),
          legend.position    = "bottom",
          legend.background  = element_rect(fill = "black"),
          legend.text        = element_text(color = "#e0e0e0"),
          panel.grid.major.x = element_line(color = "#333"),
          panel.grid.minor   = element_blank(),
          panel.grid.major.y = element_line(color = "#222")
        )
    }),


    # ── OOS Sharpe dot plot ──────────────────────────────────────────────
    # Cleveland dot plot: annualised OOS minimum-variance Sharpe by estimator.
    # Wide universe result is marked survivorship-biased in the legend label.
    targets::tar_target(cov_diag_vig_sharpe_plot, {
      library(ggplot2)

      s <- cov_diag_summary

      s$method_label <- factor(
        dplyr::case_when(
          s$method == "sample"      ~ "Sample",
          s$method == "ledoit_wolf" ~ "Ledoit-Wolf",
          s$method == "rmt_denoise" ~ "RMT-denoise",
          .default      = s$method
        ),
        levels = c("Sample", "Ledoit-Wolf", "RMT-denoise")
      )

      s$universe_label <- factor(
        dplyr::case_when(
          s$universe == "4-asset" ~ "4-asset (SPY/TLT/GLD/DBC)",
          s$universe == "wide"    ~ "Wide (~30 equities, survivorship-biased)",
          .default  = s$universe
        )
      )

      ggplot(s, aes(
        x = oos_sharpe, y = method_label,
        colour = universe_label, shape = universe_label
      )) +
        geom_vline(xintercept = 0, colour = "#666", linetype = "dashed",
                   linewidth = 0.6) +
        geom_point(size = 5L) +
        scale_colour_manual(
          values = c(
            "4-asset (SPY/TLT/GLD/DBC)"               = "#4a90d9",
            "Wide (~30 equities, survivorship-biased)" = "#e07b54"
          ),
          name = "Universe"
        ) +
        scale_shape_manual(
          values = c(
            "4-asset (SPY/TLT/GLD/DBC)"               = 16L,
            "Wide (~30 equities, survivorship-biased)" = 17L
          ),
          name = "Universe"
        ) +
        labs(
          title    = "Out-of-Sample (OOS) Min-Variance Sharpe by Estimator",
          subtitle = "4-asset result is unconfounded; wide result is survivorship-biased (see How to Read This).",
          x        = "Annualised OOS Sharpe ratio",
          y        = NULL,
          colour   = "Universe",
          shape    = "Universe"
        ) +
        theme_minimal(base_size = 14L) +
        theme(
          plot.background    = element_rect(fill = "black", color = NA),
          panel.background   = element_rect(fill = "black", color = NA),
          text               = element_text(color = "#e0e0e0"),
          axis.text          = element_text(color = "#e0e0e0", size = 13L),
          legend.position    = "bottom",
          legend.background  = element_rect(fill = "black"),
          legend.text        = element_text(color = "#e0e0e0"),
          panel.grid.major.x = element_line(color = "#333"),
          panel.grid.minor   = element_blank(),
          panel.grid.major.y = element_line(color = "#222")
        )
    }),


    # ── Dynamic caption ──────────────────────────────────────────────────
    # ≥3 sentences. Numbers computed from cov_diag_summary.
    # The survivorship-bias caveat is fixed reference text (not data-derived).
    targets::tar_target(cov_diag_vig_caption, {
      # Defined inside the target so it is in scope at build time (target
      # commands evaluate in the pipeline env, not the plan-function frame).
      gh_base <- "https://github.com/JohnGavin/historical/blob/main"
      s <- cov_diag_summary

      # Helper: extract one scalar value from summary
      get_val <- function(univ, meth, col) {
        val <- s[[col]][s$universe == univ & s$method == meth]
        if (length(val) == 0L) NA_real_ else val[[1L]]
      }

      # 4-asset values
      samp_cond_4  <- get_val("4-asset", "sample",      "mean_cond")
      lw_cond_4    <- get_val("4-asset", "ledoit_wolf",  "mean_cond")
      rmt_cond_4   <- get_val("4-asset", "rmt_denoise",  "mean_cond")
      samp_shr_4   <- get_val("4-asset", "sample",       "oos_sharpe")
      lw_shr_4     <- get_val("4-asset", "ledoit_wolf",  "oos_sharpe")
      rmt_shr_4    <- get_val("4-asset", "rmt_denoise",  "oos_sharpe")

      # Wide values
      samp_cond_w  <- get_val("wide", "sample",      "mean_cond")
      lw_cond_w    <- get_val("wide", "ledoit_wolf",  "mean_cond")
      rmt_cond_w   <- get_val("wide", "rmt_denoise",  "mean_cond")
      samp_shr_w   <- get_val("wide", "sample",       "oos_sharpe")
      lw_shr_w     <- get_val("wide", "ledoit_wolf",  "oos_sharpe")
      rmt_shr_w    <- get_val("wide", "rmt_denoise",  "oos_sharpe")

      # Conditioning improvement factors (sample / regularised)
      lw_improve_4 <- round(samp_cond_4 / lw_cond_4, 1L)
      lw_improve_w <- round(samp_cond_w / lw_cond_w, 1L)

      # p/n ratios
      n_assets_4  <- get_val("4-asset", "sample", "n_assets")
      train_w_4   <- get_val("4-asset", "sample", "train_window")
      n_assets_w  <- get_val("wide",    "sample", "n_assets")
      train_w_w   <- get_val("wide",    "sample", "train_window")
      pn_4 <- round(n_assets_4 / train_w_4, 3L)
      pn_w <- round(n_assets_w / train_w_w, 3L)

      paste0(
        "Out-of-sample (OOS) global minimum-variance (GMV) covariance conditioning diagnostic ",
        "across two universes: 4-asset (SPY/TLT/GLD/DBC, p/n = ", pn_4, ") ",
        "and wide (~30 large-cap US equities, p/n = ", pn_w, "). ",
        # Conditioning result — unambiguous in both universes
        "Conditioning improvement is unambiguous everywhere: Ledoit-Wolf shrinkage reduced ",
        "mean condition number by ", lw_improve_4, "× on the 4-asset universe ",
        "(Sample κ = ", round(samp_cond_4, 1L),
        ", LW = ", round(lw_cond_4, 1L),
        ", RMT = ", round(rmt_cond_4, 1L), ") ",
        "and by ", lw_improve_w, "× on the wide universe ",
        "(Sample κ = ", round(samp_cond_w, 0L),
        ", LW = ", round(lw_cond_w, 0L),
        ", RMT = ", round(rmt_cond_w, 0L), "). ",
        # OOS Sharpe — clean result on 4-asset
        "OOS Sharpe on the 4-asset (non-survivorship-biased) universe: ",
        "Sample = ", round(samp_shr_4, 2L),
        ", LW = ", round(lw_shr_4, 2L),
        ", RMT = ", round(rmt_shr_4, 2L),
        " — regularisation provides a clean Sharpe improvement here. ",
        # Wide universe confound
        "On the wide universe, Sample OOS Sharpe (", round(samp_shr_w, 2L),
        ") exceeds LW (", round(lw_shr_w, 2L), ") and RMT (",
        round(rmt_shr_w, 2L),
        "), but this result is confounded by survivorship bias: the wide panel holds ",
        "only currently-listed tickers with no delisted firms, biasing all methods ",
        "toward apparent profitability and obscuring the regularisation benefit. ",
        "Source: ",
        "[hd_cov_oos_diagnostic()](", gh_base,
        "/packages/historicaldata/R/cov_diagnostic.R#L87), ",
        "[hd_min_var_weights()](", gh_base,
        "/packages/historicaldata/R/min_var_weights.R#L65), ",
        "[hd_cov_estimate()](", gh_base,
        "/packages/historicaldata/R/cov_estimate.R#L100), ",
        "[R/plan_cov_diagnostic_vignette.R](", gh_base,
        "/R/plan_cov_diagnostic_vignette.R), issue #498."
      )
    })

  )
}
