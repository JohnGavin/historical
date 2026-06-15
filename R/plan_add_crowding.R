# Plan: Anomaly-Driven Demand (ADD) Crowding Column — #430
#
# Kjær & Posselt (2025) show that mechanically rebalancing published anomaly
# portfolios creates coordinated flow in the first ~6 trading days of each
# month. Strategies whose returns are correlated with this SPY month-start
# return are partially riding crowding flow, not pure mispricing.
#
# This plan computes an ADD loading for each strategy in the leaderboard:
#   add_corr: Pearson correlation between strategy's monthly return and
#             SPY's first-N-trading-day return in the same month.
#   add_beta: OLS slope (strategy_ret ~ spy_start_ret).
#   add_flag: TRUE when add_corr > crowd_corr_threshold.
#
# The correlation is a PROXY for the direct ADD measurement (which requires
# daily portfolio returns). For monthly strategies, SPY month-start return
# is the best available crowding-flow signal.
#
# See wiki: knowledge/wiki/anomaly-driven-demand.md
# Applicable rules:
#   priced-in-prohibition  — ADD clause already present; this operationalises it
#   backtest-robustness    — threshold and month_start_days are sensitivity levers
#   resulting-prohibition  — ADD loading is evidence about the mechanism, not
#                           a signal to abandon a strategy automatically
#
# Naming: add_*
# Total targets: 4

