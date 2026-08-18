# Plan: Cross-Asset Time-Series Momentum (Managed Futures) — v0 (#427)
#
# Issue #427 (high-priority): add a managed-futures / cross-asset TS-momentum
# sleeve to diversify away from the leaderboard's VIX-and-equity-only coverage.
#
# Strategy (Moskowitz-Ooi-Pedersen 2012, "Time Series Momentum"):
#   For each of 4 asset classes, compute the trailing 12-month return.
#   If positive → long; if negative → short (or zero for long-only).
#   Scale positions to a target annualized volatility (vol-targeting).
#   Combine equal-weight across assets.
#
# v0 data: ETF proxies via existing asset_monthly_returns_wide target
#   SPY  — US equity (plan_returns.R, hd_ohlcv)
#   TLT  — US long-duration bonds
#   GLD  — Gold / alternative currency
#   DBC  — Broad commodity basket
# RF from hd_factors("FF5", "monthly")
#
# Applicable rules:
#   cross-geography-pervasiveness — MOP 2012 documents TS-mom across 58
#     instruments in 4 asset classes back to 1900s; ETF proxies are v0.
#   backtest-robustness   — lookback (12m) and vol_target (10%) are the main
#     sensitivity levers; sweep deferred to v1.
#   backtesting-assumptions — 10 bps/month cost for ETF proxies documented;
#     real futures would incur roll costs (deferred to v1).
#   priced-in-prohibition — MOP premium is widely known; crowding risk exists
#     (2013-2019 trend-following drought). See ev_underperformance_periods
#     analogue: mf_underperformance_periods shows the drought period.
#   underperformance-prior — managed futures had a major 7-year underperformance
#     2013-2019 (trend-following drought); this is documented below and MUST be
#     shown before evaluating recent results.
#
# Signal lag: trailing 12m return is computed through month t-1 and applied to
#   month t, avoiding look-ahead bias. Vol estimate also lagged by 1 month.
#
# Naming: mf_*
# Total targets: 7

