# Plan: EV/EBIT Fundamental Value Sleeve — HML Proxy v0 (#426)
#
# Issue #426 (high-priority): add a fundamental value sleeve to diversify the
# leaderboard's factor exposure. All 14 existing strategies load momentum;
# value has been the systematic opposite, so adding it reduces leaderboard
# correlation and addresses the AA-QVAL gap.
#
# v0 approach: Fama-French HML (cheapness) and RMW (profitability) factors
# serve as proxies for EV/EBIT rank and quality screens respectively.
# Real per-stock EV/EBIT data (FMP / Yahoo fundamentals) is deferred to v1.
#
# Strategies:
#   ev_value_hml  — RF + HML (pure cheapness proxy, analogous to AA deep value)
#   ev_value_qual — RF + HML + RMW (cheapness + profitability, AA QVAL proxy)
#   ev_market     — Mkt-RF + RF (cap-weighted benchmark)
#
# Applicable rules:
#   underperformance-prior   — max 39-year value drawdown MUST be on the dashboard
#   priced-in-prohibition    — value premium documented over 90+ years (passes)
#   cross-geography-pervasiveness — value documented in US, intl, EM (passes)
#   backtest-robustness      — quality_weight parameter is the main sensitivity lever
#
# Naming: ev_*
# Total targets: 6

