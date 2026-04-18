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

    # ── Portfolio returns with optimal weights ────────────────────
    targets::tar_target(port_combined, {
      library(dplyr)

      strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif")
      w <- port_optimal_weights

      ret_matrix <- as.matrix(port_returns[, strat_cols])
      port_ret <- as.numeric(ret_matrix %*% w)

      # Equal-weight benchmark
      eq_ret <- rowMeans(ret_matrix)

      port_returns |>
        mutate(
          optimal_ret = port_ret,
          equalwt_ret = eq_ret,
          optimal_cum = cumprod(1 + optimal_ret),
          equalwt_cum = cumprod(1 + equalwt_ret)
        )
    }),

    # ── Portfolio metrics ─────────────────────────────────────────
    targets::tar_target(port_metrics, {
      library(dplyr)

      calc_port_metrics <- function(df, label) {
        n <- nrow(df)
        if (n < 12) return(NULL)
        tibble(
          period = label, months = n,
          opt_cagr = prod(1 + df$optimal_ret)^(12/n) - 1,
          opt_vol = sd(df$optimal_ret) * sqrt(12),
          opt_sharpe = (prod(1 + df$optimal_ret)^(12/n) - 1 - mean(df$rf_ret)*12) /
            (sd(df$optimal_ret) * sqrt(12)),
          opt_maxdd = min(cumprod(1 + df$optimal_ret) / cummax(cumprod(1 + df$optimal_ret)) - 1),
          eq_cagr = prod(1 + df$equalwt_ret)^(12/n) - 1,
          eq_vol = sd(df$equalwt_ret) * sqrt(12),
          eq_sharpe = (prod(1 + df$equalwt_ret)^(12/n) - 1 - mean(df$rf_ret)*12) /
            (sd(df$equalwt_ret) * sqrt(12)),
          eq_maxdd = min(cumprod(1 + df$equalwt_ret) / cummax(cumprod(1 + df$equalwt_ret)) - 1)
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
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      w <- port_optimal_weights
      w_label <- paste(names(w), paste0(round(w * 100), "%"), sep = "=", collapse = ", ")

      plot_data <- port_combined |>
        select(date,
               `PSO Optimal` = optimal_cum,
               `Equal Weight` = equalwt_cum) |>
        tidyr::pivot_longer(-date, names_to = "portfolio", values_to = "growth")

      ggplot(plot_data, aes(date, growth, colour = portfolio)) +
        geom_line(linewidth = 0.6) +
        geom_vline(xintercept = stk_params$test_start, linetype = "dashed",
                   colour = "grey50", linewidth = 0.4) +
        scale_y_log10(labels = dollar) +
        scale_colour_manual(values = hd_palette(2)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = "Portfolio: PSO Optimal vs Equal Weight",
             subtitle = paste("Weights:", w_label)) +
        hd_theme()
    })
  )
}
