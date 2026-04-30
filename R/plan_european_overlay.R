# Plan: European Equity RSC Overlay (#58)
#
# Test whether US VIX-based Risk State Classification (RSC) regime signals
# work better for European equity ETFs than for SPY.
#
# Rationale: US-EU vol correlation ~0.85 in crises.  Approach B (pragmatic):
# apply the EXISTING US VIX regime (rsc_regime) directly to European ETFs.
# This avoids a separate parameter fit, making it a genuine out-of-sample test
# of the RSC signals' generalisability.
#
# Upstream dependencies: rsc_regime, rsc_thresholds, rsc_params (plan_risk_state.R)
#
# Naming convention: eur_*
# Total targets: 7

plan_european_overlay <- function() {
  list(

    # ── Parameters ──────────────────────────────────────────────────────
    targets::tar_target(eur_params, {
      list(
        eu_tickers      = c("FEZ", "VGK", "EWG", "EWQ"),
        eu_ticker_labels = c(
          FEZ = "Euro Stoxx 50",
          VGK = "FTSE Europe",
          EWG = "Germany",
          EWQ = "France"
        ),
        # Same RSC exposure scaling as plan_risk_state.R
        exposure_benign   = 1.00,
        exposure_cautious = 0.50,
        exposure_hostile  = 0.10,
        oos_start         = as.Date("2020-01-01")
      )
    }),


    # ── Data: fetch European ETF returns + join RSC regime ───────────────
    targets::tar_target(eur_daily, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      # rsc_regime already has: date, regime, exposure, rf_lag, spy_ret etc.
      # We only need date, regime, exposure, rf_lag from it.
      regime_daily <- rsc_regime |>
        select(date, regime, exposure, rf_lag) |>
        arrange(date)

      # Fetch each European ETF and join regime
      purrr::map_dfr(eur_params$eu_tickers, function(tkr) {
        tryCatch({
          hd_ohlcv(tkr) |>
            mutate(date = as.Date(date)) |>
            arrange(date) |>
            mutate(
              eu_ret = adjusted / lag(adjusted) - 1,
              ticker = tkr,
              label  = eur_params$eu_ticker_labels[tkr]
            ) |>
            filter(!is.na(eu_ret)) |>
            select(date, ticker, label, eu_ret) |>
            inner_join(regime_daily, by = "date")
        }, error = function(e) {
          cli::cli_warn("Failed to fetch {tkr}: {conditionMessage(e)}")
          NULL
        })
      })
    }),


    # ── Results: overlay metrics per EU ticker ───────────────────────────
    targets::tar_target(eur_results, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      calc_metrics <- function(ret_vec, label, strategy_name, ticker) {
        ret_vec <- ret_vec[!is.na(ret_vec)]
        if (length(ret_vec) < 20) return(NULL)
        years  <- length(ret_vec) / 252
        cum    <- prod(1 + ret_vec)
        cum_dd <- cumprod(1 + ret_vec)
        hac    <- hd_hac_sharpe(ret_vec)
        tibble::tibble(
          ticker       = ticker,
          asset        = eur_params$eu_ticker_labels[ticker],
          strategy     = strategy_name,
          period       = label,
          cagr         = round((cum^(1 / years) - 1) * 100, 2),
          vol          = round(sd(ret_vec) * sqrt(252) * 100, 2),
          max_dd       = round(min((cum_dd - cummax(cum_dd)) /
                                     cummax(cum_dd)) * 100, 2),
          hac_tstat    = round(hac$hac_tstat, 3),
          hac_sharpe   = round(hac$naive_sharpe, 3)
        )
      }

      oos <- eur_params$oos_start

      purrr::map_dfr(eur_params$eu_tickers, function(tkr) {
        d <- eur_daily |>
          filter(ticker == tkr, !is.na(eu_ret), !is.na(exposure)) |>
          arrange(date) |>
          mutate(
            rf_use     = ifelse(is.na(rf_lag), 0, rf_lag),
            ret_overlay = exposure * eu_ret + (1 - exposure) * rf_use,
            ret_buyhold = eu_ret
          )

        if (nrow(d) < 20) return(NULL)

        bind_rows(
          calc_metrics(d$ret_buyhold,                          "Full",     "Buy & Hold", tkr),
          calc_metrics(d$ret_overlay,                          "Full",     "RSC Overlay", tkr),
          calc_metrics(d$ret_buyhold[d$date < oos],            "Training", "Buy & Hold", tkr),
          calc_metrics(d$ret_overlay[d$date < oos],            "Training", "RSC Overlay", tkr),
          calc_metrics(d$ret_buyhold[d$date >= oos],           "OOS",      "Buy & Hold", tkr),
          calc_metrics(d$ret_overlay[d$date >= oos],           "OOS",      "RSC Overlay", tkr)
        )
      })
    }),


    # ── Fama-French regression: falsification for each EU ticker ─────────
    targets::tar_target(eur_ff_regression, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      # Fetch FF5 + Momentum daily factors (same as plan_falsification.R)
      ff5 <- hd_factors(dataset = "FF5", frequency = "daily") |>
        filter(factor_name != "RF") |>
        mutate(value = value / 100) |>
        select(date, factor_name, value)

      mom <- hd_factors(dataset = "Mom", frequency = "daily") |>
        mutate(value = value / 100) |>
        select(date, factor_name, value)

      factors_daily <- bind_rows(ff5, mom)

      rf_daily <- hd_factors(dataset = "FF5", frequency = "daily") |>
        filter(factor_name == "RF") |>
        mutate(rf = value / 100) |>
        select(date, rf)

      purrr::map_dfr(eur_params$eu_tickers, function(tkr) {
        d <- eur_daily |>
          filter(ticker == tkr, !is.na(eu_ret), !is.na(exposure)) |>
          arrange(date) |>
          mutate(
            rf_use      = ifelse(is.na(rf_lag), 0, rf_lag),
            ret_overlay = exposure * eu_ret + (1 - exposure) * rf_use
          ) |>
          select(date, strategy_ret = ret_overlay)

        tryCatch({
          res <- hd_factor_null_test(
            strategy_daily = d,
            rf_daily       = rf_daily,
            factors_daily  = factors_daily
          )
          tibble::tibble(
            ticker       = tkr,
            asset        = eur_params$eu_ticker_labels[tkr],
            alpha_annual = round(res$alpha_annual * 100, 2),
            alpha_tstat  = round(res$alpha_tstat_hac, 3),
            r_squared    = round(res$r_squared * 100, 1)
          )
        }, error = function(e) {
          cli::cli_warn("FF regression failed for {tkr}: {conditionMessage(e)}")
          NULL
        })
      })
    }),


    # ── Comparison: US (SPY) vs European overlays ────────────────────────
    targets::tar_target(eur_comparison, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      # SPY overlay OOS metrics from rsc_portfolio (Full period)
      spy_oos <- rsc_portfolio |>
        filter(date >= eur_params$oos_start,
               !is.na(ret_strategy), !is.na(ret_buyhold)) |>
        (function(d) {
          years <- nrow(d) / 252
          bind_rows(
            tibble::tibble(
              ticker = "SPY", asset = "S&P 500 (US)", strategy = "Buy & Hold",
              period = "OOS",
              cagr   = round((prod(1 + d$ret_buyhold)^(1 / years) - 1) * 100, 2),
              vol    = round(sd(d$ret_buyhold) * sqrt(252) * 100, 2),
              max_dd = round(min((cumprod(1 + d$ret_buyhold) - cummax(cumprod(1 + d$ret_buyhold))) /
                                   cummax(cumprod(1 + d$ret_buyhold))) * 100, 2),
              hac_sharpe = round(hd_hac_sharpe(d$ret_buyhold)$naive_sharpe, 3)
            ),
            tibble::tibble(
              ticker = "SPY", asset = "S&P 500 (US)", strategy = "RSC Overlay",
              period = "OOS",
              cagr   = round((prod(1 + d$ret_strategy)^(1 / years) - 1) * 100, 2),
              vol    = round(sd(d$ret_strategy) * sqrt(252) * 100, 2),
              max_dd = round(min((cumprod(1 + d$ret_strategy) - cummax(cumprod(1 + d$ret_strategy))) /
                                   cummax(cumprod(1 + d$ret_strategy))) * 100, 2),
              hac_sharpe = round(hd_hac_sharpe(d$ret_strategy)$naive_sharpe, 3)
            )
          )
        })()

      eur_oos <- eur_results |>
        filter(period == "OOS") |>
        select(ticker, asset, strategy, period, cagr, vol, max_dd, hac_sharpe)

      bind_rows(spy_oos, eur_oos) |>
        arrange(ticker, strategy)
    }),


    # ── Caption: dynamic summary of findings ────────────────────────────
    targets::tar_target(eur_caption, {
      library(dplyr)

      # Which EU tickers improve in OOS with overlay?
      oos <- eur_results |> filter(period == "OOS")

      bh_sharpe <- oos |>
        filter(strategy == "Buy & Hold") |>
        select(ticker, asset, sharpe_bh = hac_sharpe)

      ov_sharpe <- oos |>
        filter(strategy == "RSC Overlay") |>
        select(ticker, sharpe_ov = hac_sharpe)

      comparison <- bh_sharpe |>
        inner_join(ov_sharpe, by = "ticker") |>
        mutate(delta = sharpe_ov - sharpe_bh)

      improved <- comparison |> filter(delta > 0.02)
      hurt     <- comparison |> filter(delta < -0.02)

      oos_start_yr <- format(eur_params$oos_start, "%Y")
      n_tickers    <- length(eur_params$eu_tickers)

      paste0(
        "**European equity RSC overlay (#58): US VIX regime applied to ",
        n_tickers, " European ETFs.** ",
        "Same RSC thresholds as SPY overlay; t+1 execution enforced. ",
        "OOS period: ", oos_start_yr, " onward. ",
        if (nrow(improved) > 0) {
          paste0(
            "Overlay improves Sharpe for: ",
            paste(improved$asset, collapse = ", "), ". "
          )
        } else {
          "No European ETF benefits from the US VIX overlay in OOS. "
        },
        if (nrow(hurt) > 0) {
          paste0(
            "Overlay hurts Sharpe for: ",
            paste(hurt$asset, collapse = ", "), ". "
          )
        } else {
          ""
        },
        "US-EU vol correlation is ~0.85 in crises, but the RSC thresholds ",
        "were trained on US data only — transfer may be imperfect for ",
        "European-specific vol regimes (ECB, EUR/USD)."
      )
    })

  )
}
