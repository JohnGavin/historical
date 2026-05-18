# Plan: European Equity RSC Overlay (#58)
#
# Test whether US VIX-based Risk State Classification (RSC) regime signals
# work better for European equity ETFs than for SPY.
#
# Approach A (pragmatic): apply EXISTING US VIX regime directly to EU ETFs.
# Approach B (native): use ECB CISS equity stress sub-index as European
#   vol proxy for regime classification (r=0.75 with VIX, #88).
#
# Upstream dependencies:
#   - rsc_regime, rsc_thresholds, rsc_params (plan_risk_state.R)
#   - ecb_raw (plan_ecb.R) — for CISS-based regime
#
# Naming convention: eur_*
# Total targets: 9

plan_european_overlay <- function() {
  list(

    # ── Parameters ──────────────────────────────────────────────────────
    targets::tar_target(eur_params, {
      list(
        eu_tickers      = c("EXSA.DE", "FEZ", "VGK", "EWG", "EWQ"),
        eu_ticker_labels = c(
          EXSA.DE = "STOXX Europe 600",
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
      library(dplyr)

      # rsc_regime already has: date, regime, exposure, rf_lag, spy_ret etc.
      # We only need date, regime, exposure, rf_lag from it.
      regime_daily <- rsc_regime |>
        mutate(date = as.Date(date)) |>
        select(date, regime, exposure, rf_lag) |>
        arrange(date)

      # Fetch each European ETF via Yahoo Finance chart API
      # (Not in HuggingFace equity dataset; quantmod not in nix shell;
      #  v7/download endpoint returns 401)
      fetch_yahoo_chart <- function(tkr, from = "2000-01-01") {
        from_ts <- as.integer(as.POSIXct(from, tz = "UTC"))
        to_ts   <- as.integer(Sys.time())
        url <- sprintf(
          "https://query1.finance.yahoo.com/v8/finance/chart/%s?period1=%d&period2=%d&interval=1d",
          utils::URLencode(tkr), from_ts, to_ts
        )
        resp <- tryCatch(
          jsonlite::fromJSON(url, simplifyVector = FALSE),
          error = function(e) NULL
        )
        if (is.null(resp)) return(NULL)
        result <- resp$chart$result[[1]]
        if (is.null(result)) return(NULL)
        ts_data <- unlist(result$timestamp)
        adj     <- result$indicators$adjclose[[1]]$adjclose
        adj_close <- as.numeric(unlist(adj))
        if (is.null(adj_close) || all(is.na(adj_close))) {
          # Fallback to regular close
          adj_close <- as.numeric(unlist(result$indicators$quote[[1]]$close))
          if (is.null(adj_close)) return(NULL)
        }
        # Yahoo may return mismatched lengths — truncate to shorter
        n <- min(length(ts_data), length(adj_close))
        tibble::tibble(
          date  = as.Date(as.POSIXct(ts_data[seq_len(n)], origin = "1970-01-01", tz = "UTC")),
          close = as.numeric(adj_close[seq_len(n)])
        ) |> dplyr::filter(!is.na(close))
      }

      purrr::map_dfr(eur_params$eu_tickers, function(tkr) {
        tryCatch({
          Sys.sleep(1)  # rate limit
          raw <- fetch_yahoo_chart(tkr)
          if (is.null(raw) || nrow(raw) < 20) {
            cli::cli_warn("No data for {tkr}")
            return(NULL)
          }
          raw |>
            dplyr::arrange(date) |>
            dplyr::mutate(
              eu_ret = close / dplyr::lag(close) - 1,
              ticker = tkr,
              label  = eur_params$eu_ticker_labels[tkr]
            ) |>
            dplyr::filter(!is.na(eu_ret)) |>
            dplyr::select(date, ticker, label, eu_ret) |>
            dplyr::inner_join(regime_daily, by = "date")
        }, error = function(e) {
          cli::cli_warn("Failed to fetch {tkr}: {conditionMessage(e)}")
          NULL
        })
      })
    }),


    # ── Results: overlay metrics per EU ticker ───────────────────────────
    targets::tar_target(eur_results, {
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
      library(dplyr)

      # Fetch FF5 + Momentum daily factors (same as plan_falsification.R)
      ff5 <- hd_factors(dataset = "FF5", frequency = "daily") |>
        filter(factor_name != "RF") |>
        mutate(date = as.Date(date), value = value / 100) |>
        select(date, factor_name, value)

      mom <- hd_factors(dataset = "Mom", frequency = "daily") |>
        mutate(date = as.Date(date), value = value / 100) |>
        select(date, factor_name, value)

      factors_daily <- bind_rows(ff5, mom)

      rf_daily <- hd_factors(dataset = "FF5", frequency = "daily") |>
        filter(factor_name == "RF") |>
        mutate(date = as.Date(date), rf = value / 100) |>
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
      library(dplyr)

      # SPY overlay OOS metrics from rsc_portfolio (Full period)
      spy_oos <- rsc_portfolio |>
        mutate(date = as.Date(date)) |>
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
              hac_tstat  = round(hd_hac_sharpe(d$ret_buyhold)$hac_tstat, 3),
              hac_sharpe = round(hd_hac_sharpe(d$ret_buyhold)$naive_sharpe, 3)
            ),
            tibble::tibble(
              ticker = "SPY", asset = "S&P 500 (US)", strategy = "RSC Overlay",
              period = "OOS",
              cagr   = round((prod(1 + d$ret_strategy)^(1 / years) - 1) * 100, 2),
              vol    = round(sd(d$ret_strategy) * sqrt(252) * 100, 2),
              max_dd = round(min((cumprod(1 + d$ret_strategy) - cummax(cumprod(1 + d$ret_strategy))) /
                                   cummax(cumprod(1 + d$ret_strategy))) * 100, 2),
              hac_tstat  = round(hd_hac_sharpe(d$ret_strategy)$hac_tstat, 3),
              hac_sharpe = round(hd_hac_sharpe(d$ret_strategy)$naive_sharpe, 3)
            )
          )
        })()

      eur_oos <- eur_results |>
        filter(period == "OOS") |>
        select(ticker, asset, strategy, period, cagr, vol, max_dd, hac_tstat, hac_sharpe)

      bind_rows(spy_oos, eur_oos) |>
        arrange(ticker, strategy)
    }),


    # ── CISS-based European regime (native vol proxy) ─────────────────
    targets::tar_target(eur_ciss_regime, {
      library(dplyr)

      # CISS equity stress sub-index — r=0.75 with VIX (#88)
      ciss_eq <- ecb_raw |>
        filter(series_name == "ciss_equity") |>
        select(date, ciss_equity = value) |>
        arrange(date)

      if (nrow(ciss_eq) < 100) {
        cli::cli_warn("CISS equity has only {nrow(ciss_eq)} obs — skipping")
        return(NULL)
      }

      # Classify regime using percentile thresholds on CISS equity
      # (analogous to VIX-based RSC but using European-native stress)
      q33 <- quantile(ciss_eq$ciss_equity, 0.33, na.rm = TRUE)
      q67 <- quantile(ciss_eq$ciss_equity, 0.67, na.rm = TRUE)

      ciss_eq |>
        mutate(
          ciss_regime = case_when(
            ciss_equity <= q33 ~ "benign",
            ciss_equity <= q67 ~ "cautious",
            TRUE ~ "hostile"
          ),
          ciss_exposure = case_when(
            ciss_regime == "benign"  ~ eur_params$exposure_benign,
            ciss_regime == "cautious" ~ eur_params$exposure_cautious,
            ciss_regime == "hostile" ~ eur_params$exposure_hostile
          )
        )
    }),

    # ── CISS overlay results ───────────────────────────────────────────
    targets::tar_target(eur_ciss_results, {
      library(dplyr)

      if (is.null(eur_ciss_regime)) return(NULL)

      purrr::map_dfr(eur_params$eu_tickers, function(tkr) {
        d <- eur_daily |>
          filter(ticker == tkr, !is.na(eu_ret)) |>
          select(date, eu_ret, rf_lag) |>
          inner_join(eur_ciss_regime |> select(date, ciss_exposure), by = "date") |>
          mutate(
            rf_use = ifelse(is.na(rf_lag), 0, rf_lag),
            ret_ciss_overlay = ciss_exposure * eu_ret + (1 - ciss_exposure) * rf_use,
            ret_buyhold = eu_ret
          ) |>
          filter(date >= eur_params$oos_start)

        if (nrow(d) < 20) return(NULL)

        years <- nrow(d) / 252
        bh_cum <- cumprod(1 + d$ret_buyhold)
        co_cum <- cumprod(1 + d$ret_ciss_overlay)

        tibble::tibble(
          ticker = tkr,
          asset = eur_params$eu_ticker_labels[tkr],
          strategy = c("Buy & Hold", "CISS Overlay"),
          period = "OOS",
          cagr = round(c(
            (prod(1 + d$ret_buyhold)^(1/years) - 1) * 100,
            (prod(1 + d$ret_ciss_overlay)^(1/years) - 1) * 100
          ), 2),
          vol = round(c(
            sd(d$ret_buyhold) * sqrt(252) * 100,
            sd(d$ret_ciss_overlay) * sqrt(252) * 100
          ), 2),
          max_dd = round(c(
            min((bh_cum - cummax(bh_cum)) / cummax(bh_cum)) * 100,
            min((co_cum - cummax(co_cum)) / cummax(co_cum)) * 100
          ), 2),
          hac_sharpe = round(c(
            hd_hac_sharpe(d$ret_buyhold)$naive_sharpe,
            hd_hac_sharpe(d$ret_ciss_overlay)$naive_sharpe
          ), 3)
        )
      })
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
