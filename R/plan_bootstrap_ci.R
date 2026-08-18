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
    #
    # #677 slice 2: also carry each strategy's own risk-free series --
    # already joined onto its portfolio target upstream (stk_max_portfolio,
    # stk_drif_portfolio, fm_portfolio, drif_portfolio all carry `rf_ret`)
    # -- so the bootstrap Sharpe below uses the SAME rf-adjusted definition
    # as the leaderboard (sharpe_ratio_rf(), R/utils_metrics.R). Without
    # this, boot_ci_summary's "does the Sharpe CI cross zero" flag was
    # computed on an inflated no-rf Sharpe (cagr/vol with implied rf =
    # exactly 0.00%, the same formula signature flagged in #677), which is
    # systematically more lenient than the rf-adjusted Sharpe published
    # for the same strategy elsewhere on the leaderboard -- a decision
    # judged on this file's own terms rather than migrated reflexively:
    # this IS a statistical-inference display (does the strategy's Sharpe
    # differ from zero), so it must use the same basis as what it is
    # implicitly being compared against.
    targets::tar_target(boot_monthly_returns, {
      library(dplyr)

      stk_max  <- stk_max_portfolio  |> select(ym, stk_max = port_ret,       stk_max_rf = rf_ret)
      stk_drif <- stk_drif_portfolio |> select(ym, stk_drif = port_ret,      stk_drif_rf = rf_ret)
      fac_max  <- fm_portfolio       |> select(ym, fac_max = portfolio_ret,  fac_max_rf = rf_ret)
      fac_drif <- drif_portfolio     |> select(ym, fac_drif = portfolio_ret, fac_drif_rf = rf_ret)

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
    #
    # #677 slice 2: sharpe now uses sharpe_ratio_rf() (R/utils_metrics.R)
    # paired with each strategy's own risk-free draw column (added to
    # boot_monthly_returns / boot_draws above), instead of bare cagr/vol.
    targets::tar_target(boot_metrics, {
      library(dplyr)

      strat_names <- c("stk_max", "stk_drif", "fac_max", "fac_drif")
      rf_names    <- paste0(strat_names, "_rf")

      # Compute rf-adjusted Sharpe, CAGR, max DD for a return + rf pair
      calc_boot_metrics <- function(ret, rf) {
        n <- length(ret)
        cagr <- prod(1 + ret)^(12 / n) - 1
        vol <- sd(ret) * sqrt(12)
        sr <- sharpe_ratio_rf(ret, rf, periods_per_year = 12L)
        cum <- cumprod(1 + ret)
        max_dd <- min(cum / cummax(cum) - 1)
        c(sharpe = sr$sharpe, cagr = cagr, max_dd = max_dd)
      }

      # For each draw, compute metrics per strategy
      results <- lapply(seq_along(boot_draws), function(i) {
        mat <- boot_draws[[i]]
        lapply(seq_along(strat_names), function(j) {
          m <- calc_boot_metrics(mat[, strat_names[j]], mat[, rf_names[j]])
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
        facet_wrap(~strategy_label, ncol = 2) +  # #355: fixed scales (default) so sub-plots are visually comparable
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
