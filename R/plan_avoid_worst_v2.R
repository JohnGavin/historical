# plan_avoid_worst_v2.R — Avoid Worst Days multiverse / specification-curve
#
# Extends the multiverse / specification-curve pattern introduced for DRIF
# (R/plan_drif_v2.R, issue #157) to a second core strategy, per issue #490
# Gap 2: "generalise specification-curve / multiverse beyond DRIF."
#
# Strategy chosen: Avoid Worst Days' VIX-triggered practical overlay
# (aw_practical_* targets, plan_avoid_worst.R). Per issue #726's
# detection-power audit, Avoid Worst is one of only two leaderboard
# strategies whose observed Sharpe (0.620) clears its own detectability
# bar (needs 16.1 of 33.1 available years) -- six other candidate
# strategies (Value/HML, Factor DRIF, Mom Pre-Peak, Risk State, LTR,
# Managed Futures) are flagged `detection_underpowered` and were skipped:
# per .claude/rules/detection-power-required.md, a multiverse on an
# underpowered strategy sweeps configuration on a signal that may already
# be indistinguishable from noise.
#
# The existing `aw_practical_sensitivity` target (plan_avoid_worst.R) is a
# ONE-parameter sweep -- it varies vix_thresholds OR shock_thresholds, one
# dimension at a time, and never varies cooloff or transaction cost jointly.
# This file generalises that into a full 2^4 = 16-cell grid, mirroring
# #157's DRIF pattern exactly: a grid target, a runner target reporting the
# DISTRIBUTION of OOS Sharpe (not a single point estimate), a spec-curve
# plot, and a dynamic caption. Like plan_drif_v2.R's drif_multiverse*
# targets, these are exploratory/diagnostic and are NOT written to the
# bt.* strategy registry (plan_avoid_worst.R's aw_practical_* targets
# remain the canonical, registered production path).
#
# Four dimensions varied (issue #490 Gap 2 names window length / rebalance
# interval / cost assumption as example dimensions; translated to this
# event-triggered overlay's own analysis choices):
#   1. vix_high            — VIX trigger level: 30 (current) vs 25 (more sensitive)
#   2. shock_threshold     — daily-move trigger: 0.03 (current) vs 0.02 (more sensitive)
#   3. min_cooloff_days    — cash cooling-off window: 5 (current) vs 3
#   4. cost_per_switch_bps — transaction-cost assumption: 5bp (current, realistic) vs 0bp (idealised)
#
# OOS window: aw_params$oos_start .. aw_params$test_end -- the identical
# bound used by aw_metrics' "Testing" partition (plan_avoid_worst.R), so
# the comparison across all 16 specs is purely out-of-sample and uses the
# same window as the production target.
#
# Output targets:
#   aw_multiverse_grid    — tibble of 16 parameter combinations
#   aw_multiverse         — tibble with one row per spec, OOS performance metrics
#   aw_multiverse_plot    — spec-curve fan plot, current spec highlighted
#   aw_multiverse_caption — dynamic caption for vignette use
#
# Relationship to existing code:
#   Re-uses aw_vix_daily, aw_params, aw_daily_rf, .aw_sharpe_rf_full() from
#   plan_avoid_worst.R (no duplication). plan_avoid_worst.R's aw_practical_*
#   targets remain the canonical single-spec production path.
#
# Issues: #157 (DRIF multiverse pattern this file mirrors), #490 Gap 2 (this
# generalisation), #726 (detection-power audit that ruled out the six
# underpowered candidate strategies)

