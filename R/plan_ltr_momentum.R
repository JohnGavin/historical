# LTR Cross-Sectional Momentum (#49)
#
# LambdaMART (XGBoost ranking) ranks US equities monthly by expected return.
# Long top decile, short bottom decile. 21 features from 6 lookback windows.
# Monthly rebalancing, walk-forward expanding window.
#
# NOTE: We use ~51 US non-ETF equities (not Russell 3000). Strategy demonstrates
# the methodology but results are not representative of a full-universe backtest.
# Minimum 30 stocks per month enforced for decile assignment.
#
# Reference: Burges (2010) LambdaRank/LambdaMART; Asness et al. (2013) momentum.

plan_ltr_momentum <- function() {
  list(

    # ── Parameters ────────────────────────────────────────────────────────
    targets::tar_target(ltr_params, {
      p <- bt_partitions$equity
      list(
        lookback_windows    = c(1L, 5L, 10L, 21L, 63L, 126L),
        n_quantiles         = 10L,          # deciles (universe too small for 30)
        min_history_days    = 252L,         # 1 year minimum history
        min_stocks_per_month = 30L,         # minimum for decile assignment
        rebalance_freq      = "monthly",
        train_years         = 10L,          # years of training (not 15 — less data)
        retrain_freq        = "yearly",     # retrain annually
        cost_per_trade      = 0.0010,       # 10bps per trade (tighter for demo)
        borrow_rate_annual  = 0.03,
        max_monthly_ret     = 0.20,
        oos_start           = p$test_start,
        is_end              = p$train_end,
        test_start          = p$test_start,
        test_end            = p$test_end,
        val_start           = p$val_start,
        xgb_params = list(
          max_depth    = 5L,
          eta          = 0.1,
          nrounds      = 200L,
          objective    = "rank:pairwise",   # LambdaMART
          eval_metric  = "ndcg"
        )
      )
    }),


    # ── Universe: US non-ETF equities with sufficient history ─────────────
    targets::tar_target(ltr_universe, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      # Load xgboost path for later targets
      xgb_paths <- Sys.glob("/nix/store/*-r-xgboost-*/library")
      xgb_paths <- xgb_paths[file.exists(file.path(xgb_paths, "xgboost"))]
      if (length(xgb_paths) > 0) {
        closure <- system2("nix-store", c("-qR", dirname(xgb_paths[[1]])),
                           stdout = TRUE, stderr = FALSE)
        r_libs <- closure[file.exists(file.path(closure, "library"))]
        .libPaths(c(.libPaths(), unique(file.path(r_libs, "library"))))
      }

      duckplyr_path <- Sys.glob("/nix/store/*-r-duckplyr-*/library")
      duckplyr_path <- duckplyr_path[file.exists(file.path(duckplyr_path, "duckplyr"))]
      if (length(duckplyr_path) > 0) .libPaths(c(.libPaths(), duckplyr_path[[1]]))

      ds <- hd_datasets()[["equity_daily"]]

      # Keep only US-listed equities (no dot in ticker — dots indicate
      # European exchanges: .L=LSE, .PA=Paris, .DE=Frankfurt, .ST=Stockholm, etc.)
      all_data <- duckplyr::read_parquet_duckdb(ds$url) |>
        filter(!grepl("\\.", ticker)) |>
        select(date, ticker, close, adjusted, volume, asset_class) |>
        collect()

      # Filter to tickers with at least min_history_days
      ticker_stats <- all_data |>
        group_by(ticker) |>
        summarise(n_days = n(), first_date = min(date), last_date = max(date),
                  .groups = "drop") |>
        filter(n_days >= ltr_params$min_history_days)

      cli::cli_inform(c(
        "i" = "LTR universe: {nrow(ticker_stats)} tickers with >= {ltr_params$min_history_days} days"
      ))

      all_data |>
        filter(ticker %in% ticker_stats$ticker) |>
        arrange(ticker, date)
    }),


    # ── Feature Engineering: 21 features per stock per month-end ──────────
    #
    # CRITICAL: t+1 execution — features computed from data UP TO the
    # previous month-end, applied to NEXT month's return. We use lag()
    # so signal for month m uses data up through end of month m-1.
    #
    targets::tar_target(ltr_features, {
      library(dplyr)
      library(tidyr)

      # Add xgboost + slider to libpath
      for (pkg_name in c("xgboost", "slider")) {
        if (!requireNamespace(pkg_name, quietly = TRUE)) {
          paths <- Sys.glob(sprintf("/nix/store/*-r-%s-*/library", pkg_name))
          paths <- paths[file.exists(file.path(paths, pkg_name))]
          if (length(paths) > 0) .libPaths(c(.libPaths(), paths[[1]]))
        }
      }

      univ <- ltr_universe

      # Compute daily returns (adjusted price)
      daily <- univ |>
        arrange(ticker, date) |>
        group_by(ticker) |>
        mutate(
          daily_ret  = adjusted / lag(adjusted) - 1,
          log_vol    = log(pmax(volume, 1))
        ) |>
        filter(!is.na(daily_ret)) |>
        ungroup()

      # Identify month-end dates: last trading day of each month
      month_ends <- daily |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(ticker, ym) |>
        filter(date == max(date)) |>
        ungroup() |>
        select(ticker, date, ym)

      # For each month-end date × ticker, compute rolling features
      # using data UP TO (and including) that date (for the PREVIOUS month-end)
      # t+1: we lag features forward so they apply to NEXT month's return.

      # Helper: compute cumulative return over a window ending at row i
      # slider::slide_dbl handles this efficiently
      compute_window_return <- function(ret, n) {
        slider::slide_dbl(
          ret,
          function(r) prod(1 + r) - 1,
          .before = n - 1L,
          .complete = TRUE
        )
      }

      # Rolling vol (21-day)
      compute_rolling_vol <- function(ret, n) {
        slider::slide_dbl(
          ret,
          function(r) if (length(r) < 5) NA_real_ else sd(r) * sqrt(252),
          .before = n - 1L,
          .complete = TRUE
        )
      }

      # Rolling vol (63-day)
      compute_rolling_vol63 <- function(ret, n = 63L) {
        slider::slide_dbl(
          ret,
          function(r) if (length(r) < 10) NA_real_ else sd(r) * sqrt(252),
          .before = n - 1L,
          .complete = TRUE
        )
      }

      # Rolling mean volume (for size proxy / turnover)
      compute_rolling_mean_vol <- function(vol, n) {
        slider::slide_dbl(vol, mean, .before = n - 1L, .complete = TRUE)
      }

      # Compute all features for each ticker
      tickers <- unique(daily$ticker)

      cli::cli_inform(c("i" = "LTR features: computing for {length(tickers)} tickers"))

      all_features <- lapply(tickers, function(tk) {
        d <- daily |>
          filter(ticker == tk) |>
          arrange(date)

        if (nrow(d) < ltr_params$min_history_days) return(NULL)

        ret <- d$daily_ret
        lvol <- d$log_vol

        # Raw return windows
        r1   <- compute_window_return(ret, 1L)
        r5   <- compute_window_return(ret, 5L)
        r10  <- compute_window_return(ret, 10L)
        r21  <- compute_window_return(ret, 21L)
        r63  <- compute_window_return(ret, 63L)
        r126 <- compute_window_return(ret, 126L)
        r252 <- compute_window_return(ret, 252L)

        # Rolling vols
        v21 <- compute_rolling_vol(ret, 21L)
        v63 <- compute_rolling_vol63(ret, 63L)

        # Rolling mean volume (for turnover and size proxy)
        mv21 <- compute_rolling_mean_vol(lvol, 21L)
        mv63 <- compute_rolling_mean_vol(lvol, 63L)

        tibble(
          ticker = tk,
          date   = d$date,

          # Raw returns
          ret_1d   = r1,
          ret_5d   = r5,
          ret_10d  = r10,
          ret_21d  = r21,
          ret_63d  = r63,
          ret_126d = r126,
          ret_252d = r252,

          # Vol-normalised returns: ret / annualised vol
          nret_1d   = r1   / pmax(v21 / sqrt(252), 1e-8),
          nret_5d   = r5   / pmax(v21 / sqrt(252) * sqrt(5), 1e-8),
          nret_10d  = r10  / pmax(v21 / sqrt(252) * sqrt(10), 1e-8),
          nret_21d  = r21  / pmax(v21, 1e-8),
          nret_63d  = r63  / pmax(v21, 1e-8),
          nret_126d = r126 / pmax(v21, 1e-8),

          # Momentum composite features
          mom_1_3  = r21 - r63,
          mom_3_6  = r63 - r126,
          mom_1_6  = r21 - r126,
          mom_6_12 = r126 - r252,

          # Vol features
          vol_21d   = v21,
          vol_63d   = v63,
          vol_ratio = pmin(pmax(v21 / pmax(v63, 1e-8), 0.1), 10),

          # Turnover / size proxies (log-volume based)
          turnover_21d = pmin(pmax(mv21 / pmax(mv63, 1e-8), 0.1), 10),
          size_rank    = mv63   # rank applied monthly below
        )
      })

      daily_features <- bind_rows(Filter(Negate(is.null), all_features))

      # Merge with month-end dates to get one row per ticker-month
      # Features on month m = values at end of month m (raw data up to month m)
      # We then LAG by 1 month so they correspond to PREVIOUS month-end signals
      month_end_features <- month_ends |>
        inner_join(daily_features, by = c("ticker", "date")) |>
        arrange(ticker, ym)

      # Compute next-month return (the prediction target)
      monthly_rets <- month_end_features |>
        select(ticker, ym) |>
        inner_join(
          month_end_features |>
            group_by(ticker) |>
            arrange(ym) |>
            mutate(
              price_eom = daily_features$ret_1d[match(paste(ticker, date),
                                                      paste(daily_features$ticker, daily_features$date))]
            ) |>
            ungroup(),
          by = c("ticker", "ym")
        )

      # Simpler: compute next-month return from month-end adjusted prices
      adj_eom <- univ |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(ticker, ym) |>
        filter(date == max(date)) |>
        ungroup() |>
        arrange(ticker, ym) |>
        group_by(ticker) |>
        mutate(next_ret = lead(adjusted) / adjusted - 1) |>
        ungroup() |>
        select(ticker, ym, next_ret)

      # t+1: lag features by 1 month — signal at end of month m predicts month m+1
      # We already have features at end of month m; we join them to next_ret for m+1
      feat_lagged <- month_end_features |>
        group_by(ticker) |>
        arrange(ym) |>
        mutate(
          # Shift features so they apply to next month
          ym_predict = lead(ym)
        ) |>
        filter(!is.na(ym_predict)) |>
        ungroup() |>
        rename(ym_signal = ym) |>
        rename(ym = ym_predict)

      # Cross-sectional size rank (within each month)
      feat_final <- feat_lagged |>
        group_by(ym) |>
        mutate(size_rank = rank(size_rank, ties.method = "average") / n()) |>
        ungroup() |>
        left_join(adj_eom, by = c("ticker", "ym")) |>
        filter(!is.na(next_ret)) |>
        # Remove rows with all-NA features
        filter(!is.na(ret_21d), !is.na(vol_21d))

      cli::cli_inform(c(
        "i" = "LTR features: {nrow(feat_final)} rows, {n_distinct(feat_final$ym)} months"
      ))

      feat_final
    }),


    # ── Walk-Forward Model: XGBoost LambdaMART ───────────────────────────
    #
    # Expanding window: for each year Y from 2015 onwards,
    # train on all data before year Y, predict rankings for each month in year Y.
    # Retrain annually. Never use future data.
    #
    targets::tar_target(ltr_model, {
      library(dplyr)

      # Add xgboost to libpath
      if (!requireNamespace("xgboost", quietly = TRUE)) {
        xgb_paths <- Sys.glob("/nix/store/*-r-xgboost-*/library")
        xgb_paths <- xgb_paths[file.exists(file.path(xgb_paths, "xgboost"))]
        if (length(xgb_paths) > 0) {
          closure <- system2("nix-store", c("-qR", dirname(xgb_paths[[1]])),
                             stdout = TRUE, stderr = FALSE)
          r_libs <- closure[file.exists(file.path(closure, "library"))]
          .libPaths(c(.libPaths(), unique(file.path(r_libs, "library"))))
        }
      }

      features <- ltr_features

      feature_cols <- setdiff(
        names(features),
        c("ym", "ticker", "date", "ym_signal", "next_ret",
          "ret_252d",   # optional — often NA early in history
          "mom_6_12")   # also uses 252d
      )

      # Only use months with complete features
      train_months <- sort(unique(features$ym))

      # Walk-forward: train up to year Y, predict year Y
      # Start predictions from first year with >= train_years * 12 months of data
      min_train_months <- ltr_params$train_years * 12L

      all_predictions <- list()

      first_pred_idx <- min_train_months + 1L
      if (first_pred_idx > length(train_months)) {
        cli::cli_warn(c("!" = "LTR: insufficient data for walk-forward"))
        return(tibble(ym = character(), ticker = character(),
                      predicted_rank = numeric(), ltr_score = numeric()))
      }

      # Identify test years (retrain annually)
      pred_months <- train_months[first_pred_idx:length(train_months)]
      pred_years  <- sort(unique(substr(pred_months, 1, 4)))

      cli::cli_inform(c(
        "i" = "LTR walk-forward: {length(pred_years)} test years, {length(pred_months)} test months"
      ))

      for (yr in pred_years) {
        yr_months <- pred_months[substr(pred_months, 1, 4) == yr]
        # Training data: all months BEFORE this year
        cutoff_ym <- paste0(yr, "-01")
        train_data <- features |>
          filter(ym < cutoff_ym) |>
          filter(!is.na(ret_21d), !is.na(vol_21d), !is.na(next_ret))

        # Remove columns that are mostly NA
        na_frac <- colMeans(is.na(train_data[, feature_cols, drop = FALSE]))
        good_cols <- feature_cols[na_frac < 0.3]  # keep cols with <30% NA

        if (nrow(train_data) < 200 || length(good_cols) < 5) {
          cli::cli_warn(c("!" = "LTR: skipping year {yr} — insufficient training data"))
          next
        }

        X_train <- as.matrix(train_data[, good_cols, drop = FALSE])
        y_train <- train_data$next_ret

        # Impute remaining NAs with column median
        for (col_i in seq_len(ncol(X_train))) {
          na_idx <- is.na(X_train[, col_i])
          if (any(na_idx)) {
            X_train[na_idx, col_i] <- median(X_train[!na_idx, col_i], na.rm = TRUE)
          }
        }

        # XGBoost ranking requires group information: stocks per month
        groups_train <- as.integer(table(train_data$ym))

        dtrain <- xgboost::xgb.DMatrix(
          data  = X_train,
          label = y_train
        )
        xgboost::setinfo(dtrain, "group", groups_train)

        model <- tryCatch({
          xgboost::xgb.train(
            params = list(
              objective   = ltr_params$xgb_params$objective,
              eval_metric = ltr_params$xgb_params$eval_metric,
              max_depth   = ltr_params$xgb_params$max_depth,
              eta         = ltr_params$xgb_params$eta,
              nthread     = 1L  # deterministic
            ),
            data    = dtrain,
            nrounds = ltr_params$xgb_params$nrounds,
            verbose = 0
          )
        }, error = function(e) {
          cli::cli_warn(c("!" = "LTR xgb.train failed for {yr}: {conditionMessage(e)}"))
          NULL
        })

        if (is.null(model)) next

        # Predict for each month in this year
        for (test_ym in yr_months) {
          test_data <- features |>
            filter(ym == test_ym) |>
            filter(!is.na(ret_21d), !is.na(vol_21d))

          if (nrow(test_data) < ltr_params$min_stocks_per_month) {
            cli::cli_warn(c(
              "!" = "LTR: {test_ym} has only {nrow(test_data)} stocks (need {ltr_params$min_stocks_per_month})"
            ))
            next
          }

          X_test <- as.matrix(test_data[, good_cols, drop = FALSE])
          # Impute NAs
          for (col_i in seq_len(ncol(X_test))) {
            na_idx <- is.na(X_test[, col_i])
            if (any(na_idx)) {
              X_test[na_idx, col_i] <- median(X_test[!na_idx, col_i], na.rm = TRUE)
            }
          }

          scores <- predict(model, xgboost::xgb.DMatrix(X_test))

          all_predictions[[length(all_predictions) + 1L]] <- tibble(
            ym             = test_ym,
            ticker         = test_data$ticker,
            ltr_score      = scores,
            predicted_rank = rank(-scores, ties.method = "average"),
            n_stocks       = nrow(test_data)
          )
        }
      }

      if (length(all_predictions) == 0) {
        cli::cli_warn(c("!" = "LTR: no predictions generated"))
        return(tibble(ym = character(), ticker = character(),
                      predicted_rank = numeric(), ltr_score = numeric()))
      }

      result <- bind_rows(all_predictions)
      cli::cli_inform(c(
        "v" = "LTR model: {nrow(result)} predictions, {n_distinct(result$ym)} months"
      ))
      result
    }),


    # ── Portfolio Construction: Long D10, Short D1 ────────────────────────
    targets::tar_target(ltr_portfolio, {
      library(dplyr)

      # Merge predictions with actual next-month returns
      # Actual returns come from ltr_features (next_ret column)
      rets <- ltr_features |>
        select(ticker, ym, next_ret)

      merged <- ltr_model |>
        inner_join(rets, by = c("ticker", "ym")) |>
        filter(!is.na(next_ret))

      # Assign deciles per month: decile 1 = top score (long), 10 = bottom (short)
      deciled <- merged |>
        group_by(ym) |>
        filter(n() >= ltr_params$min_stocks_per_month) |>
        mutate(
          decile = ntile(desc(ltr_score), ltr_params$n_quantiles)
        ) |>
        ungroup()

      # Monthly portfolio returns
      long_ret <- deciled |>
        filter(decile == 1L) |>
        group_by(ym) |>
        summarise(long_ret = mean(next_ret, na.rm = TRUE), n_long = n(), .groups = "drop")

      short_ret <- deciled |>
        filter(decile == ltr_params$n_quantiles) |>
        group_by(ym) |>
        summarise(short_ret = mean(next_ret, na.rm = TRUE), n_short = n(), .groups = "drop")

      port <- inner_join(long_ret, short_ret, by = "ym") |>
        mutate(
          # Winsorise returns
          long_ret  = pmin(pmax(long_ret,  -ltr_params$max_monthly_ret), ltr_params$max_monthly_ret),
          short_ret = pmin(pmax(short_ret, -ltr_params$max_monthly_ret), ltr_params$max_monthly_ret),
          # Costs: 80% turnover assumed for monthly sort
          turnover   = 0.80,
          trade_cost = turnover * ltr_params$cost_per_trade * 2 * 2,
          borrow_cost = ltr_params$borrow_rate_annual / 12,
          total_cost  = trade_cost + borrow_cost,
          # Long-short return
          port_ret  = long_ret - short_ret - total_cost,
          date      = as.Date(paste0(ym, "-15"))
        )

      # Add risk-free rate
      port |>
        left_join(stk_rf, by = "ym") |>
        mutate(
          port_cum  = cumprod(1 + port_ret),
          long_cum  = cumprod(1 + long_ret)
        )
    }),


    # ── Metrics: Training, Testing, Full ──────────────────────────────────
    targets::tar_target(ltr_metrics, {
      library(dplyr)
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      p <- ltr_params

      compute_ltr_metrics <- function(df, label) {
        df <- df |> filter(!is.na(port_ret))
        n  <- nrow(df)
        if (n < 12L) return(NULL)

        ann_ret <- prod(1 + df$port_ret)^(12 / n) - 1
        ann_vol <- sd(df$port_ret) * sqrt(12)
        rf_ann  <- mean(df$rf_ret, na.rm = TRUE) * 12
        cum     <- cumprod(1 + df$port_ret)
        max_dd  <- min(cum / cummax(cum) - 1)

        # HAC Sharpe (Newey-West)
        hac <- tryCatch(hd_hac_sharpe(df$port_ret),
                        error = function(e) list(hac_tstat = NA_real_, naive_sharpe = NA_real_))

        tibble(
          period     = label,
          months     = n,
          cagr       = ann_ret,
          vol        = ann_vol,
          sharpe     = if (ann_vol < 1e-8) NA_real_ else (ann_ret - rf_ann) / ann_vol,
          max_dd     = max_dd,
          hac_sharpe = hac$naive_sharpe,
          hac_tstat  = hac$hac_tstat,
          avg_long   = mean(df$n_long, na.rm = TRUE),
          avg_short  = mean(df$n_short, na.rm = TRUE)
        )
      }

      port <- ltr_portfolio

      bind_rows(
        compute_ltr_metrics(port |> filter(date <= p$is_end),        "Training"),
        compute_ltr_metrics(port |> filter(date >= p$test_start,
                                           date <= p$test_end),      "Testing"),
        compute_ltr_metrics(port |> filter(date >= p$val_start),     "Validation"),
        compute_ltr_metrics(port,                                     "Full Period")
      ) |> filter(!is.null(.))
    }),


    # ── Equity Curve Plot: LTR vs SPY ─────────────────────────────────────
    targets::tar_target(ltr_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      port <- ltr_portfolio

      # Get SPY monthly returns for benchmark
      spy_monthly <- stk_universe |>
        filter(ticker == "SPY") |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(ym) |>
        filter(date == max(date)) |>
        ungroup() |>
        arrange(date) |>
        mutate(spy_ret = adjusted / lag(adjusted) - 1) |>
        filter(!is.na(spy_ret)) |>
        select(ym, spy_ret)

      plot_data <- port |>
        left_join(spy_monthly, by = "ym") |>
        filter(!is.na(port_ret), !is.na(spy_ret)) |>
        mutate(
          spy_cum  = cumprod(1 + spy_ret),
          port_cum = cumprod(1 + port_ret)
        ) |>
        select(date, `LTR L/S` = port_cum, `SPY Buy & Hold` = spy_cum) |>
        tidyr::pivot_longer(-date, names_to = "strategy", values_to = "growth")

      oos_date <- ltr_params$oos_start

      ggplot(plot_data, aes(date, growth, colour = strategy)) +
        geom_line(linewidth = 0.7) +
        geom_vline(xintercept = oos_date, linetype = "dashed",
                   colour = "grey50", linewidth = 0.4) +
        annotate("text", x = oos_date + 30, y = max(plot_data$growth, na.rm = TRUE) * 0.9,
                 label = "OOS start", colour = "grey50", hjust = 0, size = 3) +
        scale_y_log10(labels = dollar) +
        scale_colour_manual(values = hd_palette(2)) +
        labs(
          x        = NULL,
          y        = "Growth of $1 (log scale)",
          colour   = NULL,
          title    = "LTR Cross-Sectional Momentum: Long-Short vs SPY",
          subtitle = paste0(
            "~", n_distinct(ltr_universe$ticker), " US equities | ",
            "10 deciles | Monthly rebalancing | Costs: ",
            round(ltr_params$cost_per_trade * 10000), "bps/trade"
          )
        ) +
        hd_theme()
    }),


    # ── Dynamic Caption ───────────────────────────────────────────────────
    targets::tar_target(ltr_caption, {
      library(dplyr)

      full_m <- ltr_metrics |> filter(period == "Full Period")
      test_m <- ltr_metrics |> filter(period == "Testing")

      if (nrow(full_m) == 0) return("LTR strategy metrics unavailable.")

      paste0(
        "LTR Cross-Sectional Momentum: LambdaMART (XGBoost rank:pairwise) ranking ",
        n_distinct(ltr_universe$ticker),
        " US equities monthly into deciles. ",
        "Long top decile, short bottom decile. ",
        "Full-period CAGR: ", round(full_m$cagr * 100, 1), "%, ",
        "Sharpe: ", round(full_m$sharpe, 2), ", ",
        "Max DD: ", round(full_m$max_dd * 100, 1), "%. ",
        if (nrow(test_m) > 0) {
          paste0(
            "OOS testing period (", ltr_params$test_start, " – ", ltr_params$test_end, "): ",
            "CAGR ", round(test_m$cagr * 100, 1), "%, ",
            "Sharpe ", round(test_m$sharpe, 2), ". "
          )
        } else "",
        "NOTE: ~", n_distinct(ltr_universe$ticker),
        " stocks vs Russell 3000 (~3000) — results illustrate methodology only. ",
        "Costs: ", round(ltr_params$cost_per_trade * 10000), "bps/trade + ",
        round(ltr_params$borrow_rate_annual * 100), "% annual borrow."
      )
    }),


    # ── Feature Importance ────────────────────────────────────────────────
    #
    # NOTE: Feature importance from XGBoost LambdaMART can be misleading.
    # With rank:pairwise objective, importance measures split gain on the
    # ranking loss — not the return prediction. See plan_xgb_signal.R (#31)
    # for lessons on monotonic constraints + shallow trees producing
    # compressed importance distributions.
    #
    targets::tar_target(ltr_feature_importance, {
      library(dplyr)

      if (!requireNamespace("xgboost", quietly = TRUE)) {
        xgb_paths <- Sys.glob("/nix/store/*-r-xgboost-*/library")
        xgb_paths <- xgb_paths[file.exists(file.path(xgb_paths, "xgboost"))]
        if (length(xgb_paths) > 0) {
          closure <- system2("nix-store", c("-qR", dirname(xgb_paths[[1]])),
                             stdout = TRUE, stderr = FALSE)
          r_libs <- closure[file.exists(file.path(closure, "library"))]
          .libPaths(c(.libPaths(), unique(file.path(r_libs, "library"))))
        }
      }

      features <- ltr_features

      feature_cols <- setdiff(
        names(features),
        c("ym", "ticker", "date", "ym_signal", "next_ret", "ret_252d", "mom_6_12")
      )

      # Train on full in-sample period
      train_data <- features |>
        filter(ym <= format(ltr_params$is_end, "%Y-%m")) |>
        filter(!is.na(ret_21d), !is.na(vol_21d), !is.na(next_ret))

      na_frac <- colMeans(is.na(train_data[, feature_cols, drop = FALSE]))
      good_cols <- feature_cols[na_frac < 0.3]

      X <- as.matrix(train_data[, good_cols, drop = FALSE])
      y <- train_data$next_ret

      for (col_i in seq_len(ncol(X))) {
        na_idx <- is.na(X[, col_i])
        if (any(na_idx)) X[na_idx, col_i] <- median(X[!na_idx, col_i], na.rm = TRUE)
      }

      groups <- as.integer(table(train_data$ym))
      dtrain <- xgboost::xgb.DMatrix(data = X, label = y)
      xgboost::setinfo(dtrain, "group", groups)

      fit <- tryCatch({
        xgboost::xgb.train(
          params = list(
            objective   = ltr_params$xgb_params$objective,
            eval_metric = ltr_params$xgb_params$eval_metric,
            max_depth   = ltr_params$xgb_params$max_depth,
            eta         = ltr_params$xgb_params$eta,
            nthread     = 1L
          ),
          data    = dtrain,
          nrounds = ltr_params$xgb_params$nrounds,
          verbose = 0
        )
      }, error = function(e) {
        cli::cli_warn(c("!" = "LTR feature importance model failed: {conditionMessage(e)}"))
        NULL
      })

      if (is.null(fit)) {
        return(tibble(Feature = character(), Gain = numeric(),
                      Cover = numeric(), Frequency = numeric()))
      }

      imp <- xgboost::xgb.importance(model = fit) |>
        as_tibble() |>
        mutate(
          feature_group = dplyr::case_when(
            grepl("^ret_",   Feature) ~ "Raw return",
            grepl("^nret_",  Feature) ~ "Vol-normalised return",
            grepl("^mom_",   Feature) ~ "Momentum differential",
            grepl("^vol_",   Feature) ~ "Volatility",
            grepl("turnover", Feature) ~ "Turnover",
            grepl("size",    Feature) ~ "Size",
            TRUE                      ~ "Other"
          )
        ) |>
        arrange(desc(Gain))

      cli::cli_inform(c(
        "i" = "LTR feature importance: top feature = {imp$Feature[1]} (gain={round(imp$Gain[1], 3)})",
        "!" = "CAVEAT: rank:pairwise importance reflects ranking loss, not return prediction."
      ))

      imp
    }),


    # ── Alpha Decay: Signal delay in months (monthly strategy) ───────────
    #
    # Monthly rebalancing: delay signal by 1-5 months.
    # Delay d means we use the signal from d months ago.
    #
    targets::tar_target(ltr_alpha_decay, {
      library(dplyr)
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      delays <- 1:5

      rets <- ltr_features |> select(ticker, ym, next_ret)

      compute_decay_metrics <- function(d) {
        # Delay signal by d months: shift predicted_rank forward by d months
        delayed_signal <- ltr_model |>
          group_by(ticker) |>
          arrange(ym) |>
          mutate(ym_delayed = dplyr::lead(ym, n = d)) |>
          filter(!is.na(ym_delayed)) |>
          ungroup() |>
          select(ticker, ym = ym_delayed, ltr_score, predicted_rank)

        merged <- delayed_signal |>
          inner_join(rets, by = c("ticker", "ym")) |>
          filter(!is.na(next_ret))

        if (nrow(merged) < 100) return(NULL)

        deciled <- merged |>
          group_by(ym) |>
          filter(n() >= ltr_params$min_stocks_per_month) |>
          mutate(decile = ntile(desc(ltr_score), ltr_params$n_quantiles)) |>
          ungroup()

        long_r  <- deciled |> filter(decile == 1L) |>
          group_by(ym) |> summarise(long_ret = mean(next_ret, na.rm = TRUE), n_long = n(), .groups = "drop")
        short_r <- deciled |> filter(decile == ltr_params$n_quantiles) |>
          group_by(ym) |> summarise(short_ret = mean(next_ret, na.rm = TRUE), n_short = n(), .groups = "drop")

        port <- inner_join(long_r, short_r, by = "ym") |>
          mutate(
            long_ret  = pmin(pmax(long_ret,  -ltr_params$max_monthly_ret), ltr_params$max_monthly_ret),
            short_ret = pmin(pmax(short_ret, -ltr_params$max_monthly_ret), ltr_params$max_monthly_ret),
            trade_cost  = 0.80 * ltr_params$cost_per_trade * 4,
            borrow_cost = ltr_params$borrow_rate_annual / 12,
            port_ret    = long_ret - short_ret - trade_cost - borrow_cost
          )

        n      <- nrow(port)
        if (n < 12) return(NULL)
        ann_ret <- prod(1 + port$port_ret)^(12 / n) - 1
        ann_vol <- sd(port$port_ret) * sqrt(12)
        sharpe  <- if (ann_vol < 1e-8) NA_real_ else ann_ret / ann_vol

        hac <- tryCatch(hd_hac_sharpe(port$port_ret),
                        error = function(e) list(hac_tstat = NA_real_, naive_sharpe = NA_real_))

        tibble(delay_months = d, months = n, cagr = ann_ret, vol = ann_vol,
               sharpe = sharpe, hac_tstat = hac$hac_tstat)
      }

      results <- lapply(delays, compute_decay_metrics)
      bind_rows(Filter(Negate(is.null), results))
    }),


    # ── Subperiod Analysis: 3 equal subperiods ───────────────────────────
    targets::tar_target(ltr_subperiod, {
      library(dplyr)
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      port <- ltr_portfolio |> filter(!is.na(port_ret)) |> arrange(date)

      if (nrow(port) < 36L) {
        return(tibble(subperiod = character(), start = as.Date(NA),
                      end = as.Date(NA), months = integer(),
                      cagr = numeric(), sharpe = numeric(), max_dd = numeric()))
      }

      n <- nrow(port)
      sp_size <- n %/% 3L
      sp_idx  <- list(
        1:(sp_size),
        (sp_size + 1L):(2L * sp_size),
        (2L * sp_size + 1L):n
      )

      compute_sp_metrics <- function(idx, label) {
        df <- port[idx, ]
        nm <- nrow(df)
        if (nm < 6L) return(NULL)
        ann_ret <- prod(1 + df$port_ret)^(12 / nm) - 1
        ann_vol <- sd(df$port_ret) * sqrt(12)
        rf_ann  <- mean(df$rf_ret, na.rm = TRUE) * 12
        cum     <- cumprod(1 + df$port_ret)
        max_dd  <- min(cum / cummax(cum) - 1)
        sharpe  <- if (ann_vol < 1e-8) NA_real_ else (ann_ret - rf_ann) / ann_vol

        hac <- tryCatch(hd_hac_sharpe(df$port_ret),
                        error = function(e) list(hac_tstat = NA_real_))

        tibble(
          subperiod  = label,
          start      = min(df$date),
          end        = max(df$date),
          months     = nm,
          cagr       = ann_ret,
          vol        = ann_vol,
          sharpe     = sharpe,
          max_dd     = max_dd,
          hac_tstat  = hac$hac_tstat
        )
      }

      bind_rows(
        compute_sp_metrics(sp_idx[[1]], "Subperiod 1"),
        compute_sp_metrics(sp_idx[[2]], "Subperiod 2"),
        compute_sp_metrics(sp_idx[[3]], "Subperiod 3")
      )
    })

  )
}
