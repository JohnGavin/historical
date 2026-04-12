# Backtesting targets: Defense First macro rotation strategy
#
# Expanding window backtest with out-of-sample holdout.
# All parameters in bt_params — change once, tar_make() rebuilds all.
#
# Usage:
#   targets::tar_make(store = "docs/_targets_backtest")

plan_backtest <- function() {
  list(
    # ── Parameters ────────────────────────────────────────────────
    targets::tar_target(bt_params, {
      list(
        tickers = c("TLT", "GLD", "DBC", "UUP"),
        benchmark = "SPY",
        cash_proxy = "BIL",
        lookback_months = c(1, 3, 6, 12),
        weights = c(0.4, 0.3, 0.2, 0.1),
        start_date = as.Date("2007-04-01"),
        is_end = as.Date("2022-12-31"),     # in-sample end
        oos_start = as.Date("2023-01-01")   # out-of-sample start
      )
    }),

    # ── Data: monthly prices ──────────────────────────────────────
    targets::tar_target(bt_prices, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      all_tickers <- c(bt_params$tickers, bt_params$benchmark, bt_params$cash_proxy)
      raw <- hd_ohlcv(all_tickers, from = as.character(bt_params$start_date))

      # Monthly close (last trading day per month)
      raw |>
        dplyr::mutate(ym = format(date, "%Y-%m")) |>
        dplyr::group_by(ticker, ym) |>
        dplyr::filter(date == max(date)) |>
        dplyr::ungroup() |>
        dplyr::select(ticker, date, close, adjusted) |>
        dplyr::arrange(ticker, date)
    }),

    # ── Data: monthly returns ─────────────────────────────────────
    targets::tar_target(bt_returns, {
      bt_prices |>
        dplyr::group_by(ticker) |>
        dplyr::arrange(date) |>
        dplyr::mutate(ret = adjusted / dplyr::lag(adjusted) - 1) |>
        dplyr::filter(!is.na(ret)) |>
        dplyr::ungroup()
    }),

    # ── Expanding window backtest (in-sample) ─────────────────────
    targets::tar_target(bt_expanding, {
      library(dplyr)

      tickers <- bt_params$tickers
      benchmark <- bt_params$benchmark
      cash <- bt_params$cash_proxy
      lookbacks <- bt_params$lookback_months
      wts <- bt_params$weights

      # Wide returns: one column per ticker
      wide <- bt_returns |>
        select(ticker, date, ret) |>
        tidyr::pivot_wider(names_from = ticker, values_from = ret) |>
        arrange(date) |>
        filter(as.Date(date) <= as.Date(bt_params$is_end))

      dates <- wide$date
      results <- list()

      # Need at least max(lookback) months of history
      min_obs <- max(lookbacks)

      for (i in (min_obs + 1):length(dates)) {
        current_date <- dates[i]
        # Expanding window: use all data from start to previous month
        hist <- wide[1:(i - 1), ]

        # Compute composite momentum for each hedge
        scores <- numeric(length(tickers))
        names(scores) <- tickers
        for (j in seq_along(tickers)) {
          tkr <- tickers[j]
          if (!tkr %in% names(hist)) next
          rets <- hist[[tkr]]
          n <- length(rets)
          # Average of 1, 3, 6, 12 month returns (simple cumulative)
          mom <- numeric(length(lookbacks))
          for (k in seq_along(lookbacks)) {
            lb <- lookbacks[k]
            if (n >= lb) {
              mom[k] <- prod(1 + tail(rets, lb)) - 1
            }
          }
          scores[j] <- mean(mom)
        }

        # Cash proxy score
        cash_score <- 0
        if (cash %in% names(hist)) {
          cash_rets <- hist[[cash]]
          n_cash <- length(cash_rets)
          cash_mom <- numeric(length(lookbacks))
          for (k in seq_along(lookbacks)) {
            lb <- lookbacks[k]
            if (n_cash >= lb) cash_mom[k] <- prod(1 + tail(cash_rets, lb)) - 1
          }
          cash_score <- mean(cash_mom)
        }

        # Rank and allocate (handle NA scores)
        scores[is.na(scores)] <- -Inf
        ranked <- sort(scores, decreasing = TRUE)
        if (all(scores < cash_score, na.rm = TRUE)) {
          # Fallback: 100% SPY
          allocation <- setNames(rep(0, length(tickers)), tickers)
          allocation[benchmark] <- 1.0
          fallback <- TRUE
        } else {
          allocation <- setNames(rep(0, length(tickers)), tickers)
          for (r in seq_along(ranked)) {
            if (r <= length(wts)) {
              allocation[names(ranked)[r]] <- wts[r]
            }
          }
          fallback <- FALSE
        }

        # Actual return this month
        actual_row <- wide[i, ]
        port_ret <- 0
        for (tkr in names(allocation)) {
          if (tkr %in% names(actual_row) && allocation[tkr] > 0) {
            port_ret <- port_ret + allocation[tkr] * actual_row[[tkr]]
          }
        }
        bench_ret <- if (benchmark %in% names(actual_row)) actual_row[[benchmark]] else NA_real_

        # Predicted return (weighted momentum score)
        pred_ret <- sum(scores * wts[rank(-scores)])

        results[[length(results) + 1]] <- tibble(
          date = current_date,
          rank_1 = names(ranked)[1],
          rank_2 = names(ranked)[2],
          rank_3 = names(ranked)[3],
          rank_4 = names(ranked)[4],
          w_1 = allocation[names(ranked)[1]],
          w_2 = allocation[names(ranked)[2]],
          w_3 = allocation[names(ranked)[3]],
          w_4 = allocation[names(ranked)[4]],
          predicted_return = pred_ret,
          actual_return = port_ret,
          benchmark_return = bench_ret,
          beat_benchmark = port_ret > bench_ret,
          fallback = fallback
        )
      }

      bind_rows(results)
    }),

    # ── Portfolio equity curve (in-sample) ────────────────────────
    targets::tar_target(bt_portfolio, {
      bt_expanding |>
        dplyr::mutate(
          cum_port = cumprod(1 + actual_return),
          cum_bench = cumprod(1 + benchmark_return)
        )
    }),

    # ── In-sample metrics ─────────────────────────────────────────
    targets::tar_target(bt_metrics_is, {
      library(dplyr)
      port <- bt_expanding$actual_return
      bench <- bt_expanding$benchmark_return
      n <- length(port)
      rf_annual <- 0.02  # approximate risk-free rate

      compute_metrics <- function(rets, label) {
        n <- length(rets)
        cum <- prod(1 + rets)
        years <- n / 12
        cagr <- cum^(1 / years) - 1
        vol <- sd(rets) * sqrt(12)
        sharpe <- (mean(rets) * 12 - rf_annual) / vol
        # Sortino: downside deviation
        down <- rets[rets < 0]
        sortino <- if (length(down) > 0) (mean(rets) * 12 - rf_annual) / (sd(down) * sqrt(12)) else NA
        # Max drawdown
        cum_series <- cumprod(1 + rets)
        peak <- cummax(cum_series)
        dd <- (cum_series - peak) / peak
        max_dd <- min(dd)
        calmar <- cagr / abs(max_dd)
        # Hit rate vs zero
        hit <- mean(rets > 0)

        tibble(
          strategy = label, n_months = n, years = round(years, 1),
          cagr = round(cagr, 4), vol = round(vol, 4),
          sharpe = round(sharpe, 2), sortino = round(sortino, 2),
          max_dd = round(max_dd, 4), calmar = round(calmar, 2),
          hit_rate = round(hit, 3)
        )
      }

      bind_rows(
        compute_metrics(port, "Defense First"),
        compute_metrics(bench, "SPY (buy & hold)")
      )
    }),

    # ── Drawdowns (in-sample) ─────────────────────────────────────
    targets::tar_target(bt_drawdowns, {
      bt_portfolio |>
        dplyr::mutate(
          peak_port = cummax(cum_port),
          dd_port = (cum_port - peak_port) / peak_port,
          peak_bench = cummax(cum_bench),
          dd_bench = (cum_bench - peak_bench) / peak_bench
        )
    }),

    # ── Regime map ────────────────────────────────────────────────
    targets::tar_target(bt_regime_map, {
      bt_expanding |>
        dplyr::select(date, rank_1, fallback)
    }),

    # ── Variant: equal weight ─────────────────────────────────────
    targets::tar_target(bt_equalwt, {
      library(dplyr)
      tickers <- bt_params$tickers
      wide <- bt_returns |>
        select(ticker, date, ret) |>
        tidyr::pivot_wider(names_from = ticker, values_from = ret) |>
        filter(as.Date(date) <= as.Date(bt_params$is_end))

      wide |>
        rowwise() |>
        mutate(port_ret = mean(c_across(all_of(tickers)), na.rm = TRUE)) |>
        ungroup() |>
        select(date, port_ret)
    }),

    # ── Variant: top one only ─────────────────────────────────────
    targets::tar_target(bt_topone, {
      bt_expanding |>
        dplyr::left_join(
          bt_returns |> dplyr::select(ticker, date, ret),
          by = c("rank_1" = "ticker", "date" = "date")
        ) |>
        dplyr::transmute(date, port_ret = dplyr::coalesce(ret, actual_return))
    }),

    # ── Comparison table (in-sample) ──────────────────────────────
    targets::tar_target(bt_comparison, {
      library(dplyr)
      rf_annual <- 0.02

      metrics <- function(rets, label) {
        rets <- rets[!is.na(rets)]
        n <- length(rets)
        if (n < 12) return(tibble(strategy = label, n_months = n))
        years <- n / 12
        cum <- prod(1 + rets)
        cagr <- cum^(1/years) - 1
        vol <- sd(rets) * sqrt(12)
        sharpe <- (mean(rets) * 12 - rf_annual) / vol
        cum_s <- cumprod(1 + rets)
        max_dd <- min((cum_s - cummax(cum_s)) / cummax(cum_s))

        tibble(strategy = label, n_months = n, years = round(years, 1),
               cagr = round(cagr, 4), vol = round(vol, 4),
               sharpe = round(sharpe, 2), max_dd = round(max_dd, 4),
               calmar = round(cagr / abs(max_dd), 2))
      }

      bind_rows(
        metrics(bt_expanding$actual_return, "Defense First (momentum)"),
        metrics(bt_expanding$benchmark_return, "SPY (buy & hold)"),
        metrics(bt_equalwt$port_ret, "Equal weight (25% each)"),
        metrics(bt_topone$port_ret, "Top 1 only (100%)")
      )
    }),

    # ── Out-of-sample (2023–2026) ─────────────────────────────────
    targets::tar_target(bt_oos, {
      library(dplyr)

      tickers <- bt_params$tickers
      benchmark <- bt_params$benchmark
      cash <- bt_params$cash_proxy
      lookbacks <- bt_params$lookback_months
      wts <- bt_params$weights

      wide <- bt_returns |>
        select(ticker, date, ret) |>
        tidyr::pivot_wider(names_from = ticker, values_from = ret) |>
        arrange(date)

      # OOS: continue expanding window from 2023-01 onwards
      oos_idx <- which(as.Date(wide$date) >= as.Date(bt_params$oos_start))
      results <- list()

      for (idx in oos_idx) {
        current_date <- wide$date[idx]
        if (idx < max(lookbacks) + 1) next
        hist <- wide[1:(idx - 1), ]

        scores <- numeric(length(tickers))
        names(scores) <- tickers
        for (j in seq_along(tickers)) {
          tkr <- tickers[j]
          if (!tkr %in% names(hist)) next
          rets <- hist[[tkr]]
          n <- length(rets)
          mom <- numeric(length(lookbacks))
          for (k in seq_along(lookbacks)) {
            lb <- lookbacks[k]
            if (n >= lb) mom[k] <- prod(1 + tail(rets, lb)) - 1
          }
          scores[j] <- mean(mom)
        }

        ranked <- sort(scores, decreasing = TRUE)
        allocation <- setNames(rep(0, length(tickers)), tickers)
        for (r in seq_along(ranked)) {
          if (r <= length(wts)) allocation[names(ranked)[r]] <- wts[r]
        }

        actual_row <- wide[idx, ]
        port_ret <- sum(sapply(names(allocation), \(t) {
          if (t %in% names(actual_row)) allocation[t] * actual_row[[t]] else 0
        }))
        bench_ret <- if (benchmark %in% names(actual_row)) actual_row[[benchmark]] else NA

        results[[length(results) + 1]] <- tibble(
          date = current_date, actual_return = port_ret,
          benchmark_return = bench_ret, beat_benchmark = port_ret > bench_ret
        )
      }

      bind_rows(results)
    }),

    # ── OOS vs IS comparison ──────────────────────────────────────
    targets::tar_target(bt_oos_vs_is, {
      library(dplyr)
      rf <- 0.02

      m <- function(rets, label) {
        rets <- rets[!is.na(rets)]
        n <- length(rets); years <- n/12
        if (n < 6) return(tibble(period = label, months = n))
        cum <- prod(1+rets); cagr <- cum^(1/years)-1
        vol <- sd(rets)*sqrt(12)
        sharpe <- (mean(rets)*12-rf)/vol
        cum_s <- cumprod(1+rets)
        max_dd <- min((cum_s-cummax(cum_s))/cummax(cum_s))
        tibble(period=label, months=n, cagr=round(cagr,4), vol=round(vol,4),
               sharpe=round(sharpe,2), max_dd=round(max_dd,4))
      }

      bind_rows(
        m(bt_expanding$actual_return, "In-sample (2009-2022)"),
        m(bt_expanding$benchmark_return, "SPY in-sample"),
        m(bt_oos$actual_return, "Out-of-sample (2023+)"),
        m(bt_oos$benchmark_return, "SPY out-of-sample")
      )
    })
  )
}
