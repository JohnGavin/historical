# Plan: Turn-of-the-Month (TOM) Overlay (#271)
#
# Documented by McConnell & Xu (2008), Ogden (1990), and confirmed in
# dozens of replications across global equity markets.  The strategy holds
# SPY only during the "TOM window" — the last N_TAIL trading days of one
# month plus the first N_HEAD trading days of the next.  It sits in cash
# (earning the risk-free rate) on all other days.
#
# Look-ahead safety:
#   Signal is purely calendar-based — no price information needed.
#   The in/out indicator is determined from the CALENDAR POSITION of the
#   date, so at any date t the signal is known from the trading calendar
#   alone (t+1 execution is trivially satisfied: set the indicator using
#   date t's calendar position, realise the return on date t).
#   No future prices ever enter the signal.
#
# Naming convention: tom_*
# Falsification bridge:  fals_tom_input (same pattern as other strategies)

plan_turn_of_month <- function() {
  list(

    # ── Parameters ────────────────────────────────────────────────
    targets::tar_target(tom_params, {
      p <- bt_partitions$equity
      list(
        ticker      = "SPY",
        n_tail      = 1L,    # last N_TAIL trading days of month (default 1)
        n_head      = 3L,    # first N_HEAD trading days of next month (default 3)
        rf_annual   = 0.00,  # cash rate when not invested (0 = conservative)
        cost_bps    = 5L,    # round-trip cost in basis points per month-end switch
        start_date  = as.Date("1994-01-01"),
        oos_start   = p$test_start,
        oos_end     = p$test_end
      )
    }),

    # ── Data: SPY daily returns ───────────────────────────────────
    targets::tar_target(tom_daily, {
      library(dplyr)

      hd_ohlcv(tom_params$ticker,
               from = as.character(tom_params$start_date)) |>
        dplyr::arrange(date) |>
        dplyr::mutate(
          date = as.Date(date, tz = "UTC"),
          ret  = adjusted_close / dplyr::lag(adjusted_close) - 1  # hd_ohlcv returns adjusted_close since #325
        ) |>
        dplyr::filter(!is.na(ret)) |>
        dplyr::select(date, ret)
    }),

    # ── TOM window indicator ─────────────────────────────────────
    #
    # For each date d:
    #   1. Number the trading days within each calendar month (1, 2, 3 ...)
    #   2. Also number them FROM THE END of the month (-1 = last, -2 = second-last ...)
    #   3. in_tom = TRUE when  (rank_from_end >= -n_tail)  OR  (rank_from_start <= n_head)
    #
    # The indicator is computed purely from the sorted date sequence —
    # no price data, no look-ahead.
    targets::tar_target(tom_indicator, {
      library(dplyr)

      tom_daily |>
        dplyr::mutate(
          yr_mon = format(date, "%Y-%m")
        ) |>
        dplyr::group_by(yr_mon) |>
        dplyr::mutate(
          # 1-based rank within month: 1 = first trading day
          rank_start = dplyr::row_number(),
          # Reverse rank: 1 = last trading day
          rank_end   = dplyr::n() - dplyr::row_number() + 1L
        ) |>
        dplyr::ungroup() |>
        dplyr::mutate(
          # Tail window: last n_tail trading days of the month (rank_end <= n_tail)
          in_tail = rank_end <= tom_params$n_tail,
          # Head window: first n_head trading days of the month (rank_start <= n_head)
          in_head = rank_start <= tom_params$n_head,
          in_tom  = in_tail | in_head
        ) |>
        dplyr::select(date, ret, yr_mon, rank_start, rank_end, in_tail, in_head, in_tom)
    }),

    # ── Strategy returns ─────────────────────────────────────────
    #
    # When in_tom == TRUE  → earn the market return (SPY)
    # When in_tom == FALSE → earn 0 (cash; rf_annual = 0 default)
    # Switching costs applied once per month on both entry and exit.
    targets::tar_target(tom_portfolio, {
      library(dplyr)

      # Daily RF rate from annual assumption
      rf_daily <- (1 + tom_params$rf_annual)^(1 / 252) - 1

      d <- tom_indicator |>
        dplyr::arrange(date) |>
        dplyr::mutate(
          # Identify switch days: in_tom changes from previous day
          prev_in_tom  = dplyr::lag(in_tom, default = FALSE),
          is_switch    = in_tom != prev_in_tom,

          # Strategy gross return
          ret_gross = dplyr::if_else(in_tom, ret, rf_daily),

          # Apply one-way transaction cost on switch days
          # One switch out + one switch in per TOM window cycle
          cost_daily = dplyr::if_else(
            is_switch,
            tom_params$cost_bps / 1e4,
            0
          ),
          ret_net = ret_gross - cost_daily,

          # Cumulative equity curves
          cum_bh       = cumprod(1 + ret),
          cum_strategy = cumprod(1 + ret_net)
        )

      d
    }),

    # ── Metrics: by partition ────────────────────────────────────
    targets::tar_target(tom_metrics, {
      library(dplyr)

      calc <- function(d, label) {
        # Strategy
        ret_s <- d$ret_net
        ret_s <- ret_s[!is.na(ret_s)]
        n     <- length(ret_s)
        if (n < 20L) return(NULL)
        years     <- n / 252
        cum_s     <- prod(1 + ret_s)
        cagr_s    <- cum_s^(1 / years) - 1
        vol_s     <- sd(ret_s) * sqrt(252)
        sharpe_s  <- if (vol_s > 0) cagr_s / vol_s else NA_real_
        eq_s      <- cumprod(1 + ret_s)
        max_dd_s  <- min(eq_s / cummax(eq_s) - 1)

        # Benchmark (buy & hold)
        ret_b  <- d$ret[!is.na(d$ret)]
        cum_b  <- prod(1 + ret_b)
        cagr_b <- cum_b^(1 / years) - 1
        vol_b  <- sd(ret_b) * sqrt(252)
        sharpe_b <- if (vol_b > 0) cagr_b / vol_b else NA_real_
        eq_b   <- cumprod(1 + ret_b)
        max_dd_b <- min(eq_b / cummax(eq_b) - 1)

        # TOM statistics
        n_tom_days <- sum(d$in_tom, na.rm = TRUE)
        pct_in_tom <- n_tom_days / n

        tibble::tibble(
          period       = label,
          n_days       = n,
          years        = round(years, 1),

          # TOM strategy
          cagr_tom     = round(cagr_s * 100, 2),
          vol_tom      = round(vol_s  * 100, 2),
          sharpe_tom   = round(sharpe_s,   3),
          max_dd_tom   = round(max_dd_s * 100, 2),

          # Buy & hold
          cagr_bh      = round(cagr_b * 100, 2),
          vol_bh       = round(vol_b  * 100, 2),
          sharpe_bh    = round(sharpe_b,    3),
          max_dd_bh    = round(max_dd_b * 100, 2),

          # Exposure statistics
          n_tom_days   = n_tom_days,
          pct_in_tom   = round(pct_in_tom * 100, 1)
        )
      }

      port     <- tom_portfolio |>
        dplyr::mutate(date = as.Date(date))
      oos      <- as.Date(tom_params$oos_start)
      oos_end  <- as.Date(tom_params$oos_end)

      dplyr::bind_rows(
        calc(port |> dplyr::filter(date < oos),                       "Training"),
        calc(port |> dplyr::filter(date >= oos & date <= oos_end),    "Testing"),
        calc(port, "Full Period")
      )
    }),

    # ── Parameter sweep: vary (n_tail, n_head) ───────────────────
    targets::tar_target(tom_param_sweep, {
      library(dplyr)

      grid <- expand.grid(
        n_tail = 1L:3L,
        n_head = 1L:4L
      )

      d_base <- tom_daily |>
        dplyr::arrange(date) |>
        dplyr::mutate(yr_mon = format(date, "%Y-%m"))

      purrr::map_dfr(seq_len(nrow(grid)), function(i) {
        nt <- grid$n_tail[i]
        nh <- grid$n_head[i]

        rf_daily <- (1 + tom_params$rf_annual)^(1 / 252) - 1

        d <- d_base |>
          dplyr::group_by(yr_mon) |>
          dplyr::mutate(
            rank_start = dplyr::row_number(),
            rank_end   = dplyr::n() - dplyr::row_number() + 1L
          ) |>
          dplyr::ungroup() |>
          dplyr::mutate(
            in_tom = (rank_end <= nt) | (rank_start <= nh),
            prev_in_tom  = dplyr::lag(in_tom, default = FALSE),
            is_switch    = in_tom != prev_in_tom,
            ret_gross    = dplyr::if_else(in_tom, ret, rf_daily),
            cost_daily   = dplyr::if_else(is_switch, tom_params$cost_bps / 1e4, 0),
            ret_net      = ret_gross - cost_daily
          )

        ret_vec <- d$ret_net[!is.na(d$ret_net)]
        n       <- length(ret_vec)
        if (n < 20L) return(NULL)
        years   <- n / 252
        cum     <- prod(1 + ret_vec)
        cagr    <- cum^(1 / years) - 1
        vol     <- sd(ret_vec) * sqrt(252)
        sharpe  <- if (vol > 0) cagr / vol else NA_real_
        eq_c    <- cumprod(1 + ret_vec)
        max_dd  <- min(eq_c / cummax(eq_c) - 1)
        pct_in  <- mean(d$in_tom, na.rm = TRUE)

        tibble::tibble(
          n_tail       = nt,
          n_head       = nh,
          n_days_in    = round(pct_in * 100, 1),
          cagr         = round(cagr  * 100, 2),
          vol          = round(vol   * 100, 2),
          sharpe       = round(sharpe,      3),
          max_dd       = round(max_dd * 100, 2)
        )
      })
    }),

    # ── Equity curve plot ────────────────────────────────────────
    targets::tar_target(tom_plot, {
      library(ggplot2)
      library(dplyr)

      plot_data <- tom_portfolio |>
        dplyr::select(date,
                       `Buy & Hold`  = cum_bh,
                       `TOM Strategy` = cum_strategy) |>
        tidyr::pivot_longer(-date, names_to = "series", values_to = "growth")

      ggplot(plot_data, aes(date, growth, colour = series)) +
        geom_line(linewidth = 0.6) +
        geom_vline(xintercept = as.Date(tom_params$oos_start),
                   linetype = "dashed", colour = "grey50", linewidth = 0.4) +
        scale_y_log10(labels = scales::dollar) +
        scale_colour_manual(values = hd_palette(2)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = paste0("Turn-of-the-Month (tail=", tom_params$n_tail,
                            ", head=", tom_params$n_head, ") vs Buy & Hold")) +
        hd_theme()
    }),

    # ── Dynamic caption ──────────────────────────────────────────
    targets::tar_target(tom_caption, {
      library(dplyr)
      m_full <- tom_metrics |> dplyr::filter(period == "Full Period")
      m_test <- tom_metrics |> dplyr::filter(period == "Testing")
      n_days <- m_full$n_days
      years  <- m_full$years

      paste0(
        "**Turn-of-the-Month (TOM) overlay on ", tom_params$ticker, ".** ",
        "Hold only during the last ", tom_params$n_tail,
        " + first ", tom_params$n_head,
        " trading days of each month (",
        m_full$pct_in_tom, "% of days invested). ",
        "Cash rate = ", round(tom_params$rf_annual * 100, 1), "% p.a. ",
        "Cost: ", tom_params$cost_bps, " bps per switch. ",
        "Full period (", years, " yr, ", format(n_days, big.mark = ","),
        " days): ",
        "TOM CAGR ", m_full$cagr_tom, "%, Sharpe ", m_full$sharpe_tom,
        ", Max DD ", m_full$max_dd_tom, "% | ",
        "B&H CAGR ", m_full$cagr_bh, "%, Sharpe ", m_full$sharpe_bh,
        ", Max DD ", m_full$max_dd_bh, "%. ",
        "OOS Sharpe (TOM vs B&H): ", m_test$sharpe_tom, " vs ", m_test$sharpe_bh, ". ",
        "Dashed line = OOS start (", format(as.Date(tom_params$oos_start), "%Y"), "). ",
        "McConnell & Xu (2008), Ogden (1990)."
      )
    }),

    # ── Falsification bridge ─────────────────────────────────────
    #
    # Same pattern as fals_avoid_worst_input, fals_drif_input, etc.
    # Provides the daily strategy return series in the canonical format
    # expected by plan_falsification.R (date + strategy_ret columns).
    targets::tar_target(fals_tom_input, {
      library(dplyr)
      tom_portfolio |>
        dplyr::select(date, strategy_ret = ret_net) |>
        dplyr::mutate(date = as.Date(date, tz = "UTC"))
    }),

    # ── Registry sentinel (#442 Tier 3) ──────────────────────────────────────
    # Upserts bt.strategy row for "tom", records one bt.run + bt.metric rows
    # (Full Period row from tom_metrics). Returns tibble(strategy_id, run_uuid).
    # Guard: returns empty tibble if DBI / duckdb are unavailable.
    # Note: tom_metrics stores cagr/vol/max_dd in percentage units (× 100)
    # per the plan's internal convention; they are stored as-is in bt.metric.
    targets::tar_target(tom_register_runs, {
      .tom_register_runs(
        strategy_names = strategy_names,
        tom_metrics    = tom_metrics,
        tom_portfolio  = tom_portfolio
      )
    })

  )
}


