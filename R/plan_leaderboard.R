# Model leaderboard: collects metrics from all strategies into one table
#
# Transposed format: metrics as rows, strategies as columns
# (fewer strategies than metrics, at least for now)

plan_leaderboard <- function() {
  list(
    # Explicit deps — targets must be named as function args
    # strat_corr_augment from plan_strategy_correlation.R provides:
    #   correlation_max, redundant, incremental_sharpe (joined by strategy_label)
    targets::tar_target(leaderboard, {
      library(dplyr)

      add_meta <- function(m, name, level, signal, url) {
        if (is.null(m) || nrow(m) == 0) return(NULL)
        m |> mutate(strategy = name, level = level, signal = signal, definition = url)
      }

      all_metrics <- bind_rows(
        add_meta(fm_metrics, "Factor MAX", "Factor", "Max daily return",
                 "factor-max.html"),
        add_meta(drif_metrics, "Factor DRIF", "Factor", "Elastic net (42 feat)",
                 "drif.html"),
        add_meta(stk_max_metrics, "Stock MAX", "Stock", "Max daily return",
                 "stock-backtest.html#stock-max"),
        add_meta(stk_drif_metrics, "Stock DRIF", "Stock", "Elastic net (42 feat)",
                 "stock-backtest.html#stock-drif"),
        add_meta(xgb_drif_metrics, "XGB DRIF", "Stock", "XGBoost monotonic (42 feat)",
                 "stock-backtest.html#stock-drif")
      )

      # Add portfolio optimal
      if (!is.null(port_metrics) && nrow(port_metrics) > 0) {
        port_row <- port_metrics |>
          transmute(
            period = period, months = months,
            cagr = opt_cagr, vol = opt_vol, sharpe = opt_sharpe, max_dd = opt_maxdd,
            strategy = "PSO Optimal", level = "Combined",
            signal = "Weighted portfolio",
            definition = "stock-backtest.html#comparison"
          )
        all_metrics <- bind_rows(all_metrics, port_row)
      }

      # ── Cost metrics (net_cagr, cum_pnl, cvar_95) ─────────────────
      # Compute per strategy per period from raw portfolio returns.
      # cost: 0.20% round-trip per month (full turnover assumed).
      COST_PER_MONTH <- 0.002

      calc_cost_metrics <- function(ret) {
        # ret: numeric vector of monthly returns
        ret <- ret[!is.na(ret)]
        n <- length(ret)
        if (n == 0L) {
          return(tibble(net_cagr = NA_real_, cum_pnl = NA_real_, cvar_95 = NA_real_))
        }
        net_ret <- ret * (1 - COST_PER_MONTH)
        net_cagr <- prod(1 + net_ret)^(12 / n) - 1
        cum_pnl_net <- prod(1 + net_ret) - 1  # net of costs, not gross
        q05      <- quantile(ret, 0.05)
        cvar_95  <- mean(ret[ret <= q05])
        # Credibility flag: >20% CAGR or >50x cum P&L is suspect
        credible <- abs(net_cagr) < 0.20 & abs(cum_pnl_net) < 50
        tibble(net_cagr = net_cagr, cum_pnl = cum_pnl_net, cvar_95 = cvar_95,
               credible = credible)
      }

      # Each portfolio target and its return column (as string) and period slicing params
      slice_portfolio <- function(port_df, ret_col_name, params) {
        ret <- list(
          Training     = port_df[port_df$date <= params$is_end, ][[ret_col_name]],
          Testing      = port_df[port_df$date >= params$test_start & port_df$date <= params$test_end, ][[ret_col_name]],
          Validation   = port_df[port_df$date >= params$val_start, ][[ret_col_name]],
          `Full Period` = port_df[[ret_col_name]]
        )
        bind_rows(lapply(names(ret), function(p) {
          calc_cost_metrics(ret[[p]]) |> mutate(period = p)
        }))
      }

      cost_rows <- bind_rows(
        slice_portfolio(fm_portfolio,        "portfolio_ret", fm_params)   |> mutate(strategy = "Factor MAX"),
        slice_portfolio(drif_portfolio,      "portfolio_ret", drif_params) |> mutate(strategy = "Factor DRIF"),
        slice_portfolio(stk_max_portfolio,   "port_ret",      stk_params)  |> mutate(strategy = "Stock MAX"),
        slice_portfolio(stk_drif_portfolio,  "port_ret",      stk_params)  |> mutate(strategy = "Stock DRIF"),
        slice_portfolio(xgb_drif_portfolio,  "port_ret",      stk_params)  |> mutate(strategy = "XGB DRIF")
      )

      # PSO Optimal: derive from port_returns (opt weights applied)
      if (!is.null(port_metrics) && nrow(port_metrics) > 0 &&
          !is.null(port_optimal_weights)) {
        w <- port_optimal_weights
        strat_cols <- names(w)
        # port_returns has columns: ym, stk_max, stk_drif, fac_max, fac_drif, rf_ret, date
        opt_returns_df <- port_returns |>
          filter(if_all(all_of(strat_cols), ~ !is.na(.x))) |>
          mutate(opt_ret = as.numeric(as.matrix(pick(all_of(strat_cols))) %*% w))

        pso_cost <- slice_portfolio(
          opt_returns_df |> rename(portfolio_ret = opt_ret),
          "portfolio_ret",
          stk_params
        ) |> mutate(strategy = "PSO Optimal")
        cost_rows <- bind_rows(cost_rows, pso_cost)
      }

      # Join cost metrics onto all_metrics
      all_metrics <- all_metrics |>
        left_join(cost_rows, by = c("strategy", "period")) |>
        # Mark strategies that draw on stk_universe (survivorship-biased); see #150
        mutate(survivorship_biased = strategy %in% c("Stock MAX", "Stock DRIF", "XGB DRIF"))

      # Join bootstrap CI columns (Sharpe CI, crosses-zero flag)
      if (!is.null(boot_ci_summary) && nrow(boot_ci_summary) > 0) {
        # Map internal names to strategy labels
        boot_join <- boot_ci_summary |>
          transmute(
            strategy = strategy_label,
            sharpe_ci_lo = round(sharpe_lo, 2),
            sharpe_ci_hi = round(sharpe_hi, 2),
            ci_crosses_zero = ci_crosses_zero
          )
        all_metrics <- all_metrics |>
          left_join(boot_join, by = "strategy")
      }

      # ── Correlation augmentation (Pillar 7, #268) ────────────────────────
      # Join correlation_max, redundant, incremental_sharpe from
      # plan_strategy_correlation.R. strat_corr_augment is keyed by strategy_label
      # which matches the display names used in all_metrics$strategy.
      # Only "Full Period" rows get meaningful values; other periods receive NA
      # (incremental Sharpe is a portfolio-level concept, not a sub-period one).
      if (!is.null(strat_corr_augment) && nrow(strat_corr_augment) > 0) {
        corr_join <- strat_corr_augment |>
          select(strategy = strategy_label, correlation_max, redundant, incremental_sharpe)
        all_metrics <- all_metrics |>
          left_join(corr_join, by = "strategy") |>
          # Zero out incremental_sharpe for sub-period rows (it's a Full-Period stat)
          mutate(
            correlation_max    = ifelse(period == "Full Period", correlation_max, NA_real_),
            redundant          = ifelse(period == "Full Period", redundant,       NA),
            incremental_sharpe = ifelse(period == "Full Period", incremental_sharpe, NA_real_)
          )
      }

      # ── Deflated Sharpe (full-sample; K_trials = Vertox K_eff_strat, not raw M) — #160 ──
      # DSR is a full-sample statistic, so it broadcasts to all period rows; the
      # vignette surfaces it only in the Full-Period view.
      if (!is.null(strat_deflated_sharpe) && nrow(strat_deflated_sharpe) > 0) {
        all_metrics <- all_metrics |>
          left_join(
            strat_deflated_sharpe |>
              select(strategy, deflated_sharpe, dsr_pvalue, k_eff_strat),
            by = "strategy"
          )
      }

      # ── Walk-Forward Correlation columns (#318) ────────────────────────────
      # wf_corr:    Pearson IS↔OOS correlation across the full parameter grid.
      # wfc_verdict: 2×2 classification from hd_wf_correlation() —
      #   "structural_edge", "consistently_loss_making", "spurious_luck", "noise".
      #
      # Strategies without a tunable parameter grid (OLMAR, TOM, Stock MAX,
      # Stock DRIF, XGB DRIF, PSO Optimal) receive NA for both columns.
      # XGB DRIF operates at the stock level (stk_drif_features) — no
      # factor-rotation grid exists; factor-level XGB is a follow-up to #318.
      #
      # wfc_all_summary is keyed by strategy (display label).  Only the
      # "Full Period" leaderboard row gets meaningful values; sub-period rows
      # receive NA (WFC is a full-history property, not a sub-period one).
      if (!is.null(wfc_all_summary) && nrow(wfc_all_summary) > 0) {
        wfc_join <- wfc_all_summary |>
          select(strategy, wf_corr = wfc_pearson, wfc_verdict = classification)
        all_metrics <- all_metrics |>
          left_join(wfc_join, by = "strategy") |>
          mutate(
            wf_corr    = ifelse(period == "Full Period", wf_corr,    NA_real_),
            wfc_verdict = ifelse(period == "Full Period", wfc_verdict, NA_character_)
          )
      }

      # ── Pillar 8: risk-architecture columns (#269, #331) ─────────────────────
      # Join avg_dd_days, max_dd_days, loss_clustered, max_cons_losses from
      # fals_results_db. fals_results_db uses strategy_id (internal code); map
      # to leaderboard labels.
      # Only "Full Period" rows carry meaningful full-history risk values.
      if (!is.null(fals_results_db) && nrow(fals_results_db) > 0) {
        fals_id_to_label <- c(
          fac_max     = "Factor MAX",
          drif        = "Factor DRIF"
          # avoid_worst, rsc, ltr, tom are not yet in the leaderboard
        )
        pillar8_join <- fals_results_db |>
          filter(strategy_id %in% names(fals_id_to_label)) |>
          mutate(strategy = fals_id_to_label[strategy_id]) |>
          select(strategy,
                 avg_dd_days      = avg_dd_duration_days,
                 max_dd_days      = max_dd_duration_days,
                 loss_clustered   = loss_clustered,
                 max_cons_losses  = max_consecutive_losses)
        all_metrics <- all_metrics |>
          left_join(pillar8_join, by = "strategy") |>
          mutate(
            avg_dd_days     = ifelse(period == "Full Period", avg_dd_days,     NA_real_),
            max_dd_days     = ifelse(period == "Full Period", max_dd_days,     NA_real_),
            loss_clustered  = ifelse(period == "Full Period", loss_clustered,  NA),
            max_cons_losses = ifelse(period == "Full Period", max_cons_losses, NA_integer_)
          )
      }

      all_metrics
    }),

    # ── Correlation matrix of monthly returns across strategies ───────
    targets::tar_target(strategy_correlation, {
      library(dplyr)

      strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif")

      ret_mat <- port_returns |>
        select(all_of(strat_cols)) |>
        filter(if_all(everything(), ~ !is.na(.x)))

      cor_mat <- cor(ret_mat)

      # Return as a tidy tibble: strategy names as both row label and columns
      as.data.frame(cor_mat) |>
        tibble::rownames_to_column("strategy") |>
        as_tibble()
    }),

    # ── Vertox K_eff_strat: correlation-aware effective strategy count ────────
    # Uses strat_corr_matrix from plan_strategy_correlation (available as dep).
    # seed = 160 for reproducibility (issue #160).
    targets::tar_target(strat_keff_vertox, {
      historicaldata::hd_strat_keff_vertox(strat_corr_matrix, n_sim = 20000L, seed = 160L)
    }),

    # ── Deflated Sharpe per strategy (#160) ───────────────────────────────────
    # K_trials = K_eff_strat (Vertox correlation-aware count, rounded to integer),
    # NOT raw M=4: correlated strategies → raw count over-penalises.
    # ann_factor = 12 (monthly returns in port_returns).
    # col_map keys match port_returns column names; values match leaderboard labels.
    targets::tar_target(strat_deflated_sharpe, {
      library(dplyr)
      k_eff <- max(1L, round(strat_keff_vertox))
      col_map <- c(stk_max = "Stock MAX", stk_drif = "Stock DRIF",
                   fac_max = "Factor MAX", fac_drif = "Factor DRIF")
      bind_rows(lapply(names(col_map), function(col) {
        r <- port_returns[[col]]
        r <- r[!is.na(r)]
        d <- historicaldata::hd_deflated_sharpe(r, K_trials = k_eff, ann_factor = 12L)
        tibble::tibble(
          strategy        = unname(col_map[[col]]),
          naive_sharpe    = d$naive_sharpe,
          deflated_sharpe = d$dsr,
          dsr_pvalue      = d$dsr_pvalue,
          dsr_haircut_pct = d$haircut_pct,
          k_eff_strat     = strat_keff_vertox,
          k_raw           = nrow(strat_corr_matrix)
        )
      }))
    })
  )
}
