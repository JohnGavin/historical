# Plan: Weight-Stability Vignette Targets (issue #507 Phase 4b)
#
# Pre-computed plot, table, and caption for the "Weight-Stability Diagnostic
# (MVO breakdown)" section in docs/falsification.qmd. Consumes
# asset_monthly_returns_wide from plan_returns.R — the same 4-asset
# (SPY/TLT/GLD/DBC) universe and train_window = 60L used by cov_diag_4asset
# in plan_cov_diagnostic.R, giving consistent cross-section comparisons.
#
# Targets produced:
#   ws_diag_raw         — raw tibble from hd_weight_stability_diagnostic()
#   ws_diag_vig_table   — tidy data.frame for fals_dt() (Method / Avg Turnover
#                         / Max |w| / OOS Sharpe / Eff N / Failed)
#   ws_diag_vig_plot    — Cleveland dot plot of OOS Sharpe by method (dark bg)
#   ws_diag_vig_caption — dynamic caption string (>=3 sentences, data-driven)
#
# Template: mirrors R/plan_cov_diagnostic_vignette.R (#498 Phase 3b).
# All plots match the dark-background theme (black panel, #e0e0e0 text).
# BL-no-views caveat: with w_mkt = 1/p and no views, BL posterior collapses
# to equal-weight tangency — documented in hd_black_litterman() and #513.

