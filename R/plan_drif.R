# DRIF targets: Daily Return Information Factor applied to FF5+Momentum
#
# Based on Alpha Architect research: elastic net on past 21 daily returns
# (chronological + rank dimensions) predicts next-month factor returns.
#
# Factor-level implementation: rotate among 6 Fama-French factors using
# the DRIF signal instead of cross-sectional stock sorting.

plan_drif <- function() {
  list(
    # ── Parameters ────────────────────────────────────────────────
    targets::tar_target(drif_params, {
      p <- bt_partitions$factor
      list(
        factors = c("HML", "SMB", "RMW", "CMA", "Mom"),
        benchmark_factor = "Mkt-RF",
        lookback_days = 21L,
        top_n = 2L,
        alpha = 0.5,
        min_train_months = 60L,
        start_date = as.Date("1963-07-01"),
        is_end = p$train_end,
        test_start = p$test_start,
        test_end = p$test_end,
        holdout_start = p$holdout_start,  # #660: observed, not sealed
        holdout_end = p$holdout_end,
        val_start = p$val_start,
        val_end = p$val_end,
        oos_start = p$test_start,
        # Cost model (#425): factor-level trades; 0.10%/trade one-way
        # (matches stk_all_caption claim; single source of truth here)
        cost_per_trade = 0.001
      )
    }),

    # ── Data: full daily factor history in one query ──────────────
    targets::tar_target(drif_daily, {
      library(dplyr)

      ff5 <- hd_factors(dataset = "FF5", frequency = "daily",
                        from = as.character(drif_params$start_date))
      mom <- hd_factors(dataset = "Mom", frequency = "daily",
                        from = as.character(drif_params$start_date))

      bind_rows(ff5, mom) |>
        filter(factor_name %in% c(drif_params$factors, drif_params$benchmark_factor, "RF")) |>
        mutate(value = value / 100) |>  # French data is in percent
        arrange(factor_name, date)
    }),

    # ── Feature matrix: chronological + rank features per factor-month
    # Built in one vectorised pass over full history ───────────────
    targets::tar_target(drif_features, {
      library(dplyr)

      all_factors <- c(drif_params$factors, drif_params$benchmark_factor)
      lb <- drif_params$lookback_days

      # Assign year-month to each day
      daily <- drif_daily |>
        filter(factor_name %in% all_factors) |>
        mutate(ym = format(date, "%Y-%m"))

      # For each factor, get the last trading day per month (for monthly returns)
      monthly_ret <- daily |>
        group_by(factor_name, ym) |>
        summarise(
          monthly_ret = prod(1 + value) - 1,
          last_date = max(date),
          n_days = n(),
          .groups = "drop"
        )

      # Build feature matrix: for each factor-month, collect prior month's
      # daily returns as chronological and rank features.
      # Do this by splitting daily data per factor, then using rolling windows.
      features_list <- lapply(all_factors, function(fac) {
        fac_daily <- daily |>
          filter(factor_name == fac) |>
          arrange(date)

        fac_monthly <- monthly_ret |>
          filter(factor_name == fac) |>
          arrange(ym)

        months <- fac_monthly$ym
        results <- vector("list", length(months))

        for (i in seq_along(months)) {
          m <- months[i]
          month_end <- fac_monthly$last_date[i]

          # Get the lb trading days BEFORE this month's first day
          prior_days <- fac_daily |>
            filter(date < as.Date(paste0(m, "-01"))) |>
            tail(lb)

          if (nrow(prior_days) < lb) next

          # Chronological features: returns in time order (day 1 = oldest)
          chrono <- setNames(prior_days$value, paste0("c", seq_len(lb)))

          # Rank features: returns sorted by magnitude (rank 1 = smallest)
          ranked <- setNames(sort(prior_days$value), paste0("r", seq_len(lb)))

          row <- c(list(factor_name = fac, ym = m,
                        target_ret = fac_monthly$monthly_ret[i]),
                   as.list(chrono), as.list(ranked))
          results[[i]] <- as.data.frame(row, stringsAsFactors = FALSE)
        }

        bind_rows(Filter(Negate(is.null), results))
      })

      bind_rows(features_list)
    }),

    # ── DRIF signal: expanding window elastic net predictions ─────
    # NOTE(#319 CPCV integrated): label horizon = 1 month, training window
    # terminates strictly at m-1 (ym < m), so classical label-window overlap
    # is absent. The inner cv.glmnet(nfolds=5) uses the expanding training
    # window without purging of folds; for monthly non-overlapping labels the
    # risk is low. Outer CPCV multi-path evaluation is added below as
    # drif_cpcv_params → drif_path_sharpe → drif_pbo (#319).
    targets::tar_target(drif_signal, {
      library(dplyr)

      features <- drif_features
      all_factors <- c(drif_params$factors, drif_params$benchmark_factor)
      months <- sort(unique(features$ym))
      min_train <- drif_params$min_train_months

      rlang::check_installed("glmnet")

      # Feature column names
      chrono_cols <- paste0("c", seq_len(drif_params$lookback_days))
      rank_cols <- paste0("r", seq_len(drif_params$lookback_days))
      feat_cols <- c(chrono_cols, rank_cols)

      # For each month from min_train onward, predict next month's returns
      trade_months <- months[(min_train + 1):length(months)]

      predictions <- lapply(trade_months, function(m) {
        m_idx <- which(months == m)
        train_months <- months[1:(m_idx - 1)]

        train <- features |> filter(ym %in% train_months)
        test <- features |> filter(ym == m)

        if (nrow(train) < min_train * length(all_factors) * 0.5) return(NULL)
        if (nrow(test) == 0) return(NULL)

        X_train <- as.matrix(train[, feat_cols])
        y_train <- train$target_ret
        X_test <- as.matrix(test[, feat_cols])

        # Remove rows with NA
        complete <- complete.cases(X_train, y_train)
        X_train <- X_train[complete, , drop = FALSE]
        y_train <- y_train[complete]

        if (length(y_train) < 50) return(NULL)

        fit <- tryCatch({
          glmnet::cv.glmnet(X_train, y_train,
                            alpha = drif_params$alpha,
                            nfolds = 5, type.measure = "mse")
        }, error = function(e) {
          cli::cli_warn("cv.glmnet failed for month {.val {m}}: {conditionMessage(e)}")
          NULL
        })

        if (is.null(fit)) return(NULL)
        pred <- as.numeric(predict(fit, X_test, s = "lambda.min"))

        tibble(
          factor_name = test$factor_name,
          ym = m,
          predicted_ret = pred,
          actual_ret = test$target_ret
        )
      })

      bind_rows(Filter(Negate(is.null), predictions)) |>
        group_by(ym) |>
        mutate(pred_rank = rank(-predicted_ret, ties.method = "min")) |>
        ungroup() |>
        arrange(ym, pred_rank)
    }),

    # ── Portfolio: long top-N predicted factors ───────────────────
    targets::tar_target(drif_portfolio, {
      library(dplyr)

      # Shared selection logic: rank-all-then-filter-benchmark-then-top_n.
      # Delegates to hd_drif_select_topn() so plan_drif_v2.R uses the same path.
      signal <- hd_drif_select_topn(
        drif_signal, drif_params, drif_params$top_n
      )

      rf <- drif_daily |>
        filter(factor_name == "RF") |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(ym) |>
        summarise(rf_monthly = prod(1 + value) - 1, .groups = "drop")

      bench <- drif_signal |>
        filter(factor_name == drif_params$benchmark_factor) |>
        select(ym, bench_ret = actual_ret)

      months <- sort(unique(signal$ym))

      # Cost model (#425): turnover = fraction of portfolio changed between
      # consecutive months. For top_n=2 of 5 factors, full rotation = 100%
      # (2 in + 2 out). Partial overlap reduces turnover proportionally.
      # Round-trip cost = cost_per_trade * turnover * 2 (sell prev + buy new).
      results <- lapply(seq_along(months), function(i) {
        m <- months[i]
        month_signal <- signal |> filter(ym == m)
        if (nrow(month_signal) == 0) return(NULL)

        selected <- month_signal
        top_n <- drif_params$top_n

        # Turnover: fraction of holdings that changed vs previous month
        if (i == 1L) {
          # First month: full cost (entering all positions from cash)
          turnover <- 1.0
        } else {
          prev_m <- months[i - 1L]
          prev_signal <- signal |> filter(ym == prev_m)
          prev_factors <- prev_signal$factor_name
          curr_factors <- selected$factor_name
          n_overlap <- length(intersect(prev_factors, curr_factors))
          # Fraction of portfolio changed = 1 - overlap / top_n
          turnover <- 1.0 - n_overlap / top_n
        }

        # Round-trip cost (both legs: sell exiting + buy entering)
        cost <- drif_params$cost_per_trade * turnover * 2.0

        gross_ret <- mean(selected$actual_ret)
        port_ret  <- gross_ret - cost

        b <- bench |> filter(ym == m)
        r <- rf |> filter(ym == m)

        tibble(
          ym = m,
          gross_port_ret = gross_ret,
          turnover = turnover,
          cost = cost,
          portfolio_ret = port_ret,
          benchmark_ret = if (nrow(b) == 1) b$bench_ret else NA_real_,
          rf_ret = if (nrow(r) == 1) r$rf_monthly else NA_real_,
          selected_factors = paste(selected$factor_name, collapse = ", "),
          n_factors = nrow(selected)
        )
      })

      # Thread last_date (actual last trading day of each month) from drif_daily.
      # This is identical to the max(date) computed inside drif_features but
      # made available here via a lightweight summarise on the dependency we
      # already have. No to_month_end_bizday() call needed: max(date) IS the
      # correct business-day date by construction (#147 layer 2).
      month_end_dates <- drif_daily |>
        filter(factor_name == drif_params$benchmark_factor) |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(ym) |>
        summarise(last_date = max(date), .groups = "drop")

      bind_rows(Filter(Negate(is.null), results)) |>
        left_join(month_end_dates, by = "ym") |>
        mutate(
          date = last_date,   # threaded from monthly_ret per #147 layer 2
          # coalesce NA → 0 to prevent cumprod NA-propagation tail; missing periods treated as zero-return
          port_cum   = cumprod(1 + dplyr::coalesce(portfolio_ret, 0)),
          bench_cum  = cumprod(1 + dplyr::coalesce(benchmark_ret, 0)),
          excess_ret = portfolio_ret - rf_ret
        ) |>
        select(-last_date)
    }),

    # ── Metrics ───────────────────────────────────────────────────
    targets::tar_target(drif_metrics, {
      library(dplyr)

      calc_metrics <- function(df, label) {
        n <- nrow(df)
        if (n < 12) return(NULL)
        ann_ret <- prod(1 + df$portfolio_ret)^(12/n) - 1
        ann_vol <- sd(df$portfolio_ret) * sqrt(12)
        # ann_rf captured as its own variable (#677 slice 4) so it can be
        # published alongside sharpe -- QA gate S17
        # (check_leaderboard_sharpe_coherence(), R/plan_qa_gates.R) asserts
        # sharpe == (cagr - ann_rf) / vol for every leaderboard row.
        ann_rf <- mean(df$rf_ret, na.rm = TRUE) * 12
        sharpe <- (ann_ret - ann_rf) / ann_vol
        cum <- cumprod(1 + df$portfolio_ret)
        max_dd <- min(cum / cummax(cum) - 1)
        hit <- mean(df$portfolio_ret > df$benchmark_ret, na.rm = TRUE)

        bench_ann <- prod(1 + df$benchmark_ret, na.rm = TRUE)^(12/n) - 1
        bench_vol <- sd(df$benchmark_ret, na.rm = TRUE) * sqrt(12)
        bench_sharpe <- (bench_ann - mean(df$rf_ret, na.rm = TRUE) * 12) / bench_vol

        tibble(
          period = label, months = n,
          cagr = ann_ret, vol = ann_vol, sharpe = sharpe, ann_rf = ann_rf,
          max_dd = max_dd, hit_rate = hit,
          bench_cagr = bench_ann, bench_vol = bench_vol,
          bench_sharpe = bench_sharpe
        )
      }

      # #666: Holdout (2024-01-01..2026-04-30, observed but not sealed) --
      # so the Holdout row emitted by slice_portfolio() in R/plan_leaderboard.R
      # finds a matching base row here and survives the left_join instead of
      # being silently dropped (the #660 KNOWN GAP).
      bind_rows(
        calc_metrics(drif_portfolio |> filter(date <= drif_params$is_end), "Training"),
        calc_metrics(drif_portfolio |> filter(date >= drif_params$test_start, date <= drif_params$test_end), "Testing"),
        calc_metrics(drif_portfolio |> filter(date >= drif_params$holdout_start, date <= drif_params$holdout_end), "Holdout"),
        calc_metrics(drif_portfolio |> filter(date >= drif_params$val_start), "Validation"),
        calc_metrics(drif_portfolio, "Full Period")
      )
    }),

    # ── Cumulative return plot ────────────────────────────────────
    targets::tar_target(drif_cumret_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)

      plot_data <- drif_portfolio |>
        select(date, `DRIF` = port_cum, `Market (Mkt-RF)` = bench_cum) |>
        tidyr::pivot_longer(-date, names_to = "strategy", values_to = "growth")

      ggplot(plot_data, aes(date, growth, colour = strategy)) +
        geom_line(linewidth = 0.6) +
        geom_vline(xintercept = drif_params$oos_start, linetype = "dashed",
                   colour = "grey50", linewidth = 0.4) +
        annotate("text", x = drif_params$oos_start, y = max(plot_data$growth) * 0.9,
                 label = "OOS start", colour = "grey60", hjust = -0.1, size = 3) +
        scale_y_log10(labels = dollar) +
        scale_colour_manual(values = hd_palette(2)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = "DRIF (factor-level) vs Market") +
        hd_theme()
    }),

    # ── Factor selection frequency ────────────────────────────────
    targets::tar_target(drif_selection_freq, {
      library(dplyr)

      drif_portfolio |>
        tidyr::separate_longer_delim(selected_factors, ", ") |>
        count(selected_factors, name = "months_selected") |>
        mutate(pct = months_selected / nrow(drif_portfolio)) |>
        arrange(desc(months_selected)) |>
        rename(factor = selected_factors)
    }),

    # ── DRIF vs Factor MAX comparison ─────────────────────────────
    targets::tar_target(drif_vs_max, {
      library(dplyr)

      drif <- drif_portfolio |>
        select(ym, date, drif_ret = portfolio_ret)  # date already last_date per #147 layer 2

      max_data <- fm_portfolio |>
        select(ym, max_ret = portfolio_ret)

      inner_join(drif, max_data, by = "ym") |>
        mutate(
          drif_cum = cumprod(1 + drif_ret),
          max_cum  = cumprod(1 + max_ret)
        )
    }),

    # ── DRIF vs MAX plot ──────────────────────────────────────────
    targets::tar_target(drif_vs_max_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)

      plot_data <- drif_vs_max |>
        select(date, `DRIF` = drif_cum, `Factor MAX` = max_cum) |>
        tidyr::pivot_longer(-date, names_to = "strategy", values_to = "growth")

      ggplot(plot_data, aes(date, growth, colour = strategy)) +
        geom_line(linewidth = 0.6) +
        scale_y_log10(labels = dollar) +
        scale_colour_manual(values = hd_palette(2)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = "DRIF vs Factor MAX: both applied to FF5+Momentum factors") +
        hd_theme()
    }),

    # ── CPCV: parameters ─────────────────────────────────────────
    # C(6,2) = 15 paths.  n_groups and n_test_groups are exposed as a
    # tar_target so they can be tuned without touching plan_drif.R.
    targets::tar_target(drif_cpcv_params, {
      list(
        n_groups      = 6L,
        n_test_groups = 2L,
        label_horizon = 1L,   # monthly labels → 1 month horizon
        embargo_n     = 1L    # 1-month embargo after each test fold
      )
    }),

    # ── CPCV: per-path OOS Sharpe distribution ───────────────────
    # Divides the full timeline of drif_portfolio into n_groups equal groups,
    # enumerates all C(n_groups, n_test_groups) train/test index combinations,
    # applies purge + embargo on each, and computes OOS Sharpe per path.
    # Result: a numeric vector of length C(n_groups, n_test_groups).
    targets::tar_target(drif_path_sharpe, {
      library(dplyr)

      port   <- drif_portfolio
      params <- drif_cpcv_params
      n      <- nrow(port)

      if (n < params$n_groups * 2L) {
        cli::cli_abort(c(
          "x" = "drif_portfolio has only {n} rows; need >= {params$n_groups * 2L} for CPCV.",
          "i" = "Reduce n_groups or wait for more history."
        ))
      }

      # Assign each row to one of n_groups equally-sized chronological groups
      group_id <- cut(seq_len(n),
                      breaks = params$n_groups,
                      labels = FALSE,
                      include.lowest = TRUE)

      # Map group number → row indices
      group_rows <- lapply(seq_len(params$n_groups), function(g) which(group_id == g))

      # Enumerate C(n_groups, n_test_groups) paths (group-index level)
      paths <- hd_cpcv_paths(
        n_groups      = params$n_groups,
        n_test_groups = params$n_test_groups
      )

      # For each path, translate group indices to row indices, apply purge +
      # embargo, then compute annualised Sharpe on the OOS test rows.
      vapply(paths, function(p) {
        # Row indices for this path's training and test groups
        train_rows <- sort(unlist(group_rows[p$train]))
        test_rows  <- sort(unlist(group_rows[p$test]))

        # Purge: drop training rows whose label window overlaps the test fold
        train_purged <- hd_cpcv_purge(
          train_idx     = train_rows,
          test_idx      = test_rows,
          label_horizon = params$label_horizon
        )

        # Embargo: drop training rows immediately after test fold end
        train_clean <- hd_cpcv_embargo(
          train_idx = train_purged,
          test_idx  = test_rows,
          embargo_n = params$embargo_n
        )

        # OOS portfolio returns for this path's test rows
        oos_ret <- port$portfolio_ret[test_rows]
        oos_ret <- oos_ret[!is.na(oos_ret)]

        if (length(oos_ret) < 3L) return(NA_real_)

        # Annualised Sharpe (monthly data → multiply by sqrt(12))
        ann_ret <- prod(1 + oos_ret)^(12 / length(oos_ret)) - 1
        ann_vol <- sd(oos_ret) * sqrt(12)
        if (ann_vol <= 0) return(NA_real_)
        ann_ret / ann_vol
      }, numeric(1L))
    }),

    # ── CPCV: Probability of Backtest Overfitting ────────────────
    # Uses the benchmark (Mkt-RF) as the reference strategy so hd_pbo() has
    # the required 2 columns (n_strategies >= 2).  DRIF is strategy 1;
    # Benchmark is strategy 2.  PBO near 0 means DRIF tends to rank above
    # the benchmark OOS on the same path where it ranks best IS — evidence
    # that DRIF's IS selection is not overfitting.
    targets::tar_target(drif_pbo, {
      library(dplyr)

      port   <- drif_portfolio
      params <- drif_cpcv_params
      n      <- nrow(port)

      # Assign groups (same split as drif_path_sharpe)
      group_id  <- cut(seq_len(n),
                       breaks = params$n_groups,
                       labels = FALSE,
                       include.lowest = TRUE)
      group_rows <- lapply(seq_len(params$n_groups), function(g) which(group_id == g))

      paths <- hd_cpcv_paths(
        n_groups      = params$n_groups,
        n_test_groups = params$n_test_groups
      )

      # Build IS and OOS score matrices (n_paths × 2 strategies)
      n_paths    <- length(paths)
      is_mat     <- matrix(NA_real_, nrow = n_paths, ncol = 2L,
                           dimnames = list(NULL, c("DRIF", "Benchmark")))
      oos_mat    <- is_mat

      for (i in seq_len(n_paths)) {
        p          <- paths[[i]]
        train_rows <- sort(unlist(group_rows[p$train]))
        test_rows  <- sort(unlist(group_rows[p$test]))

        train_purged <- hd_cpcv_purge(train_rows, test_rows, params$label_horizon)
        train_clean  <- hd_cpcv_embargo(train_purged, test_rows, params$embargo_n)

        sharpe_monthly <- function(ret) {
          ret <- ret[!is.na(ret)]
          if (length(ret) < 3L) return(NA_real_)
          ann_ret <- prod(1 + ret)^(12 / length(ret)) - 1
          ann_vol <- sd(ret) * sqrt(12)
          if (ann_vol <= 0) return(NA_real_)
          ann_ret / ann_vol
        }

        # IS scores (training folds after purge + embargo)
        is_mat[i, "DRIF"]      <- sharpe_monthly(port$portfolio_ret[train_clean])
        is_mat[i, "Benchmark"] <- sharpe_monthly(port$benchmark_ret[train_clean])

        # OOS scores (test fold)
        oos_mat[i, "DRIF"]      <- sharpe_monthly(port$portfolio_ret[test_rows])
        oos_mat[i, "Benchmark"] <- sharpe_monthly(port$benchmark_ret[test_rows])
      }

      hd_pbo(is_scores = is_mat, oos_scores = oos_mat)
    }),

    # ── Registry sentinel (#442 Tier 1) ─────────────────────────────────────
    # Upserts bt.strategy row for "drif", records one bt.run + bt.metric rows
    # (one per period from drif_metrics). Returns tibble(strategy_id, run_uuid).
    # Guard: returns empty tibble if DBI / duckdb are unavailable.
    targets::tar_target(drif_register_runs, {
      .drif_register_runs(
        strategy_names = strategy_names,
        drif_metrics   = drif_metrics,
        drif_portfolio = drif_portfolio
      )
    }),

    # ── Selection-stability diagnostic (#910 item 2) ────────────────
    # "From Alpha Signals to Portfolio" (#910) flags full-sample re-
    # selection as a warning sign: recomputing an IC/feature filter every
    # window and finding low overlap between consecutive selections means
    # the marginal features are churning noise, not signal. DRIF's monthly
    # cv.glmnet already re-fits at every step (walk-forward, S41 PASS -- see
    # R/plan_qa_gates.R), but until now nothing recorded WHICH of the 42
    # chrono/rank features it actually kept (non-zero coefficient at
    # lambda.min) from one month to the next -- drif_signal (above) only
    # ever kept the resulting PREDICTION, not the selected set that
    # produced it.
    targets::tar_target(drif_selected_features, {
      compute_drif_selected_features(drif_features, drif_params)
    }),

    targets::tar_target(drif_selection_stability, {
      jaccard_tbl <- compute_drif_selection_jaccard(drif_selected_features)
      summary_tbl <- summarise_drif_selection_stability(jaccard_tbl)
      cli::cli_inform(c("i" = paste0(
        "drif_selection_stability: median Jaccard=", round(summary_tbl$median_jaccard, 3),
        " (n_pairs=", summary_tbl$n_pairs, ", n_undefined=", summary_tbl$n_undefined,
        ", share_below_0.5=", round(summary_tbl$`share_below_0.5`, 3),
        ", range=[", round(summary_tbl$min_jaccard, 3), ", ",
        round(summary_tbl$max_jaccard, 3), "]) across consecutive monthly ",
        "cv.glmnet refits (#910 item 2)"
      )))
      list(pairs = jaccard_tbl, summary = summary_tbl)
    })

  )
}


