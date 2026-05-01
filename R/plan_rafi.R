# Plan: Synthetic RAFI / Research Affiliates Fundamental Index (#75)
#
# Tests the Fama-French critique that RAFI is a disguised value + size tilt.
# We have no per-stock fundamentals, so we construct RAFI-like portfolios
# directly from Fama-French factor returns.  Four synthetic strategies:
#
#   rafi_composite  — 50% HML + 30% SMB + 20% Mom (mimics RAFI weighting rationale)
#   revenue_proxy   — 100% HML  (revenue/price = pure value tilt)
#   equal_weight    — 100% SMB  (equal-weight overweights small caps)
#   benchmark       — Mkt-RF + RF  (cap-weighted market, SPY proxy)
#
# Falsification: if RAFI composite has R² > 50% on FF5+Mom and alpha ≈ 0,
# the strategy is factor exposure, not a genuine premium.
#
# Upstream dependencies: none (fetches factors directly via hd_factors)
# Naming convention: rafi_*
# Total targets: 7

plan_rafi <- function() {
  list(

    # ── Parameters ──────────────────────────────────────────────────────────
    targets::tar_target(rafi_params, {
      list(
        # Synthetic RAFI weights on FF factors (monthly, decimal form)
        rafi_composite = c(HML = 0.50, SMB = 0.30, Mom = 0.20),
        revenue_proxy  = c(HML = 1.0),
        equal_weight   = c(SMB = 1.0),

        # 20 bps monthly cost for monthly rebalancing
        cost_per_rebalance = 0.002,

        # OOS start: post-2010 (RAFI products widely known by then)
        oos_start = as.Date("2010-01-01")
      )
    }),


    # ── Data: monthly FF5 + Momentum factors ────────────────────────────────
    targets::tar_target(rafi_data, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      ff5 <- hd_factors(dataset = "FF5", frequency = "monthly") |>
        mutate(date = as.Date(date))

      mom <- hd_factors(dataset = "Mom", frequency = "monthly") |>
        mutate(date = as.Date(date)) |>
        filter(factor_name == "Mom")

      # Pivot FF5 wide (includes RF)
      ff5_wide <- ff5 |>
        tidyr::pivot_wider(
          id_cols     = "date",
          names_from  = "factor_name",
          values_from = "value"
        )

      # Join momentum
      mom_wide <- mom |>
        tidyr::pivot_wider(
          id_cols     = "date",
          names_from  = "factor_name",
          values_from = "value"
        )

      data <- dplyr::inner_join(ff5_wide, mom_wide, by = "date") |>
        dplyr::rename(Mkt_RF = `Mkt-RF`) |>
        dplyr::arrange(date)

      # Factor values are in PERCENTAGE (e.g., 1.5 = 1.5%); divide by 100
      numeric_cols <- setdiff(names(data), "date")
      for (col in numeric_cols) {
        data[[col]] <- data[[col]] / 100
      }

      data
    }),


    # ── Portfolios: construct 4 synthetic strategies ─────────────────────────
    targets::tar_target(rafi_portfolios, {
      library(dplyr)

      cost <- rafi_params$cost_per_rebalance

      w_rc <- rafi_params$rafi_composite   # c(HML=0.5, SMB=0.3, Mom=0.2)
      w_rv <- rafi_params$revenue_proxy    # c(HML=1.0)
      w_ew <- rafi_params$equal_weight     # c(SMB=1.0)

      d <- rafi_data |>
        mutate(
          # RAFI composite: RF + factor overlay - cost
          ret_rafi     = RF +
            w_rc["HML"] * HML +
            w_rc["SMB"] * SMB +
            w_rc["Mom"] * Mom -
            cost,

          # Revenue proxy: RF + pure HML - cost
          ret_revenue  = RF +
            w_rv["HML"] * HML -
            cost,

          # Equal-weight proxy: RF + pure SMB - cost
          ret_ew       = RF +
            w_ew["SMB"] * SMB -
            cost,

          # Benchmark: cap-weighted market (Mkt-RF + RF, no cost)
          ret_market   = Mkt_RF + RF,

          # Cumulative wealth indices (start at 1)
          cum_rafi    = cumprod(1 + ret_rafi),
          cum_revenue = cumprod(1 + ret_revenue),
          cum_ew      = cumprod(1 + ret_ew),
          cum_market  = cumprod(1 + ret_market)
        ) |>
        select(date, RF, Mkt_RF, HML, SMB, Mom,
               ret_rafi, ret_revenue, ret_ew, ret_market,
               cum_rafi, cum_revenue, cum_ew, cum_market)

      d
    }),


    # ── Metrics: performance table across periods ────────────────────────────
    targets::tar_target(rafi_metrics, {
      library(dplyr)

      oos <- rafi_params$oos_start

      calc_metrics <- function(ret_vec, strategy_name, period_name) {
        ret_vec <- ret_vec[!is.na(ret_vec)]
        if (length(ret_vec) < 12L) return(NULL)

        # Monthly annualisation
        years    <- length(ret_vec) / 12
        cum_ret  <- prod(1 + ret_vec)
        cagr     <- (cum_ret^(1 / years) - 1) * 100
        vol      <- sd(ret_vec) * sqrt(12) * 100
        sharpe   <- ifelse(vol > 0, (cagr / 100) / (vol / 100), NA_real_)

        cum_w    <- cumprod(1 + ret_vec)
        drawdown <- (cum_w - cummax(cum_w)) / cummax(cum_w)
        max_dd   <- min(drawdown) * 100
        calmar   <- ifelse(abs(max_dd) > 0, cagr / abs(max_dd), NA_real_)

        tibble::tibble(
          strategy = strategy_name,
          period   = period_name,
          n_months = length(ret_vec),
          cagr     = round(cagr, 2),
          vol      = round(vol, 2),
          sharpe   = round(sharpe, 3),
          max_dd   = round(max_dd, 2),
          calmar   = round(calmar, 3)
        )
      }

      strategies <- list(
        rafi     = rafi_portfolios$ret_rafi,
        revenue  = rafi_portfolios$ret_revenue,
        ew       = rafi_portfolios$ret_ew,
        market   = rafi_portfolios$ret_market
      )

      labels <- c(
        rafi    = "RAFI Composite (50% HML + 30% SMB + 20% Mom)",
        revenue = "Revenue Proxy (100% HML)",
        ew      = "Equal-Weight Proxy (100% SMB)",
        market  = "Benchmark (Cap-Weighted Market)"
      )

      dates  <- rafi_portfolios$date
      is_oos <- dates >= oos

      rows <- list()
      for (nm in names(strategies)) {
        ret_full  <- strategies[[nm]]
        ret_train <- strategies[[nm]][!is_oos]
        ret_oos   <- strategies[[nm]][is_oos]

        rows <- c(rows,
          list(calc_metrics(ret_full,  labels[nm], "Full")),
          list(calc_metrics(ret_train, labels[nm], "Training")),
          list(calc_metrics(ret_oos,   labels[nm], "OOS"))
        )
      }

      dplyr::bind_rows(Filter(Negate(is.null), rows))
    }),


    # ── FF regression: falsification ─────────────────────────────────────────
    targets::tar_target(rafi_ff_regression, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      # Build long-form factors for hd_factor_null_test
      # hd_factor_null_test expects: date, factor_name, value (decimal)
      # and rf_daily: date, rf; strategy_daily: date, strategy_ret
      # We already have rafi_data in decimal form

      rf_monthly <- rafi_data |>
        select(date, rf = RF)

      factors_long <- rafi_data |>
        select(date, Mkt_RF, SMB, HML, RMW, CMA, Mom) |>
        tidyr::pivot_longer(
          cols      = -date,
          names_to  = "factor_name",
          values_to = "value"
        )

      strategies <- list(
        rafi_composite = tibble::tibble(
          date         = rafi_portfolios$date,
          strategy_ret = rafi_portfolios$ret_rafi
        ),
        revenue_proxy  = tibble::tibble(
          date         = rafi_portfolios$date,
          strategy_ret = rafi_portfolios$ret_revenue
        )
      )

      labels <- c(
        rafi_composite = "RAFI Composite",
        revenue_proxy  = "Revenue Proxy (HML)"
      )

      purrr::map_dfr(names(strategies), function(nm) {
        tryCatch({
          res <- hd_factor_null_test(
            strategy_daily = strategies[[nm]],
            rf_daily       = rf_monthly,
            factors_daily  = factors_long
          )
          tibble::tibble(
            strategy     = labels[nm],
            alpha_annual = round(res$alpha_annual * 100, 2),
            alpha_tstat  = round(res$alpha_tstat_hac, 3),
            r_squared    = round(res$r_squared * 100, 1)
          )
        }, error = function(e) {
          cli::cli_warn("FF regression failed for {nm}: {conditionMessage(e)}")
          NULL
        })
      })
    }),


    # ── Decay: RAFI premium early vs late ────────────────────────────────────
    targets::tar_target(rafi_decay, {
      library(dplyr)

      dates     <- rafi_portfolios$date
      split_date <- as.Date("2000-01-01")

      calc_sharpe <- function(ret_vec, period_label, strategy_name) {
        ret_vec <- ret_vec[!is.na(ret_vec)]
        if (length(ret_vec) < 12L) return(NULL)
        years  <- length(ret_vec) / 12
        cagr   <- (prod(1 + ret_vec)^(1 / years) - 1) * 100
        vol    <- sd(ret_vec) * sqrt(12) * 100
        sharpe <- ifelse(vol > 0, cagr / vol, NA_real_)
        tibble::tibble(
          strategy = strategy_name,
          period   = period_label,
          n_months = length(ret_vec),
          cagr     = round(cagr, 2),
          vol      = round(vol, 2),
          sharpe   = round(sharpe, 3)
        )
      }

      is_early <- dates < split_date
      is_late  <- dates >= split_date

      dplyr::bind_rows(
        calc_sharpe(rafi_portfolios$ret_rafi[is_early],    "Pre-2000",  "RAFI Composite"),
        calc_sharpe(rafi_portfolios$ret_rafi[is_late],     "2000+",     "RAFI Composite"),
        calc_sharpe(rafi_portfolios$ret_revenue[is_early], "Pre-2000",  "Revenue Proxy"),
        calc_sharpe(rafi_portfolios$ret_revenue[is_late],  "2000+",     "Revenue Proxy"),
        calc_sharpe(rafi_portfolios$ret_ew[is_early],      "Pre-2000",  "Equal-Weight Proxy"),
        calc_sharpe(rafi_portfolios$ret_ew[is_late],       "2000+",     "Equal-Weight Proxy"),
        calc_sharpe(rafi_portfolios$ret_market[is_early],  "Pre-2000",  "Benchmark"),
        calc_sharpe(rafi_portfolios$ret_market[is_late],   "2000+",     "Benchmark")
      )
    }),


    # ── Caption: dynamic summary ──────────────────────────────────────────────
    targets::tar_target(rafi_caption, {
      library(dplyr)

      oos     <- rafi_params$oos_start
      oos_yr  <- format(oos, "%Y")

      rafi_oos <- rafi_metrics |>
        filter(
          strategy == "RAFI Composite (50% HML + 30% SMB + 20% Mom)",
          period == "OOS"
        )

      mkt_oos <- rafi_metrics |>
        filter(strategy == "Benchmark (Cap-Weighted Market)", period == "OOS")

      rafi_sharpe  <- if (nrow(rafi_oos) > 0) round(rafi_oos$sharpe[1], 3) else NA
      mkt_sharpe   <- if (nrow(mkt_oos) > 0)  round(mkt_oos$sharpe[1], 3) else NA

      # FF regression verdict
      rc_reg <- rafi_ff_regression |>
        filter(strategy == "RAFI Composite")

      r2_val <- if (nrow(rc_reg) > 0) rc_reg$r_squared[1] else NA
      alpha_t <- if (nrow(rc_reg) > 0) rc_reg$alpha_tstat[1] else NA

      verdict <- if (!is.na(r2_val) && !is.na(alpha_t)) {
        if (r2_val > 50 && abs(alpha_t) < 2) {
          "confirms Fama-French critique: RAFI composite is pure factor exposure (no genuine alpha)"
        } else if (r2_val > 50 && abs(alpha_t) >= 2) {
          "mixed result: high factor loading but alpha t-stat suggestive"
        } else {
          "R\u00b2 below 50%: RAFI may carry additional premium beyond FF factors"
        }
      } else {
        "regression inconclusive"
      }

      # Decay summary
      late_sharpe <- rafi_decay |>
        filter(strategy == "RAFI Composite", period == "2000+")
      early_sharpe <- rafi_decay |>
        filter(strategy == "RAFI Composite", period == "Pre-2000")

      decay_str <- if (nrow(late_sharpe) > 0 && nrow(early_sharpe) > 0) {
        es <- round(early_sharpe$sharpe[1], 3)
        ls <- round(late_sharpe$sharpe[1], 3)
        paste0(
          "RAFI Sharpe: ", es, " (pre-2000) vs ", ls, " (2000+). ",
          if (ls < es) "Premium has decayed since 2000, consistent with value crowding. "
          else "Premium has NOT decayed — early period was weaker. "
        )
      } else {
        ""
      }

      paste0(
        "**Synthetic RAFI / fundamental-index strategy (#75): FF factor decomposition.** ",
        "Four strategies constructed from monthly FF5+Mom returns: ",
        "RAFI Composite (50% HML, 30% SMB, 20% Mom), Revenue Proxy (100% HML), ",
        "Equal-Weight Proxy (100% SMB), and Cap-Weighted Benchmark. ",
        "OOS period: ", oos_yr, " onward. ",
        "OOS Sharpe: RAFI ", rafi_sharpe, " vs market ", mkt_sharpe, ". ",
        "FF5+Mom regression R\u00b2 = ", r2_val, "%, alpha t-stat = ", alpha_t, ": ",
        verdict, ". ",
        decay_str,
        "20 bps monthly rebalancing cost applied to all long-only factor strategies."
      )
    })

  )
}
