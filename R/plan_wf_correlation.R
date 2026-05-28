# Plan: Walk-Forward Correlation (WFC) diagnostic
#
# Tinsley (2026), SSRN 6324079 — evaluates whether IS optimisation surfaces
# have structural predictive power by correlating IS and OOS Sharpe across
# the full parameter grid.
#
# Scope (this PR — #297): Factor MAX (fac_max) scaffold only.
# TODO #297-follow-up: add DRIF elastic-net (alpha/lambda) and XGB DRIF grids.
#
# No IS/OOS overlap: IS grid uses dates <= bt_partitions$factor$train_end;
# OOS grid uses bt_partitions$factor$test_start to test_end.
# Enforces t+1 execution (factors held month AFTER signal — see plan_factormax.R).
#
# Reference: knowledge/wiki/walk-forward-correlation.md

plan_wf_correlation <- function() {
  list(

    # ══════════════════════════════════════════════════════════════════
    # Shared WFC parameters
    # ══════════════════════════════════════════════════════════════════

    targets::tar_target(wfc_params, {
      p <- bt_partitions$factor
      list(
        ann_factor    = 12L,       # monthly strategy
        wfc_threshold = 0.70,      # high-WFC cutoff (project threshold)
        # Calibration from Tinsley SSRN 6324079 Figure 4:
        #   high ≈ 0.881, moderate ≈ 0.581, low ≈ 0.234
        # Project uses 0.70 (midpoint of moderate–high range) as the "high" threshold
        is_end        = p$train_end,
        oos_start     = p$test_start,
        oos_end       = p$test_end
      )
    }),


    # ══════════════════════════════════════════════════════════════════
    # Factor MAX: IS × OOS grid sweep over top_n ∈ {1, 2, 3, 4, 5}
    # ══════════════════════════════════════════════════════════════════
    #
    # The fac_max strategy selects the top-N factors (by MAX daily return in
    # the prior month) and holds them equally weighted for one month.
    # top_n is the only scalar tuning parameter; it ranges from 1 (most
    # concentrated) to 5 (all 5 non-market factors).
    #
    # Depends on: fm_daily, fm_signal, bt_partitions, wfc_params

    targets::tar_target(wfc_fm_grid_is, {
      library(dplyr)

      # ── helper: run fac_max portfolio for one value of top_n on one window ──
      run_fm_portfolio <- function(signal_df, monthly_ret_df,
                                   start_date, end_date,
                                   top_n_val, rf_df) {
        months <- sort(unique(signal_df$ym))
        # Filter to months within the window
        window_months <- months[months >= format(start_date, "%Y-%m") &
                                  months <= format(end_date, "%Y-%m")]

        # Need at least 12 months of prior history before first trade
        min_history <- 12L
        trade_months <- months[(min_history + 1L):length(months)]
        trade_months <- intersect(trade_months, window_months)

        if (length(trade_months) < 6L) return(NULL)

        results <- lapply(trade_months, function(m) {
          prev_idx <- which(months == m) - 1L
          if (prev_idx < 1L) return(NULL)
          prev_m <- months[[prev_idx]]

          signal <- signal_df |> filter(ym == prev_m)
          if (nrow(signal) == 0L) return(NULL)

          selected <- signal |>
            filter(max_rank <= top_n_val) |>
            pull(factor_name)

          if (length(selected) == 0L) return(NULL)

          factor_rets <- monthly_ret_df |>
            filter(factor_name %in% selected, ym == m)

          if (nrow(factor_rets) == 0L) return(NULL)

          port_ret <- mean(factor_rets$monthly_ret)
          tibble(ym = m, portfolio_ret = port_ret)
        })

        df <- bind_rows(Filter(Negate(is.null), results))
        if (nrow(df) < 6L) return(NULL)
        df
      }

      # ── compute Sharpe for a portfolio tibble ──────────────────────────────
      annualised_sharpe <- function(port_df, ann_factor) {
        ret <- port_df$portfolio_ret
        ret <- ret[!is.na(ret)]
        if (length(ret) < 4L) return(NA_real_)
        ann_mean <- mean(ret) * ann_factor
        ann_vol  <- stats::sd(ret) * sqrt(ann_factor)
        if (ann_vol <= 0) return(NA_real_)
        ann_mean / ann_vol
      }

      # ── filter signal and monthly_ret to non-market factors ───────────────
      factors_nz <- c("HML", "SMB", "RMW", "CMA", "Mom")
      signal_df  <- fm_signal |> filter(factor_name %in% factors_nz)
      monthly_df <- fm_monthly |> filter(factor_name %in% factors_nz)

      is_start <- as.Date("1963-07-01")   # FF5 data origin
      is_end   <- wfc_params$is_end

      top_n_grid <- 1L:5L

      purrr::map_dfr(top_n_grid, function(tn) {
        port <- run_fm_portfolio(
          signal_df     = signal_df,
          monthly_ret_df = monthly_df,
          start_date    = is_start,
          end_date      = is_end,
          top_n_val     = tn,
          rf_df         = NULL
        )

        sharpe <- annualised_sharpe(port, ann_factor = wfc_params$ann_factor)

        tibble::tibble(
          theta_id    = tn,
          theta_label = paste0("top_n=", tn),
          IS_metric   = sharpe,
          partition   = "IS"
        )
      })
    }),


    targets::tar_target(wfc_fm_grid_oos, {
      library(dplyr)

      # Re-use the same helpers defined in wfc_fm_grid_is — we can't call
      # those helpers across targets, so we inline them again.  This is a
      # deliberate repetition to keep each target self-contained, following
      # the pattern in plan_falsification.R.

      run_fm_portfolio_oos <- function(signal_df, monthly_ret_df,
                                       oos_start, oos_end, top_n_val) {
        months <- sort(unique(signal_df$ym))
        window_months <- months[months >= format(oos_start, "%Y-%m") &
                                  months <= format(oos_end, "%Y-%m")]
        min_history <- 12L
        trade_months <- months[(min_history + 1L):length(months)]
        trade_months <- intersect(trade_months, window_months)
        if (length(trade_months) < 3L) return(NULL)

        results <- lapply(trade_months, function(m) {
          prev_idx <- which(months == m) - 1L
          if (prev_idx < 1L) return(NULL)
          prev_m   <- months[[prev_idx]]
          signal   <- signal_df |> filter(ym == prev_m)
          if (nrow(signal) == 0L) return(NULL)
          selected <- signal |> filter(max_rank <= top_n_val) |> pull(factor_name)
          if (length(selected) == 0L) return(NULL)
          factor_rets <- monthly_ret_df |> filter(factor_name %in% selected, ym == m)
          if (nrow(factor_rets) == 0L) return(NULL)
          tibble(ym = m, portfolio_ret = mean(factor_rets$monthly_ret))
        })

        df <- bind_rows(Filter(Negate(is.null), results))
        if (nrow(df) < 3L) return(NULL)
        df
      }

      annualised_sharpe_oos <- function(port_df, ann_factor) {
        ret <- port_df$portfolio_ret[!is.na(port_df$portfolio_ret)]
        if (length(ret) < 4L) return(NA_real_)
        ann_vol <- stats::sd(ret) * sqrt(ann_factor)
        if (ann_vol <= 0) return(NA_real_)
        mean(ret) * ann_factor / ann_vol
      }

      factors_nz <- c("HML", "SMB", "RMW", "CMA", "Mom")
      signal_df  <- fm_signal |> filter(factor_name %in% factors_nz)
      monthly_df <- fm_monthly |> filter(factor_name %in% factors_nz)

      top_n_grid <- 1L:5L

      purrr::map_dfr(top_n_grid, function(tn) {
        port <- run_fm_portfolio_oos(
          signal_df     = signal_df,
          monthly_ret_df = monthly_df,
          oos_start     = wfc_params$oos_start,
          oos_end       = wfc_params$oos_end,
          top_n_val     = tn
        )

        sharpe <- annualised_sharpe_oos(port, ann_factor = wfc_params$ann_factor)

        tibble::tibble(
          theta_id    = tn,
          theta_label = paste0("top_n=", tn),
          OOS_metric  = sharpe,
          partition   = "OOS"
        )
      })
    }),


    # ══════════════════════════════════════════════════════════════════
    # Combined IS+OOS grid tibble (one row per theta)
    # ══════════════════════════════════════════════════════════════════

    targets::tar_target(wfc_fm_grid, {
      library(dplyr)

      dplyr::inner_join(
        wfc_fm_grid_is  |> dplyr::select(theta_id, theta_label, IS_metric),
        wfc_fm_grid_oos |> dplyr::select(theta_id, OOS_metric),
        by = "theta_id"
      )
    }),


    # ══════════════════════════════════════════════════════════════════
    # WFC diagnostic: Pearson + Spearman + classification
    # ══════════════════════════════════════════════════════════════════

    targets::tar_target(wfc_fm_result, {
      hd_wf_correlation(
        wfc_fm_grid,
        wfc_threshold_high = wfc_params$wfc_threshold
      )
    }),


    # ══════════════════════════════════════════════════════════════════
    # WFC summary: one-row tibble consumable by the leaderboard vignette
    # ══════════════════════════════════════════════════════════════════

    targets::tar_target(wfc_summary, {
      tibble::tibble(
        strategy       = "fac_max",
        wfc_pearson    = wfc_fm_result$pearson,
        wfc_spearman   = wfc_fm_result$spearman,
        wfc_n_points   = wfc_fm_result$n_points,
        wfc_category   = wfc_fm_result$wfc_category,
        classification = wfc_fm_result$classification,
        median_oos     = wfc_fm_result$median_oos,
        pct_pos_oos    = wfc_fm_result$pct_positive_oos,

        # Metadata for audit trail
        is_end   = wfc_params$is_end,
        oos_start = wfc_params$oos_start,
        oos_end   = wfc_params$oos_end,
        wfc_threshold = wfc_params$wfc_threshold,
        computed_on   = Sys.Date()
      )

      # TODO (#297 follow-up): add DRIF and XGB DRIF rows once those
      # parameter grids are wired as targets.  The plan structure above
      # (wfc_fm_grid_is / wfc_fm_grid_oos / wfc_fm_grid / wfc_fm_result)
      # is the canonical scaffold to replicate for each strategy.
    })

  )
}
