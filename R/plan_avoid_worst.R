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
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

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
      })
    }),

    # ── Daily returns: Fama-French Mkt-RF (1926+) ──────────────
    targets::tar_target(aw_daily_ff, {
      library(dplyr)
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

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
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

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
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

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
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

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
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

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
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      spy <- aw_daily_returns |> filter(ticker == "SPY") |> arrange(date)
      vix <- hd_macro("VIXCLS") |>
        select(date, vix = value) |>
        arrange(date)

      spy |> left_join(vix, by = "date")
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

          # Check triggers
          shocked <- abs(d$ret[i - 1]) > shock_thresh
          vix_elevated <- !is.na(d$vix[i]) && d$vix[i] > vix_high

          if (shocked || vix_elevated) {
            in_market[i] <- FALSE
            cooloff_remaining <- max(cooloff_remaining, min_cooloff)
          } else if (cooloff_remaining > 0) {
            in_market[i] <- FALSE
          } else if (!is.na(d$vix[i]) && d$vix[i] > vix_reentry) {
            # Still elevated, stay out
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
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

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
          vix_elevated <- !is.na(d$vix[i]) && d$vix[i] > vix_high
          if (shocked || vix_elevated) {
            in_market[i] <- FALSE
            cooloff_remaining <- max(cooloff_remaining, min_cooloff)
          } else if (cooloff_remaining > 0) {
            in_market[i] <- FALSE
          } else if (!is.na(d$vix[i]) && d$vix[i] > vix_reentry) {
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
    })
  )
}
