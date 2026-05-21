# plan_drif_v2.R — DRIF multiverse / specification-curve analysis
#
# Implements the 2^4 = 16-cell specification curve described in issue #157,
# motivated by Cakici et al. 2024 (SSRN 6005614, issue #117).
#
# Four dimensions varied:
#   1. alpha          — elastic-net mix: 0.5 (current) vs 1.0 (pure LASSO)
#   2. nfolds         — CV folds: 5 (current) vs 10
#   3. feature_set    — "chrono" (21 raw daily, current) vs "both" (21 raw + 21 ranked)
#   4. lambda_rule    — model-selection rule: "lambda.min" (current) vs "lambda.1se"
#
# Output targets:
#   drif_multiverse_grid   — tibble of 16 parameter combinations
#   drif_multiverse        — tibble with one row per spec, OOS performance metrics
#   drif_multiverse_plot   — spec-curve fan plot, current spec highlighted
#   drif_multiverse_caption — dynamic caption for vignette use
#
# Relationship to existing code:
#   Re-uses drif_features, drif_params, drif_daily from plan_drif.R (no duplication).
#   plan_drif.R remains the canonical single-spec production target.
#
# Issues:   #117 (paper impl), #118 (audit), #157 (multiverse spec)
# Paper:    Cakici et al. 2024, SSRN 6005614

