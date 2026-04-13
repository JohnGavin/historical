# Factor Max targets: rotation strategy using maximum daily factor returns
#
# Based on Alpha Architect research (Dec 2025): the maximum daily return
# within a month predicts next-month factor returns. Buys high-MAX factors.
#
# Uses Fama-French FF5 + Momentum factors (already on HuggingFace).
# Expanding window methodology, same OOS holdout as Defense First.

plan_factormax <- function() {
  list(
    # ── Parameters ────────────────────────────────────────────────
    targets::tar_target(fm_params, {
      list(
        # Academic factors to rotate among
        factors = c("HML", "SMB", "RMW", "CMA", "Mom"),
        benchmark_factor = "Mkt-RF",
        top_n = 2L,             # hold top N factors by MAX signal
        start_date = as.Date("1963-07-01"),  # FF5 start
        is_end = as.Date("2019-12-31"),      # in-sample end
        oos_start = as.Date("2020-01-01")    # out-of-sample start
      )
    }),

    # ── Data: daily factor returns ────────────────────────────────
    targets::tar_target(fm_daily, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      # FF5 has HML, SMB, RMW, CMA, Mkt-RF, RF
      ff5 <- hd_factors(dataset = "FF5", frequency = "daily",
                        from = as.character(fm_params$start_date))
      # Momentum
      mom <- hd_factors(dataset = "Mom", frequency = "daily",
                        from = as.character(fm_params$start_date))

      bind_rows(ff5, mom) |>
        filter(factor_name %in% c(fm_params$factors, fm_params$benchmark_factor, "RF")) |>
        mutate(value = value / 100) |>  # French data is in percent
        arrange(factor_name, date)
    }),

    # ── MAX signal: max daily return per factor per month ──────────
    targets::tar_target(fm_signal, {
      library(dplyr)

      fm_daily |>
        filter(factor_name %in% fm_params$factors) |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(factor_name, ym) |>
        summarise(
          max_ret = max(value, na.rm = TRUE),
          mean_ret = mean(value, na.rm = TRUE),
          n_days = n(),
          .groups = "drop"
        ) |>
        # Rank factors by MAX within each month (higher MAX = buy signal)
        group_by(ym) |>
        mutate(max_rank = rank(-max_ret, ties.method = "min")) |>
        ungroup() |>
        arrange(ym, max_rank)
    }),

    # ── Monthly factor returns (for portfolio construction) ────────
    targets::tar_target(fm_monthly, {
      library(dplyr)

      fm_daily |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(factor_name, ym) |>
        summarise(
          monthly_ret = prod(1 + value) - 1,
          last_date = max(date),
          .groups = "drop"
        ) |>
        arrange(factor_name, ym)
    }),

    # ── Portfolio: expanding window backtest ───────────────────────
    targets::tar_target(fm_portfolio, {
      library(dplyr)

      months <- sort(unique(fm_signal$ym))
      benchmark <- fm_monthly |> filter(factor_name == fm_params$benchmark_factor)
      rf <- fm_monthly |> filter(factor_name == "RF")

      # Need at least 12 months of history before first trade
      min_history <- 12L
      trade_months <- months[(min_history + 1):length(months)]

      results <- lapply(trade_months, function(m) {
        # Signal: use MAX ranks from PREVIOUS month
        prev_idx <- which(months == m) - 1
        if (prev_idx < 1) return(NULL)
        prev_m <- months[prev_idx]

        signal <- fm_signal |> filter(ym == prev_m)
        if (nrow(signal) == 0) return(NULL)

        # Select top N factors
        selected <- signal |>
          filter(max_rank <= fm_params$top_n) |>
          pull(factor_name)

        if (length(selected) == 0) return(NULL)

        # Equal weight among selected factors
        factor_rets <- fm_monthly |>
          filter(factor_name %in% selected, ym == m)

        if (nrow(factor_rets) == 0) return(NULL)

        port_ret <- mean(factor_rets$monthly_ret)
        bench_ret <- benchmark |> filter(ym == m) |> pull(monthly_ret)
        rf_ret <- rf |> filter(ym == m) |> pull(monthly_ret)

        tibble(
          date = factor_rets$last_date[1],
          ym = m,
          portfolio_ret = port_ret,
          benchmark_ret = if (length(bench_ret) == 1) bench_ret else NA_real_,
          rf_ret = if (length(rf_ret) == 1) rf_ret else NA_real_,
          selected_factors = paste(selected, collapse = ", "),
          n_factors = length(selected)
        )
      })

      bind_rows(Filter(Negate(is.null), results)) |>
        mutate(
          port_cum = cumprod(1 + portfolio_ret),
          bench_cum = cumprod(1 + benchmark_ret),
          excess_ret = portfolio_ret - rf_ret
        )
    }),

    # ── Metrics: in-sample vs out-of-sample ───────────────────────
    targets::tar_target(fm_metrics, {
      library(dplyr)

      calc_metrics <- function(df, label) {
        n <- nrow(df)
        ann_ret <- prod(1 + df$portfolio_ret)^(12/n) - 1
        ann_vol <- sd(df$portfolio_ret) * sqrt(12)
        sharpe <- (ann_ret - mean(df$rf_ret) * 12) / ann_vol
        cum <- cumprod(1 + df$portfolio_ret)
        dd <- cum / cummax(cum) - 1
        max_dd <- min(dd)
        hit <- mean(df$portfolio_ret > df$benchmark_ret)

        bench_ann <- prod(1 + df$benchmark_ret)^(12/n) - 1
        bench_vol <- sd(df$benchmark_ret) * sqrt(12)
        bench_sharpe <- (bench_ann - mean(df$rf_ret) * 12) / bench_vol

        tibble(
          period = label,
          months = n,
          cagr = ann_ret, vol = ann_vol, sharpe = sharpe,
          max_dd = max_dd, hit_rate = hit,
          bench_cagr = bench_ann, bench_vol = bench_vol,
          bench_sharpe = bench_sharpe
        )
      }

      is_data <- fm_portfolio |> filter(date <= fm_params$is_end)
      oos_data <- fm_portfolio |> filter(date >= fm_params$oos_start)

      bind_rows(
        calc_metrics(is_data, "In-Sample"),
        calc_metrics(oos_data, "Out-of-Sample"),
        calc_metrics(fm_portfolio, "Full Period")
      )
    }),

    # ── Factor selection frequency ────────────────────────────────
    targets::tar_target(fm_selection_freq, {
      library(dplyr)

      fm_portfolio |>
        tidyr::separate_longer_delim(selected_factors, ", ") |>
        count(selected_factors, name = "months_selected") |>
        mutate(pct = months_selected / nrow(fm_portfolio)) |>
        arrange(desc(months_selected)) |>
        rename(factor = selected_factors)
    }),

    # ── Cumulative return plot ────────────────────────────────────
    targets::tar_target(fm_cumret_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      plot_data <- fm_portfolio |>
        select(date, `Factor MAX` = port_cum, `Market (Mkt-RF)` = bench_cum) |>
        tidyr::pivot_longer(-date, names_to = "strategy", values_to = "growth")

      ggplot(plot_data, aes(date, growth, colour = strategy)) +
        geom_line(linewidth = 0.6) +
        geom_vline(xintercept = fm_params$oos_start, linetype = "dashed",
                   colour = "grey50", linewidth = 0.4) +
        annotate("text", x = fm_params$oos_start, y = max(plot_data$growth) * 0.9,
                 label = "OOS start", colour = "grey60", hjust = -0.1, size = 3) +
        scale_y_log10(labels = dollar) +
        scale_colour_manual(values = hd_palette(2)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = "Factor MAX vs Market: cumulative returns") +
        hd_theme()
    }),

    # ── MAX signal heatmap ────────────────────────────────────────
    targets::tar_target(fm_heatmap, {
      library(ggplot2)
      library(dplyr)
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      # Last 5 years of signal for readability
      recent <- fm_signal |>
        filter(ym >= format(fm_params$oos_start - 365*2, "%Y-%m")) |>
        mutate(
          year = substr(ym, 1, 4),
          month = substr(ym, 6, 7)
        )

      ggplot(recent, aes(month, factor_name, fill = max_rank)) +
        geom_tile(colour = "grey20") +
        facet_wrap(~year, ncol = 1) +
        scale_fill_gradient(low = "#32CD32", high = "#333333",
                            breaks = 1:5, labels = paste0("#", 1:5)) +
        labs(x = "Month", y = NULL, fill = "Rank",
             title = "Factor MAX signal rankings (1 = highest MAX)") +
        hd_theme() +
        theme(axis.text.x = element_text(size = 9))
    })
  )
}
