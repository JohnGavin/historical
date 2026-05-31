# Plan: Pre-Peak Momentum Gauntlet (#365 PR 4/4)
#
# Robustness battery for the mom_prepeak strategy only (heavy treatment).
# Pillar-8 metrics are computed for all 3 siblings via utils_mom_prepeak_metrics.R
# (already extended in PR 4/4); this plan adds the remaining gauntlet tests that
# only make sense for the viable mom_prepeak strategy:
#
#   B1 — Walk-Forward Correlation (WFC) over n_quantiles ∈ {5, 10, 20}
#   B2 — Random-day-as-peak null (strategy-specific falsification)
#   B3 — HAC Sharpe + Fama-French 5+Momentum regression (monthly factors)
#   B4 — CPCV + Probability of Backtest Overfitting (PBO)
#   B5 — Registry sentinel extension (gauntlet metrics recorded into bt.metric)
#
# Heavy gauntlet treatment of the bankrupt siblings (mom_postpeak, mom_combined)
# would add noise without insight.  Generic 7-null-environment falsification
# deferred to v2 follow-up (#380).
#
# WFC grid: only n_quantiles varies (3 values × IS+OOS = 6 portfolio evaluations).
# The raw signal is invariant to n_quantiles; only portfolio-formation (decile sort)
# is re-run per grid point.  This keeps WFC computation to seconds.
#
# Precedent patterns:
#   - WFC:    R/plan_wf_correlation.R (wfc_fm_grid_is / _oos / _grid / _result)
#   - CPCV:   R/plan_drif.R:444 (drif_pbo)
#   - FF5:    R/plan_falsification.R (fals_ff_avoid_worst pattern)

