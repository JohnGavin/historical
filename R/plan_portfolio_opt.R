# Portfolio optimisation with PSO for strategy combination (#32)
#
# Finds optimal weights across 4+ strategies using Particle Swarm
# Optimisation (PSO). Constraints: weights sum to 1, max single
# strategy weight, optional long-short.
#
# Reference: https://rtichoke.netlify.app/posts/portfolio_optimisation_pso.html
#
# Key principle: optimise on TRAINING data only. Evaluate on TESTING.
# Validate once on VALIDATION (sealed envelope).

plan_portfolio_opt <- function() {
  list(
    # ── Portfolio optimisation parameters ──────────────────────────
    targets::tar_target(port_params, {
      list(
        max_weight = 0.5,      # no single strategy > 50%
        min_weight = 0.0,      # no shorting strategies
        target = "sharpe",     # optimise for Sharpe ratio
        n_particles = 50L,     # PSO particles
        max_iter = 200L        # PSO iterations
      )
    }),

    # ── Combine all strategy returns into one matrix ──────────────
    targets::tar_target(port_returns, {
      library(dplyr)

      # Collect all strategy monthly returns
      s1 <- stk_max_portfolio |> select(ym, stk_max = port_ret)
      s2 <- stk_drif_portfolio |> select(ym, stk_drif = port_ret)
      s3 <- fm_portfolio |> select(ym, fac_max = portfolio_ret)
      s4 <- drif_portfolio |> select(ym, fac_drif = portfolio_ret)

      combined <- s1 |>
        inner_join(s2, by = "ym") |>
        inner_join(s3, by = "ym") |>
        inner_join(s4, by = "ym")

      # Add risk-free
      combined |>
        left_join(stk_rf, by = "ym") |>
        mutate(date = as.Date(paste0(ym, "-15"))) |>
        arrange(date)
    }),

    # ── PSO optimisation on training data ─────────────────────────
    targets::tar_target(port_optimal_weights, {
      library(dplyr)

      strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif")
      train <- port_returns |> filter(date <= stk_params$is_end)

      if (nrow(train) < 24) {
        cli::cli_warn("Not enough training data for portfolio optimisation")
        return(setNames(rep(0.25, 4), strat_cols))
      }

      ret_matrix <- as.matrix(train[, strat_cols])
      rf_vec <- train$rf_ret
      # Remove rows with NA
      complete <- complete.cases(ret_matrix, rf_vec)
      ret_matrix <- ret_matrix[complete, , drop = FALSE]
      rf_vec <- rf_vec[complete]

      # Objective: maximise Sharpe ratio
      neg_sharpe <- function(w) {
        w <- w / sum(w)  # normalise to sum=1
        port_ret <- as.numeric(ret_matrix %*% w)
        n <- length(port_ret)
        ann_ret <- prod(1 + port_ret)^(12/n) - 1
        ann_vol <- sd(port_ret) * sqrt(12)
        rf_ann <- mean(rf_vec, na.rm = TRUE) * 12
        if (ann_vol < 1e-8) return(1e6)
        -((ann_ret - rf_ann) / ann_vol)
      }

      # PSO or grid search (PSO needs pso package, fallback to grid)
      if (requireNamespace("pso", quietly = TRUE)) {
        result <- pso::psoptim(
          par = rep(0.25, 4),
          fn = neg_sharpe,
          lower = rep(port_params$min_weight, 4),
          upper = rep(port_params$max_weight, 4),
          control = list(
            maxit = port_params$max_iter,
            s = port_params$n_particles,
            trace = FALSE
          )
        )
        weights <- result$par / sum(result$par)
      } else {
        # Grid search fallback (coarse but correct)
        cli::cli_inform("pso not installed — using grid search")
        grid <- expand.grid(
          w1 = seq(0, 0.5, 0.1),
          w2 = seq(0, 0.5, 0.1),
          w3 = seq(0, 0.5, 0.1),
          w4 = seq(0, 0.5, 0.1)
        )
        grid <- grid[abs(rowSums(grid) - 1) < 0.05, ]  # allow small tolerance
        if (nrow(grid) == 0) {
          # Fallback: equal weight
          weights <- rep(0.25, 4)
        } else {
          sharpes <- apply(grid, 1, function(w) {
            w <- w / sum(w)
            -neg_sharpe(w)
          })
          best <- grid[which.max(sharpes), ]
          weights <- as.numeric(best) / sum(as.numeric(best))
        }
      }

      setNames(weights, strat_cols)
    }),

    # ── HRP weights on training data (Lopez de Prado 2016) ────────
    targets::tar_target(port_hrp_weights, {
      library(dplyr)

      strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif")
      train <- port_returns |> filter(date <= stk_params$is_end)

      if (nrow(train) < 24) {
        cli::cli_warn("Not enough training data for HRP")
        return(setNames(rep(0.25, 4), strat_cols))
      }

      ret_matrix <- as.matrix(train[, strat_cols])
      ret_matrix <- ret_matrix[complete.cases(ret_matrix), , drop = FALSE]

      if (!requireNamespace("HierPortfolios", quietly = TRUE)) {
        cli::cli_warn("HierPortfolios not installed - falling back to equal weight")
        return(setNames(rep(0.25, 4), strat_cols))
      }

      cov_mat <- cov(ret_matrix)
      # HRP_Portfolio returns a data.frame with a 'weights' column,
      # rownames match colnames of cov_mat.
      hrp_result <- HierPortfolios::HRP_Portfolio(cov_mat)
      w <- hrp_result$weights
      names(w) <- strat_cols
      w / sum(w)
    }),

    # ── Portfolio returns with optimal weights ────────────────────
    targets::tar_target(port_combined, {
      library(dplyr)

      strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif")
      w_pso <- port_optimal_weights
      w_hrp <- port_hrp_weights

      ret_matrix <- as.matrix(port_returns[, strat_cols])
      pso_ret <- as.numeric(ret_matrix %*% w_pso)
      hrp_ret <- as.numeric(ret_matrix %*% w_hrp)
      eq_ret  <- rowMeans(ret_matrix)

      port_returns |>
        mutate(
          optimal_ret = pso_ret,
          hrp_ret     = hrp_ret,
          equalwt_ret = eq_ret,
          optimal_cum = cumprod(1 + optimal_ret),
          hrp_cum     = cumprod(1 + hrp_ret),
          equalwt_cum = cumprod(1 + equalwt_ret)
        )
    }),

    # ── Portfolio metrics ─────────────────────────────────────────
    targets::tar_target(port_metrics, {
      library(dplyr)

      calc_port_metrics <- function(df, label) {
        n <- nrow(df)
        if (n < 12) return(NULL)
        rf_ann <- mean(df$rf_ret, na.rm = TRUE) * 12
        sharpe <- function(r) {
          ann <- prod(1 + r)^(12/n) - 1
          vol <- sd(r) * sqrt(12)
          if (vol < 1e-8) NA_real_ else (ann - rf_ann) / vol
        }
        maxdd <- function(r) {
          cum <- cumprod(1 + r)
          min(cum / cummax(cum) - 1)
        }
        tibble(
          period = label, months = n,
          opt_cagr   = prod(1 + df$optimal_ret)^(12/n) - 1,
          opt_vol    = sd(df$optimal_ret) * sqrt(12),
          opt_sharpe = sharpe(df$optimal_ret),
          opt_maxdd  = maxdd(df$optimal_ret),
          hrp_cagr   = prod(1 + df$hrp_ret)^(12/n) - 1,
          hrp_sharpe = sharpe(df$hrp_ret),
          hrp_maxdd  = maxdd(df$hrp_ret),
          eq_cagr    = prod(1 + df$equalwt_ret)^(12/n) - 1,
          eq_sharpe  = sharpe(df$equalwt_ret),
          eq_maxdd   = maxdd(df$equalwt_ret)
        )
      }

      bind_rows(
        calc_port_metrics(port_combined |> filter(date <= stk_params$is_end), "Training"),
        calc_port_metrics(port_combined |> filter(date >= stk_params$test_start, date <= stk_params$test_end), "Testing"),
        calc_port_metrics(port_combined |> filter(date >= stk_params$val_start), "Validation"),
        calc_port_metrics(port_combined, "Full Period")
      )
    }),

    # ── Comparison plot ───────────────────────────────────────────
    targets::tar_target(port_comparison_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)

      w_pso <- port_optimal_weights
      w_hrp <- port_hrp_weights
      w_label <- paste0(
        "PSO: ", paste(names(w_pso), paste0(round(w_pso * 100), "%"), sep = "=", collapse = ", "),
        "  |  HRP: ", paste(names(w_hrp), paste0(round(w_hrp * 100), "%"), sep = "=", collapse = ", ")
      )

      plot_data <- port_combined |>
        select(date,
               `PSO Optimal` = optimal_cum,
               HRP           = hrp_cum,
               `Equal Weight` = equalwt_cum) |>
        tidyr::pivot_longer(-date, names_to = "portfolio", values_to = "growth")

      ggplot(plot_data, aes(date, growth, colour = portfolio)) +
        geom_line(linewidth = 0.6) +
        geom_vline(xintercept = stk_params$test_start, linetype = "dashed",
                   colour = "grey50", linewidth = 0.4) +
        scale_y_log10(labels = dollar) +
        scale_colour_manual(values = hd_palette(3)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = "Portfolio: PSO vs HRP vs Equal Weight",
             subtitle = w_label) +
        hd_theme()
    }),

    # ── Registry sentinel (#442 Tier 3) ──────────────────────────────────────
    # Upserts bt.strategy row for "pso_optimal", records one bt.run + bt.metric
    # rows (Full Period PSO-optimal columns from port_metrics).
    # Returns tibble(strategy_id, run_uuid).
    # Guard: returns empty tibble if DBI / duckdb are unavailable.
    # Note: port_metrics columns opt_cagr/opt_vol/opt_maxdd are decimal fractions
    # (canonical unit convention). Benchmark/HRP columns are excluded; only the
    # PSO optimal series columns are stored.
    targets::tar_target(pso_optimal_register_runs, {
      .pso_optimal_register_runs(
        strategy_names = strategy_names,
        port_metrics   = port_metrics,
        port_combined  = port_combined
      )
    }),

    # ── Monthly returns heatmap table ─────────────────────────────
    targets::tar_target(port_monthly_returns, {
      library(dplyr)
      library(tidyr)

      port_combined |>
        mutate(
          year = lubridate::year(date),
          month = lubridate::month(date),
          return_pct = optimal_ret * 100
        ) |>
        select(year, month, return_pct) |>
        pivot_wider(
          names_from = month,
          values_from = return_pct,
          names_sort = FALSE
        ) |>
        arrange(year) |>
        mutate(across(-year, ~if_else(is.na(.), NA_real_, .))) |>
        # Calculate annual return
        rowwise() |>
        mutate(
          Annual = (prod(1 + c_across(-year) / 100, na.rm = TRUE) - 1) * 100
        ) |>
        ungroup() |>
        # Rename month columns to month abbreviations
        rename(
          Year = year,
          Jan = `1`, Feb = `2`, Mar = `3`, Apr = `4`,
          May = `5`, Jun = `6`, Jul = `7`, Aug = `8`,
          Sep = `9`, Oct = `10`, Nov = `11`, Dec = `12`
        ) |>
        # Format all numeric columns to 1 decimal place
        mutate(across(-Year, ~format(round(., 1), nsmall = 1))) |>
        as_tibble()
    })
  )
}


