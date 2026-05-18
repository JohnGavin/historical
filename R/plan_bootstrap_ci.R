# Bootstrap confidence intervals on Sharpe/DD (#37)
#
# Block bootstrap (block_size=3) monthly returns to preserve
# autocorrelation. Reports 5th/95th percentile CI on Sharpe,
# max drawdown, and CAGR per strategy.
#
# Flags strategies where Sharpe CI crosses zero.

plan_bootstrap_ci <- function() {
  list(
    targets::tar_target(boot_params, {
      list(
        n_draws = 1000L,
        block_size = 3L,   # months per block (preserves quarterly autocorrelation)
        seed = 42L,
        ci_lo = 0.05,
        ci_hi = 0.95
      )
    }),

    # Collect monthly returns per strategy into wide format
    targets::tar_target(boot_monthly_returns, {
      library(dplyr)

      stk_max <- stk_max_portfolio |> select(ym, stk_max = port_ret)
      stk_drif <- stk_drif_portfolio |> select(ym, stk_drif = port_ret)
      fac_max <- fm_portfolio |> select(ym, fac_max = portfolio_ret)
      fac_drif <- drif_portfolio |> select(ym, fac_drif = portfolio_ret)

      stk_max |>
        inner_join(stk_drif, by = "ym") |>
        inner_join(fac_max, by = "ym") |>
        inner_join(fac_drif, by = "ym") |>
        arrange(ym)
    }),

    # Block bootstrap resampling
    targets::tar_target(boot_draws, {
      set.seed(boot_params$seed)

      ret_mat <- boot_monthly_returns |>
        dplyr::select(-ym) |>
        as.matrix()

      n <- nrow(ret_mat)
      bs <- boot_params$block_size
      n_blocks <- ceiling(n / bs)

      # Generate n_draws resampled return matrices
      lapply(seq_len(boot_params$n_draws), function(i) {
        # Sample block start indices with replacement
        starts <- sample(seq_len(n - bs + 1), n_blocks, replace = TRUE)
        # Build resampled series from blocks
        idx <- unlist(lapply(starts, function(s) s:(s + bs - 1)))
        idx <- idx[seq_len(n)]  # trim to original length
        ret_mat[idx, , drop = FALSE]
      })
    }),

    # Compute metrics for each draw
    targets::tar_target(boot_metrics, {
      library(dplyr)

      strat_names <- colnames(boot_monthly_returns |> select(-ym))

      # Compute Sharpe, CAGR, max DD for a return vector
      calc_boot_metrics <- function(ret) {
        n <- length(ret)
        cagr <- prod(1 + ret)^(12 / n) - 1
        vol <- sd(ret) * sqrt(12)
        sharpe <- if (vol > 0) cagr / vol else NA_real_
        cum <- cumprod(1 + ret)
        max_dd <- min(cum / cummax(cum) - 1)
        c(sharpe = sharpe, cagr = cagr, max_dd = max_dd)
      }

      # For each draw, compute metrics per strategy
      results <- lapply(seq_along(boot_draws), function(i) {
        mat <- boot_draws[[i]]
        lapply(seq_along(strat_names), function(j) {
          m <- calc_boot_metrics(mat[, j])
          tibble(
            draw = i,
            strategy = strat_names[j],
            sharpe = m["sharpe"],
            cagr = m["cagr"],
            max_dd = m["max_dd"]
          )
        }) |> bind_rows()
      }) |> bind_rows()

      results
    }),

    # Summary: CI per strategy
    targets::tar_target(boot_ci_summary, {
      library(dplyr)

      strategy_labels <- c(
        stk_max = "Stock MAX", stk_drif = "Stock DRIF",
        fac_max = "Factor MAX", fac_drif = "Factor DRIF"
      )

      boot_metrics |>
        group_by(strategy) |>
        summarise(
          sharpe_mean = mean(sharpe, na.rm = TRUE),
          sharpe_lo = quantile(sharpe, boot_params$ci_lo, na.rm = TRUE),
          sharpe_hi = quantile(sharpe, boot_params$ci_hi, na.rm = TRUE),
          cagr_mean = mean(cagr, na.rm = TRUE),
          cagr_lo = quantile(cagr, boot_params$ci_lo, na.rm = TRUE),
          cagr_hi = quantile(cagr, boot_params$ci_hi, na.rm = TRUE),
          dd_mean = mean(max_dd, na.rm = TRUE),
          dd_lo = quantile(max_dd, boot_params$ci_lo, na.rm = TRUE),
          dd_hi = quantile(max_dd, boot_params$ci_hi, na.rm = TRUE),
          .groups = "drop"
        ) |>
        mutate(
          strategy_label = strategy_labels[strategy],
          ci_crosses_zero = sharpe_lo <= 0 & sharpe_hi >= 0
        )
    }),

    # CI plot: Sharpe distribution per strategy
    targets::tar_target(boot_sharpe_plot, {
      library(ggplot2)
      library(dplyr)

      strategy_labels <- c(
        stk_max = "Stock MAX", stk_drif = "Stock DRIF",
        fac_max = "Factor MAX", fac_drif = "Factor DRIF"
      )

      boot_metrics |>
        mutate(strategy_label = strategy_labels[strategy]) |>
        ggplot(aes(x = sharpe, fill = strategy_label)) +
        geom_histogram(bins = 50, alpha = 0.7) +
        geom_vline(xintercept = 0, linetype = "dashed", colour = "red") +
        facet_wrap(~strategy_label, scales = "free_y", ncol = 2) +
        scale_fill_manual(values = hd_palette(4)) +
        labs(x = "Bootstrapped Sharpe Ratio", y = "Count",
             title = paste0("Bootstrap CI (", boot_params$n_draws,
                            " draws, block=", boot_params$block_size, "m)"),
             subtitle = "Red dashed line = zero. CI crossing zero = strategy may be noise.") +
        hd_theme() +
        theme(legend.position = "none")
    })
  )
}