plan_ev_ebit <- function() {
  list(

    # ── Parameters ─────────────────────────────────────────────────────────────
    targets::tar_target(ev_params, {
      list(
        # 20 bps/month: value rebalances less aggressively than momentum
        cost_per_rebalance = 0.002,

        # OOS window: 2010+ (post Global Financial Crisis; value widely followed)
        oos_start = as.Date("2010-01-01"),

        # HML weight in value+quality blend (1-quality_weight goes to RMW)
        # Sensitivity lever per backtest-robustness rule: sweep 0.3/0.5/0.7
        quality_weight = 0.5
      )
    }),


    # ── Data: monthly FF5 factors ───────────────────────────────────────────────
    targets::tar_target(ev_data, {
      library(dplyr)

      ff5 <- hd_factors(dataset = "FF5", frequency = "monthly") |>
        dplyr::mutate(date = as.Date(date))

      ff5_wide <- ff5 |>
        tidyr::pivot_wider(
          id_cols     = "date",
          names_from  = "factor_name",
          values_from = "value"
        ) |>
        dplyr::rename(Mkt_RF = `Mkt-RF`) |>
        dplyr::arrange(date)

      # Factor values arrive in PERCENTAGE form (e.g., 1.5 = 1.5%); convert
      numeric_cols <- setdiff(names(ff5_wide), "date")
      for (col in numeric_cols) ff5_wide[[col]] <- ff5_wide[[col]] / 100

      ff5_wide
    }),


    # ── Portfolios: construct 3 strategies ─────────────────────────────────────
    targets::tar_target(ev_portfolios, {
      library(dplyr)

      cost <- ev_params$cost_per_rebalance
      qw   <- ev_params$quality_weight     # HML weight in value+quality blend

      ev_data |>
        dplyr::mutate(
          # Pure cheapness proxy: RF + full HML exposure
          ret_value_hml  = RF + HML - cost,

          # Value + quality proxy: RF + blended HML/RMW (AA QVAL analogue)
          ret_value_qual = RF + qw * HML + (1 - qw) * RMW - cost,

          # Benchmark: cap-weighted market (no cost — passive)
          ret_market     = Mkt_RF + RF,

          # Cumulative wealth indices (start at 1)
          cum_value_hml  = cumprod(1 + ret_value_hml),
          cum_value_qual = cumprod(1 + ret_value_qual),
          cum_market     = cumprod(1 + ret_market)
        ) |>
        dplyr::select(date, RF, Mkt_RF, HML, RMW,
                      ret_value_hml, ret_value_qual, ret_market,
                      cum_value_hml, cum_value_qual, cum_market)
    }),


    # ── Metrics: performance table across periods ───────────────────────────────
    # #645: OOS is bounded at bt_partitions$factor$test_end (R/plan_partitions.R)
    # so it no longer silently swallows the sealed Validation partition on
    # every tar_make(). ev_ebit's strategies are FF5 factor (HML/RMW) proxies,
    # so bt_partitions$factor is the matching partition set. Training keeps
    # its original pre-2010 definition (narrower than canonical Training, a
    # comparability wart but not a seal breach -- see #645) and is unaffected
    # by this bound.
    targets::tar_target(ev_metrics, {
      library(dplyr)

      oos      <- ev_params$oos_start
      test_end <- bt_partitions$factor$test_end

      # #677 slice 2: sharpe now uses the canonical risk-free-adjusted
      # helper (R/utils_metrics.R::sharpe_ratio_rf()) instead of bare
      # cagr/vol -- this file was one of the "no rf deducted" family
      # (implied rf of exactly 0.00%, a formula signature -- see #677).
      # ev_portfolios$RF is already carried on every row (ev_data pivots
      # the RF column directly out of FF5), so no new join is needed here.
      calc_metrics <- function(ret_vec, rf_vec, date_vec, strategy_name, period_name) {
        keep     <- !is.na(ret_vec)
        ret_vec  <- ret_vec[keep]
        rf_vec   <- rf_vec[keep]
        date_vec <- date_vec[keep]
        if (length(ret_vec) < 12L) return(NULL)
        years    <- length(ret_vec) / 12
        cum_ret  <- prod(1 + ret_vec)
        cagr     <- (cum_ret^(1 / years) - 1) * 100
        vol      <- sd(ret_vec) * sqrt(12) * 100
        sr       <- sharpe_ratio_rf(ret_vec, rf_vec, periods_per_year = 12L)
        sharpe   <- sr$sharpe
        cum_w    <- cumprod(1 + ret_vec)
        drawdown <- (cum_w - cummax(cum_w)) / cummax(cum_w)
        max_dd   <- min(drawdown) * 100
        calmar   <- ifelse(abs(max_dd) > 0, cagr / abs(max_dd), NA_real_)
        tibble::tibble(
          strategy     = strategy_name,
          period       = period_name,
          n_months     = length(ret_vec),
          cagr         = round(cagr, 2),
          vol          = round(vol, 2),
          sharpe       = round(sharpe, 3),
          # ann_rf published alongside sharpe (#677 slice 4), same PERCENT
          # convention as cagr/vol above -- QA gate S17
          # (check_leaderboard_sharpe_coherence(), R/plan_qa_gates.R) asserts
          # sharpe == (cagr - ann_rf) / vol for every leaderboard row.
          ann_rf       = round(sr$ann_rf * 100, 2),
          max_dd       = round(max_dd, 2),
          calmar       = round(calmar, 3),
          window_start = min(date_vec),
          window_end   = max(date_vec)
        )
      }

      strategies <- list(
        value_hml  = ev_portfolios$ret_value_hml,
        value_qual = ev_portfolios$ret_value_qual,
        market     = ev_portfolios$ret_market
      )
      labels <- c(
        value_hml  = "Pure Value (100% HML, EV/EBIT proxy)",
        value_qual = "Value+Quality (50% HML + 50% RMW, QVAL proxy)",
        market     = "Benchmark (Cap-Weighted Market)"
      )
      dates  <- ev_portfolios$date
      rf_all <- ev_portfolios$RF

      is_pre_oos <- dates < oos
      is_oos     <- dates >= oos & dates <= test_end

      rows <- list()
      for (nm in names(strategies)) {
        rows <- c(rows,
          list(calc_metrics(strategies[[nm]],            rf_all,            dates,             labels[nm], "Full")),
          list(calc_metrics(strategies[[nm]][is_pre_oos], rf_all[is_pre_oos], dates[is_pre_oos], labels[nm], "Training")),
          list(calc_metrics(strategies[[nm]][is_oos],     rf_all[is_oos],     dates[is_oos],     labels[nm], "OOS"))
        )
      }
      dplyr::bind_rows(Filter(Negate(is.null), rows))
    }),


    # ── Underperformance prior: period-by-period value vs market ───────────────
    # Per underperformance-prior rule: value premium has historically endured
    # 14–39 year underperformance periods (Swedroe). This target shows the
    # period-by-period breakdown so results are interpreted in historical context
    # BEFORE evaluating recent performance (2013+).
    targets::tar_target(ev_underperformance_periods, {
      library(dplyr)

      dates <- ev_portfolios$date
      rval  <- ev_portfolios$ret_value_qual
      rmkt  <- ev_portfolios$ret_market
      rf    <- ev_portfolios$RF   # #677 slice 2: rf-adjusted sharpe below

      # Known value underperformance periods (from Swedroe documentation)
      p_pre66   <- dates < as.Date("1966-01-01")
      p_under66 <- dates >= as.Date("1966-01-01") & dates <= as.Date("1982-12-31")
      p_bull83  <- dates >= as.Date("1983-01-01") & dates <= as.Date("1999-12-31")
      p_under00 <- dates >= as.Date("2000-01-01") & dates <= as.Date("2012-12-31")
      p_recent  <- dates >= as.Date("2013-01-01")

      # #677 slice 2: sharpe now uses sharpe_ratio_rf() (R/utils_metrics.R)
      # instead of bare cagr/vol -- see calc_metrics() above for the same
      # fix applied to ev_metrics.
      calc_row <- function(ret_vec, rf_vec, period_label, strategy_name) {
        keep    <- !is.na(ret_vec)
        ret_vec <- ret_vec[keep]
        rf_vec  <- rf_vec[keep]
        if (length(ret_vec) < 6L) return(NULL)
        years  <- length(ret_vec) / 12
        cagr   <- (prod(1 + ret_vec)^(1 / years) - 1) * 100
        vol    <- sd(ret_vec) * sqrt(12) * 100
        sr     <- sharpe_ratio_rf(ret_vec, rf_vec, periods_per_year = 12L)
        tibble::tibble(
          strategy = strategy_name,
          period   = period_label,
          n_months = length(ret_vec),
          cagr     = round(cagr, 2),
          vol      = round(vol, 2),
          sharpe   = round(sr$sharpe, 3)
        )
      }

      dplyr::bind_rows(
        calc_row(rval[p_pre66],   rf[p_pre66],   "Pre-1966 (Value leadership)",         "Value+Quality"),
        calc_row(rmkt[p_pre66],   rf[p_pre66],   "Pre-1966 (Value leadership)",         "Market"),
        calc_row(rval[p_under66], rf[p_under66], "1966-1982 (Value underperformance)",  "Value+Quality"),
        calc_row(rmkt[p_under66], rf[p_under66], "1966-1982 (Value underperformance)",  "Market"),
        calc_row(rval[p_bull83],  rf[p_bull83],  "1983-1999 (Value recovery)",          "Value+Quality"),
        calc_row(rmkt[p_bull83],  rf[p_bull83],  "1983-1999 (Value recovery)",          "Market"),
        calc_row(rval[p_under00], rf[p_under00], "2000-2012 (Value underperformance)",  "Value+Quality"),
        calc_row(rmkt[p_under00], rf[p_under00], "2000-2012 (Value underperformance)",  "Market"),
        calc_row(rval[p_recent],  rf[p_recent],  "2013+ (Recent period)",               "Value+Quality"),
        calc_row(rmkt[p_recent],  rf[p_recent],  "2013+ (Recent period)",               "Market")
      )
    }),


    # ── Caption: dynamic summary ──────────────────────────────────────────────
    targets::tar_target(ev_caption, {
      library(dplyr)

      oos    <- ev_params$oos_start
      oos_yr <- format(oos, "%Y")
      qw     <- ev_params$quality_weight

      qual_oos  <- ev_metrics |>
        dplyr::filter(strategy == "Value+Quality (50% HML + 50% RMW, QVAL proxy)",
                      period == "OOS")
      qual_full <- ev_metrics |>
        dplyr::filter(strategy == "Value+Quality (50% HML + 50% RMW, QVAL proxy)",
                      period == "Full")
      mkt_oos   <- ev_metrics |>
        dplyr::filter(strategy == "Benchmark (Cap-Weighted Market)", period == "OOS")

      qual_oos_sharpe  <- if (nrow(qual_oos) > 0)  round(qual_oos$sharpe[1], 3)  else NA
      mkt_oos_sharpe   <- if (nrow(mkt_oos) > 0)   round(mkt_oos$sharpe[1], 3)   else NA
      qual_full_cagr   <- if (nrow(qual_full) > 0)  round(qual_full$cagr[1], 2)   else NA
      qual_full_sharpe <- if (nrow(qual_full) > 0)  round(qual_full$sharpe[1], 3) else NA

      # 2000-2012 underperformance severity
      under00_val <- ev_underperformance_periods |>
        dplyr::filter(period == "2000-2012 (Value underperformance)",
                      strategy == "Value+Quality")
      under00_mkt <- ev_underperformance_periods |>
        dplyr::filter(period == "2000-2012 (Value underperformance)",
                      strategy == "Market")
      under_str <- if (nrow(under00_val) > 0 && nrow(under00_mkt) > 0) {
        paste0(
          "Most recent underperformance period (2000-2012): ",
          "Value+Quality Sharpe ", round(under00_val$sharpe[1], 3),
          " vs market ", round(under00_mkt$sharpe[1], 3), ". "
        )
      } else ""

      paste0(
        "**EV/EBIT Fundamental Value Sleeve — HML Proxy v0 (#426).** ",
        "Three strategies from monthly FF5 factors: ",
        "Pure Value (100% HML), Value+Quality (", round(qw * 100), "% HML + ",
        round((1 - qw) * 100), "% RMW, AA QVAL proxy), and Cap-Weighted Benchmark. ",
        "v0 uses HML as an EV/EBIT rank proxy and RMW as a profitability quality screen; ",
        "real per-stock EV/EBIT data is deferred to v1. ",
        "Full-period: CAGR ", qual_full_cagr, "%, Sharpe ", qual_full_sharpe, ". ",
        "OOS (", oos_yr, "+): Value+Quality Sharpe ", qual_oos_sharpe,
        " vs market ", mkt_oos_sharpe, ". ",
        under_str,
        "Underperformance-prior context (Swedroe): value has endured up to 39-year ",
        "underperformance periods historically (1966-1982 and 2000-2012 visible above); ",
        "recent underperformance does not falsify the premium per the underperformance-prior rule. ",
        "20 bps/month rebalancing cost applied. ",
        "Value premium meets cross-geography-pervasiveness bar: documented in US, ",
        "international, and EM markets over 90+ years."
      )
    })

  )
}