# ── Internal helper ────────────────────────────────────────────────────────────
# Prefixed .pso_optimal_* (private; not exported from the package).
# Mirrors .drif_register_runs() from plan_drif.R.

#' Register PSO Optimal portfolio backtest run in the strategy registry
#'
#' @param strategy_names Tibble from the `strategy_names` target.
#' @param port_metrics Tibble from the `port_metrics` target. Full-period
#'   PSO-optimal columns (`opt_cagr`, `opt_vol`, `opt_sharpe`, `opt_maxdd`)
#'   are used for the bt.metric insert. Values are decimal fractions.
#' @param port_combined Tibble from the `port_combined` target; used to
#'   extract `optimal_ret` (monthly) for SSR/top5pct stability metrics.
#'
#' @return Tibble with columns: strategy_id, run_uuid.
#' @noRd
.pso_optimal_register_runs <- function(strategy_names, port_metrics,
                                       port_combined) {
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
    dplyr::filter(.data$code_name == "pso_optimal") |>
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
    strategy_id      = "pso_optimal",
    partition        = "phase1",
    pipeline_version = "phase1"
  )

  # Record Full Period PSO-optimal metrics (decimal fractions; canonical units).
  # Only store PSO columns; HRP/equal-weight columns belong to separate strategies
  # if they are ever registered.
  full_row <- port_metrics[port_metrics$period == "Full Period", , drop = FALSE]
  if (nrow(full_row) == 1L) {
    pso_cols <- intersect(
      c("months", "opt_cagr", "opt_vol", "opt_sharpe", "opt_maxdd"),
      names(full_row)
    )
    if (length(pso_cols) > 0L) {
      historicaldata::hd_metric_record(
        con, uu, full_row[, pso_cols, drop = FALSE]
      )
    }
  }

  # Record SSR + top5pct stability metrics (#400). Monthly: w=36, ann_factor=12.
  rets <- port_combined$optimal_ret
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

  tibble::tibble(strategy_id = "pso_optimal", run_uuid = uu)
}
