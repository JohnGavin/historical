# Plan: Walk-Forward Correlation (WFC) diagnostic
#
# Tinsley (2026), SSRN 6324079 — evaluates whether IS optimisation surfaces
# have structural predictive power by correlating IS and OOS Sharpe across
# the full parameter grid.
#
# Scope (PR #318):
#   - Factor MAX: top_n ∈ {1..5} (from PR #309, unchanged)
#   - DRIF elastic-net: alpha ∈ {0.0, 0.25, 0.5, 0.75, 1.0}, lambda chosen
#     by cv.glmnet's internal cross-validation (lambda.min rule)
#   - XGB DRIF: NOT included.  The existing xgb_drif strategy operates at
#     the stock level (stk_drif_features / xgb_drif_portfolio), not as a
#     factor-rotation grid sweep.  A factor-level XGB is a separate effort;
#     tracked as follow-up to #318.
#
# No IS/OOS overlap: IS grid uses dates <= bt_partitions$factor$train_end;
# OOS grid uses bt_partitions$factor$test_start to test_end.
# Enforces t+1 execution (factors held month AFTER signal — see plan_factormax.R,
# plan_drif.R).  t+0 execution is impossible per the look-ahead-bias-prevention
# rule and project memory (alpha-decay min t+1).
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
    # DRIF elastic-net: IS × OOS grid sweep over alpha ∈ {0,0.25,0.5,0.75,1}
    # ══════════════════════════════════════════════════════════════════
    #
    # DRIF uses an expanding-window elastic net (glmnet::cv.glmnet) on the
    # 42 chronological+rank features from drif_features.  The single free
    # tuning scalar visible to the WFC diagnostic is alpha (mix between L1
    # and L2 penalty).  Lambda is always chosen by cv.glmnet's own
    # cross-validation (lambda.min), consistent with the production target in
    # plan_drif.R.
    #
    # IS window:  dates up to   wfc_params$is_end
    # OOS window: dates from    wfc_params$oos_start to wfc_params$oos_end
    # Annualised Sharpe (monthly, ann_factor=12) is the WFC metric.
    #
    # Depends on: drif_features, drif_params, wfc_params

    targets::tar_target(wfc_drif_grid_is, {
      library(dplyr)
      rlang::check_installed("glmnet")

      features  <- drif_features
      params    <- drif_params
      wfc_p     <- wfc_params

      # Feature column names (match plan_drif.R)
      lb         <- params$lookback_days
      chrono_cols <- paste0("c", seq_len(lb))
      rank_cols   <- paste0("r", seq_len(lb))
      feat_cols   <- c(chrono_cols, rank_cols)

      min_train <- params$min_train_months
      all_factors <- c(params$factors, params$benchmark_factor)
      months    <- sort(unique(features$ym))

      # IS window: only months up to is_end
      is_end_ym <- format(wfc_p$is_end, "%Y-%m")
      is_months <- months[months <= is_end_ym]
      trade_months_is <- is_months[(min_train + 1L):length(is_months)]
      if (length(trade_months_is) < 6L) {
        return(tibble::tibble(theta_id = integer(0), theta_label = character(0),
                              IS_metric = numeric(0), partition = character(0)))
      }

      # ── Helper: run DRIF portfolio for one alpha value on one window ──
      run_drif_window <- function(trade_months_w, alpha_val) {
        predictions <- lapply(trade_months_w, function(m) {
          m_idx        <- which(months == m)
          train_months <- months[1L:(m_idx - 1L)]

          train <- features |> filter(ym %in% train_months,
                                      factor_name %in% all_factors)
          test  <- features |> filter(ym == m,
                                      factor_name %in% params$factors)
          if (nrow(train) == 0L || nrow(test) == 0L) return(NULL)

          X_train <- as.matrix(train[, feat_cols])
          y_train <- train$target_ret
          X_test  <- as.matrix(test[, feat_cols])

          cc <- complete.cases(X_train, y_train)
          X_train <- X_train[cc, , drop = FALSE]
          y_train <- y_train[cc]
          if (length(y_train) < 50L) return(NULL)

          fit <- tryCatch(
            glmnet::cv.glmnet(X_train, y_train,
                              alpha = alpha_val,
                              nfolds = 5L,
                              type.measure = "mse"),
            error = function(e) NULL
          )
          if (is.null(fit)) return(NULL)

          pred <- as.numeric(predict(fit, X_test, s = "lambda.min"))
          tibble::tibble(
            factor_name   = test$factor_name,
            ym            = m,
            predicted_ret = pred,
            actual_ret    = test$target_ret
          )
        })

        preds <- dplyr::bind_rows(Filter(Negate(is.null), predictions))
        if (nrow(preds) == 0L) return(NULL)

        # Select top-N (same as drif_params$top_n = 2) by predicted return
        port <- preds |>
          group_by(ym) |>
          dplyr::mutate(pred_rank = rank(-predicted_ret, ties.method = "min")) |>
          dplyr::filter(pred_rank <= params$top_n) |>
          dplyr::summarise(portfolio_ret = mean(actual_ret), .groups = "drop")
        port
      }

      # ── Annualised Sharpe helper ───────────────────────────────────
      ann_sharpe <- function(port_df, ann_factor) {
        if (is.null(port_df) || nrow(port_df) < 4L) return(NA_real_)
        ret <- port_df$portfolio_ret[!is.na(port_df$portfolio_ret)]
        if (length(ret) < 4L) return(NA_real_)
        ann_vol <- stats::sd(ret) * sqrt(ann_factor)
        if (ann_vol <= 0) return(NA_real_)
        mean(ret) * ann_factor / ann_vol
      }

      alpha_grid <- c(0.00, 0.25, 0.50, 0.75, 1.00)

      purrr::map_dfr(seq_along(alpha_grid), function(i) {
        a    <- alpha_grid[[i]]
        port <- run_drif_window(trade_months_is, alpha_val = a)
        tibble::tibble(
          theta_id    = i,
          theta_label = paste0("alpha=", a),
          IS_metric   = ann_sharpe(port, wfc_p$ann_factor),
          partition   = "IS"
        )
      })
    }),


    targets::tar_target(wfc_drif_grid_oos, {
      library(dplyr)
      rlang::check_installed("glmnet")

      features  <- drif_features
      params    <- drif_params
      wfc_p     <- wfc_params

      lb          <- params$lookback_days
      chrono_cols <- paste0("c", seq_len(lb))
      rank_cols   <- paste0("r", seq_len(lb))
      feat_cols   <- c(chrono_cols, rank_cols)

      min_train   <- params$min_train_months
      all_factors <- c(params$factors, params$benchmark_factor)
      months      <- sort(unique(features$ym))

      # OOS window: months from oos_start to oos_end
      oos_start_ym <- format(wfc_p$oos_start, "%Y-%m")
      oos_end_ym   <- format(wfc_p$oos_end,   "%Y-%m")
      oos_months   <- months[months >= oos_start_ym & months <= oos_end_ym]
      if (length(oos_months) < 3L) {
        return(tibble::tibble(theta_id = integer(0), theta_label = character(0),
                              OOS_metric = numeric(0), partition = character(0)))
      }

      run_drif_oos <- function(oos_months_w, alpha_val) {
        predictions <- lapply(oos_months_w, function(m) {
          m_idx        <- which(months == m)
          train_months <- months[1L:(m_idx - 1L)]

          train <- features |> filter(ym %in% train_months,
                                      factor_name %in% all_factors)
          test  <- features |> filter(ym == m,
                                      factor_name %in% params$factors)
          if (nrow(train) == 0L || nrow(test) == 0L) return(NULL)

          X_train <- as.matrix(train[, feat_cols])
          y_train <- train$target_ret
          X_test  <- as.matrix(test[, feat_cols])

          cc <- complete.cases(X_train, y_train)
          X_train <- X_train[cc, , drop = FALSE]
          y_train <- y_train[cc]
          if (length(y_train) < 50L) return(NULL)

          fit <- tryCatch(
            glmnet::cv.glmnet(X_train, y_train,
                              alpha = alpha_val,
                              nfolds = 5L,
                              type.measure = "mse"),
            error = function(e) NULL
          )
          if (is.null(fit)) return(NULL)

          pred <- as.numeric(predict(fit, X_test, s = "lambda.min"))
          tibble::tibble(
            factor_name   = test$factor_name,
            ym            = m,
            predicted_ret = pred,
            actual_ret    = test$target_ret
          )
        })

        preds <- dplyr::bind_rows(Filter(Negate(is.null), predictions))
        if (nrow(preds) == 0L) return(NULL)

        port <- preds |>
          group_by(ym) |>
          dplyr::mutate(pred_rank = rank(-predicted_ret, ties.method = "min")) |>
          dplyr::filter(pred_rank <= params$top_n) |>
          dplyr::summarise(portfolio_ret = mean(actual_ret), .groups = "drop")
        port
      }

      ann_sharpe_oos <- function(port_df, ann_factor) {
        if (is.null(port_df) || nrow(port_df) < 3L) return(NA_real_)
        ret <- port_df$portfolio_ret[!is.na(port_df$portfolio_ret)]
        if (length(ret) < 3L) return(NA_real_)
        ann_vol <- stats::sd(ret) * sqrt(ann_factor)
        if (ann_vol <= 0) return(NA_real_)
        mean(ret) * ann_factor / ann_vol
      }

      alpha_grid <- c(0.00, 0.25, 0.50, 0.75, 1.00)

      purrr::map_dfr(seq_along(alpha_grid), function(i) {
        a    <- alpha_grid[[i]]
        port <- run_drif_oos(oos_months, alpha_val = a)
        tibble::tibble(
          theta_id    = i,
          theta_label = paste0("alpha=", a),
          OOS_metric  = ann_sharpe_oos(port, wfc_p$ann_factor),
          partition   = "OOS"
        )
      })
    }),


    # ══════════════════════════════════════════════════════════════════
    # DRIF combined IS+OOS grid
    # ══════════════════════════════════════════════════════════════════

    targets::tar_target(wfc_drif_grid, {
      dplyr::inner_join(
        wfc_drif_grid_is  |> dplyr::select(theta_id, theta_label, IS_metric),
        wfc_drif_grid_oos |> dplyr::select(theta_id, OOS_metric),
        by = "theta_id"
      )
    }),


    # ══════════════════════════════════════════════════════════════════
    # DRIF WFC diagnostic
    # ══════════════════════════════════════════════════════════════════

    targets::tar_target(wfc_drif_result, {
      hd_wf_correlation(
        wfc_drif_grid,
        wfc_threshold_high = wfc_params$wfc_threshold
      )
    }),


    # ══════════════════════════════════════════════════════════════════
    # WFC all-strategy summary (FM + DRIF): leaderboard-ready tibble
    # ══════════════════════════════════════════════════════════════════
    #
    # XGB DRIF is not included: the existing xgb_drif operates at the
    # stock level (stk_drif_features) with no factor-rotation grid, so
    # there is no (IS, OOS) Sharpe pair per parameter to correlate.
    # A factor-level XGB is tracked as a follow-up to #318.
    #
    # OLMAR, TOM, and other non-parametric strategies have no tunable
    # grid — wf_corr and wfc_verdict will be NA_real_ / NA_character_
    # for those rows in the leaderboard (see plan_leaderboard.R).

    targets::tar_target(wfc_all_summary, {
      audit <- list(
        is_end        = wfc_params$is_end,
        oos_start     = wfc_params$oos_start,
        oos_end       = wfc_params$oos_end,
        wfc_threshold = wfc_params$wfc_threshold,
        computed_on   = Sys.Date()
      )

      make_row <- function(strategy_name, result) {
        tibble::tibble(
          strategy       = strategy_name,
          wfc_pearson    = result$pearson,
          wfc_spearman   = result$spearman,
          wfc_n_points   = result$n_points,
          wfc_category   = result$wfc_category,
          classification = result$classification,
          median_oos     = result$median_oos,
          pct_pos_oos    = result$pct_positive_oos,
          is_end         = audit$is_end,
          oos_start      = audit$oos_start,
          oos_end        = audit$oos_end,
          wfc_threshold  = audit$wfc_threshold,
          computed_on    = audit$computed_on
        )
      }

      dplyr::bind_rows(
        make_row("Factor MAX",   wfc_fm_result),
        make_row("Factor DRIF",  wfc_drif_result)
      )
    }),


    # ══════════════════════════════════════════════════════════════════
    # wfc_summary: backward-compatible one-row alias (FM only)
    # Kept for targets cache compatibility with PR #309.
    # New code should use wfc_all_summary.
    # ══════════════════════════════════════════════════════════════════

    targets::tar_target(wfc_summary, {
      wfc_all_summary |> dplyr::filter(strategy == "Factor MAX")
    })

  )
}