plan_add_crowding <- function() {
  list(

    # ── Parameters ─────────────────────────────────────────────────────────────
    targets::tar_target(add_params, {
      list(
        # Number of trading days at month-start to use for the SPY signal.
        # 6 is the canonical ADD rebalancing window (Kjær & Posselt 2025).
        # Sensitivity lever: sweep 4, 6, 8 in v1.
        month_start_days     = 6L,

        # Correlation threshold above which a strategy is flagged as ADD-crowded.
        # 0.40 = moderate-to-strong linear association.
        # Sensitivity lever: sweep 0.30 / 0.40 / 0.50 in v1.
        crowd_corr_threshold = 0.40,

        # Minimum matched months required to compute a meaningful correlation.
        min_months           = 24L
      )
    }),


    # ── SPY daily returns: build once, reuse for all month-start windows ──────
    # Per look-ahead-bias-prevention: we are computing an ex-post diagnostic
    # statistic (ADD loading), NOT a forward-looking signal. The daily SPY
    # returns are used purely to characterise PAST return distributions.
    # No future data leaks into strategy returns (which are already fixed).
    targets::tar_target(add_spy_daily, {
      library(dplyr)

      hd_ohlcv("SPY", collect = TRUE) |>
        dplyr::arrange(.data$date) |>
        dplyr::mutate(
          date      = as.Date(.data$date),
          daily_ret = .data$adjusted_close / dplyr::lag(.data$adjusted_close) - 1,
          ym        = format(.data$date, "%Y-%m")
        ) |>
        dplyr::filter(!is.na(.data$daily_ret)) |>
        dplyr::select("date", "ym", "adjusted_close", "daily_ret")
    }),


    # ── SPY first-N-trading-days return per calendar month ────────────────────
    # spy_start_ret = compounded return over the first N trading days of each month.
    # spy_rest_ret  = compounded return over the remaining days.
    # Both are informational; only spy_start_ret enters the correlation.
    targets::tar_target(add_spy_month_start, {
      library(dplyr)

      n_start <- add_params$month_start_days

      add_spy_daily |>
        dplyr::group_by(.data$ym) |>
        dplyr::arrange(.data$date, .by_group = TRUE) |>
        dplyr::summarise(
          n_days       = dplyr::n(),
          spy_start_ret = prod(1 + head(.data$daily_ret, n_start)) - 1,
          spy_full_ret  = prod(1 + .data$daily_ret) - 1,
          spy_rest_ret  = (1 + .data$spy_full_ret) /
                          (1 + .data$spy_start_ret) - 1,
          .groups = "drop"
        ) |>
        dplyr::filter(.data$n_days >= n_start)
    }),


    # ── ADD crowding per strategy ─────────────────────────────────────────────
    # Collects monthly return vectors from all accessible strategy portfolios,
    # joins them with spy_start_ret by year-month, then computes:
    #   add_corr — Pearson r between strategy return and SPY month-start return
    #   add_beta — OLS beta (strategy_ret ~ spy_start_ret), annualised units
    #   add_flag — TRUE if add_corr > threshold
    #
    # Coverage: strategies with accessible monthly return vectors and a
    # date / exec_date column for ym construction. Strategies without a
    # supported return column receive NA for all three ADD columns.
    #
    # Interpretability:
    #   add_corr > 0.40  → mild ADD exposure
    #   add_corr > 0.60  → strong ADD exposure (returns partly driven by flow)
    #   add_corr ~ 0     → no rebalancing-flow signature
    #   add_corr < 0     → counter-cyclical to month-start flow (unusual)
    targets::tar_target(add_crowding, {
      library(dplyr)

      threshold  <- add_params$crowd_corr_threshold
      min_mo     <- add_params$min_months
      spy_ms     <- add_spy_month_start |> dplyr::select("ym", "spy_start_ret")

      # Helper: safely extract ym + ret from a portfolio tibble
      .to_ym_ret <- function(df, date_col, ret_col) {
        if (is.null(df) || !all(c(date_col, ret_col) %in% names(df))) return(NULL)
        df |>
          dplyr::transmute(
            ym  = format(as.Date(.data[[date_col]]), "%Y-%m"),
            ret = .data[[ret_col]]
          )
      }

      strat_rets <- list(
        # Factor-level strategies (monthly, portfolio_ret column)
        "Factor MAX"      = .to_ym_ret(fm_portfolio,       "date", "portfolio_ret"),
        "Factor DRIF"     = .to_ym_ret(drif_portfolio,     "date", "portfolio_ret"),
        # Stock-level strategies (monthly, port_ret column)
        "Stock MAX"       = .to_ym_ret(stk_max_portfolio,  "date", "port_ret"),
        "Stock DRIF"      = .to_ym_ret(stk_drif_portfolio, "date", "port_ret"),
        "XGB DRIF"        = .to_ym_ret(xgb_drif_portfolio, "date", "port_ret"),
        # LTR (monthly, port_ret)
        "LTR"             = .to_ym_ret(ltr_portfolio,      "date", "port_ret"),
        # Mom siblings (exec_date column, ret_ls column)
        "Mom Pre-Peak"    = .to_ym_ret(mom_prepeak_returns,  "exec_date", "ret_ls"),
        "Mom Post-Peak"   = .to_ym_ret(mom_postpeak_returns, "exec_date", "ret_ls"),
        "Mom 12-2"        = .to_ym_ret(mom_combined_returns, "exec_date", "ret_ls"),
        # FIP-screened momentum (exec_date, ret_ls)
        "Mom FIP Screen"  = .to_ym_ret(fip_returns,          "exec_date", "ret_ls"),
        # Managed futures (date, ret_ls)
        "Managed Futures" = .to_ym_ret(mf_portfolios, "date", "ret_ls")
      )

      # Remove strategies with no data
      strat_rets <- Filter(Negate(is.null), strat_rets)

      dplyr::bind_rows(lapply(names(strat_rets), function(nm) {
        df <- dplyr::inner_join(strat_rets[[nm]], spy_ms, by = "ym") |>
          dplyr::filter(!is.na(.data$ret), !is.na(.data$spy_start_ret))

        if (nrow(df) < min_mo) {
          return(tibble::tibble(
            strategy         = nm,
            n_months_matched = nrow(df),
            add_corr         = NA_real_,
            add_beta         = NA_real_,
            add_flag         = NA
          ))
        }

        corr <- cor(df$ret, df$spy_start_ret, use = "complete.obs")
        fit  <- lm(ret ~ spy_start_ret, data = df)
        beta <- unname(stats::coef(fit)[2])

        tibble::tibble(
          strategy         = nm,
          n_months_matched = nrow(df),
          add_corr         = round(corr, 3),
          add_beta         = round(beta, 3),
          add_flag         = !is.na(corr) && corr > threshold
        )
      }))
    })

  )
}