# ── Internal helper ────────────────────────────────────────────────────────────
# Prefixed .tom_* (private; not exported from the package).
# Mirrors .drif_register_runs() from plan_drif.R.

#' Register Turn-of-the-Month backtest run in the strategy registry
#'
#' @param strategy_names Tibble from the `strategy_names` target.
#' @param tom_metrics Tibble from the `tom_metrics` target. Full-period row
#'   is used for the bt.metric insert. Note: cagr/vol/max_dd columns are in
#'   percentage units (× 100) as produced by the plan's internal convention.
#' @param tom_portfolio Tibble from the `tom_portfolio` target; used to
#'   extract daily returns for SSR/top5pct stability metrics.
#'
#' @return Tibble with columns: strategy_id, run_uuid.
#' @noRd
.tom_register_runs <- function(strategy_names, tom_metrics, tom_portfolio) {
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
    dplyr::filter(.data$code_name == "tom") |>
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
    strategy_id      = "tom",
    partition        = "phase1",
    pipeline_version = "phase1"
  )

  # Record Full Period metrics row (#640: cagr_*/vol_*/max_dd_*/pct_in_tom
  # are PERCENT — round(x*100, ...) in calc() above; sharpe_* are scale-free
  # ratios; n_days/n_tom_days are counts; years is a year-duration).
  full_row <- tom_metrics[tom_metrics$period == "Full Period", , drop = FALSE]
  if (nrow(full_row) == 1L) {
    metric_cols <- setdiff(names(full_row), "period")
    tom_units <- c(
      n_days = "count", years = "years",
      cagr_tom = "percent", vol_tom = "percent", sharpe_tom = "ratio",
      max_dd_tom = "percent",
      cagr_bh = "percent", vol_bh = "percent", sharpe_bh = "ratio",
      max_dd_bh = "percent",
      n_tom_days = "count", pct_in_tom = "percent"
    )
    historicaldata::hd_metric_record(
      con, uu, full_row[, metric_cols, drop = FALSE], units = tom_units
    )
  }

  # Record SSR + top5pct stability metrics (#400). Daily: w=252, ann_factor=252.
  rets <- tom_portfolio$ret_net
  rets <- rets[!is.na(rets)]
  if (length(rets) > 0L) {
    historicaldata::hd_record_stability_metrics(
      con        = con,
      run_uuid   = uu,
      returns    = rets,
      w          = 252L,
      ann_factor = 252L
    )
  }

  tibble::tibble(strategy_id = "tom", run_uuid = uu)
}
