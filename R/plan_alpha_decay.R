# Alpha decay analysis: t+1 to t+10 execution delay (#36)
#
# Measures how quickly alpha erodes when execution is delayed by d
# trading days. The signal (decile rank) is frozen at month-end;
# only the RETURN window shifts forward by d days.
#
# Method:
#   For delay d and month m:
#     - Return = price on day-(d+1) of month-(m+1) / price on day-(d+1) of month-m - 1
#     - Decile assignment uses the same signal as the undelayed strategy
#
# Consumes: stk_max_signal, stk_drif_signal, stk_daily_ret, stk_monthly,
#           stk_params, stk_rf
# Produces: decay_params, decay_delayed_returns, decay_metrics,
#           decay_half_life, decay_plot

plan_alpha_decay <- function() {
  list(
    # ── Parameters ────────────────────────────────────────────────
    targets::tar_target(decay_params, {
      list(
        delays     = 1:10,             # trading-day delays to test
        strategies = c("stk_max", "stk_drif"),
        min_months = 36L               # minimum months required for metrics
      )
    }),

    # ── Delayed returns for each strategy × delay combination ─────
    targets::tar_target(decay_delayed_returns, {
      library(dplyr)
      library(tidyr)

      # Helper: for a given delay d, compute the "shifted" monthly return
      # for each stock.  We use stk_daily_ret: for month m, find the trading
      # day at position d within that month's trading days (0-indexed: d=0
      # means the first day = standard month-end approach).
      #
      # Practical approach:
      #   - For each stock × month, get all trading days sorted
      #   - "entry price day" = the d-th trading day of the CURRENT month
      #     (1-indexed; d=1 means the first trading day of the month)
      #   - "exit price day"  = the d-th trading day of the NEXT month
      #   - delayed_ret = exit / entry - 1

      daily <- stk_daily_ret |>
        arrange(ticker, date) |>
        mutate(ym = format(date, "%Y-%m"))

      # Get all trading dates per ticker-month, with rank within month
      daily_ranked <- daily |>
        group_by(ticker, ym) |>
        arrange(date, .by_group = TRUE) |>
        mutate(day_rank = row_number(), n_days_month = n()) |>
        ungroup()

      # Compute adjusted price from cumulative daily returns
      # We work in return-space: price_d = prod(1 + r_1 .. r_d)
      # Return from day d1 to d2 (within same ticker) = prod(1+r) over [d1+1..d2]
      # We capture the "end-of-day-d price index" per ticker-month
      price_index <- daily_ranked |>
        group_by(ticker, ym) |>
        arrange(date, .by_group = TRUE) |>
        mutate(cum_ret = cumprod(1 + daily_ret)) |>
        ungroup()

      # For each delay d, compute returns
      results <- lapply(decay_params$delays, function(d) {
        # For each ticker-month, the entry price is cum_ret at day_rank == d
        # (within the current month). The exit price is cum_ret at day_rank == d
        # in the NEXT month.
        # If the month has fewer than d days, skip (NA).

        entry <- price_index |>
          filter(day_rank == d) |>
          select(ticker, ym, entry_cum = cum_ret, entry_date = date)

        # Get next month for each ticker-ym
        # Build a lookup: ym -> next_ym per ticker
        months_by_ticker <- daily |>
          select(ticker, ym) |>
          distinct() |>
          group_by(ticker) |>
          arrange(ym, .by_group = TRUE) |>
          mutate(next_ym = dplyr::lead(ym)) |>
          ungroup()

        exit <- price_index |>
          filter(day_rank == d) |>
          select(ticker, ym, exit_cum = cum_ret, exit_date = date)

        # Join: entry in month m, exit in month m+1
        delayed <- entry |>
          inner_join(months_by_ticker, by = c("ticker", "ym")) |>
          filter(!is.na(next_ym)) |>
          inner_join(
            exit |> rename(next_ym = ym),
            by = c("ticker", "next_ym")
          ) |>
          mutate(
            delayed_ret = exit_cum / entry_cum - 1,
            delay       = d
          ) |>
          select(ticker, ym = next_ym, delayed_ret, delay)

        delayed
      })

      bind_rows(results)
    }),

    # ── Metrics per strategy × delay ─────────────────────────────
    targets::tar_target(decay_metrics, {
      library(dplyr)

      # Helper: compute metrics for one strategy at one delay
      calc_decay_strategy <- function(signal_df, signal_col_name,
                                      delayed_ret_df, delay_d,
                                      strategy_name) {
        delayed_d <- delayed_ret_df |> filter(delay == delay_d)

        # Signal: previous-month signal used to form deciles
        # (same as standard portfolio construction)
        signal_lagged <- signal_df |>
          group_by(ticker) |>
          arrange(ym) |>
          mutate(ym = dplyr::lead(ym)) |>   # signal predicts NEXT month
          filter(!is.na(ym)) |>
          ungroup()

        merged <- signal_lagged |>
          inner_join(
            delayed_d |> rename(monthly_ret = delayed_ret),
            by = c("ticker", "ym")
          )

        if (nrow(merged) < 100) return(NULL)

        # Assign deciles using the signal column
        sig_sym   <- rlang::sym(signal_col_name)
        deciled   <- assign_decile(merged, !!sig_sym, stk_params$n_deciles)
        port      <- portfolio_longshort(
          deciled,
          long_decile         = 1L,
          short_decile        = 10L,
          cost_per_trade      = stk_params$cost_per_trade,
          borrow_rate_annual  = stk_params$borrow_rate_annual,
          max_monthly_ret     = stk_params$max_monthly_ret
        )

        port <- port |> left_join(stk_rf, by = "ym") |>
          mutate(date = as.Date(paste0(ym, "-15")))

        if (nrow(port) < decay_params$min_months) return(NULL)

        n       <- nrow(port)
        ann_ret <- prod(1 + port$port_ret)^(12/n) - 1
        ann_vol <- sd(port$port_ret) * sqrt(12)
        rf_ann  <- mean(port$rf_ret, na.rm = TRUE) * 12
        sharpe  <- if (ann_vol < 1e-8) NA_real_ else (ann_ret - rf_ann) / ann_vol
        cum     <- cumprod(1 + port$port_ret)
        max_dd  <- min(cum / cummax(cum) - 1)

        dplyr::tibble(
          strategy = strategy_name,
          delay    = delay_d,
          months   = n,
          cagr     = ann_ret,
          vol      = ann_vol,
          sharpe   = sharpe,
          max_dd   = max_dd
        )
      }

      # stk_max signal column is "max_ret"
      max_results <- lapply(decay_params$delays, function(d) {
        calc_decay_strategy(
          signal_df      = stk_max_signal,
          signal_col_name = "max_ret",
          delayed_ret_df = decay_delayed_returns,
          delay_d        = d,
          strategy_name  = "stk_max"
        )
      })

      # stk_drif signal column is "predicted_ret"
      drif_results <- lapply(decay_params$delays, function(d) {
        calc_decay_strategy(
          signal_df      = stk_drif_signal,
          signal_col_name = "predicted_ret",
          delayed_ret_df = decay_delayed_returns,
          delay_d        = d,
          strategy_name  = "stk_drif"
        )
      })

      bind_rows(Filter(Negate(is.null), c(max_results, drif_results)))
    }),

    # ── Half-life: delay at which Sharpe drops to 50% of t+0 ─────
    targets::tar_target(decay_half_life, {
      library(dplyr)

      # t+0 Sharpe (delay=1 is the earliest available; use as baseline)
      # Note: delay=0 is not computed — standard portfolio is computed
      # with month-end prices (the reference). We approximate t+0 by
      # extrapolating or using delay=1 as the baseline.
      baselines <- decay_metrics |>
        filter(delay == min(decay_params$delays)) |>
        select(strategy, base_sharpe = sharpe)

      decay_metrics |>
        left_join(baselines, by = "strategy") |>
        filter(!is.na(base_sharpe), base_sharpe > 0, !is.na(sharpe)) |>
        mutate(sharpe_ratio = sharpe / base_sharpe) |>
        group_by(strategy) |>
        # Find first delay where sharpe drops to or below 50%
        summarise(
          base_sharpe   = first(base_sharpe),
          half_life_days = {
            idx <- which(sharpe_ratio <= 0.5)
            if (length(idx) == 0) NA_integer_ else min(delay[idx])
          },
          .groups = "drop"
        )
    }),

    # ── Plot: Sharpe vs delay, one line per strategy ──────────────
    targets::tar_target(decay_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      # Normalise Sharpe to fraction of baseline (delay=1)
      baselines <- decay_metrics |>
        filter(delay == min(decay_params$delays)) |>
        select(strategy, base_sharpe = sharpe)

      plot_data <- decay_metrics |>
        left_join(baselines, by = "strategy") |>
        mutate(
          sharpe_pct = if_else(
            !is.na(base_sharpe) & base_sharpe > 0,
            sharpe / base_sharpe,
            NA_real_
          ),
          strategy_label = dplyr::recode(
            strategy,
            "stk_max"  = "Stock MAX",
            "stk_drif" = "Stock DRIF"
          )
        )

      ggplot(plot_data, aes(delay, sharpe_pct, colour = strategy_label)) +
        geom_line(linewidth = 0.7) +
        geom_point(size = 2) +
        geom_hline(yintercept = 0.5, linetype = "dashed",
                   colour = "grey40", linewidth = 0.4) +
        annotate("text", x = max(decay_params$delays) * 0.95, y = 0.52,
                 label = "50% of base Sharpe", colour = "grey40",
                 hjust = 1, size = 3) +
        scale_x_continuous(breaks = decay_params$delays) +
        scale_y_continuous(labels = percent, limits = c(NA, 1.1)) +
        scale_colour_manual(values = hd_palette(2)) +
        labs(
          x      = "Execution delay (trading days)",
          y      = "Sharpe ratio (relative to delay=1)",
          colour = NULL,
          title  = "Alpha Decay: Sharpe vs Execution Delay",
          subtitle = "Dashed line = 50% of baseline Sharpe (half-life threshold)"
        ) +
        hd_theme()
    })
  )
}
