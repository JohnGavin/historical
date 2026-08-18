# Plan: OLMAR-1 Online Moving Average Reversion (#200)
#
# Li & Hoi (2012). Passive-aggressive update on SMA/price predicted
# price relatives. First concrete use case of the research-log DB (#270).
#
# Look-ahead safety: weights at t are formed from prices up to and
# including t. Returns are realised from prices[t+1]. No future prices
# ever enter weight formation. This mirrors the t+1 execution discipline
# in plan_mean_reversion.R.
#
# Deferred items (do NOT build here):
#   - Leverage sweep across multiple values
#   - S&P 600 universe
#   - Cross-geography replication
#   - Leaderboard integration
#   - Vignette
#   - Production-scale 500-stock run

plan_olmar <- function() {
  list(

    # ── Parameters ──────────────────────────────────────────────
    targets::tar_target(olmar_params, {
      p <- bt_partitions$equity
      list(
        # OLMAR-1 hyperparameters
        window   = 25L,      # SMA window (trading days)
        epsilon  = 10,       # mean-reversion threshold (> 1)
        leverage = 0.2,      # tilt fraction around equal weight
        cost_bps = 10,       # one-way turnover cost in basis points

        # Partitions (from bt_partitions$equity — single source of truth)
        start_date = as.Date("2010-01-01"),
        train_end  = p$train_end,
        test_start = p$test_start,
        test_end   = p$test_end,
        val_start  = p$val_start,

        # Universe: ~30 large-cap + broad ETF tickers (MVP proxy for S&P 500)
        # Identical to mr_params$tickers so both plans share the same universe.
        tickers = c("SPY", "QQQ", "IWM", "DIA", "XLF", "XLE", "XLV",
                    "XLK", "XLI", "XLP", "XLU", "XLB", "XLY", "XLRE",
                    "AAPL", "MSFT", "GOOGL", "AMZN", "META",
                    "JPM", "BAC", "GS", "JNJ", "PFE", "UNH",
                    "XOM", "CVX", "HD", "WMT", "PG")
      )
    }),

    # ── Data: adjusted-close price matrix ───────────────────────
    targets::tar_target(olmar_prices, {
      library(dplyr)

      raw <- purrr::map(olmar_params$tickers, function(tkr) {
        tryCatch({
          hd_ohlcv(tkr, from = as.character(olmar_params$start_date)) |>
            dplyr::arrange(date) |>
            dplyr::select(date, adjusted_close) |>
            dplyr::mutate(date = as.Date(date, tz = "UTC"),
                          ticker = tkr)
        }, error = function(e) {
          cli::cli_warn("OLMAR: failed to fetch {tkr}: {conditionMessage(e)}")
          NULL
        })
      })

      raw <- purrr::compact(raw)

      if (length(raw) == 0L) {
        cli::cli_abort(c(
          "x" = "olmar_prices: no tickers returned data.",
          "i" = "Check network access to HuggingFace parquet store."
        ))
      }

      # Pivot to wide: rows = date, cols = ticker
      wide <- dplyr::bind_rows(raw) |>
        tidyr::pivot_wider(names_from = ticker, values_from = adjusted_close) |>
        dplyr::arrange(date)

      # Drop tickers that have too little history
      # (need at least olmar_params$window + 1 non-NA days)
      min_obs <- olmar_params$window + 1L
      keep <- vapply(names(wide)[-1L], function(col) {
        sum(!is.na(wide[[col]])) >= min_obs
      }, logical(1L))
      n_drop <- sum(!keep)
      if (n_drop > 0L) {
        cli::cli_warn("olmar_prices: dropping {n_drop} ticker(s) with < {min_obs} obs.")
      }

      wide[, c("date", names(keep)[keep]), drop = FALSE]
    }),

    # ── Backtest ─────────────────────────────────────────────────
    targets::tar_target(olmar_portfolio, {
      library(dplyr)

      # olmar_backtest expects rows=dates, cols=assets; date column is stripped
      result <- historicaldata::olmar_backtest(
        prices   = olmar_prices,
        window   = olmar_params$window,
        epsilon  = olmar_params$epsilon,
        leverage = olmar_params$leverage,
        cost_bps = olmar_params$cost_bps
      )

      result |>
        dplyr::mutate(
          date     = as.Date(date),
          cum_gross = cumprod(1 + gross_ret),
          cum_net   = cumprod(1 + net_ret)
        ) |>
        .olmar_join_rf(daily_rf)
    }),

    # ── Metrics ─────────────────────────────────────────────────
    # #677 slice 3b: sharpe was previously mean(ret)*252/vol -- arithmetic
    # numerator, NO risk-free deduction, while cagr two lines above was
    # already geometric. The reported Sharpe was not the Sharpe of the
    # reported CAGR. Now uses the canonical sharpe_ratio_rf()
    # (R/utils_metrics.R): geometric numerator, rf-deducted, daily
    # (periods_per_year = 252L) -- and cagr/vol are read straight off the
    # same sharpe_ratio_rf() call so all three figures are guaranteed
    # coherent with each other (the inconsistency this migration fixes).
    targets::tar_target(olmar_metrics, {
      library(dplyr)

      calc <- function(d, label) {
        keep   <- !is.na(d$net_ret)
        d      <- d[keep, , drop = FALSE]
        ret    <- d$net_ret
        rf_ret <- d$rf_ret
        n      <- length(ret)
        if (n < 20L) return(NULL)

        sr       <- sharpe_ratio_rf(ret, rf_ret, periods_per_year = 252L, na.rm = TRUE)
        eq_curve <- cumprod(1 + ret)
        dd       <- (eq_curve - cummax(eq_curve)) / cummax(eq_curve)
        max_dd   <- min(dd)
        avg_tv   <- mean(d$turnover, na.rm = TRUE)

        tibble::tibble(
          period   = label,
          days     = n,
          years    = round(n / 252, 1),
          cagr     = round(sr$ann_ret * 100, 2),
          vol      = round(sr$ann_vol * 100, 2),
          sharpe   = round(sr$sharpe, 3),
          # ann_rf published alongside sharpe (#677 slice 4), same PERCENT
          # convention as cagr/vol above -- QA gate S17
          # (check_leaderboard_sharpe_coherence(), R/plan_qa_gates.R) asserts
          # sharpe == (cagr - ann_rf) / vol for every leaderboard row.
          ann_rf   = round(sr$ann_rf * 100, 2),
          max_dd   = round(max_dd * 100, 2),
          avg_turnover_daily = round(avg_tv, 4)
        )
      }

      port     <- olmar_portfolio |> dplyr::mutate(date = as.Date(date))
      oos      <- as.Date(olmar_params$test_start)
      test_end <- as.Date(olmar_params$test_end)

      dplyr::bind_rows(
        calc(port |> dplyr::filter(date < oos),                         "Training"),
        calc(port |> dplyr::filter(date >= oos & date <= test_end),     "Testing"),
        calc(port, "Full Period")
      )
    }),

    # ── Dynamic caption ──────────────────────────────────────────
    targets::tar_target(olmar_caption, {
      m_full <- olmar_metrics |> dplyr::filter(period == "Full Period")
      m_test <- olmar_metrics |> dplyr::filter(period == "Testing")
      n_tkr  <- ncol(olmar_prices) - 1L  # subtract date column
      paste0(
        "OLMAR-1 (Online Moving Average Reversion, Li & Hoi 2012): ",
        "SMA(", olmar_params$window, ")-day mean-reversion signal, ",
        "epsilon=", olmar_params$epsilon, ", leverage=", olmar_params$leverage,
        ", cost=", olmar_params$cost_bps, "bps. ",
        "Universe: ", n_tkr, " large-cap + ETF tickers. ",
        "Full-period net CAGR: ", m_full$cagr, "%, Vol: ", m_full$vol,
        "%, Sharpe: ", m_full$sharpe, ", Max DD: ", m_full$max_dd, "%. ",
        "OOS Sharpe: ", m_test$sharpe, ". ",
        "Look-ahead-safe: weights formed at close of day t, realised on t+1."
      )
    }),

    # ── Research-log lineage target (THE HEADLINE: #200 + #270) ─
    targets::tar_target(olmar_research_log, {
      # Guard: report clearly on DB write failure, do not silently swallow
      tryCatch({
        base_dir <- historicaldata::hd_rlog_path()

        # Pull full-period metrics for logging
        m_full <- olmar_metrics |> dplyr::filter(period == "Full Period")
        m_train <- olmar_metrics |> dplyr::filter(period == "Training")
        m_test  <- olmar_metrics |> dplyr::filter(period == "Testing")
        n_tkr   <- ncol(olmar_prices) - 1L

        # Pre-generate ids to enable parent-child lineage chaining
        hyp_id  <- historicaldata::hd_rlog_uuid()
        impl_id <- historicaldata::hd_rlog_uuid()
        res_id  <- historicaldata::hd_rlog_uuid()

        # 1. Hypothesis
        historicaldata::hd_rlog_append("hypotheses",
          tibble::tibble(
            uuid            = hyp_id,
            economic_claim  = paste0(
              "Equity prices mean-revert toward a short moving average ",
              "over daily horizons. The SMA/price ratio provides a ",
              "sufficient statistic for next-day expected return."
            ),
            dependent_var   = "next-day portfolio return",
            predictor       = paste0(
              "MA/price ratio (OLMAR-1): SMA(", olmar_params$window, "d) / p_t"
            ),
            sample_spec     = paste0(
              n_tkr, " large-cap + ETF tickers, ",
              olmar_params$start_date, " to ", max(olmar_portfolio$date)
            ),
            null_hypothesis = "No MA-reversion premium net of transaction costs",
            status          = "tested",
            extra_json      = NA_character_
          ),
          base_dir = base_dir
        )

        # 2. Implementation
        historicaldata::hd_rlog_append("implementations",
          tibble::tibble(
            uuid          = impl_id,
            parent_uuid   = hyp_id,
            code_ref      = "R/plan_olmar.R + packages/historicaldata/R/olmar.R",
            notebook_path = NA_character_,
            params_json   = jsonlite::toJSON(
              list(
                window   = olmar_params$window,
                epsilon  = olmar_params$epsilon,
                leverage = olmar_params$leverage,
                cost_bps = olmar_params$cost_bps
              ),
              auto_unbox = TRUE
            ),
            extra_json    = NA_character_
          ),
          base_dir = base_dir
        )

        # 3. Results (full period)
        n_obs_full <- as.integer(m_full$days)
        historicaldata::hd_rlog_append("results",
          tibble::tibble(
            uuid                = res_id,
            parent_uuid         = impl_id,
            strategy_id         = "olmar",
            partition           = "full",
            cagr                = as.double(m_full$cagr / 100),
            sharpe_hac          = as.double(m_full$sharpe),
            max_dd              = as.double(m_full$max_dd / 100),
            turnover_annual     = as.double(m_full$avg_turnover_daily * 252),
            n_obs               = n_obs_full,
            results_db_run_date = Sys.Date(),
            extra_json          = NA_character_
          ),
          base_dir = base_dir
        )

        # 4. Critiques: document the two highest-catch-rate Kinlay defect classes
        critique_ids <- c(
          historicaldata::hd_rlog_uuid(),
          historicaldata::hd_rlog_uuid()
        )
        historicaldata::hd_rlog_append("critiques",
          tibble::tibble(
            uuid         = critique_ids,
            parent_uuid  = res_id,
            defect_class = c("look_ahead", "omitted_costs"),
            severity     = c("critical", "major"),
            finding      = c(
              paste0(
                "weights at t formed from prices[1:t, ] only; ",
                "r_{t+1} (prices[t+1]) never used in b_next formation. ",
                "Look-ahead guard test: perturbing only the last day's prices ",
                "leaves all earlier weights unchanged."
              ),
              paste0(
                olmar_params$cost_bps,
                " bps one-way turnover cost applied per day; ",
                "net_ret = gross_ret - (cost_bps/1e4) * turnover. ",
                "Full-period avg daily turnover: ",
                round(mean(olmar_portfolio$turnover, na.rm = TRUE), 4)
              )
            ),
            cell_ref     = c(
              "packages/historicaldata/R/olmar.R:olmar_backtest()",
              "packages/historicaldata/R/olmar.R:olmar_backtest()"
            ),
            resolved     = c(TRUE, TRUE)
          ),
          base_dir = base_dir
        )

        # 5. Robustness: one row per partition
        rob_ids <- c(
          historicaldata::hd_rlog_uuid(),
          historicaldata::hd_rlog_uuid()
        )
        sharpe_train <- as.double(m_train$sharpe)
        sharpe_test  <- as.double(m_test$sharpe)
        historicaldata::hd_rlog_append("robustness",
          tibble::tibble(
            uuid         = rob_ids,
            parent_uuid  = res_id,
            panel_name   = c("Training", "Testing"),
            variation    = paste0("window=", olmar_params$window,
                                  ", epsilon=", olmar_params$epsilon,
                                  ", leverage=", olmar_params$leverage),
            metric_name  = "sharpe",
            metric_value = c(sharpe_train, sharpe_test),
            passed       = c(
              !is.na(sharpe_train) && abs(sharpe_train) < 5,
              !is.na(sharpe_test)  && abs(sharpe_test)  < 5
            ),
            extra_json   = NA_character_
          ),
          base_dir = base_dir
        )

        tibble::tibble(
          hyp_id  = hyp_id,
          impl_id = impl_id,
          res_id  = res_id
        )

      }, error = function(e) {
        cli::cli_abort(c(
          "x" = "olmar_research_log: DB write failed.",
          "i" = conditionMessage(e)
        ))
      })
    })

  )
}


