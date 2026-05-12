# XGBoost monotonic binning for signal improvement (#31)
#
# Uses XGBoost with monotonic constraints to learn non-linear transforms
# of the DRIF/MAX signals before decile sorting. The hypothesis: raw
# linear signals miss non-linear relationships that XGBoost can capture
# while preserving economic intuition (monotonic constraint = higher
# signal → higher expected return, always).
#
# Reference: https://rtichoke.netlify.app/posts/monotonic-binning-using-xgboost.html

plan_xgb_signal <- function() {
  list(
    # ── XGBoost parameters ────────────────────────────────────────
    targets::tar_target(xgb_params, {
      list(
        nrounds = 100L,
        max_depth = 3L,          # shallow trees to prevent overfitting
        eta = 0.1,               # learning rate
        subsample = 0.8,
        colsample_bytree = 0.8,
        min_train_months = 60L,  # same as DRIF
        # Monotonic constraints: all features should have positive
        # relationship with next-month return (higher signal → higher return)
        monotone_constraints = 1L  # 1 = increasing, applied to all features
      )
    }),

    # ── XGBoost signal on DRIF features (stock-level) ─────────────
    # Replace elastic net with XGBoost using same 42 features
    targets::tar_target(xgb_drif_signal, {
      library(dplyr)
      rlang::check_installed("xgboost")

      features <- stk_drif_features
      lb <- stk_params$lookback_days
      chrono_cols <- paste0("c", seq_len(lb))
      rank_cols <- paste0("r", seq_len(lb))
      feat_cols <- intersect(c(chrono_cols, rank_cols), names(features))

      months <- sort(unique(features$ym))
      min_train <- xgb_params$min_train_months
      trade_months <- months[(min_train + 1):length(months)]

      cli::cli_inform(c("i" = "XGBoost DRIF: {length(trade_months)} months, {length(feat_cols)} features"))

      predictions <- lapply(seq_along(trade_months), function(j) {
        m <- trade_months[j]
        if (j %% 24 == 0) cli::cli_inform(c("i" = "  Month {j}/{length(trade_months)}: {m}"))
        m_idx <- which(months == m)
        train_months <- months[1:(m_idx - 1)]

        train <- features |> filter(ym %in% train_months)
        test <- features |> filter(ym == m)
        if (nrow(test) == 0) return(NULL)

        X_train <- as.matrix(train[, feat_cols])
        y_train <- train$target_ret
        X_test <- as.matrix(test[, feat_cols])

        complete <- complete.cases(X_train, y_train)
        X_train <- X_train[complete, , drop = FALSE]
        y_train <- y_train[complete]
        if (length(y_train) < 200) return(NULL)

        # Monotonic constraint: all features positively related to return
        mono <- rep(xgb_params$monotone_constraints, length(feat_cols))

        dtrain <- xgboost::xgb.DMatrix(X_train, label = y_train)
        dtest <- xgboost::xgb.DMatrix(X_test)

        fit <- tryCatch({
          xgboost::xgb.train(
            params = list(
              objective = "reg:squarederror",
              max_depth = xgb_params$max_depth,
              eta = xgb_params$eta,
              subsample = xgb_params$subsample,
              colsample_bytree = xgb_params$colsample_bytree,
              monotone_constraints = paste0("(", paste(mono, collapse = ","), ")")
            ),
            data = dtrain,
            nrounds = xgb_params$nrounds,
            verbose = 0
          )
        }, error = function(e) NULL)

        if (is.null(fit)) return(NULL)
        pred <- predict(fit, dtest)

        tibble(
          ticker = test$ticker, ym = m,
          predicted_ret = pred, actual_ret = test$target_ret
        )
      })

      bind_rows(Filter(Negate(is.null), predictions))
    }),

    # ── XGBoost decile portfolios ─────────────────────────────────
    targets::tar_target(xgb_drif_portfolio, {
      library(dplyr)

      signal <- xgb_drif_signal |>
        inner_join(stk_monthly |> select(ticker, ym, monthly_ret), by = c("ticker", "ym"))

      deciled <- assign_decile(signal, predicted_ret, stk_params$n_deciles)
      port <- portfolio_longshort(deciled, long_decile = 1L, short_decile = 10L,
                                   cost_per_trade = stk_params$cost_per_trade,
                                   borrow_rate_annual = stk_params$borrow_rate_annual,
                                   max_monthly_ret = stk_params$max_monthly_ret)

      port |>
        left_join(stk_rf, by = "ym") |>
        mutate(
          date = as.Date(paste0(ym, "-15")),
          port_cum = cumprod(1 + port_ret),
          long_cum = cumprod(1 + long_ret)
        )
    }),

    # ── XGBoost metrics ───────────────────────────────────────────
    targets::tar_target(xgb_drif_metrics, {
      library(dplyr)
      p <- xgb_drif_portfolio
      bind_rows(
        calc_backtest_metrics(p |> filter(date <= stk_params$is_end), "Training"),
        calc_backtest_metrics(p |> filter(date >= stk_params$test_start, date <= stk_params$test_end), "Testing"),
        calc_backtest_metrics(p |> filter(date >= stk_params$val_start), "Validation"),
        calc_backtest_metrics(p, "Full Period")
      ) |> mutate(survivorship_biased = TRUE)  # stk_universe is survivorship-biased; see #150
    }),

    # ── XGBoost vs Elastic Net comparison ─────────────────────────
    targets::tar_target(xgb_vs_enet, {
      library(dplyr)

      xgb <- xgb_drif_portfolio |> select(ym, xgb_ret = port_ret)
      enet <- stk_drif_portfolio |> select(ym, enet_ret = port_ret)

      inner_join(xgb, enet, by = "ym") |>
        mutate(
          xgb_cum = cumprod(1 + xgb_ret),
          enet_cum = cumprod(1 + enet_ret),
          date = as.Date(paste0(ym, "-15"))
        )
    }),

    # ── Comparison plot ───────────────────────────────────────────
    targets::tar_target(xgb_vs_enet_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      comp <- xgb_vs_enet
      plot_data <- comp |>
        select(date,
               `XGBoost (monotonic)` = xgb_cum,
               `Elastic Net` = enet_cum) |>
        tidyr::pivot_longer(-date, names_to = "model", values_to = "growth")

      ggplot(plot_data, aes(date, growth, colour = model)) +
        geom_line(linewidth = 0.6) +
        geom_vline(xintercept = stk_params$test_start, linetype = "dashed",
                   colour = "grey50", linewidth = 0.4) +
        scale_y_log10(labels = dollar) +
        scale_colour_manual(values = hd_palette(2)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = "DRIF Signal: XGBoost (monotonic) vs Elastic Net") +
        hd_theme()
    }),

    # ── Feature importance from XGBoost ───────────────────────────
    targets::tar_target(xgb_feature_importance, {
      library(dplyr)
      rlang::check_installed("xgboost")

      # Train one final model on all training data for feature importance
      features <- stk_drif_features
      lb <- stk_params$lookback_days
      chrono_cols <- paste0("c", seq_len(lb))
      rank_cols <- paste0("r", seq_len(lb))
      feat_cols <- intersect(c(chrono_cols, rank_cols), names(features))

      train <- features |> filter(ym <= format(stk_params$is_end, "%Y-%m"))
      X <- as.matrix(train[, feat_cols])
      y <- train$target_ret
      complete <- complete.cases(X, y)
      X <- X[complete, , drop = FALSE]
      y <- y[complete]

      mono <- rep(1L, length(feat_cols))
      dtrain <- xgboost::xgb.DMatrix(X, label = y)

      fit <- xgboost::xgb.train(
        params = list(
          objective = "reg:squarederror",
          max_depth = 3L, eta = 0.1,
          monotone_constraints = paste0("(", paste(mono, collapse = ","), ")")
        ),
        data = dtrain, nrounds = 100L, verbose = 0
      )

      imp <- xgboost::xgb.importance(model = fit)
      imp |>
        as_tibble() |>
        mutate(
          type = ifelse(grepl("^c", Feature), "Chronological", "Rank"),
          day = as.integer(gsub("[cr]", "", Feature))
        ) |>
        arrange(desc(Gain))
    })
  )
}