plan_mom_prepeak_gauntlet <- function() {
  list(

    # ══════════════════════════════════════════════════════════════════════════
    # B1 — Walk-Forward Correlation
    # Grid: n_quantiles ∈ {5, 10, 20}; min_obs_days fixed at production value.
    # IS = first half of mom_prepeak_returns; OOS = second half.
    # ══════════════════════════════════════════════════════════════════════════

    targets::tar_target(mom_prepeak_wfc_params, {
      # IS/OOS split at the midpoint of the mom_prepeak return series.
      # Returns are arranged by as_of_date; split at row n/2.
      list(
        n_quantiles_grid = c(5L, 10L, 20L),
        min_obs_days     = 100L,            # fixed at production value
        min_stocks       = 30L,             # matches mom_prepeak_params
        ann_factor       = 12L,
        wfc_threshold    = 0.70             # project threshold (plan_wf_correlation.R)
      )
    }),

    # IS Sharpe for each n_quantiles value (portfolio re-formed on first half of dates)
    targets::tar_target(mom_prepeak_wfc_grid_is, {
      library(dplyr)
      params   <- mom_prepeak_wfc_params
      sig_raw  <- mom_prepeak_signal_raw
      ret_full <- mom_prepeak_returns

      # IS = first half of execution months
      n        <- nrow(ret_full)
      is_dates <- ret_full$as_of_date[seq_len(floor(n / 2))]

      purrr::map_dfr(params$n_quantiles_grid, function(nq) {
        port <- .mom_prepeak_form_portfolio(
          signal_tbl  = sig_raw |> dplyr::filter(.data$as_of_date %in% is_dates),
          signal_col  = "pre_peak_return",
          n_quantiles = nq,
          min_stocks  = params$min_stocks
        )
        ret  <- .mom_prepeak_compute_returns(
          portfolio_tbl  = port,
          universe_tbl   = ltr_universe,
          cost_per_trade = 0.001
        )
        r    <- ret$ret_ls[!is.na(ret$ret_ls)]
        ann_ret <- mean(r) * params$ann_factor
        ann_vol <- stats::sd(r) * sqrt(params$ann_factor)
        sharpe  <- if (length(r) >= 4L && ann_vol > 0) ann_ret / ann_vol else NA_real_
        tibble::tibble(
          theta_id    = nq,
          theta_label = paste0("n_quantiles=", nq),
          IS_metric   = sharpe
        )
      })
    }),

    # OOS Sharpe for each n_quantiles value (portfolio re-formed on second half of dates)
    targets::tar_target(mom_prepeak_wfc_grid_oos, {
      library(dplyr)
      params   <- mom_prepeak_wfc_params
      sig_raw  <- mom_prepeak_signal_raw
      ret_full <- mom_prepeak_returns

      # OOS = second half of execution months
      n         <- nrow(ret_full)
      oos_dates <- ret_full$as_of_date[(floor(n / 2) + 1L):n]

      purrr::map_dfr(params$n_quantiles_grid, function(nq) {
        port <- .mom_prepeak_form_portfolio(
          signal_tbl  = sig_raw |> dplyr::filter(.data$as_of_date %in% oos_dates),
          signal_col  = "pre_peak_return",
          n_quantiles = nq,
          min_stocks  = params$min_stocks
        )
        ret  <- .mom_prepeak_compute_returns(
          portfolio_tbl  = port,
          universe_tbl   = ltr_universe,
          cost_per_trade = 0.001
        )
        r    <- ret$ret_ls[!is.na(ret$ret_ls)]
        ann_ret <- if (length(r) >= 1L) mean(r) * params$ann_factor else NA_real_
        ann_vol <- if (length(r) >= 2L) stats::sd(r) * sqrt(params$ann_factor) else NA_real_
        sharpe  <- if (!is.na(ann_vol) && ann_vol > 0) ann_ret / ann_vol else NA_real_
        tibble::tibble(
          theta_id    = nq,
          theta_label = paste0("n_quantiles=", nq),
          OOS_metric  = sharpe
        )
      })
    }),

    # Combined IS+OOS grid (one row per theta) — shape required by hd_wf_correlation()
    targets::tar_target(mom_prepeak_wfc_grid, {
      library(dplyr)
      dplyr::inner_join(
        mom_prepeak_wfc_grid_is  |> dplyr::select("theta_id", "theta_label", "IS_metric"),
        mom_prepeak_wfc_grid_oos |> dplyr::select("theta_id", "OOS_metric"),
        by = "theta_id"
      )
    }),

    # WFC diagnostic: Pearson + Spearman + 2×2 classification
    targets::tar_target(mom_prepeak_wfc_result, {
      hd_wf_correlation(
        mom_prepeak_wfc_grid,
        wfc_threshold_high = mom_prepeak_wfc_params$wfc_threshold
      )
    }),


    # ══════════════════════════════════════════════════════════════════════════
    # B2 — Random-day-as-peak falsification
    #
    # Strategy-specific null: pick a random day within the formation window
    # as the "peak" instead of the actual max-price day.  If our strategy's
    # alpha survives this null (random-peak Sharpe ≥ actual), the peak-finding
    # adds no edge.
    # ══════════════════════════════════════════════════════════════════════════

    targets::tar_target(mom_prepeak_random_peak_signal, {
      .mom_prepeak_random_peak_signal(
        daily_prices = ltr_universe,
        as_of_dates  = mom_prepeak_as_of_dates,
        seed         = 42L
      )
    }),

    targets::tar_target(mom_prepeak_random_peak_portfolio, {
      .mom_prepeak_form_portfolio(
        signal_tbl  = mom_prepeak_random_peak_signal,
        signal_col  = "pre_peak_return",
        n_quantiles = mom_prepeak_params$n_quantiles,
        min_stocks  = mom_prepeak_params$min_stocks_per_month
      )
    }),

    targets::tar_target(mom_prepeak_random_peak_returns, {
      .mom_prepeak_compute_returns(
        portfolio_tbl  = mom_prepeak_random_peak_portfolio,
        universe_tbl   = ltr_universe,
        cost_per_trade = mom_prepeak_params$cost_per_trade
      )
    }),

    targets::tar_target(mom_prepeak_random_peak_metrics, {
      .mom_prepeak_compute_metrics(
        mom_prepeak_random_peak_returns,
        strategy = "mom_prepeak_random_peak"
      )
    }),

    # Comparison: random-peak Sharpe vs actual Sharpe
    targets::tar_target(mom_prepeak_random_peak_test, {
      actual_sharpe <- mom_prepeak_metrics$sharpe
      random_sharpe <- mom_prepeak_random_peak_metrics$sharpe
      tibble::tibble(
        actual_sharpe = actual_sharpe,
        random_sharpe = random_sharpe,
        null_dominates = if (is.na(random_sharpe) || is.na(actual_sharpe)) {
          NA
        } else {
          random_sharpe >= actual_sharpe
        }
      )
    }),


    # ══════════════════════════════════════════════════════════════════════════
    # B3 — HAC Sharpe + Fama-French 5+Momentum regression (monthly)
    #
    # mom_prepeak uses MONTHLY returns; we use monthly FF5 + Momentum factors.
    # hd_factor_null_test() joins on date — monthly dates must align.
    # The strategy input format is {date, strategy_ret} where date is the
    # execution date (exec_date from mom_prepeak_returns).
    # ══════════════════════════════════════════════════════════════════════════

    targets::tar_target(mom_prepeak_hac, {
      hd_hac_sharpe(mom_prepeak_returns$ret_ls, ann_factor = 12L)
    }),

    # Monthly FF5 + Momentum factors for the regression
    targets::tar_target(mom_prepeak_ff_factors_monthly, {
      library(dplyr)
      ff5 <- hd_factors(dataset = "FF5", frequency = "monthly")
      mom <- hd_factors(dataset = "Mom", frequency = "monthly")
      dplyr::bind_rows(ff5, mom) |>
        dplyr::filter(.data$factor_name != "RF") |>
        dplyr::mutate(
          value = .data$value / 100,
          date  = as.Date(.data$date)
        ) |>
        dplyr::select("date", "factor_name", "value")
    }),

    targets::tar_target(mom_prepeak_rf_monthly, {
      library(dplyr)
      hd_factors(dataset = "FF5", frequency = "monthly") |>
        dplyr::filter(.data$factor_name == "RF") |>
        dplyr::mutate(
          rf   = .data$value / 100,
          date = as.Date(.data$date)
        ) |>
        dplyr::select("date", "rf")
    }),

    # FF5+Momentum alpha regression for mom_prepeak
    # Input to hd_factor_null_test: {date, strategy_ret} using exec_date.
    # FF factors arrive at month-start; strategy returns are stamped at month-end.
    # floor_date aligns both to month-key for the join.
    targets::tar_target(mom_prepeak_ff_reg, {
      library(dplyr)
      strategy_monthly <- mom_prepeak_returns |>
        dplyr::select(date = "exec_date", strategy_ret = "ret_ls") |>
        dplyr::filter(!is.na(.data$strategy_ret)) |>
        dplyr::mutate(date = lubridate::floor_date(as.Date(.data$date), "month"))

      rf_keyed <- mom_prepeak_rf_monthly |>
        dplyr::mutate(date = lubridate::floor_date(.data$date, "month"))

      ff_keyed <- mom_prepeak_ff_factors_monthly |>
        dplyr::mutate(date = lubridate::floor_date(.data$date, "month"))

      hd_factor_null_test(
        strategy_daily = strategy_monthly,
        rf_daily       = rf_keyed,
        factors_daily  = ff_keyed
      )
    }),


    # ══════════════════════════════════════════════════════════════════════════
    # B4 — CPCV + Probability of Backtest Overfitting
    #
    # Since mom_prepeak has no scalar tuning parameter in production, we use
    # n_quantiles ∈ {5, 10, 20} as the "strategy dimension" for PBO.
    # This gives a real overfitting test: the PBO measures whether the IS-best
    # n_quantiles value also dominates OOS.
    #
    # C(6, 2) = 15 paths with n_groups=6, n_test_groups=2.
    # Label horizon = 1 (monthly L/S: each portfolio uses t+1 execution).
    # Embargo = 1 month (drop train rows immediately after each test fold).
    # ══════════════════════════════════════════════════════════════════════════

    targets::tar_target(mom_prepeak_cpcv_params, {
      list(
        n_groups      = 6L,
        n_test_groups = 2L,
        label_horizon = 1L,
        embargo_n     = 1L,
        ann_factor    = 12L
      )
    }),

    # PBO over the 3 n_quantiles configurations
    # (mirrors drif_pbo from R/plan_drif.R:444 — see that target for pattern notes)
    targets::tar_target(mom_prepeak_pbo, {
      library(dplyr)

      params   <- mom_prepeak_cpcv_params
      sig_raw  <- mom_prepeak_signal_raw
      ret_full <- mom_prepeak_returns
      n        <- nrow(ret_full)

      # Assign each observation to a group (contiguous time blocks)
      group_id   <- cut(seq_len(n), breaks = params$n_groups,
                        labels = FALSE, include.lowest = TRUE)
      group_rows <- lapply(seq_len(params$n_groups), function(g) which(group_id == g))

      paths    <- hd_cpcv_paths(
        n_groups      = params$n_groups,
        n_test_groups = params$n_test_groups
      )
      n_paths    <- length(paths)
      nq_vals    <- c(5L, 10L, 20L)
      n_strat    <- length(nq_vals)
      strat_labs <- paste0("nq", nq_vals)

      # Helper: compute annualised Sharpe from a vector of monthly returns
      sharpe_monthly <- function(ret) {
        ret <- ret[!is.na(ret)]
        if (length(ret) < 3L) return(NA_real_)
        ann_ret <- mean(ret) * params$ann_factor
        ann_vol <- stats::sd(ret) * sqrt(params$ann_factor)
        if (ann_vol <= 0) return(NA_real_)
        ann_ret / ann_vol
      }

      is_mat  <- matrix(NA_real_, nrow = n_paths, ncol = n_strat,
                        dimnames = list(NULL, strat_labs))
      oos_mat <- is_mat

      for (i in seq_len(n_paths)) {
        p           <- paths[[i]]
        train_rows  <- sort(unlist(group_rows[p$train]))
        test_rows   <- sort(unlist(group_rows[p$test]))
        train_purged <- hd_cpcv_purge(train_rows, test_rows, params$label_horizon)
        train_clean  <- hd_cpcv_embargo(train_purged, test_rows, params$embargo_n)

        # as_of_dates for train / test folds (from ret_full row positions)
        train_aod <- ret_full$as_of_date[train_clean]
        test_aod  <- ret_full$as_of_date[test_rows]

        for (j in seq_along(nq_vals)) {
          nq <- nq_vals[[j]]

          # IS score
          port_is <- tryCatch({
            .mom_prepeak_form_portfolio(
              signal_tbl  = sig_raw |> dplyr::filter(.data$as_of_date %in% train_aod),
              signal_col  = "pre_peak_return",
              n_quantiles = nq,
              min_stocks  = 10L   # relaxed for cross-val folds (fewer obs)
            )
          }, error = function(e) NULL)

          if (!is.null(port_is) && nrow(port_is) > 0L) {
            ret_is <- tryCatch(
              .mom_prepeak_compute_returns(port_is, ltr_universe, 0.001),
              error = function(e) NULL
            )
            if (!is.null(ret_is)) is_mat[i, j] <- sharpe_monthly(ret_is$ret_ls)
          }

          # OOS score
          port_oos <- tryCatch({
            .mom_prepeak_form_portfolio(
              signal_tbl  = sig_raw |> dplyr::filter(.data$as_of_date %in% test_aod),
              signal_col  = "pre_peak_return",
              n_quantiles = nq,
              min_stocks  = 10L
            )
          }, error = function(e) NULL)

          if (!is.null(port_oos) && nrow(port_oos) > 0L) {
            ret_oos <- tryCatch(
              .mom_prepeak_compute_returns(port_oos, ltr_universe, 0.001),
              error = function(e) NULL
            )
            if (!is.null(ret_oos)) oos_mat[i, j] <- sharpe_monthly(ret_oos$ret_ls)
          }
        }
      }

      hd_pbo(is_scores = is_mat, oos_scores = oos_mat)
    }),


    # ══════════════════════════════════════════════════════════════════════════
    # B5 — Registry sentinel extension
    #
    # Record gauntlet metrics (hac_sharpe, hac_pvalue, ff5_alpha, ff5_alpha_t,
    # pbo, wfc_pearson, avg_dd_days, max_dd_days, max_cons_losses) into bt.metric
    # under the existing mom_prepeak run_uuid from mom_prepeak_register_runs.
    #
    # NOTE: idempotency bug #375 is known — deterministic UUID re-running produces
    # duplicate rows.  This target writes correctly on the FIRST tar_make invocation.
    # Manual cleanup handled by the orchestrator if needed.
    # ══════════════════════════════════════════════════════════════════════════

    targets::tar_target(mom_prepeak_gauntlet_register, {
      .mom_prepeak_gauntlet_register(
        mom_prepeak_register_runs  = mom_prepeak_register_runs,
        mom_prepeak_metrics        = mom_prepeak_metrics,
        mom_prepeak_hac            = mom_prepeak_hac,
        mom_prepeak_ff_reg         = mom_prepeak_ff_reg,
        mom_prepeak_pbo            = mom_prepeak_pbo,
        mom_prepeak_wfc_result     = mom_prepeak_wfc_result
      )
    })

  )
}


