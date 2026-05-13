# Plan: Mean Reversion with Risk Filters (#50)
#
# Buy large single-day drops relative to each stock's own volatility,
# expecting reversion. Filter dangerous names using skewness, semivariance
# ratio, and CVaR 5%. Max 25 simultaneous positions. Daily frequency.
#
# Source: quantitativo substack
# Critical: t+1 execution, high turnover costs

plan_mean_reversion <- function() {
  list(

    # ── Parameters ──────────────────────────────────────────────
    targets::tar_target(mr_params, {
      p <- bt_partitions$equity
      list(
        # Signal
        lookback_vol   = 21L,       # rolling vol window (trading days)
        drop_threshold = -2.0,      # buy when z-score < this (2 sigma drop)
        hold_days      = 5L,        # fixed holding period
        max_positions  = 25L,       # max simultaneous positions

        # Risk filters
        min_skew       = -1.5,      # exclude stocks with skew < this (crash-prone)
        max_semivar_ratio = 1.5,    # downside_vol / upside_vol ratio
        max_cvar_pct   = -0.08,     # exclude if 5% CVaR worse than -8%
        risk_lookback  = 63L,       # 3 months for risk stats

        # Costs
        cost_per_trade = 0.0020,    # 20bps per trade (daily turnover is expensive)

        # Partitions
        start_date = as.Date("2005-01-01"),
        is_end     = p$train_end,
        test_start = p$test_start,
        test_end   = p$test_end,
        val_start  = p$val_start,

        # Universe
        tickers = c("SPY", "QQQ", "IWM", "DIA", "XLF", "XLE", "XLV",
                     "XLK", "XLI", "XLP", "XLU", "XLB", "XLY", "XLRE",
                     "AAPL", "MSFT", "GOOGL", "AMZN", "META",
                     "JPM", "BAC", "GS", "JNJ", "PFE", "UNH",
                     "XOM", "CVX", "HD", "WMT", "PG")
      )
    }),

    # ── Data: daily returns for universe ────────────────────────
    targets::tar_target(mr_daily, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      purrr::map_dfr(mr_params$tickers, function(tkr) {
        tryCatch({
          hd_ohlcv(tkr, from = as.character(mr_params$start_date)) |>
            dplyr::arrange(date) |>
            dplyr::mutate(
              ret = adjusted / dplyr::lag(adjusted) - 1,
              ticker = tkr
            ) |>
            dplyr::filter(!is.na(ret)) |>
            dplyr::select(date, ticker, ret, adjusted, volume)
        }, error = function(e) NULL)
      }) |>
        dplyr::mutate(date = as.Date(date, tz = "UTC"))
    }),

    # ── Rolling risk stats per stock ────────────────────────────
    targets::tar_target(mr_risk_stats, {
      library(dplyr)

      lb_vol  <- mr_params$lookback_vol
      lb_risk <- mr_params$risk_lookback

      mr_daily |>
        dplyr::group_by(ticker) |>
        dplyr::arrange(date) |>
        dplyr::mutate(
          # Rolling volatility (for z-score signal)
          roll_vol = slider::slide_dbl(ret, sd, .before = lb_vol - 1L, .complete = TRUE),

          # Z-score: today's return / rolling vol
          z_score = ret / pmax(roll_vol, 1e-8),

          # Risk filters (longer lookback)
          roll_skew = slider::slide_dbl(ret, function(r) {
            if (length(r) < 20) return(NA_real_)
            n <- length(r); mu <- mean(r); s <- sd(r)
            if (s < 1e-10) return(0)
            sum((r - mu)^3) / n / s^3
          }, .before = lb_risk - 1L, .complete = TRUE),

          roll_semivar_ratio = slider::slide_dbl(ret, function(r) {
            if (length(r) < 20) return(NA_real_)
            down <- r[r < 0]; up <- r[r > 0]
            if (length(down) < 5 || length(up) < 5) return(1)
            sd(down) / pmax(sd(up), 1e-8)
          }, .before = lb_risk - 1L, .complete = TRUE),

          roll_cvar5 = slider::slide_dbl(ret, function(r) {
            if (length(r) < 20) return(NA_real_)
            q5 <- quantile(r, 0.05)
            mean(r[r <= q5])
          }, .before = lb_risk - 1L, .complete = TRUE)
        ) |>
        dplyr::ungroup()
    }),

    # ── Signal + portfolio construction ─────────────────────────
    targets::tar_target(mr_portfolio, {
      library(dplyr)

      d <- mr_risk_stats |>
        dplyr::filter(!is.na(z_score), !is.na(roll_skew))

      # All trading dates
      all_dates <- sort(unique(d$date))

      # Track open positions: list of (ticker, entry_date, entry_idx)
      positions <- list()
      daily_results <- vector("list", length(all_dates))

      for (i in seq_along(all_dates)) {
        dt <- all_dates[i]
        today <- d |> dplyr::filter(date == dt)

        # Close positions that have reached hold_days
        positions <- Filter(function(p) {
          (i - p$entry_idx) < mr_params$hold_days
        }, positions)

        # Current tickers in portfolio
        held_tickers <- vapply(positions, `[[`, "ticker", FUN.VALUE = character(1))

        # Find new signals: z_score < threshold, passes risk filters,
        # not already held, use PREVIOUS day's z_score (t+1 execution)
        if (i > 1) {
          yesterday <- all_dates[i - 1]
          signals <- d |>
            dplyr::filter(
              date == yesterday,
              z_score < mr_params$drop_threshold,
              roll_skew > mr_params$min_skew,
              roll_semivar_ratio < mr_params$max_semivar_ratio,
              roll_cvar5 > mr_params$max_cvar_pct,
              !ticker %in% held_tickers
            ) |>
            dplyr::arrange(z_score) |>
            dplyr::slice_head(n = mr_params$max_positions - length(positions))

          # Open new positions
          for (j in seq_len(nrow(signals))) {
            positions[[length(positions) + 1L]] <- list(
              ticker = signals$ticker[j],
              entry_idx = i
            )
          }
        }

        # Compute portfolio return: equal weight across open positions
        held_now <- vapply(positions, `[[`, "ticker", FUN.VALUE = character(1))
        n_held <- length(held_now)

        if (n_held > 0) {
          held_rets <- today |>
            dplyr::filter(ticker %in% held_now) |>
            dplyr::pull(ret)
          port_ret <- mean(held_rets, na.rm = TRUE)
        } else {
          port_ret <- 0
        }

        # Count trades (new entries today)
        n_new <- if (i > 1) nrow(signals) else 0L

        daily_results[[i]] <- tibble::tibble(
          date = dt,
          port_ret = port_ret,
          n_positions = n_held,
          n_new_trades = n_new
        )
      }

      result <- dplyr::bind_rows(daily_results)

      # Apply transaction costs
      result |>
        dplyr::mutate(
          trade_cost = n_new_trades * mr_params$cost_per_trade * 2 /
                        pmax(n_positions, 1),
          net_ret = port_ret - trade_cost,
          cum_gross = cumprod(1 + port_ret),
          cum_net = cumprod(1 + net_ret)
        )
    }),

    # ── Metrics ─────────────────────────────────────────────────
    targets::tar_target(mr_metrics, {
      library(dplyr)

      calc <- function(d, label) {
        ret <- d$net_ret
        ret <- ret[!is.na(ret)]
        n <- length(ret)
        if (n < 20) return(NULL)
        years <- n / 252
        cum <- prod(1 + ret)
        cagr <- (cum^(1 / years) - 1)
        vol <- sd(ret) * sqrt(252)
        sharpe <- if (vol > 0) mean(ret) * 252 / vol else NA_real_
        dd <- (cumprod(1 + ret) - cummax(cumprod(1 + ret))) / cummax(cumprod(1 + ret))
        max_dd <- min(dd)
        avg_trades <- mean(d$n_new_trades)
        avg_pos <- mean(d$n_positions)

        tibble::tibble(
          period = label, days = n, years = round(years, 1),
          cagr = round(cagr * 100, 1), vol = round(vol * 100, 1),
          sharpe = round(sharpe, 2), max_dd = round(max_dd * 100, 1),
          avg_positions = round(avg_pos, 1),
          avg_daily_trades = round(avg_trades, 2)
        )
      }

      port <- mr_portfolio |>
        dplyr::mutate(date = as.Date(date))
      oos <- as.Date(mr_params$test_start)

      dplyr::bind_rows(
        calc(port |> filter(date < oos), "Training"),
        calc(port |> filter(date >= oos), "Testing"),
        calc(port, "Full Period")
      )
    }),

    # ── Equity curve plot ───────────────────────────────────────
    targets::tar_target(mr_plot, {
      library(ggplot2)
      library(dplyr)
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      # SPY benchmark
      spy <- hd_ohlcv("SPY", from = as.character(mr_params$start_date)) |>
        arrange(date) |>
        mutate(ret = adjusted / lag(adjusted) - 1) |>
        filter(!is.na(ret)) |>
        mutate(cum_spy = cumprod(1 + ret)) |>
        select(date, cum_spy)

      plot_data <- mr_portfolio |>
        left_join(spy, by = "date") |>
        tidyr::pivot_longer(
          cols = c(cum_net, cum_spy),
          names_to = "series",
          values_to = "growth"
        ) |>
        mutate(series = ifelse(series == "cum_net",
                                "Mean Reversion (net)", "SPY Buy & Hold"))

      ggplot(plot_data, aes(date, growth, colour = series)) +
        geom_line(linewidth = 0.6) +
        geom_vline(xintercept = mr_params$test_start, linetype = "dashed",
                   colour = "grey50") +
        scale_y_log10(labels = scales::dollar) +
        scale_colour_manual(values = c("Mean Reversion (net)" = "#2ecc71",
                                        "SPY Buy & Hold" = "#4a90d9")) +
        labs(x = NULL, y = "Growth of $1 (log)", colour = NULL,
             title = "Mean Reversion vs SPY") +
        theme_minimal(base_size = 14) +
        theme(
          plot.background = element_rect(fill = "black", color = NA),
          panel.background = element_rect(fill = "black", color = NA),
          text = element_text(color = "#e0e0e0"),
          axis.text = element_text(color = "#e0e0e0"),
          legend.position = "top",
          legend.background = element_rect(fill = "black"),
          panel.grid.major = element_line(color = "#333"),
          panel.grid.minor = element_blank()
        )
    }),

    # ── Caption (dynamic) ───────────────────────────────────────
    targets::tar_target(mr_caption, {
      m <- mr_metrics |> dplyr::filter(period == "Full Period")
      paste0(
        "Mean reversion strategy: buy stocks with z-score < ",
        mr_params$drop_threshold, " (", mr_params$lookback_vol,
        "-day rolling vol). Hold ", mr_params$hold_days,
        " days, max ", mr_params$max_positions, " positions. ",
        "Risk filters: skew > ", mr_params$min_skew,
        ", semivar ratio < ", mr_params$max_semivar_ratio,
        ", CVaR 5% > ", mr_params$max_cvar_pct * 100, "%. ",
        "Net CAGR: ", m$cagr, "%, Vol: ", m$vol,
        "%, Sharpe: ", m$sharpe, ", Max DD: ", m$max_dd, "%. ",
        "Cost: ", mr_params$cost_per_trade * 100, "bps/trade. ",
        "Universe: ", length(mr_params$tickers), " tickers (ETFs + large caps). ",
        "Dashed line = OOS start."
      )
    })

  )
}
