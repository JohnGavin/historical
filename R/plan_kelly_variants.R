# Enhanced Kelly position sizing variants (#56)
#
# Compares four Kelly methods per strategy:
#   1. Fractional Kelly sweep (25%, 50%, 75%, 100%)
#   2. Bayesian Kelly (Beta-Binomial posterior mean)
#   3. Bounded Kelly (survival-constrained, quarter-Kelly)
#
# All inputs are from fals_*_input targets (OOS returns, look-ahead-bias safe).

plan_kelly_variants <- function() {
  list(
    targets::tar_target(kv_params, {
      list(
        fractions = c(0.25, 0.50, 0.75, 1.00),
        rolling_windows = c(63L, 126L, 252L),
        seed = 42L
      )
    }),

    targets::tar_target(kv_sweep, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      strategies <- list(
        drif    = fals_drif_input$strategy_ret,
        fac_max = fals_fac_max_input$strategy_ret,
        ltr     = fals_ltr_input$strategy_ret
      )

      # Fractional Kelly sweep
      purrr::map_dfr(names(strategies), function(strat) {
        ret <- strategies[[strat]]
        ret <- ret[!is.na(ret)]
        purrr::map_dfr(kv_params$fractions, function(frac) {
          f <- mean(ret) / var(ret) * frac
          f <- max(0, min(1, f))
          strat_ret <- ret * f
          n <- length(strat_ret)
          tibble(
            strategy   = strat,
            method     = paste0("Fractional (", frac * 100, "%)"),
            fraction   = frac,
            f_star     = round(f, 4),
            cagr_pct   = round((prod(1 + strat_ret)^(12 / n) - 1) * 100, 1),
            vol_pct    = round(sd(strat_ret) * sqrt(12) * 100, 1),
            sharpe     = round(mean(strat_ret) / sd(strat_ret) * sqrt(12), 2),
            max_dd_pct = round(
              min((cumprod(1 + strat_ret) -
                     cummax(cumprod(1 + strat_ret))) /
                    cummax(cumprod(1 + strat_ret))) * 100, 1),
            bankrupt   = any(cumprod(1 + strat_ret) < 0.01)
          )
        })
      })
    }),

    targets::tar_target(kv_bayesian, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      strategies <- list(
        drif    = fals_drif_input$strategy_ret,
        fac_max = fals_fac_max_input$strategy_ret,
        ltr     = fals_ltr_input$strategy_ret
      )

      purrr::map_dfr(names(strategies), function(strat) {
        ret <- strategies[[strat]]
        ret <- ret[!is.na(ret)]
        bk  <- hd_kelly_bayesian(ret)
        f   <- max(0, min(1, bk$f_star))
        strat_ret <- ret * f
        n <- length(strat_ret)
        tibble(
          strategy   = strat,
          method     = "Bayesian",
          fraction   = NA_real_,
          f_star     = round(f, 4),
          cagr_pct   = round((prod(1 + strat_ret)^(12 / n) - 1) * 100, 1),
          vol_pct    = round(sd(strat_ret) * sqrt(12) * 100, 1),
          sharpe     = round(mean(strat_ret) / sd(strat_ret) * sqrt(12), 2),
          max_dd_pct = round(
            min((cumprod(1 + strat_ret) -
                   cummax(cumprod(1 + strat_ret))) /
                  cummax(cumprod(1 + strat_ret))) * 100, 1),
          bankrupt   = any(cumprod(1 + strat_ret) < 0.01)
        )
      })
    }),

    targets::tar_target(kv_bounded, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)

      strategies <- list(
        drif    = fals_drif_input$strategy_ret,
        fac_max = fals_fac_max_input$strategy_ret,
        ltr     = fals_ltr_input$strategy_ret
      )

      purrr::map_dfr(names(strategies), function(strat) {
        ret <- strategies[[strat]]
        ret <- ret[!is.na(ret)]
        bk  <- hd_kelly_bounded(ret, fraction = 0.25)
        f   <- max(0, min(1, bk$f_star))
        strat_ret <- ret * f
        n <- length(strat_ret)
        tibble(
          strategy   = strat,
          method     = "Bounded",
          fraction   = 0.25,
          f_star     = round(f, 4),
          cagr_pct   = round((prod(1 + strat_ret)^(12 / n) - 1) * 100, 1),
          vol_pct    = round(sd(strat_ret) * sqrt(12) * 100, 1),
          sharpe     = round(mean(strat_ret) / sd(strat_ret) * sqrt(12), 2),
          max_dd_pct = round(
            min((cumprod(1 + strat_ret) -
                   cummax(cumprod(1 + strat_ret))) /
                  cummax(cumprod(1 + strat_ret))) * 100, 1),
          bankrupt   = any(cumprod(1 + strat_ret) < 0.01)
        )
      })
    }),

    targets::tar_target(kv_comparison, {
      library(dplyr)
      bind_rows(kv_sweep, kv_bayesian, kv_bounded) |>
        arrange(strategy, method)
    }),

    targets::tar_target(kv_caption, {
      library(dplyr)
      best <- kv_comparison |>
        group_by(strategy) |>
        slice_max(sharpe, n = 1, with_ties = FALSE)

      paste0(
        "Kelly criterion variants across ", n_distinct(kv_comparison$strategy),
        " strategies. ", nrow(kv_comparison), " configurations tested. ",
        "Best per strategy: ",
        paste(best$strategy, best$method, "(Sharpe", best$sharpe, ")",
              collapse = "; "),
        ". Bankrupt: ", sum(kv_comparison$bankrupt),
        " configurations hit ruin (<1% of peak)."
      )
    })
  )
}