# ── Internal helpers ───────────────────────────────────────────────────────────


#' Random-day-as-peak signal (strategy-specific falsification null)
#'
#' Mirrors hd_mom_prepeak_signal() but replaces which.max() (true peak detection)
#' with sample.int() — a uniformly random day within the formation window.
#' Using set.seed(seed) ensures reproducibility.
#'
#' If the random index falls on the first day: pre_peak_return = 0,
#' post_peak_return = total_return (same as if peak were on day 1).
#'
#' @param daily_prices Tibble: ticker, date (Date), adjusted.
#' @param as_of_dates Date vector of rebalance dates.
#' @param seed Integer random seed (default 42L).
#' @param lookback_months_start Integer (default 12L).
#' @param lookback_months_end Integer (default 2L).
#' @param min_obs_days Integer minimum trading days in window (default 100L).
#'
#' @return Tibble with same columns as hd_mom_prepeak_signal().
#' @noRd
.mom_prepeak_random_peak_signal <- function(daily_prices,
                                             as_of_dates,
                                             seed                  = 42L,
                                             lookback_months_start = 12L,
                                             lookback_months_end   = 2L,
                                             min_obs_days          = 100L) {
  set.seed(seed)

  if (inherits(daily_prices$date, "POSIXct")) {
    daily_prices$date <- as.Date(daily_prices$date)
  }
  as_of_dates <- as.Date(as_of_dates)

  prices_by_ticker <- split(daily_prices, daily_prices$ticker)

  dplyr::bind_rows(purrr::map(
    names(prices_by_ticker),
    function(tk) {
      tk_prices <- prices_by_ticker[[tk]]
      tk_prices <- tk_prices[order(tk_prices$date), ]

      dplyr::bind_rows(purrr::map(
        as_of_dates,
        function(aod) {
          formation_start <- lubridate::`%m-%`(aod, months(lookback_months_start))
          formation_end   <- lubridate::`%m-%`(aod, months(lookback_months_end))

          win <- tk_prices[
            tk_prices$date >= formation_start &
              tk_prices$date <= formation_end, ,
            drop = FALSE
          ]
          n_obs <- nrow(win)
          if (n_obs < min_obs_days) return(tibble::tibble(
            ticker          = character(0),
            as_of_date      = as.Date(character(0)),
            formation_start = as.Date(character(0)),
            formation_end   = as.Date(character(0)),
            peak_date       = as.Date(character(0)),
            n_obs           = integer(0),
            pre_peak_return  = numeric(0),
            post_peak_return = numeric(0),
            total_return     = numeric(0),
            peak_position    = numeric(0)
          ))

          # Key difference: random index instead of which.max()
          peak_idx  <- sample.int(n_obs, 1L)
          peak_date <- win$date[peak_idx]

          price_start <- win$adjusted[1L]
          price_peak  <- win$adjusted[peak_idx]
          price_end   <- win$adjusted[n_obs]

          pre_peak_return  <- price_peak  / price_start - 1
          post_peak_return <- price_end   / price_peak  - 1
          total_return     <- price_end   / price_start - 1
          peak_position    <- (peak_idx - 1L) / (n_obs - 1L)

          tibble::tibble(
            ticker          = tk,
            as_of_date      = aod,
            formation_start = win$date[1L],
            formation_end   = win$date[n_obs],
            peak_date       = peak_date,
            n_obs           = n_obs,
            pre_peak_return  = pre_peak_return,
            post_peak_return = post_peak_return,
            total_return     = total_return,
            peak_position    = peak_position
          )
        }
      ))
    }
  ))
}


