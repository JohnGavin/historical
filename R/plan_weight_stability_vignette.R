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
#   ws_diag_vig_table   — tidy data.frame for fals_dt() (Method / Avg turnover
#                         / Max weight / Effective holdings / OOS Sharpe)
#   ws_diag_vig_plot    — Cleveland dot plot of average turnover by method
#   ws_diag_vig_caption — plain-language caption string (data-driven)
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
    # Columns: how much each method trades (Avg turnover), how concentrated it
    # gets (Max weight), how many assets it effectively holds, and its OOS
    # Sharpe. Sorted by turnover (steadiest first). The n_failed column is
    # dropped here: it is always 0 on this 4-asset universe (the covariance is
    # never singular) and only matters in wide universes where p approaches the
    # training window.
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
          `Avg turnover`       = round(avg_turnover,   3L),
          `Max weight`         = round(max_abs_weight, 3L),
          `Effective holdings` = round(mean_eff_n,     1L),
          `OOS Sharpe`         = round(oos_sharpe,     2L)
        ) |>
        # Steadiest method first: this is a *stability* diagnostic, so sort by
        # how much each method trades, not by return.
        dplyr::arrange(avg_turnover) |>
        dplyr::select(
          Method, `Avg turnover`, `Max weight`, `Effective holdings`, `OOS Sharpe`
        )
    }),


    # ── Turnover Cleveland dot plot ────────────────────────────────────────
    # Horizontal dotchart (Cleveland convention, per visualization-standards):
    # one point per method = average monthly turnover. This is a weight-
    # stability section, so turnover (how much each method trades) is the
    # headline metric — not Sharpe, where plug-in MVO can look fine on a small
    # universe while still making wild, concentrated bets. Sorted ascending
    # (steadiest at bottom); Raw MVO is coloured orange-red as the outlier.
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

      # Sort ascending (least trading at bottom, most at top).
      sort_idx <- order(s$avg_turnover, na.last = FALSE)
      s$label  <- factor(s$label, levels = s$label[sort_idx])

      ggplot(s, aes(x = avg_turnover, y = label, colour = label)) +
        geom_point(size = 5L) +
        scale_colour_manual(values = method_colours, guide = "none") +
        labs(
          title    = "How much each method trades (average monthly turnover)",
          subtitle = paste0(
            "4-asset universe (SPY/TLT/GLD/DBC). Higher = more trading each ",
            "rebalance. Plug-in MVO trades far more than every alternative."
          ),
          x = "Average monthly turnover (sum of absolute weight changes)",
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


    # ── Plain-language caption ─────────────────────────────────────────────
    # No jargon, no source links (those live, working, in the "How to Read
    # This" tab), no full number-dump (the table carries the figures). Only the
    # two numbers that make the point vivid — MVO's concentration — plus the
    # honest read: on 4 assets MVO's instability shows up as trading and
    # concentration, NOT worse Sharpe. Computed from ws_diag_raw at build time.
    targets::tar_target(ws_diag_vig_caption, {
      s <- ws_diag_raw

      get_val <- function(meth, col) {
        val <- s[[col]][s$method == meth]
        if (length(val) == 0L) NA_real_ else val[[1L]]
      }

      mvo_maxw  <- get_val("raw_mvo", "max_abs_weight")
      mvo_effn  <- get_val("raw_mvo", "mean_eff_n")
      n_assets  <- attr(s, "n_assets")
      train_win <- attr(s, "train_window")

      paste0(
        "All six methods turn the same ", n_assets,
        " assets (SPY, TLT, GLD, DBC) into portfolio weights; we rebalance ",
        "monthly over rolling ", train_win,
        "-month windows and score the next month out of sample. The table ",
        "shows how much each method trades, how concentrated it gets, and its ",
        "return. ",

        "Plug-in mean-variance — the textbook recipe built straight from raw ",
        "sample estimates — is by far the least stable: it trades far more ",
        "than any other method and puts ", round(mvo_maxw * 100),
        "% into a single asset, effectively holding just ", round(mvo_effn, 1),
        " of the ", n_assets, ". On these few well-behaved assets that ",
        "concentrated bet happened to earn the highest Sharpe, but that is ",
        "luck, not skill — the same behaviour is what blows up in larger ",
        "universes. Shrinking the return estimates (Shrunk-μ) earns almost the ",
        "same Sharpe far more steadily. ",

        "Black-Litterman is run with no investor views, so it simply reproduces ",
        "the equal-weight benchmark — expected, not a bug: with no views there ",
        "is nothing to tilt away from equal weight."
      )
    })

  )
}
