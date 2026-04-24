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
        )
      )
    }),


    # ═══════════════════════════════════════════════════════════════════
    # Results database: persist this run to parquet log
    # ═══════════════════════════════════════════════════════════════════

    targets::tar_target(fals_results_db, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      summary <- fals_summary

      # Build results rows from falsification summary
      rows <- tibble::tibble(
        run_date    = Sys.Date(),
        strategy_id = summary$strategy,
        asset_class = c("overlay", "factor", "factor", "overlay", "equity"),  # avoid_worst, drif, fac_max, rsc, ltr
        partition   = "full",
        benchmark   = "SPY",
        is_negative = c(TRUE, FALSE, FALSE, TRUE, FALSE),

        # From falsification
        hac_tstat      = summary$hac_tstat,
        sharpe_hac     = summary$hac_sharpe,
        ff_alpha_annual = summary$ff_alpha_annual,
        ff_alpha_tstat  = summary$ff_alpha_tstat,
        ff_r_squared    = summary$ff_r_squared,
        rej_rate_wn    = summary$rej_rate_wn,
        rej_rate_rv    = summary$rej_rate_rv,
        rej_rate_ma1   = summary$rej_rate_ma1,
        rej_rate_fn    = summary$rej_rate_fn,
        rej_rate_garch = summary$rej_rate_garch,
        rej_rate_gjr   = summary$rej_rate_gjr,

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

      # Add K_eff and delta_z (same for all strategies in a run)
      rows$k_eff    <- fals_keff$K_eff
      rows$delta_z  <- fals_delta_z$delta_z

      hd_results_append(rows)
      rows
    }, cue = targets::tar_cue(mode = "always"))

  )
}
