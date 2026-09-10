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
    #
    # #603/#656: this used to be a 4-way inner_join chain, so any `ym`
    # missing from ONE of the four constituents silently deleted that month
    # for ALL FOUR (historically ~128 of ~190 rows -- see #603). Worse: the
    # block bootstrap below (boot_draws) resamples CONTIGUOUS row-index
    # blocks to preserve serial dependence, so a join that leaves calendar
    # gaps let a "3-month block" splice two non-adjacent calendar months
    # together, defeating the entire point of block resampling.
    #
    # Fix mirrors #651 (R/plan_portfolio_opt.R's port_returns, the same
    # defect on the identical four constituents): an explicit
    # calendar-complete monthly spine, bounded to the OVERLAP of the two
    # stock-level series' own date ranges, with everything LEFT-joined onto
    # it. A missing constituent is now an explicit NA in its own column,
    # never a deleted row -- and because the spine is one row per calendar
    # month, row order downstream is always calendar-contiguous, so a block
    # sampled from it can never straddle a gap. calc_boot_metrics() in
    # boot_metrics below drops NA pairwise per strategy/rf pair, so one
    # strategy's gap cannot poison another strategy's draws for the same
    # block (they use their own, independently-paired columns).
    targets::tar_target(boot_monthly_returns, {
      library(dplyr)

      stk_max  <- stk_max_portfolio  |> select(ym, stk_max = port_ret,       stk_max_rf = rf_ret)
      stk_drif <- stk_drif_portfolio |> select(ym, stk_drif = port_ret,      stk_drif_rf = rf_ret)
      fac_max  <- fm_portfolio       |> select(ym, fac_max = portfolio_ret,  fac_max_rf = rf_ret)
      fac_drif <- drif_portfolio     |> select(ym, fac_drif = portfolio_ret, fac_drif_rf = rf_ret)

      # Calendar-complete monthly spine bounded to the stock-level overlap
      # window -- NOT the literal set of ym values present in stk_max/
      # stk_drif, which is exactly what would silently re-drop a month if
      # either ever loses one again (see the #651 comment on port_returns,
      # R/plan_portfolio_opt.R, for the full rationale on this bound).
      spine_start <- max(min(stk_max$ym), min(stk_drif$ym))
      spine_end   <- min(max(stk_max$ym), max(stk_drif$ym))
      spine <- tibble::tibble(
        ym = format(
          seq(as.Date(paste0(spine_start, "-01")),
              as.Date(paste0(spine_end, "-01")),
              by = "month"),
          "%Y-%m"
        )
      )

      combined <- spine |>
        left_join(stk_max, by = "ym") |>
        left_join(stk_drif, by = "ym") |>
        left_join(fac_max, by = "ym") |>
        left_join(fac_drif, by = "ym") |>
        arrange(ym)

      # Fail loud, not null (fail-loud-not-null.md #4): report which months
      # and strategies are missing rather than letting the gap pass
      # silently. This is expected to be empty in the current data (#656
      # measured 193/193 exact) -- it exists as a regression guard, not a
      # live-defect report.
      strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif")
      avail <- rowSums(!is.na(as.matrix(combined[, strat_cols])))
      thin <- combined[avail < length(strat_cols), , drop = FALSE]
      if (nrow(thin) > 0L) {
        thin_msgs <- vapply(seq_len(nrow(thin)), function(i) {
          row <- thin[i, ]
          missing_strats <- strat_cols[is.na(row[strat_cols])]
          sprintf("  %s -- missing: %s", row$ym, paste(missing_strats, collapse = ", "))
        }, character(1L))
        cli::cli_warn(c(
          "!" = paste0(
            length(thin_msgs), " month(s) in boot_monthly_returns have at ",
            "least one missing constituent strategy (#603/#656):"
          ),
          setNames(thin_msgs, rep("i", length(thin_msgs))),
          "i" = paste0(
            "calc_boot_metrics() (boot_metrics target below) drops NA ",
            "pairwise per strategy, so this cannot poison another ",
            "strategy's bootstrap draws."
          )
        ))
      }

      combined
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

      # Derive the strategy list from the data, NOT a hardcoded vector. The
      # pre-#677 code used colnames(boot_monthly_returns |> select(-ym));
      # adding the paired `<strat>_rf` columns broke that (an rf column would
      # be treated as a strategy), and the first fix was to enumerate the
      # four names literally. That is the "scope drawn around the known
      # instances" pattern this repo keeps being bitten by (#667 S11's
      # enumerated pair, PR #661's paths: glob, #674's one-directional
      # registry check) -- a fifth strategy added to boot_monthly_returns
      # would have been silently dropped from the bootstrap with nothing
      # saying so. Derive by excluding the `_rf` suffix instead, and assert
      # the pairing is complete (fail-loud-not-null.md).
      # Derived from the draws matrix boot_metrics already holds, NOT from
      # boot_monthly_returns -- reading the latter here would add a new DAG
      # edge for nothing, since every draw carries the same columns.
      all_cols    <- setdiff(colnames(boot_draws[[1]]), "ym")
      strat_names <- all_cols[!grepl("_rf$", all_cols)]
      rf_names    <- paste0(strat_names, "_rf")

      missing_rf <- setdiff(rf_names, all_cols)
      if (length(missing_rf) > 0L) {
        cli::cli_abort(c(
          "x" = "{length(missing_rf)} strateg{?y/ies} in boot_monthly_returns have no paired risk-free column:",
          "i" = "Missing: {.field {missing_rf}}.",
          "i" = "Every `<strategy>` column must have a matching `<strategy>_rf` (see boot_monthly_returns above, #677)."
        ))
      }
      if (length(strat_names) == 0L) {
        cli::cli_abort(c(
          "x" = "boot_monthly_returns has no strategy columns (only ym and/or _rf columns).",
          "i" = "Check the select() in boot_monthly_returns (R/plan_bootstrap_ci.R)."
        ))
      }

      # Compute rf-adjusted Sharpe, CAGR, max DD for a return + rf pair
      #
      # #603/#656: ret/rf can now contain NA (a missing constituent month,
      # via the calendar spine built in boot_monthly_returns above). prod()/
      # sd()/cumprod() on a vector containing any NA all return NA, so drop
      # pairwise before computing -- this keeps one strategy's gap from
      # poisoning ITS OWN cagr/vol/max_dd while leaving the other three
      # strategies' draws for that same block untouched (each uses its own,
      # independently-paired ret/rf columns).
      calc_boot_metrics <- function(ret, rf) {
        keep <- !is.na(ret) & !is.na(rf)
        ret <- ret[keep]
        rf  <- rf[keep]
        n <- length(ret)
        if (n < 2L) {
          return(c(sharpe = NA_real_, cagr = NA_real_, max_dd = NA_real_))
        }
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
