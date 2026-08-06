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
      p <- bt_partitions$factor
      list(
        factors = c("HML", "SMB", "RMW", "CMA", "Mom"),
        benchmark_factor = "Mkt-RF",
        top_n = 2L,
        start_date = as.Date("1963-07-01"),  # FF5 data start
        is_end = p$train_end,
        test_start = p$test_start,
        test_end = p$test_end,
        holdout_start = p$holdout_start,  # #660: observed, not sealed
        holdout_end = p$holdout_end,
        val_start = p$val_start,
        val_end = p$val_end,
        oos_start = p$test_start,      # backwards compat
        # Cost model (#425): factor-level trades; 0.10%/trade one-way
        # (matches stk_all_caption claim; single source of truth in drif_params)
        cost_per_trade = 0.001
      )
    }),

    # ── Data: daily factor returns ────────────────────────────────
    targets::tar_target(fm_daily, {
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
    # NOTE(#299 CPCV): MAX signal is computed from current-month daily returns
    # and predicts NEXT month's return (portfolio rebalances at month-end for
    # t+1). Label horizon = 0 within the outer CV scheme (signal = current
    # month, label = next month = a different outer target). No label-window
    # purging needed here. CPCV multi-path integration deferred to #299 follow-up.
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

      # Track previous month's holdings to compute turnover (#425)
      prev_selected <- character(0L)

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

        # Cost model (#425): turnover = fraction of portfolio changed
        # vs previous holdings. Full rotation = 100% (top_n slots all changed).
        n_overlap <- length(intersect(prev_selected, selected))
        top_n <- fm_params$top_n
        # First trade month: prev_selected is empty → full entry cost
        turnover <- if (length(prev_selected) == 0L) 1.0 else
          1.0 - n_overlap / top_n

        cost <- fm_params$cost_per_trade * turnover * 2.0  # round-trip

        # Update for next iteration (<<- to mutate enclosing scope)
        prev_selected <<- selected

        gross_ret <- mean(factor_rets$monthly_ret)
        port_ret  <- gross_ret - cost

        bench_ret <- benchmark |> filter(ym == m) |> pull(monthly_ret)
        rf_ret    <- rf |> filter(ym == m) |> pull(monthly_ret)

        tibble(
          date = factor_rets$last_date[1],
          ym = m,
          gross_port_ret = gross_ret,
          turnover = turnover,
          cost = cost,
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
        # #660: val_start moves to 2026-05-01 (first month past the current
        # data boundary), so the Validation slice below is empty against
        # today's data (0 rows) -- without this guard, n=0 would propagate
        # through 1^Inf/NA arithmetic and emit a spurious row instead of
        # silently contributing nothing, unlike every sibling calc_metrics()/
        # calc_backtest_metrics() in this codebase (R/plan_drif.R,
        # R/plan_stock_backtest.R, R/plan_etf_replication.R,
        # R/plan_portfolio_opt.R, R/plan_ltr_momentum.R all already guard
        # at n < 12 or n < 6).
        if (n < 12) return(NULL)
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

      train_data <- fm_portfolio |> filter(date <= fm_params$is_end)
      test_data <- fm_portfolio |> filter(date >= fm_params$test_start, date <= fm_params$test_end)
      # #666: Holdout (2024-01-01..2026-04-30, observed but not sealed) --
      # so the Holdout row emitted by slice_portfolio() in R/plan_leaderboard.R
      # finds a matching base row here and survives the left_join instead of
      # being silently dropped (the #660 KNOWN GAP).
      holdout_data <- fm_portfolio |> filter(date >= fm_params$holdout_start, date <= fm_params$holdout_end)
      val_data <- fm_portfolio |> filter(date >= fm_params$val_start)

      bind_rows(
        calc_metrics(train_data, "Training"),
        calc_metrics(test_data, "Testing"),
        calc_metrics(holdout_data, "Holdout"),
        calc_metrics(val_data, "Validation"),
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

    # ── MAX signal bump chart ─────────────────────────────────────
    targets::tar_target(fm_heatmap, {
      library(ggplot2)
      library(dplyr)

      # Last 3 years for readability
      recent <- fm_signal |>
        filter(ym >= format(fm_params$oos_start - 365, "%Y-%m")) |>
        mutate(date = as.Date(paste0(ym, "-15")))

      # Colours per factor
      factor_cols <- setNames(hd_palette(5), sort(unique(recent$factor_name)))

      # Label first and last points
      first_last <- recent |>
        group_by(factor_name) |>
        filter(date == min(date) | date == max(date)) |>
        ungroup()

      ggplot(recent, aes(date, max_rank, colour = factor_name, group = factor_name)) +
        geom_line(linewidth = 0.8, alpha = 0.7) +
        geom_point(size = 2) +
        geom_text(data = first_last |> filter(date == max(date)),
                  aes(label = factor_name), hjust = -0.2, size = 4, fontface = "bold") +
        scale_y_reverse(breaks = 1:5, labels = paste0("#", 1:5)) +
        scale_colour_manual(values = factor_cols) +
        labs(x = NULL, y = "MAX Rank", colour = NULL,
             title = "Factor MAX signal rankings over time (1 = highest MAX)") +
        hd_theme() +
        theme(legend.position = "none",
              plot.margin = margin(5, 40, 5, 5))  # right margin for labels
    }),

    # ── ETF comparison: real-world factor ETFs ────────────────────
    targets::tar_target(fm_etf_data, {
      library(dplyr)

      # Factor ETFs mapped to academic factors
      etf_map <- dplyr::tribble(
        ~etf,   ~factor,       ~label,
        "VLUE", "HML",         "Value (VLUE vs HML)",
        "MTUM", "Mom",         "Momentum (MTUM vs Mom)",
        "QUAL", "RMW",         "Quality (QUAL vs RMW)",
        "USMV", "Mkt-RF",     "Low Vol (USMV vs Market)",
        "VTV",  "HML",         "Value alt (VTV vs HML)",
        "IWD",  "HML",         "Value R1000 (IWD vs HML)"
      )

      # Get ETF monthly returns
      etf_tickers <- unique(etf_map$etf)
      etf_raw <- hd_ohlcv(etf_tickers, from = "2013-05-01")

      if (nrow(etf_raw) == 0) return(NULL)

      etf_monthly <- etf_raw |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(ticker, ym) |>
        filter(date == max(date)) |>
        ungroup() |>
        group_by(ticker) |>
        arrange(date) |>
        mutate(ret = adjusted / dplyr::lag(adjusted) - 1) |>
        filter(!is.na(ret)) |>
        ungroup() |>
        select(ticker, date, ym, ret)

      # Get academic factor monthly returns for same period
      factor_monthly <- fm_monthly |>
        filter(factor_name %in% unique(etf_map$factor),
               ym >= min(etf_monthly$ym), ym <= max(etf_monthly$ym))

      list(etf_monthly = etf_monthly, factor_monthly = factor_monthly, etf_map = etf_map)
    }),

    # ── ETF vs Academic: correlation table ────────────────────────
    targets::tar_target(fm_etf_corr, {
      library(dplyr)
      if (is.null(fm_etf_data)) return(NULL)

      etf_m <- fm_etf_data$etf_monthly
      fac_m <- fm_etf_data$factor_monthly
      emap <- fm_etf_data$etf_map

      results <- lapply(seq_len(nrow(emap)), function(i) {
        e <- emap$etf[i]
        f <- emap$factor[i]
        etf_ret <- etf_m |> filter(ticker == e) |> select(ym, etf_ret = ret)
        fac_ret <- fac_m |> filter(factor_name == f) |> select(ym, fac_ret = monthly_ret)
        joined <- inner_join(etf_ret, fac_ret, by = "ym")
        if (nrow(joined) < 12) return(NULL)
        tibble(
          ETF = e, Factor = f, Label = emap$label[i],
          Months = nrow(joined),
          Correlation = round(cor(joined$etf_ret, joined$fac_ret), 3),
          ETF_CAGR = round((prod(1 + joined$etf_ret)^(12/nrow(joined)) - 1) * 100, 1),
          Factor_CAGR = round((prod(1 + joined$fac_ret)^(12/nrow(joined)) - 1) * 100, 1)
        )
      })

      dplyr::bind_rows(Filter(Negate(is.null), results))
    }),

    # ── ETF vs Academic: cumulative return plot ───────────────────
    targets::tar_target(fm_etf_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)
      if (is.null(fm_etf_data)) return(NULL)

      # Plot VLUE vs HML and MTUM vs Mom (most interesting pair)
      etf_m <- fm_etf_data$etf_monthly
      fac_m <- fm_etf_data$factor_monthly

      vlue <- etf_m |> filter(ticker == "VLUE") |>
        transmute(ym, strategy = "VLUE (ETF)", ret)
      hml <- fac_m |> filter(factor_name == "HML") |>
        transmute(ym, strategy = "HML (Academic)", ret = monthly_ret)
      mtum <- etf_m |> filter(ticker == "MTUM") |>
        transmute(ym, strategy = "MTUM (ETF)", ret)
      mom <- fac_m |> filter(factor_name == "Mom") |>
        transmute(ym, strategy = "Mom (Academic)", ret = monthly_ret)

      combined <- bind_rows(vlue, hml, mtum, mom) |>
        filter(ym >= "2013-05") |>
        group_by(strategy) |>
        arrange(ym) |>
        mutate(cum = cumprod(1 + ret)) |>
        ungroup()

      # Get dates for x-axis from only the plotted ETF tickers (VLUE and MTUM).
      # Using all of etf_m risks picking up a later month-end date from an
      # unrelated ticker (different holiday calendar), silently drifting every
      # series' x-position for that month. Scope to the plotted subset first,
      # then take the maximum date within that subset to resolve any remaining
      # within-subset calendar differences (slice_max keeps one row per ym).
      PLOT_TICKERS <- c("VLUE", "MTUM")
      date_lookup <- etf_m |>
        dplyr::filter(ticker %in% PLOT_TICKERS) |>
        dplyr::group_by(ym) |>
        dplyr::slice_max(date, n = 1L, with_ties = FALSE) |>
        dplyr::ungroup() |>
        dplyr::select(ym, date)
      # Regression guard (#216): each date in date_lookup must equal the max date
      # for that ym within the plotted subset — catches a foreign-calendar date
      # being selected when an unrelated ticker (QUAL, USMV, VTV, IWD) has a
      # later month-end on a different holiday calendar.
      expected_dates <- etf_m |>
        dplyr::filter(ticker %in% PLOT_TICKERS) |>
        dplyr::group_by(ym) |>
        dplyr::summarise(max_date = max(date), .groups = "drop")
      stopifnot(
        "date_lookup month set mismatch (regression #216)" =
          setequal(date_lookup$ym, expected_dates$ym),
        "date_lookup has duplicate months" =
          !anyDuplicated(date_lookup$ym)
      )
      check <- date_lookup |>
        dplyr::inner_join(expected_dates, by = "ym")
      stopifnot(
        "plan_factormax: date_lookup contains a foreign-calendar date — guard against the #216 regression" =
          all(check$date == check$max_date)
      )
      combined <- combined |> left_join(date_lookup, by = "ym")

      ggplot(combined, aes(date, cum, colour = strategy)) +
        geom_line(linewidth = 0.6) +
        scale_y_log10(labels = dollar) +
        scale_colour_manual(values = hd_palette(4)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = "Factor ETFs vs Academic Factors (2013-2026)") +
        hd_theme()
    }),

    # ── Registry sentinel (#442 Tier 1) ─────────────────────────────────────
    # Upserts bt.strategy row for "fac_max", records one bt.run + bt.metric rows
    # (full-period slice of fm_metrics). Returns tibble(strategy_id, run_uuid).
    # Guard: returns empty tibble if DBI / duckdb are unavailable.
    targets::tar_target(fm_register_runs, {
      .fm_register_runs(
        strategy_names = strategy_names,
        fm_metrics     = fm_metrics,
        fm_portfolio   = fm_portfolio
      )
    })

  )
}