# ── Internal helper ────────────────────────────────────────────────────────────
# Prefixed .olmar_* (private; not exported from the package).

#' Join the shared daily risk-free series onto OLMAR's daily portfolio (#677)
#'
#' Mirrors \code{.tom_join_rf_daily()} in R/plan_turn_of_month.R -- OLMAR-1
#' is the fifth strategy to consume the coverage policy in
#' \code{.join_rf_series()} (R/utils_metrics.R), which distinguishes THREE
#' cases (leading / trailing / interior) -- see that function's roxygen for
#' the full policy. A missing risk-free series must never be treated as
#' zero -- see fail-loud-not-null.md.
#'
#' @param port Tibble with a `date` column (the OLMAR-1 daily portfolio).
#' @param rf Tibble with columns `date`, `rf_ret` (the `daily_rf` target,
#'   R/plan_stock_backtest.R).
#' @return `port` with `rf_ret` joined, trailing uncovered dates removed.
#' @noRd
.olmar_join_rf <- function(port, rf) {
  .join_rf_series(
    df = port, rf = rf, key = "date",
    label = ".olmar_join_rf", rf_label = "daily_rf",
    rf_source = "the daily_rf target, R/plan_stock_backtest.R",
    df_label = "olmar_portfolio", strategy_label = "OLMAR-1",
    period_noun = "date", df_arg_name = "port"
  )
}
