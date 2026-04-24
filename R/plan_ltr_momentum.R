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
      # Only fetch columns we need to minimise memory
      all_data <- duckplyr::read_parquet_duckdb(ds$url) |>
        filter(!grepl("\\.", ticker)) |>
        select(date, ticker, adjusted, volume) |>
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


    # ── Feature Engineering: pre-computed via scripts/compute_ltr_features.R
    #
    # 21 features per stock per month-end, t+1 execution enforced.
    # Pre-computed outside targets (too memory-intensive for callr subprocess).
    # Run: Rscript scripts/compute_ltr_features.R
    #
    targets::tar_target(ltr_features, {
      library(dplyr)
      feat_path <- here::here("data", "raw", "ltr_features.parquet")
      if (!file.exists(feat_path)) {
        cli::cli_abort(c(
          "x" = "LTR features not found at {feat_path}",
          "i" = "Run: Rscript scripts/compute_ltr_features.R"
        ))
      }
      feat <- arrow::read_parquet(feat_path)
      cli::cli_inform(c(
        "v" = "LTR features: {nrow(feat)} rows, {n_distinct(feat$ticker)} tickers, {n_distinct(feat$ym)} months"
      ))
      feat
    }),


    # ── Walk-Forward Model + Portfolio: pre-computed via nix develop ──────
    #
    # XGBoost LambdaMART requires nix develop shell (compiled .so ABI mismatch
    # from global dev shell causes segfault). Pre-computed via:
    #   nix develop . --command Rscript scripts/compute_ltr_model.R
    #
    # Reads: data/raw/ltr_portfolio.parquet, data/raw/ltr_model_importance.parquet
    #
    targets::tar_target(ltr_portfolio, {
      library(dplyr)
      port_path <- here::here("data", "raw", "ltr_portfolio.parquet")
      if (!file.exists(port_path)) {
        cli::cli_abort(c(
          "x" = "LTR portfolio not found at {port_path}",
          "i" = "Run: nix develop . --command Rscript scripts/compute_ltr_model.R"
        ))
      }
      port <- arrow::read_parquet(port_path)
      cli::cli_inform(c(
        "v" = "LTR portfolio: {nrow(port)} months, {format(min(port$date), '%Y-%m')} to {format(max(port$date), '%Y-%m')}"
      ))
      port |> mutate(
        port_ret = ls_ret_net,
        port_cum = cumprod(1 + port_ret)
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
        cum     <- cumprod(1 + df$port_ret)
        max_dd  <- min(cum / cummax(cum) - 1)

        hac <- tryCatch(hd_hac_sharpe(df$port_ret),
                        error = function(e) list(hac_tstat = NA_real_, naive_sharpe = NA_real_))

        tibble::tibble(
          period     = label,
          months     = n,
          cagr       = round(ann_ret * 100, 1),
          vol        = round(ann_vol * 100, 1),
          max_dd     = round(max_dd * 100, 1),
          hac_sharpe = round(hac$naive_sharpe, 2),
          hac_tstat  = round(hac$hac_tstat, 2),
          avg_long   = if ("n_long" %in% names(df)) round(mean(df$n_long, na.rm = TRUE)) else NA_integer_,
          avg_short  = if ("n_short" %in% names(df)) round(mean(df$n_short, na.rm = TRUE)) else NA_integer_
        )
      }

      port <- ltr_portfolio

      bind_rows(Filter(Negate(is.null), list(
        compute_ltr_metrics(port |> filter(as.Date(date) <= p$is_end),         "Training"),
        compute_ltr_metrics(port |> filter(as.Date(date) >= p$test_start,
                                            as.Date(date) <= p$test_end),       "Testing"),
        compute_ltr_metrics(port |> filter(as.Date(date) >= p$val_start),      "Validation"),
        compute_ltr_metrics(port,                                               "Full Period")
      )))
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
        "**LTR Cross-Sectional Momentum.** LambdaMART (XGBoost rank:pairwise) ranking ",
        "US equities monthly into deciles. ",
        "Long top decile, short bottom decile. ",
        "Full-period CAGR: ", full_m$cagr, "%, ",
        "HAC Sharpe: ", full_m$hac_sharpe, ", ",
        "Max DD: ", full_m$max_dd, "%. ",
        if (nrow(test_m) > 0) {
          paste0(
            "OOS (", ltr_params$test_start, "\u2013", ltr_params$test_end, "): ",
            "CAGR ", test_m$cagr, "%, ",
            "HAC Sharpe ", test_m$hac_sharpe, ". "
          )
        } else "",
        "Costs: 10bps/trade + 3% annual borrow."
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
    # ── Feature Importance: pre-computed via nix develop ──────────────
    targets::tar_target(ltr_feature_importance, {
      library(dplyr)
      imp_path <- here::here("data", "raw", "ltr_model_importance.parquet")
      if (!file.exists(imp_path)) {
        cli::cli_warn("LTR importance not found — run: nix develop . --command Rscript scripts/compute_ltr_model.R")
        return(tibble::tibble(Feature = character(), Gain = numeric()))
      }
      imp <- arrow::read_parquet(imp_path) |>
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
        )
      # Aggregate across years (importance computed per training year)
      imp |>
        group_by(Feature, feature_group) |>
        summarise(Gain = mean(Gain), Cover = mean(Cover),
                  Frequency = mean(Frequency), .groups = "drop") |>
        arrange(desc(Gain))
    }),


    # ── Alpha Decay: Signal delay in months (monthly strategy) ───────────
    #
    # Monthly rebalancing: delay signal by 1-5 months.
    # Delay d means we use the signal from d months ago.
    #
    # ── Alpha Decay: not applicable to pre-computed model ───────────
    # Alpha decay requires re-running the model with delayed signals,
    # which needs nix develop. For LTR, the t+1 execution is already
    # enforced by lagging features in compute_ltr_features.R.
    # The monthly rebalancing frequency means alpha decay is naturally
    # slow (signal persists ~1 month by construction).
    targets::tar_target(ltr_alpha_decay, {
      tibble::tibble(
        delay_months = 1:5,
        note = "Alpha decay requires re-running XGBoost in nix develop. Deferred — monthly signal naturally persists ~1 month."
      )
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