# ── Internal helper ────────────────────────────────────────────────────────────
# Prefixed .drif_* (private; not exported from the package).
# Mirrors .mom_prepeak_register_runs() from plan_mom_prepeak.R.

#' Register DRIF backtest run in the strategy registry
#'
#' @param strategy_names Tibble from the `strategy_names` target.
#' @param drif_metrics Tibble from the `drif_metrics` target.
#' @param drif_portfolio Tibble from the `drif_portfolio` target; used to
#'   extract returns for SSR/top5pct stability metrics.
#'
#' @return Tibble with columns: strategy_id, run_uuid.
#' @noRd
.drif_register_runs <- function(strategy_names, drif_metrics,
                                drif_portfolio) {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("duckdb", quietly = TRUE)) {
    return(tibble::tibble(
      strategy_id = character(),
      run_uuid    = character()
    ))
  }

  path <- hd_registry_path()
  hd_registry_init(path)
  con <- hd_registry_open(path, read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  strat_row <- strategy_names |>
    dplyr::filter(.data$code_name == "drif") |>
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

  hd_strategy_upsert(con, strat_row)

  uu <- hd_run_upsert(
    con,
    strategy_id      = "drif",
    partition        = "phase1",
    pipeline_version = "phase1"
  )

  # Record full-period metrics row
  # Units (#640): drif_metrics stores cagr/vol/max_dd/hit_rate/bench_* as
  # decimal fractions (see calc_metrics() above), sharpe/bench_sharpe are
  # scale-free ratios, and months is a period count. ann_rf (#677 slice 4,
  # #691) is a decimal fraction, same convention as cagr
  # (ann_rf <- mean(df$rf_ret, na.rm = TRUE) * 12 above, never *100).
  full_row <- drif_metrics[drif_metrics$period == "Full Period", , drop = FALSE]
  if (nrow(full_row) == 1L) {
    metric_cols <- setdiff(names(full_row), "period")
    drif_units <- c(
      months = "count", cagr = "fraction", vol = "fraction",
      sharpe = "ratio", max_dd = "fraction", hit_rate = "fraction",
      bench_cagr = "fraction", bench_vol = "fraction", bench_sharpe = "ratio",
      ann_rf = "fraction"
    )
    hd_metric_record(
      con, uu, full_row[, metric_cols, drop = FALSE], units = drif_units
    )
  }

  # Record SSR + top5pct stability metrics (#400). Monthly: w=36, ann_factor=12.
  rets <- drif_portfolio$portfolio_ret
  rets <- rets[!is.na(rets)]
  if (length(rets) > 0L) {
    hd_record_stability_metrics(
      con        = con,
      run_uuid   = uu,
      returns    = rets,
      w          = 36L,
      ann_factor = 12L
    )
  }

  tibble::tibble(strategy_id = "drif", run_uuid = uu)
}