plan_avoid_worst_v2 <- function() {
  list(

    # ── 1. Parameter grid ─────────────────────────────────────────
    #' @title Avoid Worst multiverse parameter grid (2^4 = 16 specifications)
    targets::tar_target(aw_multiverse_grid, {
      tidyr::expand_grid(
        vix_high            = c(25, 30),
        shock_threshold     = c(0.02, 0.03),
        min_cooloff_days    = c(3L, 5L),
        cost_per_switch_bps = c(0, 5)
      ) |>
        dplyr::mutate(
          spec_id = sprintf("S%02d", dplyr::row_number()),
          # aw_practical_params defaults (plan_avoid_worst.R): vix_high=30,
          # shock_threshold=0.03, min_cooloff_days=5, 5bp/switch cost.
          is_current = vix_high == 30 &
                       shock_threshold == 0.03 &
                       min_cooloff_days == 5L &
                       cost_per_switch_bps == 5
        )
    }),

    # ── 2. Multiverse runner ──────────────────────────────────────
    # Iterates over the 16-cell grid, re-running the VIX-triggered overlay
    # rule (same decision logic as aw_practical_backtest()'s run_strategy())
    # restricted to the OOS-only window, so the comparison across specs is
    # purely out-of-sample and uses the same bound as aw_metrics' "Testing"
    # partition.
    targets::tar_target(aw_multiverse, {
      library(dplyr)

      grid      <- aw_multiverse_grid
      oos_start <- as.Date(aw_params$oos_start)
      test_end  <- as.Date(aw_params$test_end)

      d <- aw_vix_daily |>
        dplyr::filter(!is.na(vix), !is.na(ret)) |>
        dplyr::mutate(date = as.Date(date)) |>
        dplyr::filter(date >= oos_start, date <= test_end) |>
        dplyr::arrange(date)

      # Helper: run one specification on the OOS window, return metrics.
      run_spec <- function(vix_h, shock_t, cooloff, cost_bps) {
        n <- nrow(d)
        if (n < 60L) return(NULL)   # need at least ~3 trading months OOS

        vix_r  <- vix_h - 5
        in_mkt <- rep(TRUE, n)
        cool   <- 0L
        for (i in 2:n) {
          if (cool > 0) cool <- cool - 1L
          # t+1 execution: decision uses PREVIOUS day's signal only.
          shocked      <- abs(d$ret[i - 1]) > shock_t
          vp           <- d$vix[i - 1]
          vix_elevated <- !is.na(vp) && vp > vix_h
          if (shocked || vix_elevated) {
            in_mkt[i] <- FALSE
            cool <- max(cool, cooloff)
          } else if (cool > 0) {
            in_mkt[i] <- FALSE
          } else if (!is.na(vp) && vp > vix_r) {
            in_mkt[i] <- FALSE
          }
        }

        strat_ret <- ifelse(in_mkt, d$ret, 0)
        # Deduct transaction cost on days the position flips (mirrors the
        # aw_transaction_costs convention: cost_per_switch applied per switch).
        switch_day <- c(FALSE, diff(as.integer(in_mkt)) != 0)
        n_switches <- sum(switch_day)
        cost_frac  <- cost_bps / 10000
        strat_ret[switch_day] <- strat_ret[switch_day] - cost_frac

        # #677 convention: canonical rf-adjusted geometric Sharpe, passing the
        # FULL aw_daily_rf (not a pre-sliced subset) -- matches every other
        # spec/window runner in plan_avoid_worst.R (aw_metrics, aw_walkforward).
        sr <- .aw_sharpe_rf_full(d$date, strat_ret, aw_daily_rf, ann_factor = 252L)

        years  <- n / 252
        cum    <- cumprod(1 + strat_ret)
        max_dd <- min((cum - cummax(cum)) / cummax(cum))

        tibble::tibble(
          n_days     = n,
          oos_cagr   = utils::tail(cum, 1)^(1 / years) - 1,
          oos_vol    = stats::sd(strat_ret) * sqrt(252),
          oos_sharpe = sr$sharpe,
          oos_max_dd = max_dd,
          n_switches = n_switches,
          pct_cash   = sum(!in_mkt) / n
        )
      }

      results <- purrr::pmap(
        list(
          vix_h    = grid$vix_high,
          shock_t  = grid$shock_threshold,
          cooloff  = grid$min_cooloff_days,
          cost_bps = grid$cost_per_switch_bps
        ),
        function(vix_h, shock_t, cooloff, cost_bps) {
          cli::cli_inform(c(
            "i" = "Avoid Worst multiverse: vix_high={vix_h} shock={shock_t} cooloff={cooloff} cost_bps={cost_bps}"
          ))
          run_spec(vix_h, shock_t, cooloff, cost_bps)
        }
      )

      grid |>
        dplyr::bind_cols(
          dplyr::bind_rows(
            purrr::map(results, ~ if (is.null(.x)) {
              tibble::tibble(n_days = NA_integer_, oos_cagr = NA_real_,
                             oos_vol = NA_real_, oos_sharpe = NA_real_,
                             oos_max_dd = NA_real_, n_switches = NA_integer_,
                             pct_cash = NA_real_)
            } else .x)
          )
        )
    }),

    # ── 3. Spec-curve plot ────────────────────────────────────────
    # Fan chart: each bar = one specification, sorted by OOS Sharpe.
    # Current spec highlighted with a different fill.
    targets::tar_target(aw_multiverse_plot, {
      library(ggplot2)
      library(dplyr)

      d <- aw_multiverse |>
        filter(!is.na(oos_sharpe)) |>
        arrange(oos_sharpe) |>
        mutate(
          spec_label = paste0(spec_id,
                              " (vix=", vix_high,
                              " shock=", shock_threshold,
                              " cool=", min_cooloff_days,
                              " cost=", cost_per_switch_bps, "bp)"),
          spec_label = factor(spec_label, levels = unique(spec_label)),
          highlight  = is_current
        )

      current_sharpe <- d |> filter(is_current) |> pull(oos_sharpe)
      current_rank   <- which(d$is_current)
      n_specs        <- nrow(d)

      ggplot(d, aes(x = spec_label, y = oos_sharpe, fill = highlight)) +
        geom_col(width = 0.7) +
        geom_hline(yintercept = 0, linewidth = 0.4, colour = "grey50") +
        geom_hline(yintercept = current_sharpe, linetype = "dashed",
                   colour = "grey40", linewidth = 0.35) +
        scale_fill_manual(
          values = c("TRUE" = "#4ea8de", "FALSE" = "#69d4a0"),
          labels = c("TRUE" = "Current spec", "FALSE" = "Alternative"),
          guide  = guide_legend(title = NULL)
        ) +
        coord_flip() +
        labs(
          x     = NULL,
          y     = "OOS Annualised Sharpe",
          title = "Avoid Worst (VIX Overlay) Specification Curve (2^4 = 16 specs)",
          subtitle = sprintf(
            "Current spec ranks %d of %d by OOS Sharpe (range %.2f to %.2f)",
            current_rank, n_specs,
            min(d$oos_sharpe, na.rm = TRUE),
            max(d$oos_sharpe, na.rm = TRUE)
          )
        ) +
        hd_theme() +
        theme(legend.position = "bottom")
    }),

    # ── 4. Dynamic caption ────────────────────────────────────────
    # Per dynamic-prose-values rule: every value computed at pipeline time,
    # not hardcoded, including the current-spec description itself.
    targets::tar_target(aw_multiverse_caption, {
      d <- aw_multiverse |>
        dplyr::filter(!is.na(oos_sharpe)) |>
        dplyr::arrange(oos_sharpe)

      n_specs        <- nrow(d)
      current_rank   <- which(d$is_current)
      min_sharpe     <- round(min(d$oos_sharpe, na.rm = TRUE), 2)
      max_sharpe     <- round(max(d$oos_sharpe, na.rm = TRUE), 2)
      current_sharpe <- round(d$oos_sharpe[current_rank], 2)
      current_row    <- d[current_rank, ]
      current_desc   <- sprintf(
        "%s: vix=%s, shock=%s, cooloff=%sd, cost=%sbp",
        current_row$spec_id, current_row$vix_high,
        current_row$shock_threshold, current_row$min_cooloff_days,
        current_row$cost_per_switch_bps
      )

      paste0(
        "Of ", n_specs, " specifications tested (varying VIX trigger, ",
        "shock threshold, cooling-off window, and transaction-cost ",
        "assumption), the current Avoid Worst VIX-overlay spec (",
        current_desc, ") ranks ", current_rank,
        " by OOS Sharpe (", current_sharpe,
        "). Sharpe range across specs: ", min_sharpe, " to ", max_sharpe,
        ". Source: plan_avoid_worst_v2.R; pattern: #157 (DRIF multiverse)."
      )
    })
  )
}
