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

      # Variant A (filter-then-rank, Cakici 2023 / #449):
      # Drop sub-ADV names BEFORE cutting deciles — illiquid micro-caps with
      # extreme XGB predictions cannot end up in decile 1 or 10.
      # ADV source: stk_monthly_adv (column adv_dollars = median_daily_volume × avg_close).
      # stk_params$adv_threshold is the single source of truth (no hardcoding).
      # XGB A/B evidence: see explorations/cakici_design_ab/results/xgb_SUMMARY.md
      signal <- signal |>
        inner_join(
          stk_monthly_adv |> select(ticker, ym, adv_dollars),
          by = c("ticker", "ym")
        ) |>
        filter(adv_dollars >= stk_params$adv_threshold)

      # Re-apply minimum-stocks guard AFTER the ADV filter (#449):
      # the gate can drop names and push some months below the decile threshold.
      stocks_per_month <- signal |> count(ym, name = "n_stocks")
      valid_months <- stocks_per_month |>
        filter(n_stocks >= stk_params$n_deciles * 5L) |>
        pull(ym)
      signal <- signal |> filter(ym %in% valid_months)

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

      # #354: inner_join does NOT preserve chronological order; without an
      # explicit arrange(ym) the subsequent cumprod() runs over rows in
      # whatever order inner_join leaves them. The plot then draws a line
      # by date through the out-of-order cumulative series, producing the
      # ~2005 vertical jump and the apparent "2026 drop" (just the last
      # out-of-order row plotted at the end of the x-axis).
      inner_join(xgb, enet, by = "ym") |>
        arrange(ym) |>
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
    }),

    # ── Registry sentinel (#442 Tier 2) ──────────────────────────────────────
    # Upserts bt.strategy row for "xgb_drif", records bt.run + bt.metric rows
    # (full-period metrics) + bt.diagnostic (survivorship_biased flag).
    # Returns tibble(strategy_id, run_uuid).
    # Guard: returns empty tibble if DBI / duckdb are unavailable.
    targets::tar_target(xgb_drif_register_runs, {
      .xgb_drif_register_runs(
        strategy_names    = strategy_names,
        xgb_drif_metrics  = xgb_drif_metrics,
        xgb_drif_portfolio = xgb_drif_portfolio
      )
    })

  )
}


# ── Internal helper ────────────────────────────────────────────────────────────
# Prefixed .xgb_drif_* (private; not exported from the package).
# Mirrors .drif_register_runs() from plan_drif.R.

#' Register XGB DRIF backtest run in the strategy registry
#'
#' @param strategy_names Tibble from the `strategy_names` target.
#' @param xgb_drif_metrics Tibble from the `xgb_drif_metrics` target.
#' @param xgb_drif_portfolio Tibble from the `xgb_drif_portfolio` target; used
#'   to extract returns for SSR/top5pct stability metrics.
#'
#' @return Tibble with columns: strategy_id, run_uuid.
#' @noRd
.xgb_drif_register_runs <- function(strategy_names, xgb_drif_metrics,
                                    xgb_drif_portfolio) {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("duckdb", quietly = TRUE)) {
    return(tibble::tibble(
      strategy_id = character(),
      run_uuid    = character()
    ))
  }

  path <- historicaldata::hd_registry_path()
  historicaldata::hd_registry_init(path)
  con <- historicaldata::hd_registry_open(path, read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  strat_row <- strategy_names |>
    dplyr::filter(.data$code_name == "xgb_drif") |>
    dplyr::transmute(
      strategy_id        = .data$code_name,
      short_name         = .data$short_name,
      long_name          = .data$long_name,
      asset_class        = .data$asset_class,
      frequency          = .data$frequency,
      ann_factor         = as.integer(.data$ann_factor),
      directionality     = as.character(.data$directionality),
      liquidity_tier     = as.character(.data$liquidity_tier),
      time_horizon_days  = as.integer(.data$time_horizon_days_avg),
      trades_per_year    = as.numeric(.data$trades_per_year_avg),
      turnover_pct       = as.numeric(.data$turnover_pct_per_period_avg),
      tags               = .data$tags,
      research_paper_doi = .data$research_paper_doi
    )

  historicaldata::hd_strategy_upsert(con, strat_row)

  uu <- historicaldata::hd_run_upsert(
    con,
    strategy_id      = "xgb_drif",
    partition        = "phase1",
    pipeline_version = "phase1"
  )

  # Record full-period metrics row (numeric cols only; survivorship_biased
  # logical is silently skipped by .normalise_metric_long).
  full_row <- xgb_drif_metrics[xgb_drif_metrics$period == "Full Period", , drop = FALSE]
  if (nrow(full_row) == 1L) {
    metric_cols <- setdiff(names(full_row), "period")
    historicaldata::hd_metric_record(con, uu, full_row[, metric_cols, drop = FALSE])
  }

  # Record survivorship_biased as a diagnostic (#442).
  if ("survivorship_biased" %in% names(xgb_drif_metrics)) {
    historicaldata::hd_diagnostic_record(con, uu, tibble::tibble(
      diagnostic_name = "survivorship_biased",
      value_num  = as.numeric(any(xgb_drif_metrics$survivorship_biased)),
      value_text = as.character(any(xgb_drif_metrics$survivorship_biased))
    ))
  }

  # Record SSR + top5pct stability metrics (#400). Monthly: w=36, ann_factor=12.
  rets <- xgb_drif_portfolio$port_ret
  rets <- rets[!is.na(rets)]
  if (length(rets) > 0L) {
    historicaldata::hd_record_stability_metrics(
      con        = con,
      run_uuid   = uu,
      returns    = rets,
      w          = 36L,
      ann_factor = 12L
    )
  }

  tibble::tibble(strategy_id = "xgb_drif", run_uuid = uu)
}