# ── Selection-stability diagnostic helpers (#910 item 2) ────────────────────
# Not prefixed .drif_* like .drif_register_runs() above: these mirror the
# compute_*()/check_*() naming already used for other QA/diagnostic helpers
# in this codebase (e.g. compute_olmar_window_neighbourhood_sharpes(),
# R/plan_qa_gates.R) rather than the registry-sentinel-specific .drif_*
# prefix, since these are referenced from R/plan_qa_gates.R-adjacent
# reporting as well as from this file's own targets.

#' Extract DRIF's monthly cv.glmnet selected (non-zero-coefficient) feature
#' set, per walk-forward refit (#910 item 2)
#'
#' Mirrors the \code{drif_signal} target's walk-forward loop (this file,
#' above) EXACTLY -- same \code{train_months} construction
#' (\code{months[1:(m_idx - 1)]}), same \code{feat_cols}, same
#' \code{alpha}/\code{nfolds} -- but returns, per trade month, the names of
#' the features whose fitted coefficient at \code{s = "lambda.min"} is
#' non-zero, instead of (or alongside) a prediction. This is the "selected
#' set" the article ("From Alpha Signals to Portfolio", #910) asks to track
#' for a selection-stability diagnostic: how much does the elastic net's
#' chosen feature subset change from one monthly refit to the next?
#'
#' A month is OMITTED from the result (not recorded as an empty set) when
#' the same skip conditions \code{drif_signal} itself uses apply (too few
#' training rows, no test rows, \code{cv.glmnet} error) -- this is
#' deliberate: an omitted month means "no model was fit", which is a
#' different fact from "a model was fit and selected zero features"
#' (fail-loud-not-null.md Pattern 5 -- collapsing the two into the same
#' NULL/empty-vector representation would silently launder a fit failure
#' into a data point in the stability summary). If EVERY trade month is
#' skipped, this aborts rather than returning an empty list silently (same
#' rule, applied at the whole-result level).
#'
#' @param features \code{drif_features} target.
#' @param params \code{drif_params} target (or an equivalent list with
#'   \code{factors}, \code{benchmark_factor}, \code{lookback_days},
#'   \code{alpha}, \code{min_train_months}).
#' @return Named list, one element per trade month that fit successfully
#'   (name = \code{ym}, value = character vector of selected feature names,
#'   possibly \code{character(0)} when the fit converged but selected
#'   nothing). Months where no model was fit are absent from the list
#'   entirely.
#' @noRd
compute_drif_selected_features <- function(features, params) {
  rlang::check_installed("glmnet")

  all_factors <- c(params$factors, params$benchmark_factor)
  months      <- sort(unique(features$ym))
  min_train   <- params$min_train_months
  lb          <- params$lookback_days
  chrono_cols <- paste0("c", seq_len(lb))
  rank_cols   <- paste0("r", seq_len(lb))
  feat_cols   <- c(chrono_cols, rank_cols)

  trade_months <- months[(min_train + 1):length(months)]

  selected <- lapply(trade_months, function(m) {
    m_idx        <- which(months == m)
    train_months <- months[1:(m_idx - 1)]

    train <- features[features$ym %in% train_months, , drop = FALSE]
    test  <- features[features$ym == m, , drop = FALSE]

    if (nrow(train) < min_train * length(all_factors) * 0.5) return(NULL)
    if (nrow(test) == 0) return(NULL)

    X_train <- as.matrix(train[, feat_cols])
    y_train <- train$target_ret
    complete <- stats::complete.cases(X_train, y_train)
    X_train  <- X_train[complete, , drop = FALSE]
    y_train  <- y_train[complete]
    if (length(y_train) < 50) return(NULL)

    fit <- tryCatch({
      glmnet::cv.glmnet(X_train, y_train, alpha = params$alpha,
                        nfolds = 5, type.measure = "mse")
    }, error = function(e) {
      cli::cli_warn("compute_drif_selected_features: cv.glmnet failed for month {.val {m}}: {conditionMessage(e)}")
      NULL
    })
    if (is.null(fit)) return(NULL)

    co <- as.matrix(stats::coef(fit, s = "lambda.min"))
    nz <- rownames(co)[co[, 1] != 0]
    setdiff(nz, "(Intercept)")
  })
  names(selected) <- trade_months
  selected <- Filter(Negate(is.null), selected)

  if (length(selected) == 0L) {
    cli::cli_abort(c(
      "x" = "compute_drif_selected_features(): no trade month produced a fitted model.",
      "i" = paste0(
        "Every one of the ", length(trade_months), " trade month(s) was ",
        "skipped by the same min-training-rows / min-test-rows guard ",
        "drif_signal itself uses -- check drif_features / drif_params (#910 item 2)."
      )
    ))
  }
  selected
}

