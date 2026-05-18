# Plan: Beat the Market by Avoiding Its Worst Days
#
# Demonstrates return asymmetry: removing the N worst days improves
# cumulative returns more than removing the N best days hurts them.
# NOT a tradeable strategy — worst and best days cluster together.
#
# Source: Morningstar, "You Can Beat the Stock Market by Avoiding
# Its Worst Days. You Won't."

plan_avoid_worst <- function() {
  list(
    # ── Parameters ──────────────────────────────────────────────
    targets::tar_target(aw_params, {
      list(
        n_remove = c(1L, 5L, 10L, 20L, 50L),
        primary_ticker = "SPY",
        index_tickers = c("SPY", "QQQ", "IWM", "DIA"),
        oos_start = as.Date("2020-01-01")
      )
    }),

    # ── Daily returns: index ETFs ───────────────────────────────
    targets::tar_target(aw_daily_returns, {
      library(dplyr)

      purrr::map_dfr(aw_params$index_tickers, function(tkr) {
        d <- hd_ohlcv(tkr) |>
          arrange(date) |>
          mutate(
            ret = adjusted / lag(adjusted) - 1,
            ticker = tkr
          ) |>
          filter(!is.na(ret)) |>
          select(date, ticker, ret)
        d
      }) |>
        dplyr::mutate(date = as.Date(date, tz = "UTC"))
    }),

    # ── Daily returns: Fama-French Mkt-RF (1926+) ──────────────
    targets::tar_target(aw_daily_ff, {
      library(dplyr)

      ff <- hd_factors() |>
        filter(factor_name == "Mkt-RF", frequency == "daily") |>
        mutate(ret = value / 100) |>
        select(date, ret) |>
        arrange(date)

      # Also get RF for Sharpe calculations
      rf <- hd_factors() |>
        filter(factor_name == "RF", frequency == "daily") |>
        mutate(rf = value / 100) |>
        select(date, rf)

      ff |> left_join(rf, by = "date") |> mutate(ticker = "Mkt-RF")
    }),

    # ── Core: remove N worst/best days ──────────────────────────
    targets::tar_target(aw_remove_days, {
      library(dplyr)

      compute_scenarios <- function(returns_df, ticker_name, n_values) {
        ret <- returns_df$ret
        dates <- returns_df$date
        n_total <- length(ret)

        purrr::map_dfr(n_values, function(n) {
          if (n >= n_total) return(NULL)

          # Indices of worst and best days
          ord <- order(ret)
          worst_idx <- ord[seq_len(n)]
          best_idx <- ord[seq(n_total - n + 1, n_total)]

          cum_all <- prod(1 + ret)
          cum_no_worst <- prod(1 + ret[-worst_idx])
          cum_no_best <- prod(1 + ret[-best_idx])
          cum_no_both <- prod(1 + ret[-c(worst_idx, best_idx)])

          years <- n_total / 252

          cagr <- function(cum, yrs) (cum^(1 / yrs) - 1) * 100
          vol <- function(r) sd(r, na.rm = TRUE) * sqrt(252) * 100
          max_dd <- function(r) {
            cum <- cumprod(1 + r)
            peak <- cummax(cum)
            min((cum - peak) / peak) * 100
          }

          tibble::tibble(
            ticker = ticker_name,
            n_removed = n,
            n_total_days = n_total,
            pct_removed = round(n / n_total * 100, 2),
            scenario = c("All Days", "Remove Worst", "Remove Best", "Remove Both"),
            cumulative = c(cum_all, cum_no_worst, cum_no_best, cum_no_both),
            cagr = c(cagr(cum_all, years), cagr(cum_no_worst, years),
                     cagr(cum_no_best, years), cagr(cum_no_both, years)),
            vol = c(vol(ret), vol(ret[-worst_idx]),
                    vol(ret[-best_idx]), vol(ret[-c(worst_idx, best_idx)])),
            max_dd = c(max_dd(ret), max_dd(ret[-worst_idx]),
                       max_dd(ret[-best_idx]), max_dd(ret[-c(worst_idx, best_idx)]))
          )
        })
      }

      # SPY
      spy <- aw_daily_returns |> filter(ticker == "SPY")
      spy_results <- compute_scenarios(spy, "SPY", aw_params$n_remove)

      # Mkt-RF (long history)
      ff_results <- compute_scenarios(aw_daily_ff, "Mkt-RF", aw_params$n_remove)

      bind_rows(spy_results, ff_results)
    }),

    # ── Asymmetry table ─────────────────────────────────────────
    targets::tar_target(aw_asymmetry_table, {
      library(dplyr)

      aw_remove_days |>
        select(ticker, n_removed, scenario, cumulative, cagr) |>
        tidyr::pivot_wider(
          names_from = scenario,
          values_from = c(cumulative, cagr)
        ) |>
        mutate(
          gain_from_avoiding_worst = `cumulative_Remove Worst` - `cumulative_All Days`,
          loss_from_missing_best = `cumulative_All Days` - `cumulative_Remove Best`,
          asymmetry_ratio = round(
            gain_from_avoiding_worst / pmax(loss_from_missing_best, 0.01), 2
          )
        ) |>
        select(
          ticker, n_removed,
          cagr_all = `cagr_All Days`,
          cagr_no_worst = `cagr_Remove Worst`,
          cagr_no_best = `cagr_Remove Best`,
          asymmetry_ratio
        ) |>
        mutate(across(starts_with("cagr"), ~ round(., 1)))
    }),

    # ── Equity curve plot (SPY) ─────────────────────────────────
    targets::tar_target(aw_cumret_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)

      spy <- aw_daily_returns |> filter(ticker == "SPY") |> arrange(date)
      ret <- spy$ret
      dates <- spy$date
      n_total <- length(ret)

      # Build equity curves for remove-10-worst and remove-10-best
      n <- 10L
      ord <- order(ret)
      worst_idx <- ord[seq_len(n)]
      best_idx <- ord[seq(n_total - n + 1, n_total)]

      plot_data <- tibble::tibble(
        date = rep(dates, 3),
        growth = c(
          cumprod(1 + ret),
          cumprod(1 + ifelse(seq_along(ret) %in% worst_idx, 0, ret)),
          cumprod(1 + ifelse(seq_along(ret) %in% best_idx, 0, ret))
        ),
        scenario = rep(c("All Days", "Remove 10 Worst", "Remove 10 Best"),
                       each = n_total)
      )

      ggplot(plot_data, aes(date, growth, colour = scenario)) +
        geom_line(linewidth = 0.6) +
        geom_vline(xintercept = aw_params$oos_start, linetype = "dashed",
                   colour = "grey50", linewidth = 0.4) +
        scale_y_log10(labels = dollar) +
        scale_colour_manual(values = hd_palette(3)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = "SPY: Effect of Removing 10 Best vs 10 Worst Days") +
        hd_theme()
    }),

    # ── Equity curve caption (dynamic) ──────────────────────────
    targets::tar_target(aw_cumret_caption, {
      library(dplyr)
      spy <- aw_daily_returns |> filter(ticker == "SPY")
      n_total <- nrow(spy)
      years <- round(n_total / 252)
      date_range <- paste0(format(min(spy$date), "%Y"), "\u2013",
                           format(max(spy$date), "%Y"))
      ret <- spy$ret
      ord <- order(ret)
      worst_10 <- ord[seq_len(10)]
      best_10 <- ord[seq(n_total - 9, n_total)]
      cum_all <- prod(1 + ret)
      cum_no_worst <- prod(1 + ifelse(seq_along(ret) %in% worst_10, 0, ret))
      cum_no_best <- prod(1 + ifelse(seq_along(ret) %in% best_10, 0, ret))

      fmt <- function(x) {
        if (x >= 10) paste0("$", round(x, 0))
        else paste0("$", round(x, 2))
      }

      paste0(
        "**SPY equity curves: all days vs removing 10 worst/best days.** ",
        "Growth of $1, log scale, ~", years, " years (", date_range, ", ",
        format(n_total, big.mark = ","), " trading days). ",
        "All days: ", fmt(cum_all), ". ",
        "Remove 10 worst: ", fmt(cum_no_worst), " (",
        round((cum_no_worst / cum_all - 1) * 100), "% improvement). ",
        "Remove 10 best: ", fmt(cum_no_best), " (",
        round((1 - cum_no_best / cum_all) * 100), "% loss). ",
        "Removing 10 days = ", round(10 / n_total * 100, 2), "% of all days. ",
        "Dashed line = OOS start (", format(aw_params$oos_start, "%Y"), ")."
      )
    }),

    # ── Temporal clustering: worst & best days ──────────────────
    targets::tar_target(aw_clustering, {
      library(dplyr)

      spy <- aw_daily_returns |> filter(ticker == "SPY") |> arrange(date)
      ret <- spy$ret
      dates <- spy$date
      n_total <- length(ret)

      # 10 worst and 10 best
      ord <- order(ret)
      worst_dates <- dates[ord[1:10]]
      best_dates <- dates[ord[(n_total - 9):n_total]]
      worst_rets <- ret[ord[1:10]]
      best_rets <- ret[ord[(n_total - 9):n_total]]

      # Distance from each worst day to nearest best day
      worst_info <- tibble::tibble(
        date = worst_dates,
        ret_pct = round(worst_rets * 100, 2),
        type = "Worst"
      ) |> rowwise() |>
        mutate(
          nearest_best = best_dates[which.min(abs(as.numeric(date - best_dates)))],
          days_to_nearest_best = as.integer(abs(date - nearest_best))
        ) |> ungroup()

      best_info <- tibble::tibble(
        date = best_dates,
        ret_pct = round(best_rets * 100, 2),
        type = "Best"
      ) |> rowwise() |>
        mutate(
          nearest_worst = worst_dates[which.min(abs(as.numeric(date - worst_dates)))],
          days_to_nearest_worst = as.integer(abs(date - nearest_worst))
        ) |> ungroup()

      list(worst = worst_info, best = best_info)
    }),

    # ── Clustering timeline plot ────────────────────────────────
    targets::tar_target(aw_clustering_plot, {
      library(ggplot2)
      library(dplyr)

      worst <- aw_clustering$worst |> mutate(type = "10 Worst Days")
      best <- aw_clustering$best |> mutate(type = "10 Best Days")
      events <- bind_rows(worst, best)

      ggplot(events, aes(x = date, y = ret_pct, colour = type)) +
        geom_segment(aes(xend = date, yend = 0), linewidth = 1.2) +
        geom_point(size = 2) +
        scale_colour_manual(values = c("10 Best Days" = "#2ecc71",
                                        "10 Worst Days" = "#e74c3c")) +
        labs(x = NULL, y = "Daily Return (%)", colour = NULL,
             title = "SPY: 10 Worst and 10 Best Days (Temporal Clustering)") +
        hd_theme()
    }),

    # ── Clustering caption (dynamic) ────────────────────────────
    targets::tar_target(aw_clustering_caption, {
      worst <- aw_clustering$worst
      median_dist <- median(worst$days_to_nearest_best)
      within_20 <- sum(worst$days_to_nearest_best <= 20)
      paste0(
        "**Temporal clustering of SPY's 10 worst and 10 best days.** ",
        "Worst and best days cluster together in crisis periods. ",
        "Median distance from a worst day to the nearest best day: ",
        median_dist, " calendar days. ",
        within_20, " of 10 worst days occur within 20 calendar days of a best day. ",
        "This makes selective avoidance impractical: ",
        "missing the worst days almost certainly means missing the best days too."
      )
    }),

    # ── Multi-index comparison ──────────────────────────────────
    targets::tar_target(aw_multi_index, {
      library(dplyr)

      purrr::map_dfr(aw_params$index_tickers, function(tkr) {
        d <- aw_daily_returns |> filter(ticker == tkr) |> arrange(date)
        ret <- d$ret
        n_total <- length(ret)
        if (n_total < 100) return(NULL)

        ord <- order(ret)
        years <- n_total / 252

        purrr::map_dfr(c(10L, 20L), function(n) {
          worst_idx <- ord[seq_len(n)]
          best_idx <- ord[seq(n_total - n + 1, n_total)]

          cum_all <- prod(1 + ret)
          cum_no_worst <- prod(1 + ret[-worst_idx])
          cum_no_best <- prod(1 + ret[-best_idx])

          cagr <- function(x) round((x^(1 / years) - 1) * 100, 1)

          tibble::tibble(
            ticker = tkr,
            n_removed = n,
            n_days = n_total,
            years = round(years, 1),
            cagr_all = cagr(cum_all),
            cagr_no_worst = cagr(cum_no_worst),
            cagr_no_best = cagr(cum_no_best),
            asymmetry = round((cum_no_worst - cum_all) /
                                pmax(cum_all - cum_no_best, 0.01), 2)
          )
        })
      })
    }),

    # ── Rolling analysis: 1-year windows ────────────────────────
    targets::tar_target(aw_rolling, {
      library(dplyr)

      spy <- aw_daily_returns |> filter(ticker == "SPY") |> arrange(date)
      ret <- spy$ret
      dates <- spy$date
      window <- 252L  # 1 year of trading days

      if (length(ret) < window + 10) return(NULL)

      purrr::map_dfr(seq(window, length(ret)), function(i) {
        w_ret <- ret[(i - window + 1):i]
        w_dates <- dates[(i - window + 1):i]
        n <- 10L
        ord <- order(w_ret)
        worst_idx <- ord[seq_len(n)]
        best_idx <- ord[seq(window - n + 1, window)]

        cum_all <- prod(1 + w_ret) - 1
        cum_no_worst <- prod(1 + w_ret[-worst_idx]) - 1
        cum_no_best <- prod(1 + w_ret[-best_idx]) - 1

        # Net benefit = gain from avoiding worst - loss from also missing best
        gain_avoid_worst <- cum_no_worst - cum_all
        loss_miss_best <- cum_all - cum_no_best
        net <- gain_avoid_worst - loss_miss_best

        tibble::tibble(
          date = dates[i],
          ret_all = round(cum_all * 100, 1),
          ret_no_worst = round(cum_no_worst * 100, 1),
          ret_no_best = round(cum_no_best * 100, 1),
          gain_avoid_worst = round(gain_avoid_worst * 100, 1),
          loss_miss_best = round(loss_miss_best * 100, 1),
          net_benefit = round(net * 100, 1)
        )
      })
    }),

    # ── Rolling plot ────────────────────────────────────────────
    targets::tar_target(aw_rolling_plot, {
      library(ggplot2)
      library(dplyr)

      plot_data <- aw_rolling |>
        select(date, `All Days` = ret_all,
               `Remove 10 Worst` = ret_no_worst,
               `Remove 10 Best` = ret_no_best) |>
        tidyr::pivot_longer(-date, names_to = "scenario", values_to = "return_pct")

      ggplot(plot_data, aes(date, return_pct, colour = scenario)) +
        geom_line(linewidth = 0.4, alpha = 0.8) +
        geom_hline(yintercept = 0, linetype = "dotted", colour = "grey50") +
        scale_colour_manual(values = hd_palette(3)) +
        labs(x = NULL, y = "Rolling 1-Year Return (%)", colour = NULL,
             title = "SPY: Rolling 1-Year Returns by Scenario") +
        hd_theme()
    }),

    # ── Net benefit plot ────────────────────────────────────────
    targets::tar_target(aw_net_benefit_plot, {
      library(ggplot2)
      library(dplyr)

      plot_data <- aw_rolling |>
        select(date,
               `Gain (avoid worst)` = gain_avoid_worst,
               `Loss (miss best)` = loss_miss_best,
               `Net benefit` = net_benefit) |>
        tidyr::pivot_longer(-date, names_to = "component", values_to = "pp")

      ggplot(plot_data, aes(date, pp, colour = component)) +
        geom_line(linewidth = 0.5, alpha = 0.8) +
        geom_hline(yintercept = 0, linetype = "dotted", colour = "grey50") +
        scale_colour_manual(values = c(
          "Gain (avoid worst)" = "#2ecc71",
          "Loss (miss best)" = "#e74c3c",
          "Net benefit" = hd_palette(1)
        )) +
        labs(x = NULL,
             y = "Rolling 1-Year Effect (pp)",
             colour = NULL,
             title = "Net Benefit = Gain from Avoiding Worst - Loss from Missing Best") +
        hd_theme()
    }),

    # ── Summary metrics by partition ────────────────────────────
    targets::tar_target(aw_metrics, {
      library(dplyr)

      spy <- aw_daily_returns |> filter(ticker == "SPY") |> arrange(date)

      calc <- function(d, label) {
        ret <- d$ret
        n <- length(ret)
        if (n < 20) return(NULL)
        ord <- order(ret)
        years <- n / 252
        worst_10 <- ord[seq_len(min(10, n - 1))]
        best_10 <- ord[seq(max(1, n - 9), n)]

        metrics_for <- function(r, scenario) {
          tibble::tibble(
            period = label,
            scenario = scenario,
            years = round(years, 1),
            n_days = length(r),
            cagr = round((prod(1 + r)^(1 / years) - 1) * 100, 1),
            vol = round(sd(r) * sqrt(252) * 100, 1),
            max_dd = round(min((cumprod(1 + r) -
                                  cummax(cumprod(1 + r))) /
                                 cummax(cumprod(1 + r))) * 100, 1),
            sharpe = round(mean(r) / sd(r) * sqrt(252), 2)
          )
        }

        bind_rows(
          metrics_for(ret, "All Days"),
          metrics_for(ret[-worst_10], "Remove 10 Worst"),
          metrics_for(ret[-best_10], "Remove 10 Best")
        )
      }

      oos <- as.Date(aw_params$oos_start)
      bind_rows(
        calc(spy |> filter(as.Date(date) < oos), "Training"),
        calc(spy |> filter(as.Date(date) >= oos), "Testing"),
        calc(spy, "Full Period")
      )
    }),

    # ── Practical: VIX-triggered protection ─────────────────────
    # After a large move or when VIX is elevated, go to cash
    # for a cooling-off period until vol subsides
    targets::tar_target(aw_vix_daily, {
      library(dplyr)

      # Coerce both sides to Date BEFORE joining: hd_macro() may return POSIXct,
      # and a Date vs POSIXct left_join silently produces zero matches.
      spy <- aw_daily_returns |>
        filter(ticker == "SPY") |>
        dplyr::mutate(date = as.Date(date)) |>
        arrange(date)
      vix <- hd_macro("VIXCLS") |>
        select(date, vix = value) |>
        dplyr::mutate(date = as.Date(date)) |>
        arrange(date)

      spy |>
        left_join(vix, by = "date")
    }),

    targets::tar_target(aw_practical_params, {
      list(
        # Shock trigger: absolute daily return > this
        shock_threshold = 0.03,  # 3% daily move
        # VIX trigger: go to cash when VIX > this
        vix_high = 30,
        # VIX re-entry: return to market when VIX < this
        vix_reentry = 25,
        # Cooling-off: min days in cash after shock (even if VIX drops)
        min_cooloff_days = 5L,
        # Variants to test
        vix_thresholds = c(25, 30, 35, 40),
        shock_thresholds = c(0.02, 0.03, 0.04, 0.05)
      )
    }),

    targets::tar_target(aw_practical_backtest, {
      library(dplyr)

      d <- aw_vix_daily |> filter(!is.na(vix), !is.na(ret))

      run_strategy <- function(d, shock_thresh, vix_high, vix_reentry,
                               min_cooloff) {
        n <- nrow(d)
        in_market <- rep(TRUE, n)
        cooloff_remaining <- 0L

        for (i in 2:n) {
          # Decrement cooloff
          if (cooloff_remaining > 0) cooloff_remaining <- cooloff_remaining - 1L

          # Check triggers — ALL signals use PREVIOUS day (t+1 execution)
          # You cannot act on today's VIX; you see it at close and trade next day
          shocked <- abs(d$ret[i - 1]) > shock_thresh
          vix_prev <- d$vix[i - 1]
          vix_elevated <- !is.na(vix_prev) && vix_prev > vix_high

          if (shocked || vix_elevated) {
            in_market[i] <- FALSE
            cooloff_remaining <- max(cooloff_remaining, min_cooloff)
          } else if (cooloff_remaining > 0) {
            in_market[i] <- FALSE
          } else if (!is.na(vix_prev) && vix_prev > vix_reentry) {
            # Still elevated yesterday, stay out
            in_market[i] <- FALSE
          } else {
            in_market[i] <- TRUE
          }
        }

        strat_ret <- ifelse(in_market, d$ret, 0)
        tibble::tibble(
          date = d$date,
          ret_market = d$ret,
          ret_strategy = strat_ret,
          in_market = in_market,
          vix = d$vix,
          cum_market = cumprod(1 + d$ret),
          cum_strategy = cumprod(1 + strat_ret)
        )
      }

      # Run default parameters
      result <- run_strategy(d,
        shock_thresh = aw_practical_params$shock_threshold,
        vix_high = aw_practical_params$vix_high,
        vix_reentry = aw_practical_params$vix_reentry,
        min_cooloff = aw_practical_params$min_cooloff_days
      )

      result
    }),

    # ── Practical: equity curve plot ────────────────────────────
    targets::tar_target(aw_practical_plot, {
      library(ggplot2)
      library(dplyr)

      plot_data <- aw_practical_backtest |>
        select(date,
               `Buy & Hold` = cum_market,
               `VIX Protection` = cum_strategy) |>
        tidyr::pivot_longer(-date, names_to = "strategy", values_to = "growth")

      # Shade cash periods
      cash_periods <- aw_practical_backtest |>
        filter(!in_market) |>
        select(date)

      p <- ggplot(plot_data, aes(date, growth, colour = strategy)) +
        geom_line(linewidth = 0.6) +
        scale_y_log10(labels = scales::dollar) +
        scale_colour_manual(values = hd_palette(2)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = "VIX-Triggered Protection vs Buy & Hold") +
        hd_theme()

      p
    }),

    # ── Practical: dynamic caption ──────────────────────────────
    targets::tar_target(aw_practical_caption, {
      library(dplyr)
      d <- aw_practical_backtest
      n_total <- nrow(d)
      n_cash <- sum(!d$in_market)
      pct_cash <- round(n_cash / n_total * 100, 1)
      years <- n_total / 252

      cum_mkt <- tail(d$cum_market, 1)
      cum_strat <- tail(d$cum_strategy, 1)
      cagr_mkt <- round((cum_mkt^(1 / years) - 1) * 100, 1)
      cagr_strat <- round((cum_strat^(1 / years) - 1) * 100, 1)

      vol_mkt <- round(sd(d$ret_market) * sqrt(252) * 100, 1)
      vol_strat <- round(sd(d$ret_strategy) * sqrt(252) * 100, 1)

      dd <- function(r) {
        cum <- cumprod(1 + r)
        round(min((cum - cummax(cum)) / cummax(cum)) * 100, 1)
      }

      paste0(
        "**VIX-triggered protection vs buy & hold (SPY).** ",
        "Rule: go to cash when VIX > ", aw_practical_params$vix_high,
        " or after a >", aw_practical_params$shock_threshold * 100,
        "% daily move; re-enter when VIX < ", aw_practical_params$vix_reentry,
        " (min ", aw_practical_params$min_cooloff_days, "-day cooloff). ",
        "Out of market ", pct_cash, "% of days (", n_cash, "/", n_total, "). ",
        "Buy & hold: CAGR ", cagr_mkt, "%, vol ", vol_mkt,
        "%, max DD ", dd(d$ret_market), "%. ",
        "VIX protection: CAGR ", cagr_strat, "%, vol ", vol_strat,
        "%, max DD ", dd(d$ret_strategy), "%. ",
        format(min(d$date), "%Y"), "\u2013", format(max(d$date), "%Y"), "."
      )
    }),

    # ── Practical: parameter sensitivity ────────────────────────
    targets::tar_target(aw_practical_sensitivity, {
      library(dplyr)

      d <- aw_vix_daily |> filter(!is.na(vix), !is.na(ret))

      run_variant <- function(d, shock_thresh, vix_high, vix_reentry, min_cooloff) {
        n <- nrow(d)
        in_market <- rep(TRUE, n)
        cooloff_remaining <- 0L
        for (i in 2:n) {
          if (cooloff_remaining > 0) cooloff_remaining <- cooloff_remaining - 1L
          shocked <- abs(d$ret[i - 1]) > shock_thresh
          vp <- d$vix[i - 1]  # previous day VIX (t+1 execution)
          vix_elevated <- !is.na(vp) && vp > vix_high
          if (shocked || vix_elevated) {
            in_market[i] <- FALSE
            cooloff_remaining <- max(cooloff_remaining, min_cooloff)
          } else if (cooloff_remaining > 0) {
            in_market[i] <- FALSE
          } else if (!is.na(vp) && vp > vix_reentry) {
            in_market[i] <- FALSE
          } else {
            in_market[i] <- TRUE
          }
        }
        strat_ret <- ifelse(in_market, d$ret, 0)
        years <- n / 252
        cum <- prod(1 + strat_ret)
        cum_dd <- cumprod(1 + strat_ret)
        list(
          cagr = round((cum^(1 / years) - 1) * 100, 1),
          vol = round(sd(strat_ret) * sqrt(252) * 100, 1),
          max_dd = round(min((cum_dd - cummax(cum_dd)) / cummax(cum_dd)) * 100, 1),
          sharpe = round(mean(strat_ret) / sd(strat_ret) * sqrt(252), 2),
          pct_cash = round(sum(!in_market) / n * 100, 1)
        )
      }

      # Vary VIX threshold
      vix_results <- purrr::map_dfr(aw_practical_params$vix_thresholds, function(vh) {
        r <- run_variant(d, 0.03, vh, vh - 5, 5L)
        tibble::as_tibble(c(list(variant = paste0("VIX>", vh)), r))
      })

      # Vary shock threshold
      shock_results <- purrr::map_dfr(aw_practical_params$shock_thresholds, function(st) {
        r <- run_variant(d, st, 30, 25, 5L)
        tibble::as_tibble(c(list(variant = paste0("Shock>", st * 100, "%")), r))
      })

      # Buy & hold baseline
      bh <- run_variant(d, 999, 999, 999, 0L)  # never triggers
      baseline <- tibble::as_tibble(c(list(variant = "Buy & Hold"), bh))

      bind_rows(baseline, vix_results, shock_results)
    }),

    # ── Walk-forward: yearly expanding-window optimisation (#46) ─
    targets::tar_target(aw_walkforward, {
      library(dplyr)

      d <- aw_vix_daily |> filter(!is.na(vix), !is.na(ret))

      # Helper: run strategy and return annual metrics
      run_strat <- function(data, shock_t, vix_h, vix_r, cooloff) {
        n <- nrow(data)
        if (n < 20) return(list(cagr = NA_real_, sharpe = NA_real_, max_dd = NA_real_))
        in_mkt <- rep(TRUE, n)
        cool <- 0L
        for (i in 2:n) {
          if (cool > 0) cool <- cool - 1L
          vp <- data$vix[i - 1]  # previous day VIX (t+1 execution)
          if (abs(data$ret[i - 1]) > shock_t ||
              (!is.na(vp) && vp > vix_h)) {
            in_mkt[i] <- FALSE
            cool <- max(cool, cooloff)
          } else if (cool > 0 || (!is.na(vp) && vp > vix_r)) {
            in_mkt[i] <- FALSE
          }
        }
        sr <- ifelse(in_mkt, data$ret, 0)
        yrs <- n / 252
        cum <- prod(1 + sr)
        cum_dd <- cumprod(1 + sr)
        list(
          cagr = (cum^(1 / yrs) - 1) * 100,
          sharpe = mean(sr) / sd(sr) * sqrt(252),
          max_dd = min((cum_dd - cummax(cum_dd)) / cummax(cum_dd)) * 100,
          n_switches = sum(diff(as.integer(in_mkt)) != 0),
          pct_cash = sum(!in_mkt) / n * 100
        )
      }

      # Walk-forward: for each year, optimise on all prior data
      years <- seq(2000L, as.integer(format(max(d$date), "%Y")) - 1L)
      vix_grid <- seq(20, 45, by = 5)

      wf_results <- purrr::map_dfr(years, function(yr) {
        train <- d |> filter(as.Date(date) < as.Date(paste0(yr, "-01-01")))
        test <- d |> filter(as.Date(date) >= as.Date(paste0(yr, "-01-01")),
                            as.Date(date) < as.Date(paste0(yr + 1, "-01-01")))
        if (nrow(train) < 252 || nrow(test) < 20) return(NULL)

        # Find best VIX threshold on training data (maximise Sharpe)
        train_results <- purrr::map_dfr(vix_grid, function(vh) {
          r <- run_strat(train, 0.03, vh, vh - 5, 5L)
          tibble::tibble(vix_high = vh, sharpe = r$sharpe)
        })
        best_vix <- train_results$vix_high[which.max(train_results$sharpe)]

        # Apply to test year
        test_r <- run_strat(test, 0.03, best_vix, best_vix - 5, 5L)

        # Also compute buy-and-hold for test year
        bh_cum <- prod(1 + test$ret)
        bh_cagr <- (bh_cum^(252 / nrow(test)) - 1) * 100

        tibble::tibble(
          year = yr,
          chosen_vix = best_vix,
          oos_cagr = round(test_r$cagr * 252 / nrow(test), 1),  # annualised
          oos_sharpe = round(test_r$sharpe, 2),
          oos_max_dd = round(test_r$max_dd, 1),
          bh_cagr = round(bh_cagr, 1),
          n_switches = test_r$n_switches,
          pct_cash = round(test_r$pct_cash, 1)
        )
      })

      wf_results
    }),

    # ── Walk-forward equity curve ───────────────────────────────
    targets::tar_target(aw_walkforward_curve, {
      library(dplyr)
      library(ggplot2)

      d <- aw_vix_daily |> filter(!is.na(vix), !is.na(ret))
      wf <- aw_walkforward

      # Build walk-forward equity curve by applying each year's chosen threshold
      years <- wf$year
      curves <- purrr::map_dfr(seq_along(years), function(idx) {
        yr <- years[idx]
        vh <- wf$chosen_vix[idx]
        chunk <- d |> filter(as.Date(date) >= as.Date(paste0(yr, "-01-01")),
                             as.Date(date) < as.Date(paste0(yr + 1, "-01-01")))
        if (nrow(chunk) < 2) return(NULL)

        n <- nrow(chunk)
        in_mkt <- rep(TRUE, n)
        cool <- 0L
        for (i in 2:n) {
          if (cool > 0) cool <- cool - 1L
          vp <- chunk$vix[i - 1]  # previous day VIX (t+1 execution)
          if (abs(chunk$ret[i - 1]) > 0.03 ||
              (!is.na(vp) && vp > vh)) {
            in_mkt[i] <- FALSE
            cool <- max(cool, 5L)
          } else if (cool > 0 || (!is.na(vp) && vp > (vh - 5))) {
            in_mkt[i] <- FALSE
          }
        }
        tibble::tibble(date = chunk$date,
                       ret_wf = ifelse(in_mkt, chunk$ret, 0),
                       ret_bh = chunk$ret)
      })

      if (nrow(curves) == 0) return(NULL)
      curves <- curves |>
        arrange(date) |>
        mutate(
          cum_wf = cumprod(1 + ret_wf),
          cum_bh = cumprod(1 + ret_bh),
          cum_hindsight = aw_practical_backtest |>
            filter(date %in% curves$date) |>
            arrange(date) |>
            pull(cum_strategy)
        )

      plot_data <- curves |>
        select(date,
               `Buy & Hold` = cum_bh,
               `Walk-Forward` = cum_wf,
               `Hindsight (VIX>30)` = cum_hindsight) |>
        tidyr::pivot_longer(-date, names_to = "strategy", values_to = "growth")

      ggplot(plot_data, aes(date, growth, colour = strategy)) +
        geom_line(linewidth = 0.6) +
        scale_y_log10(labels = scales::dollar) +
        scale_colour_manual(values = hd_palette(3)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = "Walk-Forward vs Hindsight vs Buy & Hold") +
        hd_theme()
    }),

    # ── Transaction costs (#45) ─────────────────────────────────
    targets::tar_target(aw_transaction_costs, {
      library(dplyr)

      d <- aw_practical_backtest
      switches <- sum(diff(as.integer(d$in_market)) != 0)
      cost_per_switch <- 0.0005  # 5bps per switch (spread + slippage)
      total_cost <- switches * cost_per_switch
      years <- nrow(d) / 252

      # Gross metrics
      cum_gross <- tail(d$cum_strategy, 1)
      cagr_gross <- (cum_gross^(1 / years) - 1) * 100

      # Net metrics (apply cost as lump deduction from cumulative)
      cum_net <- cum_gross * (1 - cost_per_switch)^switches
      cagr_net <- (cum_net^(1 / years) - 1) * 100

      # Buy & hold (no switches)
      cum_bh <- tail(d$cum_market, 1)
      cagr_bh <- (cum_bh^(1 / years) - 1) * 100

      compound_cost <- round((1 - (1 - cost_per_switch)^switches) * 100, 2)
      tibble::tibble(
        scenario = c("Buy & Hold", "VIX Protection (gross)", "VIX Protection (net)"),
        switches = c(0L, as.integer(switches), as.integer(switches)),
        cost_per_switch_bps = c(0, 5, 5),
        total_cost_pct = c(0, round(total_cost * 100, 2), compound_cost),
        cumulative = c(round(cum_bh, 1), round(cum_gross, 1), round(cum_net, 1)),
        cagr = c(round(cagr_bh, 1), round(cagr_gross, 1), round(cagr_net, 1))
      )
    }),

    # ── Subperiod stability (#45) ───────────────────────────────
    targets::tar_target(aw_subperiod, {
      library(dplyr)

      d <- aw_vix_daily |> filter(!is.na(vix), !is.na(ret))

      run_period <- function(data, label) {
        n <- nrow(data)
        if (n < 50) return(NULL)
        in_mkt <- rep(TRUE, n)
        cool <- 0L
        for (i in 2:n) {
          if (cool > 0) cool <- cool - 1L
          vp <- data$vix[i - 1]  # previous day VIX (t+1 execution)
          if (abs(data$ret[i - 1]) > 0.03 ||
              (!is.na(vp) && vp > 30)) {
            in_mkt[i] <- FALSE
            cool <- max(cool, 5L)
          } else if (cool > 0 || (!is.na(vp) && vp > 25)) {
            in_mkt[i] <- FALSE
          }
        }
        sr <- ifelse(in_mkt, data$ret, 0)
        yrs <- n / 252
        cum_s <- prod(1 + sr)
        cum_b <- prod(1 + data$ret)
        cum_dd_s <- cumprod(1 + sr)
        cum_dd_b <- cumprod(1 + data$ret)

        tibble::tibble(
          period = label,
          n_days = n,
          years = round(yrs, 1),
          cagr_bh = round((cum_b^(1 / yrs) - 1) * 100, 1),
          cagr_strat = round((cum_s^(1 / yrs) - 1) * 100, 1),
          max_dd_bh = round(min((cum_dd_b - cummax(cum_dd_b)) /
                                  cummax(cum_dd_b)) * 100, 1),
          max_dd_strat = round(min((cum_dd_s - cummax(cum_dd_s)) /
                                     cummax(cum_dd_s)) * 100, 1),
          pct_cash = round(sum(!in_mkt) / n * 100, 1)
        )
      }

      bind_rows(
        run_period(d |> filter(as.Date(date) < as.Date("2008-01-01")),
                   "1993-2007"),
        run_period(d |> filter(as.Date(date) >= as.Date("2008-01-01"),
                               as.Date(date) < as.Date("2020-01-01")),
                   "2008-2019"),
        run_period(d |> filter(as.Date(date) >= as.Date("2020-01-01")),
                   "2020-2026"),
        run_period(d, "Full Period")
      )
    }),

    # ── Cross-market validation (#45) ───────────────────────────
    targets::tar_target(aw_cross_market, {
      library(dplyr)

      vix <- hd_macro("VIXCLS") |> select(date, vix = value) |> arrange(date)

      purrr::map_dfr(c("SPY", "QQQ", "IWM", "DIA"), function(tkr) {
        d <- aw_daily_returns |>
          filter(ticker == tkr) |>
          arrange(date) |>
          left_join(vix, by = "date") |>
          filter(!is.na(vix), !is.na(ret))

        n <- nrow(d)
        if (n < 252) return(NULL)
        in_mkt <- rep(TRUE, n)
        cool <- 0L
        for (i in 2:n) {
          if (cool > 0) cool <- cool - 1L
          vp <- d$vix[i - 1]  # previous day VIX (t+1 execution)
          if (abs(d$ret[i - 1]) > 0.03 ||
              (!is.na(vp) && vp > 30)) {
            in_mkt[i] <- FALSE
            cool <- max(cool, 5L)
          } else if (cool > 0 || (!is.na(vp) && vp > 25)) {
            in_mkt[i] <- FALSE
          }
        }
        sr <- ifelse(in_mkt, d$ret, 0)
        yrs <- n / 252
        cum_s <- prod(1 + sr)
        cum_b <- prod(1 + d$ret)
        cum_dd_s <- cumprod(1 + sr)
        cum_dd_b <- cumprod(1 + d$ret)

        tibble::tibble(
          ticker = tkr,
          years = round(yrs, 1),
          cagr_bh = round((cum_b^(1 / yrs) - 1) * 100, 1),
          cagr_strat = round((cum_s^(1 / yrs) - 1) * 100, 1),
          max_dd_bh = round(min((cum_dd_b - cummax(cum_dd_b)) /
                                  cummax(cum_dd_b)) * 100, 1),
          max_dd_strat = round(min((cum_dd_s - cummax(cum_dd_s)) /
                                     cummax(cum_dd_s)) * 100, 1),
          sharpe_bh = round(mean(d$ret) / sd(d$ret) * sqrt(252), 2),
          sharpe_strat = round(mean(sr) / sd(sr) * sqrt(252), 2),
          pct_cash = round(sum(!in_mkt) / n * 100, 1)
        )
      })
    }),

    # ── Bootstrap CI on Sharpe (#45) ────────────────────────────
    targets::tar_target(aw_bootstrap_ci, {
      library(dplyr)

      d <- aw_practical_backtest
      strat_ret <- d$ret_strategy
      mkt_ret <- d$ret_market
      n <- length(strat_ret)
      block_size <- 63L  # ~3 months
      n_boot <- 1000L

      set.seed(42)
      boot_sharpe_strat <- numeric(n_boot)
      boot_sharpe_mkt <- numeric(n_boot)

      for (b in seq_len(n_boot)) {
        # Block bootstrap: sample block start positions
        n_blocks <- ceiling(n / block_size)
        starts <- sample(seq_len(n - block_size + 1), n_blocks, replace = TRUE)
        idx <- unlist(lapply(starts, function(s) s:(s + block_size - 1)))[1:n]

        bs <- strat_ret[idx]
        bm <- mkt_ret[idx]
        boot_sharpe_strat[b] <- mean(bs) / sd(bs) * sqrt(252)
        boot_sharpe_mkt[b] <- mean(bm) / sd(bm) * sqrt(252)
      }

      tibble::tibble(
        scenario = c("Buy & Hold", "VIX Protection"),
        sharpe_point = c(
          round(mean(mkt_ret) / sd(mkt_ret) * sqrt(252), 2),
          round(mean(strat_ret) / sd(strat_ret) * sqrt(252), 2)
        ),
        sharpe_ci_lo = c(
          round(quantile(boot_sharpe_mkt, 0.05), 2),
          round(quantile(boot_sharpe_strat, 0.05), 2)
        ),
        sharpe_ci_hi = c(
          round(quantile(boot_sharpe_mkt, 0.95), 2),
          round(quantile(boot_sharpe_strat, 0.95), 2)
        ),
        ci_crosses_zero = c(
          quantile(boot_sharpe_mkt, 0.05) < 0,
          quantile(boot_sharpe_strat, 0.05) < 0
        )
      )
    }),

    # ── Alpha decay: delay signal by 1-10 days ─────────────────
    targets::tar_target(aw_alpha_decay, {
      library(dplyr)

      d <- aw_vix_daily |> filter(!is.na(vix), !is.na(ret))
      n <- nrow(d)

      # Run strategy with delayed signal: the exit/re-entry decision
      # is based on VIX and shock from `delay` days ago
      run_delayed <- function(d, delay) {
        n <- nrow(d)
        in_mkt <- rep(TRUE, n)
        cool <- 0L
        for (i in 2:n) {
          if (cool > 0) cool <- cool - 1L
          # Look at signal from `delay` days ago
          sig_idx <- max(1L, i - delay)
          shocked <- abs(d$ret[sig_idx]) > 0.03
          vix_high <- !is.na(d$vix[sig_idx]) && d$vix[sig_idx] > 30
          vix_reentry <- !is.na(d$vix[sig_idx]) && d$vix[sig_idx] > 25

          if (shocked || vix_high) {
            in_mkt[i] <- FALSE
            cool <- max(cool, 5L)
          } else if (cool > 0 || vix_reentry) {
            in_mkt[i] <- FALSE
          }
        }
        sr <- ifelse(in_mkt, d$ret, 0)
        yrs <- n / 252
        cum <- prod(1 + sr)
        cum_dd <- cumprod(1 + sr)
        list(
          cagr = round((cum^(1 / yrs) - 1) * 100, 1),
          vol = round(sd(sr) * sqrt(252) * 100, 1),
          max_dd = round(min((cum_dd - cummax(cum_dd)) / cummax(cum_dd)) * 100, 1),
          sharpe = round(mean(sr) / sd(sr) * sqrt(252), 2),
          pct_cash = round(sum(!in_mkt) / n * 100, 1)
        )
      }

      delays <- 1:10  # t+1 minimum — t+0 execution is impossible
      purrr::map_dfr(delays, function(delay) {
        r <- run_delayed(d, delay)
        tibble::as_tibble(c(list(delay_days = delay), r))
      })
    })
  )
}