plan_weight_stability_vignette <- function() {

  list(

    # ── Raw diagnostic compute ─────────────────────────────────────────────
    # Walk-forward OOS weight-stability diagnostic on the 4-asset universe.
    # asset_monthly_returns_wide is a wide tibble (date col + 4 ticker cols);
    # hd_weight_stability_diagnostic() silently drops the date column.
    # cov_method defaults to "ledoit_wolf" — regularised Sigma for gmv,
    # shrunk_mu, black_litterman, hrp.
    targets::tar_target(ws_diag_raw, {
      hd_weight_stability_diagnostic(
        returns      = asset_monthly_returns_wide,
        methods      = c(
          "raw_mvo", "gmv", "shrunk_mu", "black_litterman",
          "equal_weight", "hrp"
        ),
        train_window = 60L
      )
    }),


    # ── Display table ──────────────────────────────────────────────────────
    # Five core columns per task specification, plus Failed (n_failed) which
    # is essential for interpreting raw_mvo (singular sample Sigma windows).
    # Arranged descending by OOS Sharpe: best method at top of the table.
    targets::tar_target(ws_diag_vig_table, {
      library(dplyr)

      ws_diag_raw |>
        dplyr::mutate(
          Method = dplyr::case_when(
            method == "raw_mvo"         ~ "Raw MVO",
            method == "gmv"             ~ "GMV (Global Min-Var)",
            method == "shrunk_mu"       ~ "Shrunk-μ (James-Stein)",
            method == "black_litterman" ~ "Black-Litterman (no views)†",
            method == "equal_weight"    ~ "Equal-Weight (1/N)",
            method == "hrp"             ~ "HRP (Hierarchical RP)",
            .default = method
          ),
          `Avg Turnover` = round(avg_turnover,   3L),
          `Max |w|`      = round(max_abs_weight, 3L),
          `OOS Sharpe`   = round(oos_sharpe,     2L),
          `Eff N`        = round(mean_eff_n,      1L),
          Failed         = as.integer(n_failed)
        ) |>
        dplyr::arrange(dplyr::desc(oos_sharpe)) |>
        dplyr::select(
          Method, `Avg Turnover`, `Max |w|`, `OOS Sharpe`, `Eff N`, Failed
        )
    }),


    # ── OOS Sharpe Cleveland dot plot ──────────────────────────────────────
    # Horizontal dotchart (Cleveland convention, per visualization-standards):
    # one point per method, sorted ascending so the worst Sharpe is at the
    # bottom, best at the top. Raw MVO is coloured orange-red to flag it as
    # the error-maximiser. Dashed zero line for reference.
    # No legend: colours are self-labelled by the y-axis tick labels.
    targets::tar_target(ws_diag_vig_plot, {
      library(ggplot2)

      method_colours <- c(
        "Raw MVO"                          = "#e07b54",
        "GMV (Global Min-Var)"             = "#4a90d9",
        "Shrunk-μ (James-Stein)"      = "#69d4a0",
        "Black-Litterman (no views)†" = "#a8d4b0",
        "Equal-Weight (1/N)"               = "#c9b7e8",
        "HRP (Hierarchical RP)"            = "#f0c040"
      )

      s <- ws_diag_raw

      s$label <- dplyr::case_when(
        s$method == "raw_mvo"         ~ "Raw MVO",
        s$method == "gmv"             ~ "GMV (Global Min-Var)",
        s$method == "shrunk_mu"       ~ "Shrunk-μ (James-Stein)",
        s$method == "black_litterman" ~ "Black-Litterman (no views)†",
        s$method == "equal_weight"    ~ "Equal-Weight (1/N)",
        s$method == "hrp"             ~ "HRP (Hierarchical RP)",
        .default = s$method
      )

      # Sort ascending (lowest Sharpe at bottom); NA goes first (bottom).
      sort_idx <- order(s$oos_sharpe, na.last = FALSE)
      s$label  <- factor(s$label, levels = s$label[sort_idx])

      ggplot(s, aes(x = oos_sharpe, y = label, colour = label)) +
        geom_vline(
          xintercept = 0, colour = "#666", linetype = "dashed", linewidth = 0.6
        ) +
        geom_point(size = 5L) +
        scale_colour_manual(values = method_colours, guide = "none") +
        labs(
          title    = "Out-of-Sample (OOS) Sharpe by Portfolio Construction Method",
          subtitle = paste0(
            "4-asset universe (SPY/TLT/GLD/DBC). ",
            "Raw MVO = error maximiser. †BL shown at no-views equilibrium prior."
          ),
          x = "Annualised OOS Sharpe ratio",
          y = NULL
        ) +
        theme_minimal(base_size = 14L) +
        theme(
          plot.background    = element_rect(fill = "black", color = NA),
          panel.background   = element_rect(fill = "black", color = NA),
          text               = element_text(color = "#e0e0e0"),
          axis.text          = element_text(color = "#e0e0e0", size = 13L),
          legend.position    = "none",
          panel.grid.major.x = element_line(color = "#333"),
          panel.grid.minor   = element_blank(),
          panel.grid.major.y = element_line(color = "#222")
        )
    }),


    # ── Dynamic caption ────────────────────────────────────────────────────
    # >=3 sentences. All numbers computed from ws_diag_raw at build time.
    # Includes the BL-no-views caveat (#513 invariant) so readers do not read
    # the coincidence of BL == Equal-Weight as a bug in the implementation.
    targets::tar_target(ws_diag_vig_caption, {
      gh_base <- "https://github.com/JohnGavin/historical/blob/main"

      s <- ws_diag_raw

      get_val <- function(meth, col) {
        val <- s[[col]][s$method == meth]
        if (length(val) == 0L) NA_real_ else val[[1L]]
      }

      mvo_turnover   <- get_val("raw_mvo",        "avg_turnover")
      ew_turnover    <- get_val("equal_weight",    "avg_turnover")
      gmv_turnover   <- get_val("gmv",             "avg_turnover")
      hrp_turnover   <- get_val("hrp",             "avg_turnover")

      mvo_maxw       <- get_val("raw_mvo",         "max_abs_weight")
      ew_maxw        <- get_val("equal_weight",     "max_abs_weight")

      mvo_sharpe     <- get_val("raw_mvo",         "oos_sharpe")
      gmv_sharpe     <- get_val("gmv",             "oos_sharpe")
      hrp_sharpe     <- get_val("hrp",             "oos_sharpe")
      ew_sharpe      <- get_val("equal_weight",    "oos_sharpe")
      shrunk_sharpe  <- get_val("shrunk_mu",       "oos_sharpe")
      bl_sharpe      <- get_val("black_litterman", "oos_sharpe")

      mvo_failed     <- as.integer(get_val("raw_mvo", "n_failed"))

      n_assets  <- attr(s, "n_assets")
      train_win <- attr(s, "train_window")
      n_per     <- attr(s, "n_periods")

      fail_note <- if (!is.na(mvo_failed) && mvo_failed > 0L) {
        paste0(
          " (", mvo_failed, " window",
          if (mvo_failed != 1L) "s" else "",
          " with singular sample covariance, counted as failed)"
        )
      } else {
        ""
      }

      paste0(
        "Walk-forward weight-stability diagnostic across six portfolio construction ",
        "methods on the 4-asset universe (SPY/TLT/GLD/DBC; p = ", n_assets,
        ", T = ", n_per, " months, training window = ", train_win, " months). ",

        "Raw MVO (plug-in tangency; sample Σ and μ, no regularisation) ",
        "is the literature’s error maximiser: ",
        "avg turnover = ", round(mvo_turnover, 3),
        " vs GMV = ", round(gmv_turnover, 3),
        ", Equal-Weight = ", round(ew_turnover, 3),
        ", HRP = ", round(hrp_turnover, 3),
        "; max |w| = ", round(mvo_maxw, 3),
        " vs Equal-Weight = ", round(ew_maxw, 3),
        "; OOS Sharpe = ", round(mvo_sharpe, 2), fail_note, ". ",

        "Stable alternatives cluster rightward: ",
        "GMV = ", round(gmv_sharpe, 2),
        ", HRP = ", round(hrp_sharpe, 2),
        ", Equal-Weight = ", round(ew_sharpe, 2),
        "; expected-return regularisation: ",
        "Shrunk-μ (James-Stein) = ", round(shrunk_sharpe, 2),
        ", Black-Litterman (no views)† = ", round(bl_sharpe, 2), ". ",

        "† Black-Litterman is shown at the no-views equilibrium prior ",
        "(w_mkt = 1/p equal-weight, risk_aversion = 2.5), ",
        "the #513 invariant; with no investor views the BL posterior mu-hat ",
        "collapses to Pi = lambda*Sigma*w_mkt, so BL tangency weights ",
        "are approximately equal-weight (by construction, not a bug). ",

        "Source: ",
        "[hd_weight_stability_diagnostic()](", gh_base,
        "/packages/historicaldata/R/weight_stability.R#L130), ",
        "[R/plan_weight_stability_vignette.R](", gh_base,
        "/R/plan_weight_stability_vignette.R), issue #507."
      )
    })

  )
}