plan_drif_v2 <- function() {
  list(

    # ── 1. Parameter grid ─────────────────────────────────────────
    #' @title DRIF multiverse parameter grid (2^4 = 16 specifications)
    targets::tar_target(drif_multiverse_grid, {
      tidyr::expand_grid(
        alpha       = c(0.5, 1.0),
        nfolds      = c(5L, 10L),
        feature_set = c("chrono", "both"),
        lambda_rule = c("lambda.min", "lambda.1se")
      ) |>
        dplyr::mutate(
          spec_id = sprintf("S%02d", dplyr::row_number()),
          is_current = alpha == 0.5 &
                       nfolds == 5L &
                       feature_set == "chrono" &
                       lambda_rule == "lambda.min"
        )
    }),

    # ── 2. Multiverse runner ──────────────────────────────────────
    # Iterates over the 16-cell grid, re-running the expanding-window elastic
    # net on the pre-built drif_features object from plan_drif.R.
    # Each spec produces OOS-only metrics (test_start onward) so that the
    # comparison is purely out-of-sample and uses the same OOS window as the
    # production target.
    targets::tar_target(drif_multiverse, {
      library(dplyr)
      rlang::check_installed("glmnet")

      features <- drif_features          # from plan_drif.R
      params   <- drif_params            # from plan_drif.R
      grid     <- drif_multiverse_grid

      all_factors <- c(params$factors, params$benchmark_factor)
      months      <- sort(unique(features$ym))
      min_train   <- params$min_train_months

      # OOS months only (align with production target)
      oos_start_ym <- format(params$oos_start, "%Y-%m")
      trade_months <- months[(min_train + 1):length(months)]
      oos_months   <- trade_months[trade_months >= oos_start_ym]

      rf_monthly <- drif_daily |>
        filter(factor_name == "RF") |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(ym) |>
        summarise(rf = prod(1 + value) - 1, .groups = "drop")

      # Helper: run one specification, return OOS perf metrics
      run_spec <- function(a, nf, fset, lrule) {
        chrono_cols <- paste0("c", seq_len(params$lookback_days))
        rank_cols   <- paste0("r", seq_len(params$lookback_days))
        feat_cols   <- if (fset == "chrono") chrono_cols else c(chrono_cols, rank_cols)

        preds <- lapply(oos_months, function(m) {
          m_idx     <- which(months == m)
          train_yms <- months[seq_len(m_idx - 1L)]
          train     <- features |> filter(ym %in% train_yms)
          test      <- features |> filter(ym == m)

          if (nrow(test) == 0L) return(NULL)

          avail_feats <- intersect(feat_cols, names(train))
          if (length(avail_feats) < 21L) return(NULL)

          X_train <- as.matrix(train[, avail_feats])
          y_train <- train$target_ret
          X_test  <- as.matrix(test[, avail_feats])

          ok <- complete.cases(X_train, y_train)
          X_train <- X_train[ok, , drop = FALSE]
          y_train <- y_train[ok]

          if (length(y_train) < 50L) return(NULL)

          fit <- tryCatch(
            glmnet::cv.glmnet(X_train, y_train,
                              alpha = a, nfolds = nf,
                              type.measure = "mse"),
            error = function(e) {
              cli::cli_warn("multiverse cv.glmnet failed {.val {m}}: {conditionMessage(e)}")
              NULL
            }
          )
          if (is.null(fit)) return(NULL)

          pred_vec <- as.numeric(predict(fit, X_test, s = lrule))

          tibble(
            factor_name  = test$factor_name,
            ym           = m,
            predicted    = pred_vec,
            actual       = test$target_ret
          )
        })

        all_preds <- bind_rows(Filter(Negate(is.null), preds))
        if (nrow(all_preds) == 0L) return(NULL)

        # Long top-N predicted factors each month (same rule as production)
        port <- all_preds |>
          filter(factor_name %in% params$factors) |>
          group_by(ym) |>
          mutate(pred_rank = rank(-predicted, ties.method = "min")) |>
          filter(pred_rank <= params$top_n) |>
          summarise(port_ret = mean(actual), .groups = "drop") |>
          left_join(rf_monthly, by = "ym")

        n  <- nrow(port)
        if (n < 12L) return(NULL)
        ret  <- port$port_ret
        rfv  <- port$rf
        xret <- ret - coalesce(rfv, 0)

        ann_ret <- prod(1 + ret)^(12 / n) - 1
        ann_vol <- sd(ret) * sqrt(12)
        sharpe  <- if (ann_vol > 0) ann_ret / ann_vol else NA_real_
        cum     <- cumprod(1 + ret)
        max_dd  <- min(cum / cummax(cum) - 1)
        hit     <- mean(ret > 0, na.rm = TRUE)

        tibble(
          n_months  = n,
          oos_cagr  = ann_ret,
          oos_vol   = ann_vol,
          oos_sharpe = sharpe,
          oos_max_dd = max_dd,
          oos_hit   = hit
        )
      }

      # Iterate over grid rows
      results <- purrr::pmap(
        list(
          a     = grid$alpha,
          nf    = grid$nfolds,
          fset  = grid$feature_set,
          lrule = grid$lambda_rule
        ),
        function(a, nf, fset, lrule) {
          cli::cli_inform(c(
            "i" = "DRIF multiverse: alpha={a} nfolds={nf} fset={fset} lambda={lrule}"
          ))
          run_spec(a, nf, fset, lrule)
        }
      )

      grid |>
        dplyr::bind_cols(
          bind_rows(
            purrr::map(results, ~ if (is.null(.x)) {
              tibble(n_months = NA_integer_, oos_cagr = NA_real_,
                     oos_vol = NA_real_, oos_sharpe = NA_real_,
                     oos_max_dd = NA_real_, oos_hit = NA_real_)
            } else .x)
          )
        )
    }),

    # ── 3. Spec-curve plot ────────────────────────────────────────
    # Fan chart: each bar = one specification, sorted by OOS Sharpe.
    # Current spec highlighted with a different fill.
    targets::tar_target(drif_multiverse_plot, {
      library(ggplot2)
      library(dplyr)

      d <- drif_multiverse |>
        filter(!is.na(oos_sharpe)) |>
        arrange(oos_sharpe) |>
        mutate(
          spec_label = paste0(spec_id,
                              " (a=", alpha,
                              " k=", nfolds,
                              " f=", feature_set,
                              " l=", sub("lambda\\.", "", lambda_rule), ")"),
          spec_label = forcats::fct_inorder(spec_label),
          highlight  = is_current
        )

      current_sharpe <- d |> filter(is_current) |> pull(oos_sharpe)
      current_rank   <- which(d$is_current)
      n_specs        <- nrow(d)

      ggplot(d, aes(x = spec_label, y = oos_sharpe, fill = highlight)) +
        geom_col(width = 0.7) +
        geom_hline(yintercept = 0, linewidth = 0.4, colour = "grey50") +
        geom_hline(yintercept = current_sharpe, linetype = "dashed",
                   colour = "grey40", linewidth = 0.35) +
        scale_fill_manual(
          values = c("TRUE" = "#4ea8de", "FALSE" = "#69d4a0"),
          labels = c("TRUE" = "Current spec", "FALSE" = "Alternative"),
          guide  = guide_legend(title = NULL)
        ) +
        coord_flip() +
        labs(
          x     = NULL,
          y     = "OOS Annualised Sharpe",
          title = "DRIF Specification Curve (2^4 = 16 specs)",
          subtitle = sprintf(
            "Current spec ranks %d of %d by OOS Sharpe (range %.2f to %.2f)",
            current_rank, n_specs,
            min(d$oos_sharpe, na.rm = TRUE),
            max(d$oos_sharpe, na.rm = TRUE)
          )
        ) +
        hd_theme() +
        theme(legend.position = "bottom")
    }),

    # ── 4. Dynamic caption ────────────────────────────────────────
    # Per dynamic-prose-values rule: compute at pipeline time, not at render.
    targets::tar_target(drif_multiverse_caption, {
      d <- drif_multiverse |>
        dplyr::filter(!is.na(oos_sharpe)) |>
        dplyr::arrange(oos_sharpe)

      n_specs        <- nrow(d)
      current_rank   <- which(d$is_current)
      min_sharpe     <- round(min(d$oos_sharpe, na.rm = TRUE), 2)
      max_sharpe     <- round(max(d$oos_sharpe, na.rm = TRUE), 2)
      current_sharpe <- round(d$oos_sharpe[current_rank], 2)

      paste0(
        "Of ", n_specs, " specifications tested (varying elastic-net alpha, ",
        "CV folds, feature set, and lambda rule), the current DRIF spec ",
        "(S01: alpha=0.5, k=5, chrono, lambda.min) ranks ", current_rank,
        " by OOS Sharpe (", current_sharpe,
        "). Sharpe range across specs: ", min_sharpe, " to ", max_sharpe,
        ". Source: plan_drif_v2.R; paper: Cakici et al. 2024 (SSRN 6005614)."
      )
    })
  )
}
