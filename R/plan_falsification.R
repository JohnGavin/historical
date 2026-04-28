# Plan: Falsification Framework — Phase 1
#
# Five strategies: avoid_worst (VIX protection), drif (factor rotation),
# fac_max (factor momentum), rsc (risk-state condition), ltr (LambdaMART CS momentum).
# Tests each strategy against:
#   - HAC t-statistic (Newey-West)
#   - 5 null environments (white noise, regime vol, MA(1), factor null, GARCH)
#   - 2 GARCH variants (GARCH(1,1) and GJR-GARCH)
#   - Fama-French 5-factor + Momentum alpha regression
#
# Total (with ltr): 1 + 4 + 2 + 32 + 2 + 1 = 42 targets
#
# Reference: Harvey, Liu & Zhu (2016), Lopez de Prado (2018).

plan_falsification <- function() {
  list(

    # ── Shared parameters ─────────────────────────────────────────────
    targets::tar_target(fals_params, {
      list(
        M           = 100L,     # null simulations per environment
        seed        = 42L,
        alpha_level = 0.05
      )
    }),


    # ═══════════════════════════════════════════════════════════════════
    # Bridge targets: extract strategy returns from upstream targets
    # ═══════════════════════════════════════════════════════════════════

    # avoid_worst: daily returns from VIX-triggered strategy
    targets::tar_target(fals_avoid_worst_input, {
      library(dplyr)
      aw_practical_backtest |>
        dplyr::select(date, strategy_ret = ret_strategy)
    }),

    # drif: monthly portfolio returns
    targets::tar_target(fals_drif_input, {
      library(dplyr)
      drif_portfolio |>
        dplyr::select(date, strategy_ret = portfolio_ret)
    }),

    # fac_max: monthly portfolio returns
    targets::tar_target(fals_fac_max_input, {
      library(dplyr)
      fm_portfolio |>
        dplyr::select(date, strategy_ret = portfolio_ret)
    }),

    # rsc: daily returns from RSC overlay on SPY
    targets::tar_target(fals_rsc_input, {
      library(dplyr)
      rsc_portfolio |>
        dplyr::select(date, strategy_ret = ret_strategy)
    }),

    # ltr: monthly long-short returns from LambdaMART CS momentum
    targets::tar_target(fals_ltr_input, {
      library(dplyr)
      ltr_portfolio |>
        dplyr::select(date, strategy_ret = port_ret)
    }),


    # ═══════════════════════════════════════════════════════════════════
    # Shared data: factors and risk-free rate (fetched once)
    # ═══════════════════════════════════════════════════════════════════

    targets::tar_target(fals_factors, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      ff5 <- hd_factors(dataset = "FF5", frequency = "daily")
      mom <- hd_factors(dataset = "Mom", frequency = "daily")
      dplyr::bind_rows(ff5, mom) |>
        dplyr::filter(factor_name != "RF") |>
        dplyr::mutate(value = value / 100) |>
        dplyr::select(date, factor_name, value)
    }),

    targets::tar_target(fals_rf, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      hd_factors(dataset = "FF5", frequency = "daily") |>
        dplyr::filter(factor_name == "RF") |>
        dplyr::mutate(rf = value / 100) |>
        dplyr::select(date, rf)
    }),


    # ═══════════════════════════════════════════════════════════════════
    # Per-strategy tests: avoid_worst
    # ═══════════════════════════════════════════════════════════════════

    targets::tar_target(fals_hac_avoid_worst, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_hac_sharpe(fals_avoid_worst_input$strategy_ret)
    }),

    targets::tar_target(fals_wn_avoid_worst, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret    <- fals_avoid_worst_input$strategy_ret
      T_obs  <- sum(!is.na(ret))
      nulls  <- hd_null_env_white_noise(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_rv_avoid_worst, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_avoid_worst_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_regime_vol(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_ma1_avoid_worst, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_avoid_worst_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_ma1(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_fn_avoid_worst, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_avoid_worst_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_factor_null(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_garch_avoid_worst, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_avoid_worst_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_garch11(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_gjr_avoid_worst, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_avoid_worst_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_gjr_garch(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_ff_avoid_worst, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_factor_null_test(
        strategy_daily = fals_avoid_worst_input,
        rf_daily       = fals_rf,
        factors_daily  = fals_factors
      )
    }),


    # ═══════════════════════════════════════════════════════════════════
    # Per-strategy tests: drif
    # ═══════════════════════════════════════════════════════════════════

    targets::tar_target(fals_hac_drif, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_hac_sharpe(fals_drif_input$strategy_ret)
    }),

    targets::tar_target(fals_wn_drif, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_drif_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_white_noise(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_rv_drif, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_drif_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_regime_vol(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_ma1_drif, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_drif_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_ma1(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_fn_drif, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_drif_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_factor_null(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_garch_drif, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_drif_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_garch11(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_gjr_drif, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_drif_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_gjr_garch(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_ff_drif, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_factor_null_test(
        strategy_daily = fals_drif_input,
        rf_daily       = fals_rf,
        factors_daily  = fals_factors
      )
    }),


    # ═══════════════════════════════════════════════════════════════════
    # Per-strategy tests: fac_max
    # ═══════════════════════════════════════════════════════════════════

    targets::tar_target(fals_hac_fac_max, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_hac_sharpe(fals_fac_max_input$strategy_ret)
    }),

    targets::tar_target(fals_wn_fac_max, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_fac_max_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_white_noise(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_rv_fac_max, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_fac_max_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_regime_vol(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_ma1_fac_max, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_fac_max_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_ma1(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_fn_fac_max, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_fac_max_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_factor_null(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_garch_fac_max, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_fac_max_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_garch11(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_gjr_fac_max, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_fac_max_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_gjr_garch(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_ff_fac_max, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_factor_null_test(
        strategy_daily = fals_fac_max_input,
        rf_daily       = fals_rf,
        factors_daily  = fals_factors
      )
    }),


    # ═══════════════════════════════════════════════════════════════════
    # Per-strategy tests: rsc
    # ═══════════════════════════════════════════════════════════════════

    targets::tar_target(fals_hac_rsc, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_hac_sharpe(fals_rsc_input$strategy_ret)
    }),

    targets::tar_target(fals_wn_rsc, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret    <- fals_rsc_input$strategy_ret
      T_obs  <- sum(!is.na(ret))
      nulls  <- hd_null_env_white_noise(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_rv_rsc, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_rsc_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_regime_vol(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_ma1_rsc, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_rsc_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_ma1(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_fn_rsc, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_rsc_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_factor_null(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_garch_rsc, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_rsc_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_garch11(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_gjr_rsc, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_rsc_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_gjr_garch(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_ff_rsc, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_factor_null_test(
        strategy_daily = fals_rsc_input,
        rf_daily       = fals_rf,
        factors_daily  = fals_factors
      )
    }),


    # ═══════════════════════════════════════════════════════════════════
    # Per-strategy tests: ltr (LambdaMART cross-sectional momentum)
    # ═══════════════════════════════════════════════════════════════════

    targets::tar_target(fals_hac_ltr, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_hac_sharpe(fals_ltr_input$strategy_ret)
    }),

    targets::tar_target(fals_wn_ltr, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_ltr_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_white_noise(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_rv_ltr, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_ltr_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_regime_vol(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_ma1_ltr, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_ltr_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_ma1(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_fn_ltr, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_ltr_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_factor_null(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_garch_ltr, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_ltr_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_garch11(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_gjr_ltr, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      ret   <- fals_ltr_input$strategy_ret
      T_obs <- sum(!is.na(ret))
      nulls <- hd_null_env_gjr_garch(T_obs, M = fals_params$M, seed = fals_params$seed)
      hd_null_rejection_rate(
        strategy_fn = function(r) hd_hac_tstat(r)$t_stat,
        null_series = nulls,
        alpha_level = fals_params$alpha_level
      )
    }),

    targets::tar_target(fals_ff_ltr, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_factor_null_test(
        strategy_daily = fals_ltr_input,
        rf_daily       = fals_rf,
        factors_daily  = fals_factors
      )
    }),


    # ═══════════════════════════════════════════════════════════════════
    # Cross-strategy targets
    # ═══════════════════════════════════════════════════════════════════

    targets::tar_target(fals_keff, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      all_rets <- Reduce(
        function(a, b) dplyr::full_join(a, b, by = "date"),
        list(
          fals_avoid_worst_input |> dplyr::rename(avoid_worst = strategy_ret),
          fals_drif_input        |> dplyr::rename(drif        = strategy_ret),
          fals_fac_max_input     |> dplyr::rename(fac_max     = strategy_ret),
          fals_rsc_input         |> dplyr::rename(rsc         = strategy_ret),
          fals_ltr_input         |> dplyr::rename(ltr         = strategy_ret)
        )
      )

      mat <- as.matrix(all_rets[, c("avoid_worst", "drif", "fac_max", "rsc", "ltr")])
      hd_keff(mat)
    }),

    targets::tar_target(fals_delta_z, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      z_is <- c(
        fals_hac_avoid_worst$hac_tstat,
        fals_hac_drif$hac_tstat,
        fals_hac_fac_max$hac_tstat,
        fals_hac_rsc$hac_tstat,
        fals_hac_ltr$hac_tstat
      )
      z_oos <- c(
        fals_ff_avoid_worst$alpha_tstat_hac,
        fals_ff_drif$alpha_tstat_hac,
        fals_ff_fac_max$alpha_tstat_hac,
        fals_ff_rsc$alpha_tstat_hac,
        fals_ff_ltr$alpha_tstat_hac
      )

      hd_delta_z(z_is, z_oos, K_eff = fals_keff$K_eff)
    }),


    # ═══════════════════════════════════════════════════════════════════
    # Deflated Sharpe Ratio (DSR): adjusts for skewness, kurtosis, K trials
    # ═══════════════════════════════════════════════════════════════════

    targets::tar_target(fals_dsr_avoid_worst, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_deflated_sharpe(fals_avoid_worst_input$strategy_ret, K_trials = 5L, ann_factor = 252L)
    }),
    targets::tar_target(fals_dsr_drif, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_deflated_sharpe(fals_drif_input$strategy_ret, K_trials = 5L, ann_factor = 12L)
    }),
    targets::tar_target(fals_dsr_fac_max, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_deflated_sharpe(fals_fac_max_input$strategy_ret, K_trials = 5L, ann_factor = 12L)
    }),
    targets::tar_target(fals_dsr_rsc, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_deflated_sharpe(fals_rsc_input$strategy_ret, K_trials = 5L, ann_factor = 252L)
    }),
    targets::tar_target(fals_dsr_ltr, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      hd_deflated_sharpe(fals_ltr_input$strategy_ret, K_trials = 5L, ann_factor = 12L)
    }),


    # ═══════════════════════════════════════════════════════════════════
    # Summary: one row per strategy with all test results
    # ═══════════════════════════════════════════════════════════════════

    targets::tar_target(fals_summary, {
      tibble::tibble(
        strategy = c("avoid_worst", "drif", "fac_max", "rsc", "ltr"),

        # HAC t-statistics
        hac_tstat = c(
          fals_hac_avoid_worst$hac_tstat,
          fals_hac_drif$hac_tstat,
          fals_hac_fac_max$hac_tstat,
          fals_hac_rsc$hac_tstat,
          fals_hac_ltr$hac_tstat
        ),
        hac_sharpe = c(
          fals_hac_avoid_worst$naive_sharpe,
          fals_hac_drif$naive_sharpe,
          fals_hac_fac_max$naive_sharpe,
          fals_hac_rsc$naive_sharpe,
          fals_hac_ltr$naive_sharpe
        ),

        # Null rejection rates (ideally <= 0.075)
        rej_rate_wn = c(
          fals_wn_avoid_worst$rejection_rate,
          fals_wn_drif$rejection_rate,
          fals_wn_fac_max$rejection_rate,
          fals_wn_rsc$rejection_rate,
          fals_wn_ltr$rejection_rate
        ),
        rej_rate_rv = c(
          fals_rv_avoid_worst$rejection_rate,
          fals_rv_drif$rejection_rate,
          fals_rv_fac_max$rejection_rate,
          fals_rv_rsc$rejection_rate,
          fals_rv_ltr$rejection_rate
        ),
        rej_rate_ma1 = c(
          fals_ma1_avoid_worst$rejection_rate,
          fals_ma1_drif$rejection_rate,
          fals_ma1_fac_max$rejection_rate,
          fals_ma1_rsc$rejection_rate,
          fals_ma1_ltr$rejection_rate
        ),
        rej_rate_fn = c(
          fals_fn_avoid_worst$rejection_rate,
          fals_fn_drif$rejection_rate,
          fals_fn_fac_max$rejection_rate,
          fals_fn_rsc$rejection_rate,
          fals_fn_ltr$rejection_rate
        ),
        rej_rate_garch = c(
          fals_garch_avoid_worst$rejection_rate,
          fals_garch_drif$rejection_rate,
          fals_garch_fac_max$rejection_rate,
          fals_garch_rsc$rejection_rate,
          fals_garch_ltr$rejection_rate
        ),
        rej_rate_gjr = c(
          fals_gjr_avoid_worst$rejection_rate,
          fals_gjr_drif$rejection_rate,
          fals_gjr_fac_max$rejection_rate,
          fals_gjr_rsc$rejection_rate,
          fals_gjr_ltr$rejection_rate
        ),

        # FF5+Mom alpha regression
        ff_alpha_annual = c(
          fals_ff_avoid_worst$alpha_annual,
          fals_ff_drif$alpha_annual,
          fals_ff_fac_max$alpha_annual,
          fals_ff_rsc$alpha_annual,
          fals_ff_ltr$alpha_annual
        ),
        ff_alpha_tstat = c(
          fals_ff_avoid_worst$alpha_tstat_hac,
          fals_ff_drif$alpha_tstat_hac,
          fals_ff_fac_max$alpha_tstat_hac,
          fals_ff_rsc$alpha_tstat_hac,
          fals_ff_ltr$alpha_tstat_hac
        ),
        ff_r_squared = c(
          fals_ff_avoid_worst$r_squared,
          fals_ff_drif$r_squared,
          fals_ff_fac_max$r_squared,
          fals_ff_rsc$r_squared,
          fals_ff_ltr$r_squared
        ),

        # Deflated Sharpe Ratio (Lopez de Prado 2018)
        dsr = c(
          fals_dsr_avoid_worst$dsr,
          fals_dsr_drif$dsr,
          fals_dsr_fac_max$dsr,
          fals_dsr_rsc$dsr,
          fals_dsr_ltr$dsr
        ),
        dsr_pvalue = c(
          fals_dsr_avoid_worst$dsr_pvalue,
          fals_dsr_drif$dsr_pvalue,
          fals_dsr_fac_max$dsr_pvalue,
          fals_dsr_rsc$dsr_pvalue,
          fals_dsr_ltr$dsr_pvalue
        ),
        dsr_haircut_pct = c(
          fals_dsr_avoid_worst$haircut_pct,
          fals_dsr_drif$haircut_pct,
          fals_dsr_fac_max$haircut_pct,
          fals_dsr_rsc$haircut_pct,
          fals_dsr_ltr$haircut_pct
        )
      )
    }),


    # ═══════════════════════════════════════════════════════════════════
    # Benchmark returns: SPY daily (fetched once)
    # ═══════════════════════════════════════════════════════════════════

    targets::tar_target(fals_spy_ret, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      hd_ohlcv("SPY") |>
        dplyr::arrange(date) |>
        dplyr::mutate(spy_ret = (close / dplyr::lag(close)) - 1) |>
        dplyr::filter(!is.na(spy_ret)) |>
        dplyr::select(date, spy_ret)
    }),


    # ═══════════════════════════════════════════════════════════════════
    # Results database: persist this run to parquet log
    # ═══════════════════════════════════════════════════════════════════

    targets::tar_target(fals_results_db, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      # ── Helper: drawdown analysis ──────────────────────────────────
      compute_drawdowns <- function(ret) {
        ret <- ret[!is.na(ret)]
        if (length(ret) == 0L) {
          return(list(max_dd = NA_real_, avg_dd = NA_real_,
                      max_dd_duration_days = NA_integer_,
                      n_drawdowns = NA_integer_,
                      recovery_days = NA_integer_))
        }
        cum  <- cumprod(1 + ret)
        peak <- cummax(cum)
        dd   <- (cum - peak) / peak

        max_dd <- min(dd, na.rm = TRUE)

        # Distinct drawdown events (threshold: -1%)
        in_dd  <- dd < -0.01
        # Run-length encode to find distinct events
        rle_dd  <- rle(in_dd)
        dd_runs <- rle_dd$lengths[rle_dd$values]
        n_drawdowns <- length(dd_runs)
        avg_dd <- if (any(in_dd)) mean(dd[in_dd], na.rm = TRUE) else NA_real_

        # Max drawdown duration in observations (calendar days proxy: *1 for daily, *21 for monthly)
        max_dd_duration <- if (n_drawdowns > 0L) as.integer(max(dd_runs)) else NA_integer_

        # Recovery: obs from max_dd trough to first recovery above prior peak
        trough_idx <- which.min(dd)
        recovery_obs <- NA_integer_
        if (!is.na(trough_idx) && trough_idx < length(dd)) {
          post_trough <- dd[(trough_idx + 1L):length(dd)]
          rec_rel <- which(post_trough >= -0.001)[1L]  # within 0.1% of peak
          if (!is.na(rec_rel)) recovery_obs <- as.integer(rec_rel)
        }

        list(
          max_dd               = max_dd,
          avg_dd               = avg_dd,
          max_dd_duration_obs  = max_dd_duration,
          n_drawdowns          = as.integer(n_drawdowns),
          recovery_obs         = recovery_obs
        )
      }

      # ── Helper: compute all backfill metrics for one strategy ──────
      compute_backfill_metrics <- function(daily_ret_df, spy_ret_df,
                                           ann_factor = 252L,
                                           ff_result = NULL) {
        ret <- daily_ret_df$strategy_ret
        ret <- ret[!is.na(ret)]

        if (length(ret) < 10L) {
          return(list(
            start_date = NA, end_date = NA, duration_days = NA_integer_,
            exposure_time_pct = NA_real_, total_return_pct = NA_real_,
            cagr = NA_real_, vol = NA_real_, sharpe_naive = NA_real_,
            sortino = NA_real_, calmar = NA_real_,
            correlation_benchmark = NA_real_,
            max_dd = NA_real_, avg_dd = NA_real_,
            max_dd_duration_days = NA_integer_, n_drawdowns = NA_integer_,
            recovery_days = NA_integer_,
            cvar_5pct = NA_real_, skewness = NA_real_, kurtosis = NA_real_,
            beta_mkt = NA_real_, best_month = NA_real_, worst_month = NA_real_,
            hit_rate_months = NA_real_
          ))
        }

        dates <- daily_ret_df$date[!is.na(daily_ret_df$strategy_ret)]
        start_date <- min(dates)
        end_date   <- max(dates)
        duration_days <- as.integer(as.numeric(difftime(end_date, start_date, units = "days")))

        # Exposure: 100% for all strategies (fully invested when in market)
        exposure_time_pct <- 100.0

        # Cumulative return
        total_return_pct <- (prod(1 + ret) - 1) * 100

        # CAGR
        n_years <- duration_days / 365.25
        cagr <- if (n_years > 0) (prod(1 + ret)^(1 / n_years)) - 1 else NA_real_

        # Volatility (annualised)
        vol <- stats::sd(ret, na.rm = TRUE) * sqrt(ann_factor)

        # Sharpe (naive, no risk-free adjustment)
        ann_mean <- mean(ret) * ann_factor
        sharpe_naive <- if (!is.na(vol) && vol > 0) ann_mean / vol else NA_real_

        # Sortino
        neg_ret  <- ret[ret < 0]
        downside <- if (length(neg_ret) >= 4L) {
          stats::sd(neg_ret) * sqrt(ann_factor)
        } else NA_real_
        sortino <- if (!is.na(downside) && downside > 0) ann_mean / downside else NA_real_

        # Drawdown metrics (observations-based; convert to calendar-days using ann_factor)
        obs_per_month <- ann_factor / 12
        dd_list <- compute_drawdowns(ret)
        max_dd   <- dd_list$max_dd
        avg_dd   <- dd_list$avg_dd
        n_drawdowns <- dd_list$n_drawdowns
        # Convert observation counts to calendar days
        max_dd_duration_days <- if (!is.na(dd_list$max_dd_duration_obs)) {
          as.integer(round(dd_list$max_dd_duration_obs * (365.25 / ann_factor)))
        } else NA_integer_
        recovery_days <- if (!is.na(dd_list$recovery_obs)) {
          as.integer(round(dd_list$recovery_obs * (365.25 / ann_factor)))
        } else NA_integer_

        # Calmar
        calmar <- if (!is.na(max_dd) && max_dd < 0) cagr / abs(max_dd) else NA_real_

        # Correlation with SPY benchmark (align dates)
        aligned <- dplyr::inner_join(daily_ret_df, spy_ret_df, by = "date") |>
          dplyr::filter(!is.na(strategy_ret), !is.na(spy_ret))
        correlation_benchmark <- if (nrow(aligned) >= 10L) {
          stats::cor(aligned$strategy_ret, aligned$spy_ret, use = "complete.obs")
        } else NA_real_

        # CVaR 5%
        q5     <- stats::quantile(ret, 0.05, na.rm = TRUE)
        cvar_5 <- mean(ret[ret <= q5], na.rm = TRUE)

        # Higher moments
        n      <- length(ret)
        mu     <- mean(ret)
        sigma  <- stats::sd(ret)
        skewness <- if (sigma > 0 && n >= 4L) {
          (sum((ret - mu)^3) / n) / sigma^3
        } else NA_real_
        kurtosis <- if (sigma > 0 && n >= 4L) {
          (sum((ret - mu)^4) / n) / sigma^4
        } else NA_real_

        # Beta to market (from FF regression if available)
        beta_mkt <- if (!is.null(ff_result) && "beta_Mkt_RF" %in% names(ff_result)) {
          ff_result$beta_Mkt_RF[[1L]]
        } else NA_real_

        # Monthly aggregation for best/worst month and hit rate
        # Group by year-month regardless of ann_factor
        monthly_ret <- daily_ret_df |>
          dplyr::filter(!is.na(strategy_ret)) |>
          dplyr::mutate(ym = format(date, "%Y-%m")) |>
          dplyr::group_by(ym) |>
          dplyr::summarise(
            m_ret = prod(1 + strategy_ret) - 1,
            .groups = "drop"
          )
        best_month  <- if (nrow(monthly_ret) > 0L) max(monthly_ret$m_ret) else NA_real_
        worst_month <- if (nrow(monthly_ret) > 0L) min(monthly_ret$m_ret) else NA_real_
        hit_rate_months <- if (nrow(monthly_ret) > 0L) {
          mean(monthly_ret$m_ret > 0)
        } else NA_real_

        list(
          start_date            = start_date,
          end_date              = end_date,
          duration_days         = duration_days,
          exposure_time_pct     = exposure_time_pct,
          total_return_pct      = total_return_pct,
          cagr                  = cagr,
          vol                   = vol,
          sharpe_naive          = sharpe_naive,
          sortino               = sortino,
          calmar                = calmar,
          correlation_benchmark = correlation_benchmark,
          max_dd                = max_dd,
          avg_dd                = avg_dd,
          max_dd_duration_days  = max_dd_duration_days,
          n_drawdowns           = n_drawdowns,
          recovery_days         = recovery_days,
          cvar_5pct             = cvar_5,
          skewness              = skewness,
          kurtosis              = kurtosis,
          beta_mkt              = beta_mkt,
          best_month            = best_month,
          worst_month           = worst_month,
          hit_rate_months       = hit_rate_months
        )
      }

      # ── Per-strategy ann_factors ───────────────────────────────────
      # avoid_worst=daily(252), drif=monthly(12), fac_max=monthly(12),
      # rsc=daily(252), ltr=monthly(12)
      strategy_ann <- c(
        avoid_worst = 252L,
        drif        = 12L,
        fac_max     = 12L,
        rsc         = 252L,
        ltr         = 12L
      )

      strategy_inputs <- list(
        avoid_worst = fals_avoid_worst_input,
        drif        = fals_drif_input,
        fac_max     = fals_fac_max_input,
        rsc         = fals_rsc_input,
        ltr         = fals_ltr_input
      )

      ff_results <- list(
        avoid_worst = fals_ff_avoid_worst,
        drif        = fals_ff_drif,
        fac_max     = fals_ff_fac_max,
        rsc         = fals_ff_rsc,
        ltr         = fals_ff_ltr
      )

      # ── Compute metrics for each strategy ─────────────────────────
      metrics_list <- lapply(names(strategy_inputs), function(strat) {
        compute_backfill_metrics(
          daily_ret_df  = strategy_inputs[[strat]],
          spy_ret_df    = fals_spy_ret,
          ann_factor    = strategy_ann[[strat]],
          ff_result     = ff_results[[strat]]
        )
      })
      names(metrics_list) <- names(strategy_inputs)

      # ── Build base results rows ────────────────────────────────────
      summary <- fals_summary

      rows <- tibble::tibble(
        run_date    = Sys.Date(),
        strategy_id = summary$strategy,
        asset_class = c("overlay", "factor", "factor", "overlay", "equity"),
        partition   = "full",
        benchmark   = "SPY",
        is_negative = c(TRUE, FALSE, FALSE, TRUE, FALSE),

        # Performance metrics (backfilled)
        start_date            = as.Date(sapply(metrics_list, `[[`, "start_date")),
        end_date              = as.Date(sapply(metrics_list, `[[`, "end_date")),
        duration_days         = as.integer(sapply(metrics_list, `[[`, "duration_days")),
        exposure_time_pct     = as.double(sapply(metrics_list, `[[`, "exposure_time_pct")),
        total_return_pct      = as.double(sapply(metrics_list, `[[`, "total_return_pct")),
        cagr                  = as.double(sapply(metrics_list, `[[`, "cagr")),
        vol                   = as.double(sapply(metrics_list, `[[`, "vol")),
        sharpe_naive          = as.double(sapply(metrics_list, `[[`, "sharpe_naive")),
        sortino               = as.double(sapply(metrics_list, `[[`, "sortino")),
        calmar                = as.double(sapply(metrics_list, `[[`, "calmar")),
        correlation_benchmark = as.double(sapply(metrics_list, `[[`, "correlation_benchmark")),

        # From HAC falsification
        hac_tstat  = summary$hac_tstat,
        sharpe_hac = summary$hac_sharpe,

        # Drawdown metrics (backfilled)
        max_dd               = as.double(sapply(metrics_list, `[[`, "max_dd")),
        avg_dd               = as.double(sapply(metrics_list, `[[`, "avg_dd")),
        max_dd_duration_days = as.integer(sapply(metrics_list, `[[`, "max_dd_duration_days")),
        n_drawdowns          = as.integer(sapply(metrics_list, `[[`, "n_drawdowns")),
        recovery_days        = as.integer(sapply(metrics_list, `[[`, "recovery_days")),

        # Risk metrics (backfilled)
        cvar_5pct       = as.double(sapply(metrics_list, `[[`, "cvar_5pct")),
        skewness        = as.double(sapply(metrics_list, `[[`, "skewness")),
        kurtosis        = as.double(sapply(metrics_list, `[[`, "kurtosis")),
        beta_mkt        = as.double(sapply(metrics_list, `[[`, "beta_mkt")),
        best_month      = as.double(sapply(metrics_list, `[[`, "best_month")),
        worst_month     = as.double(sapply(metrics_list, `[[`, "worst_month")),
        hit_rate_months = as.double(sapply(metrics_list, `[[`, "hit_rate_months")),

        # Falsification
        ff_alpha_annual = summary$ff_alpha_annual,
        ff_alpha_tstat  = summary$ff_alpha_tstat,
        ff_r_squared    = summary$ff_r_squared,
        rej_rate_wn     = summary$rej_rate_wn,
        rej_rate_rv     = summary$rej_rate_rv,
        rej_rate_ma1    = summary$rej_rate_ma1,
        rej_rate_fn     = summary$rej_rate_fn,
        rej_rate_garch  = summary$rej_rate_garch,
        rej_rate_gjr    = summary$rej_rate_gjr,

        # Notes
        note_1 = c(
          "Pure market beta (R\u00b2=41%)",
          "Genuine alpha",
          "Genuine alpha",
          "Pure market beta (R\u00b2=88%)",
          "Cross-sectional momentum (~51 US stocks, demo)"
        ),
        tag_1 = c("vol-timing", "momentum", "momentum", "vol-timing", "cross-sectional"),
        tag_2 = c("daily", "monthly", "monthly", "daily", "monthly")
      )

      # K_eff and delta_z (same for all strategies in a run)
      rows$k_eff   <- fals_keff$K_eff
      rows$delta_z <- fals_delta_z$delta_z

      hd_results_append(rows)
      rows
    }, cue = targets::tar_cue(mode = "always"))

  )
}