#' Jaccard overlap of DRIF's selected feature set between CONSECUTIVE
#' monthly refits (#910 item 2)
#'
#' @param selected_sets Named list as returned by
#'   \code{\link{compute_drif_selected_features}} -- names are \code{ym}, in
#'   any order (sorted internally before pairing).
#' @return Tibble with one row per consecutive PRESENT pair: \code{ym_from},
#'   \code{ym_to}, \code{jaccard} (\code{NA_real_} when BOTH sets are empty
#'   -- undefined, not zero; two months that each selected nothing have no
#'   overlap to measure, which is a different fact from two DISJOINT
#'   non-empty sets, which correctly score 0 -- fail-loud-not-null.md).
#'   "Consecutive" means adjacent in the sorted key sequence of
#'   \code{selected_sets}, which may skip a month that had no fitted model
#'   (see \code{\link{compute_drif_selected_features}}) -- such a gap is a
#'   fact about the input, not itself flagged here.
#' @noRd
compute_drif_selection_jaccard <- function(selected_sets) {
  if (length(selected_sets) < 2L) {
    cli::cli_abort(c(
      "x" = "compute_drif_selection_jaccard() needs at least 2 months of selected features to form a consecutive pair.",
      "i" = "Got {length(selected_sets)}."
    ))
  }

  ms <- sort(names(selected_sets))
  jaccard_one <- function(a, b) {
    if (length(a) == 0L && length(b) == 0L) return(NA_real_)
    length(intersect(a, b)) / length(union(a, b))
  }
  j <- vapply(seq_len(length(ms) - 1L), function(i) {
    jaccard_one(selected_sets[[ms[i]]], selected_sets[[ms[i + 1L]]])
  }, numeric(1))

  tibble::tibble(
    ym_from = ms[seq_len(length(ms) - 1L)],
    ym_to   = ms[seq(2L, length(ms))],
    jaccard = j
  )
}