# ── Internal helper ────────────────────────────────────────────────────────────
# Prefixed .fm_* (private; not exported from the package).
# Mirrors .mom_prepeak_register_runs() from plan_mom_prepeak.R.

#' Register Factor MAX backtest run in the strategy registry
#'
#' @param strategy_names Tibble from the `strategy_names` target.
#' @param fm_metrics Tibble from the `fm_metrics` target.
#' @param fm_portfolio Tibble from the `fm_portfolio` target; used to
#'   extract returns for SSR/top5pct stability metrics.
#'
#' @return Tibble with columns: strategy_id, run_uuid.
#' @noRd
.fm_register_runs <- function(strategy_names, fm_metrics, fm_portfolio) {
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
    dplyr::filter(.data$code_name == "fac_max") |>
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
    strategy_id      = "fac_max",
    partition        = "phase1",
    pipeline_version = "phase1"
  )

  # Record full-period metrics row
  # Units (#640): fm_metrics stores cagr/vol/max_dd/hit_rate/bench_* as
  # decimal fractions (see .fm_metrics calc_metrics()), sharpe/bench_sharpe
  # are scale-free ratios, and months is a period count.
  full_row <- fm_metrics[fm_metrics$period == "Full Period", , drop = FALSE]
  if (nrow(full_row) == 1L) {
    metric_cols <- setdiff(names(full_row), "period")
    fm_units <- c(
      months = "count", cagr = "fraction", vol = "fraction",
      sharpe = "ratio", max_dd = "fraction", hit_rate = "fraction",
      bench_cagr = "fraction", bench_vol = "fraction", bench_sharpe = "ratio"
    )
    historicaldata::hd_metric_record(
      con, uu, full_row[, metric_cols, drop = FALSE], units = fm_units
    )
  }

  # Record SSR + top5pct stability metrics (#400). Monthly: w=36, ann_factor=12.
  rets <- fm_portfolio$portfolio_ret
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

  tibble::tibble(strategy_id = "fac_max", run_uuid = uu)
}