#' Register gauntlet metrics into bt.metric for the mom_prepeak run
#'
#' Appends HAC, FF5, PBO, and WFC metrics to the bt.metric table for the
#' mom_prepeak run_uuid established in mom_prepeak_register_runs.
#' Returns an empty tibble if DBI / duckdb are unavailable.
#'
#' @noRd
.mom_prepeak_gauntlet_register <- function(mom_prepeak_register_runs,
                                            mom_prepeak_metrics,
                                            mom_prepeak_hac,
                                            mom_prepeak_ff_reg,
                                            mom_prepeak_pbo,
                                            mom_prepeak_wfc_result) {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("duckdb", quietly = TRUE)) {
    return(tibble::tibble(run_uuid = character(), metric_rows = integer()))
  }

  # Identify the mom_prepeak run_uuid from the sentinel
  reg_row <- mom_prepeak_register_runs[
    mom_prepeak_register_runs$strategy_id == "mom_prepeak", ,
    drop = FALSE
  ]
  if (nrow(reg_row) == 0L) {
    cli::cli_warn("mom_prepeak run_uuid not found in mom_prepeak_register_runs — skipping gauntlet registry write.")
    return(tibble::tibble(run_uuid = character(), metric_rows = integer()))
  }
  uu <- reg_row$run_uuid[[1L]]

  path <- historicaldata::hd_registry_path()
  con  <- historicaldata::hd_registry_open(path, read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # Build gauntlet metric row (wide format: one column per metric)
  gauntlet_wide <- tibble::tibble(
    hac_sharpe     = if (!is.null(mom_prepeak_hac$naive_sharpe))
      mom_prepeak_hac$naive_sharpe else NA_real_,
    hac_tstat      = if (!is.null(mom_prepeak_hac$hac_tstat))
      mom_prepeak_hac$hac_tstat else NA_real_,
    ff5_alpha      = if (nrow(mom_prepeak_ff_reg) == 1L)
      mom_prepeak_ff_reg$alpha_annual else NA_real_,
    ff5_alpha_t    = if (nrow(mom_prepeak_ff_reg) == 1L)
      mom_prepeak_ff_reg$alpha_tstat_hac else NA_real_,
    ff5_r2         = if (nrow(mom_prepeak_ff_reg) == 1L)
      mom_prepeak_ff_reg$r_squared else NA_real_,
    pbo            = if (!is.null(mom_prepeak_pbo$pbo))
      mom_prepeak_pbo$pbo else NA_real_,
    wfc_pearson    = if (!is.null(mom_prepeak_wfc_result$pearson_rho))
      mom_prepeak_wfc_result$pearson_rho else NA_real_,
    wfc_class      = if (!is.null(mom_prepeak_wfc_result$classification))
      mom_prepeak_wfc_result$classification else NA_character_,
    avg_dd_days    = mom_prepeak_metrics$avg_dd_days,
    max_dd_days    = mom_prepeak_metrics$max_dd_days,
    max_cons_losses = mom_prepeak_metrics$max_cons_losses
  )

  historicaldata::hd_metric_record(con, uu, gauntlet_wide)

  tibble::tibble(run_uuid = uu, metric_rows = 1L)
}
