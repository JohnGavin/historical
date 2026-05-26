# Model leaderboard: collects metrics from all strategies into one table
#
# Transposed format: metrics as rows, strategies as columns
# (fewer strategies than metrics, at least for now)

plan_leaderboard <- function() {
  list(
    # Explicit deps — targets must be named as function args
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

      # Deflated Sharpe (full-sample; K_trials = Vertox K_eff_strat, not raw M) — #160
      if (!is.null(strat_deflated_sharpe)) {
        all_metrics <- all_metrics |>
          left_join(
            strat_deflated_sharpe |>
              select(strategy, deflated_sharpe, dsr_pvalue, k_eff_strat),
            by = "strategy"
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

    # ── Vertox K_eff_strat → Deflated Sharpe chain — #160 ─────────────

    # Numeric matrix form of strategy_correlation (feeds hd_strat_keff_vertox)
    targets::tar_target(strat_corr_matrix, {
      cm <- as.matrix(strategy_correlation[, setdiff(names(strategy_correlation), "strategy")])
      rownames(cm) <- strategy_correlation$strategy
      cm
    }),

    # Correlation-aware effective count of strategies (fixed seed for reproducible MC)
    targets::tar_target(strat_keff_vertox, {
      historicaldata::hd_strat_keff_vertox(strat_corr_matrix, n_sim = 20000L, seed = 160L)
    }),

    # Per-strategy Deflated Sharpe using K_eff_strat as K_trials (not raw M=4)
    targets::tar_target(strat_deflated_sharpe, {
      library(dplyr)
      k_eff <- max(1L, round(strat_keff_vertox))
      col_map <- c(stk_max = "Stock MAX", stk_drif = "Stock DRIF",
                   fac_max = "Factor MAX", fac_drif = "Factor DRIF")
      bind_rows(lapply(seq_along(col_map), function(i) {
        col   <- names(col_map)[i]
        label <- col_map[i]
        r <- port_returns[[col]]
        r <- r[!is.na(r)]
        d <- historicaldata::hd_deflated_sharpe(r, K_trials = k_eff, ann_factor = 12L)
        tibble::tibble(
          strategy        = label,
          naive_sharpe    = d$naive_sharpe,
          deflated_sharpe = d$dsr,
          dsr_pvalue      = d$dsr_pvalue,
          dsr_haircut_pct = d$haircut_pct,
          k_eff_strat     = strat_keff_vertox,
          k_raw           = length(col_map)
        )
      }))
    })
  )
}