#' Summarise DRIF's monthly selection-stability Jaccard series (#910 item 2)
#'
#' @param jaccard_tbl Tibble as returned by
#'   \code{\link{compute_drif_selection_jaccard}}.
#' @return Single-row tibble: \code{n_pairs}, \code{n_undefined} (pairs
#'   where both sets were empty -- excluded from every statistic below),
#'   \code{median_jaccard}, \code{mean_jaccard}, \code{share_below_0.5}
#'   (computed over non-undefined pairs only), \code{min_jaccard},
#'   \code{max_jaccard}. All statistic columns are \code{NA_real_} when
#'   every pair is undefined (\code{n_pairs == n_undefined}) -- an honest
#'   "cannot summarise" rather than a manufactured 0
#'   (fail-loud-not-null.md).
#' @noRd
summarise_drif_selection_stability <- function(jaccard_tbl) {
  if (!all(c("ym_from", "ym_to", "jaccard") %in% names(jaccard_tbl))) {
    cli::cli_abort(c(
      "x" = "summarise_drif_selection_stability(): jaccard_tbl is missing required column(s): ym_from, ym_to, jaccard.",
      "i" = "Expected the tibble returned by compute_drif_selection_jaccard()."
    ))
  }

  j       <- jaccard_tbl$jaccard
  n_na    <- sum(is.na(j))
  n_pairs <- length(j)
  j_valid <- j[!is.na(j)]
  has_valid <- length(j_valid) > 0L

  tibble::tibble(
    n_pairs           = n_pairs,
    n_undefined       = n_na,
    median_jaccard    = if (has_valid) stats::median(j_valid) else NA_real_,
    mean_jaccard       = if (has_valid) mean(j_valid) else NA_real_,
    `share_below_0.5` = if (has_valid) mean(j_valid < 0.5) else NA_real_,
    min_jaccard        = if (has_valid) min(j_valid) else NA_real_,
    max_jaccard        = if (has_valid) max(j_valid) else NA_real_
  )
}