plan_managed_futures <- function() {
  list(

    # ── Parameters ─────────────────────────────────────────────────────────────
    targets::tar_target(mf_params, {
      list(
        lookback     = 12L,           # 12-month TS-momentum lookback (MOP canonical)
        vol_target   = 0.10,          # 10% annualised vol target per asset (MOP canonical)
        max_leverage = 3,             # cap position scale (prevent extreme leverage)
        cost_monthly = 0.001,         # 10 bps/month: ETF proxy (real futures ~20bps)
        oos_start    = as.Date("2010-01-01"),   # post-GFC; DBC live since 2006
        # Document proxy choice per backtesting-assumptions rule
        proxy_note   = paste0(
          "v0 uses ETF proxies: SPY (equity), TLT (bonds), GLD (gold), ",
          "DBC (commodities). Real managed futures use futures contracts with ",
          "roll costs and 1256 tax treatment. ETF proxies understate real-world ",
          "capacity and overstate tradability for institutions."
        )
      )
    }),


    # ── Data: join asset returns with RF ────────────────────────────────────────
    # asset_monthly_returns_wide (from plan_returns.R) provides SPY, TLT, GLD, DBC.
    # FF5 provides RF. Align by year-month to handle last-trading-day vs month-end.
    targets::tar_target(mf_data, {
      library(dplyr)

      ff5 <- hd_factors(dataset = "FF5", frequency = "monthly") |>
        dplyr::mutate(date = as.Date(date)) |>
        tidyr::pivot_wider(
          id_cols     = "date",
          names_from  = "factor_name",
          values_from = "value"
        ) |>
        dplyr::mutate(
          RF = RF / 100,
          ym = format(date, "%Y-%m")
        ) |>
        dplyr::select(ym, RF)

      assets <- asset_monthly_returns_wide |>
        dplyr::mutate(ym = format(date, "%Y-%m")) |>
        dplyr::select(-date)

      dplyr::inner_join(assets, ff5, by = "ym") |>
        dplyr::mutate(date = as.Date(paste0(ym, "-01"))) |>
        dplyr::select(date, SPY, TLT, GLD, DBC, RF) |>
        dplyr::arrange(date)
    }),


    # ── Signals: 12m trailing return + vol per asset ────────────────────────────
    # Per look-ahead-bias-prevention rule: signal for month t uses returns through
    # month t-1 only. Implemented via lag(sign(cum12)) and lag(vol12).
    # Vol-targeting: scale each position to vol_target / trailing_vol, cap at max_leverage.
    targets::tar_target(mf_signals, {
      library(dplyr)

      lb <- mf_params$lookback
      vt <- mf_params$vol_target
      ml <- mf_params$max_leverage

      df <- mf_data

      for (asset in c("SPY", "TLT", "GLD", "DBC")) {
        ret <- df[[asset]]

        # Trailing 12m compound return via cumprod: return from t-12 to t-1
        # cum[t-1] / cum[t-13] - 1, where cum = cumprod(1+ret)
        cum_ret <- cumprod(1 + ifelse(is.na(ret), 0, ret))
        cum12   <- dplyr::lag(cum_ret, 1) / dplyr::lag(cum_ret, lb + 1L) - 1

        # 12m trailing vol (annualised), lagged by 1 month for implementation
        vol12_current <- roll_sd_safe(ret, n = lb, min_frac = 0.7) * sqrt(12)

        # Signal: sign of trailing 12m return, lagged → no look-ahead
        sig      <- sign(cum12)
        lag_vol  <- dplyr::lag(vol12_current, 1L)

        # Vol-scaled position, NA → 0 (treat as flat during warm-up)
        pos <- sig * pmin(vt / lag_vol, ml)
        pos <- ifelse(is.na(pos), 0, pos)

        df[[paste0("sig_",  asset)]] <- sig
        df[[paste0("vol_",  asset)]] <- lag_vol
        df[[paste0("pos_",  asset)]] <- pos
      }

      df
    }),


    # ── Portfolios: 3 strategy variants ────────────────────────────────────────
    targets::tar_target(mf_portfolios, {
      library(dplyr)

      cost <- mf_params$cost_monthly

      mf_signals |>
        dplyr::mutate(
          # Excess returns per asset (total return minus risk-free)
          exc_SPY = SPY - RF,
          exc_TLT = TLT - RF,
          exc_GLD = GLD - RF,
          exc_DBC = DBC - RF,

          # 1. Long-only TS-mom: go long at 1× if signal positive, else RF.
          #    Equal-weight across 4 assets (0.25 each when all signals positive).
          ret_lo = RF + (
            pmax(sig_SPY, 0) * exc_SPY +
            pmax(sig_TLT, 0) * exc_TLT +
            pmax(sig_GLD, 0) * exc_GLD +
            pmax(sig_DBC, 0) * exc_DBC
          ) / 4 - cost,

          # 2. Long-short vol-targeted TS-mom (MOP 2012 canonical).
          #    pos_* ∈ [-max_leverage, max_leverage]; equal-weight combination.
          ret_ls = RF + (
            pos_SPY * exc_SPY +
            pos_TLT * exc_TLT +
            pos_GLD * exc_GLD +
            pos_DBC * exc_DBC
          ) / 4 - cost,

          # 3. Equal-weight buy-and-hold benchmark (no cost — passive)
          ret_ew = (SPY + TLT + GLD + DBC) / 4,

          # Cumulative wealth indices
          cum_lo = cumprod(1 + ret_lo),
          cum_ls = cumprod(1 + ret_ls),
          cum_ew = cumprod(1 + ret_ew)
        ) |>
        dplyr::filter(!is.na(ret_lo))
    }),


    # ── Metrics: performance table (Full / Training / OOS) ─────────────────────
    # #645: OOS is bounded at bt_partitions$macro$test_end (R/plan_partitions.R)
    # so it no longer silently swallows the sealed Validation partition on
    # every tar_make(). Managed futures uses SPY+TLT+GLD+DBC -- the macro
    # asset class -- so bt_partitions$macro is the matching partition set.
    # Training keeps its original pre-2010 definition (narrower than
    # canonical Training, a comparability wart but not a seal breach --
    # see #645) and is unaffected by this bound.
    targets::tar_target(mf_metrics, {
      library(dplyr)

      oos      <- mf_params$oos_start
      test_end <- bt_partitions$macro$test_end

      # #677 slice 2: sharpe now uses the canonical risk-free-adjusted
      # helper (R/utils_metrics.R::sharpe_ratio_rf()) instead of bare
      # cagr/vol -- this file was one of the "no rf deducted" family
      # (implied rf of exactly 0.00%, a formula signature -- see #677).
      # mf_portfolios$RF is already joined onto every row (mf_data's
      # inner_join with FF5's RF), so no new join is needed here.
      calc_metrics <- function(ret_vec, rf_vec, date_vec, strategy_name, period_name) {
        keep     <- !is.na(ret_vec)
        ret_vec  <- ret_vec[keep]
        rf_vec   <- rf_vec[keep]
        date_vec <- date_vec[keep]
        if (length(ret_vec) < 12L) return(NULL)
        years   <- length(ret_vec) / 12
        cum_ret <- prod(1 + ret_vec)
        cagr    <- (cum_ret^(1 / years) - 1) * 100
        vol     <- stats::sd(ret_vec) * sqrt(12) * 100
        sr      <- sharpe_ratio_rf(ret_vec, rf_vec, periods_per_year = 12L)
        sharpe  <- sr$sharpe
        cum_w   <- cumprod(1 + ret_vec)
        dd      <- (cum_w - cummax(cum_w)) / cummax(cum_w)
        max_dd  <- min(dd) * 100
        calmar  <- ifelse(abs(max_dd) > 0, cagr / abs(max_dd), NA_real_)
        tibble::tibble(
          strategy     = strategy_name,
          period       = period_name,
          n_months     = length(ret_vec),
          cagr         = round(cagr, 2),
          vol          = round(vol, 2),
          sharpe       = round(sharpe, 3),
          max_dd       = round(max_dd, 2),
          calmar       = round(calmar, 3),
          window_start = min(date_vec),
          window_end   = max(date_vec)
        )
      }

      strategies <- list(
        lo = mf_portfolios$ret_lo,
        ls = mf_portfolios$ret_ls,
        ew = mf_portfolios$ret_ew
      )
      labels <- c(
        lo = "Long-Only TS-Mom (12m signal, equal-weight)",
        ls = "Long-Short TS-Mom (MOP 2012, vol-targeted)",
        ew = "Equal-Weight Benchmark (SPY+TLT+GLD+DBC)"
      )
      dates  <- mf_portfolios$date
      rf_all <- mf_portfolios$RF

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


    # ── Underperformance periods: trend-following drought + prior context ───────
    # Per underperformance-prior rule: managed futures had a severe 7-year
    # underperformance period 2013-2019 (the "trend-following drought") during
    # the low-vol, central-bank-suppressed-dispersion era. MOP 2012 also
    # documents drawdowns across the longer 1900-2011 history. This target
    # shows period-by-period results so the reader interprets OOS results
    # IN CONTEXT of historically documented drawdowns before evaluating them.
    targets::tar_target(mf_underperformance_periods, {
      library(dplyr)

      dates <- mf_portfolios$date
      rls   <- mf_portfolios$ret_ls   # canonical long-short MOP strategy
      rew   <- mf_portfolios$ret_ew   # benchmark
      rf    <- mf_portfolios$RF       # #677 slice 2: rf-adjusted sharpe below

      # Trend-following era breakpoints (based on documented performance regimes)
      p_pre2010  <- dates < as.Date("2010-01-01")
      p_drought  <- dates >= as.Date("2010-01-01") & dates <= as.Date("2019-12-31")
      p_covid    <- dates >= as.Date("2020-01-01") & dates <= as.Date("2022-12-31")
      p_recent   <- dates >= as.Date("2023-01-01")

      # #677 slice 2: sharpe now uses sharpe_ratio_rf() (R/utils_metrics.R)
      # instead of bare cagr/vol -- see calc_metrics() above for the same fix
      # applied to mf_metrics.
      calc_row <- function(ret_vec, rf_vec, period_label, strategy_name) {
        keep    <- !is.na(ret_vec)
        ret_vec <- ret_vec[keep]
        rf_vec  <- rf_vec[keep]
        if (length(ret_vec) < 6L) return(NULL)
        years  <- length(ret_vec) / 12
        cagr   <- (prod(1 + ret_vec)^(1 / years) - 1) * 100
        vol    <- stats::sd(ret_vec) * sqrt(12) * 100
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
        calc_row(rls[p_pre2010], rf[p_pre2010], "Pre-2010 (GFC, high dispersion)",       "TS-Mom L/S"),
        calc_row(rew[p_pre2010], rf[p_pre2010], "Pre-2010 (GFC, high dispersion)",       "EW Benchmark"),
        calc_row(rls[p_drought], rf[p_drought], "2010-2019 (trend-following drought)",    "TS-Mom L/S"),
        calc_row(rew[p_drought], rf[p_drought], "2010-2019 (trend-following drought)",    "EW Benchmark"),
        calc_row(rls[p_covid],   rf[p_covid],   "2020-2022 (COVID + rates surge)",        "TS-Mom L/S"),
        calc_row(rew[p_covid],   rf[p_covid],   "2020-2022 (COVID + rates surge)",        "EW Benchmark"),
        calc_row(rls[p_recent],  rf[p_recent],  "2023+ (recent period)",                  "TS-Mom L/S"),
        calc_row(rew[p_recent],  rf[p_recent],  "2023+ (recent period)",                  "EW Benchmark")
      )
    }),


    # ── Caption: dynamic summary ──────────────────────────────────────────────
    targets::tar_target(mf_caption, {
      library(dplyr)

      oos    <- mf_params$oos_start
      oos_yr <- format(oos, "%Y")

      ls_oos  <- mf_metrics |>
        dplyr::filter(strategy == "Long-Short TS-Mom (MOP 2012, vol-targeted)",
                      period == "OOS")
      ls_full <- mf_metrics |>
        dplyr::filter(strategy == "Long-Short TS-Mom (MOP 2012, vol-targeted)",
                      period == "Full")
      ew_oos  <- mf_metrics |>
        dplyr::filter(strategy == "Equal-Weight Benchmark (SPY+TLT+GLD+DBC)",
                      period == "OOS")

      ls_oos_sharpe  <- if (nrow(ls_oos) > 0)  round(ls_oos$sharpe[1], 3)  else NA
      ew_oos_sharpe  <- if (nrow(ew_oos) > 0)  round(ew_oos$sharpe[1], 3)  else NA
      ls_full_cagr   <- if (nrow(ls_full) > 0)  round(ls_full$cagr[1], 2)   else NA
      ls_full_sharpe <- if (nrow(ls_full) > 0)  round(ls_full$sharpe[1], 3) else NA

      drought_ls  <- mf_underperformance_periods |>
        dplyr::filter(period == "2010-2019 (trend-following drought)",
                      strategy == "TS-Mom L/S")
      drought_str <- if (nrow(drought_ls) > 0) {
        paste0("Drought period (2010-2019): Sharpe ", round(drought_ls$sharpe[1], 3), ". ")
      } else ""

      n_assets <- length(mf_params$vol_target)

      paste0(
        "**Cross-Asset Time-Series Momentum — Managed Futures v0 (#427).** ",
        "MOP 2012 strategy across 4 ETF proxies: SPY (equity), TLT (bonds), ",
        "GLD (gold), DBC (commodities). ",
        "Signal: sign of trailing 12-month return, lagged 1 month (no look-ahead). ",
        "Vol-targeting: each position scaled to 10% annualized vol, capped at 3×. ",
        "Full-period: CAGR ", ls_full_cagr, "%, Sharpe ", ls_full_sharpe, ". ",
        "OOS (", oos_yr, "+): TS-Mom L/S Sharpe ", ls_oos_sharpe,
        " vs equal-weight ", ew_oos_sharpe, ". ",
        drought_str,
        "Underperformance-prior context (Swedroe): managed futures had a documented ",
        "7-year drought 2010-2019 driven by central-bank vol suppression; ",
        "this is within the historically documented range for trend-following strategies. ",
        "10 bps/month cost for ETF proxies (real futures ~20 bps including roll). ",
        "Cross-geography pervasiveness: MOP 2012 documents TS-mom across 58 instruments ",
        "in 4 asset classes back to 1900s (passes the bar). ",
        "v0 proxy note: ", mf_params$proxy_note
      )
    })

  )
}
