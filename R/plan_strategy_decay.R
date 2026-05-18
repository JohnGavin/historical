# Plan: Strategy Decay Detection (#73)
#
# Measures how each strategy holds up across structurally distinct
# macro regimes. Strategies with high decay get downweighted.
#
# Regimes defined by: Fed funds rate direction (hiking/easing),
# yield curve (inverted/normal), VIX level (low/high/crisis).

plan_strategy_decay <- function() {
  list(

    # ── Macro regime classification ─────────────────────────────
    targets::tar_target(decay_regimes, {
      library(dplyr)

      # Monthly macro data for regime classification
      ff_rate <- hd_macro("FEDFUNDS") |>
        mutate(date = as.Date(date), ym = format(date, "%Y-%m")) |>
        group_by(ym) |>
        summarise(fed_funds = mean(value, na.rm = TRUE), .groups = "drop")

      spread <- hd_macro("T10Y2Y") |>
        mutate(date = as.Date(date), ym = format(date, "%Y-%m")) |>
        group_by(ym) |>
        summarise(t10y2y = mean(value, na.rm = TRUE), .groups = "drop")

      vix <- hd_macro("VIXCLS") |>
        mutate(date = as.Date(date), ym = format(date, "%Y-%m")) |>
        group_by(ym) |>
        summarise(vix = mean(value, na.rm = TRUE), .groups = "drop")

      # Combine and classify
      regimes <- ff_rate |>
        left_join(spread, by = "ym") |>
        left_join(vix, by = "ym") |>
        arrange(ym) |>
        mutate(
          # Fed direction: 6-month change in fed funds
          fed_delta_6m = fed_funds - lag(fed_funds, 6),
          fed_regime = case_when(
            is.na(fed_delta_6m) ~ "unknown",
            fed_delta_6m > 0.25 ~ "hiking",
            fed_delta_6m < -0.25 ~ "easing",
            TRUE ~ "stable"
          ),

          # Yield curve
          curve_regime = case_when(
            is.na(t10y2y) ~ "unknown",
            t10y2y < 0 ~ "inverted",
            t10y2y < 0.5 ~ "flat",
            TRUE ~ "normal"
          ),

          # VIX regime
          vix_regime = case_when(
            is.na(vix) ~ "unknown",
            vix > 30 ~ "crisis",
            vix > 20 ~ "elevated",
            TRUE ~ "calm"
          )
        ) |>
        filter(fed_regime != "unknown")

      regimes
    }),

    # ── Per-strategy × per-regime performance ───────────────────
    targets::tar_target(decay_analysis, {
      library(dplyr)

      regimes <- decay_regimes

      # Strategy returns aligned to year-month
      strategies <- list(
        drif = fals_drif_input |> mutate(ym = format(as.Date(date), "%Y-%m")),
        fac_max = fals_fac_max_input |> mutate(ym = format(as.Date(date), "%Y-%m")),
        ltr = fals_ltr_input |> mutate(ym = format(as.Date(date), "%Y-%m"))
      )

      # For each regime dimension × strategy: compute Sharpe
      regime_dims <- c("fed_regime", "curve_regime", "vix_regime")

      results <- list()
      for (strat_name in names(strategies)) {
        strat <- strategies[[strat_name]] |>
          select(ym, ret = strategy_ret)

        for (rdim in regime_dims) {
          reg_col <- regimes[[rdim]]
          reg_df <- tibble::tibble(ym = regimes$ym, regime = reg_col)
          merged <- strat |>
            inner_join(reg_df, by = "ym") |>
            filter(!is.na(ret), regime != "unknown")

          regime_stats <- merged |>
            group_by(regime) |>
            summarise(
              n_months = n(),
              ann_ret = mean(ret) * 12 * 100,
              ann_vol = sd(ret) * sqrt(12) * 100,
              sharpe = if (sd(ret) > 0) mean(ret) / sd(ret) * sqrt(12) else NA_real_,
              max_dd = min((cumprod(1 + ret) - cummax(cumprod(1 + ret))) /
                             cummax(cumprod(1 + ret))) * 100,
              .groups = "drop"
            ) |>
            mutate(
              strategy = strat_name,
              regime_dim = rdim,
              ann_ret = round(ann_ret, 1),
              ann_vol = round(ann_vol, 1),
              sharpe = round(sharpe, 2),
              max_dd = round(max_dd, 1)
            )

          results[[length(results) + 1]] <- regime_stats
        }
      }

      bind_rows(results)
    }),

    # ── Decay metric: recent vs historical ──────────────────────
    targets::tar_target(decay_scores, {
      library(dplyr)

      regimes <- decay_regimes
      strategies <- list(
        drif = fals_drif_input |> mutate(ym = format(as.Date(date), "%Y-%m")),
        fac_max = fals_fac_max_input |> mutate(ym = format(as.Date(date), "%Y-%m")),
        ltr = fals_ltr_input |> mutate(ym = format(as.Date(date), "%Y-%m"))
      )

      # Split: first half vs second half of each strategy's history
      decay_list <- lapply(names(strategies), function(strat_name) {
        strat <- strategies[[strat_name]] |>
          select(ym, ret = strategy_ret) |>
          filter(!is.na(ret)) |>
          arrange(ym)

        mid <- nrow(strat) %/% 2
        early <- strat[1:mid, ]
        late <- strat[(mid + 1):nrow(strat), ]

        early_sharpe <- if (sd(early$ret) > 0) mean(early$ret) / sd(early$ret) * sqrt(12) else 0
        late_sharpe <- if (sd(late$ret) > 0) mean(late$ret) / sd(late$ret) * sqrt(12) else 0

        # Decay = (early - late) / |early| — positive means decay
        decay <- if (abs(early_sharpe) > 0.01) {
          (early_sharpe - late_sharpe) / abs(early_sharpe)
        } else NA_real_

        tibble(
          strategy = strat_name,
          early_period = paste(min(early$ym), "to", max(early$ym)),
          late_period = paste(min(late$ym), "to", max(late$ym)),
          early_months = nrow(early),
          late_months = nrow(late),
          early_sharpe = round(early_sharpe, 2),
          late_sharpe = round(late_sharpe, 2),
          decay_pct = round(decay * 100, 1),
          decayed = !is.na(decay) && decay > 0.5  # >50% decay = flag
        )
      })

      bind_rows(decay_list)
    }),

    # ── Caption ─────────────────────────────────────────────────
    targets::tar_target(decay_caption, {
      ds <- decay_scores
      nms <- strategy_names |>
        dplyr::filter(code_name %in% ds$strategy)

      decayed <- ds |> dplyr::filter(decayed)
      stable <- ds |> dplyr::filter(!decayed)

      paste0(
        "Strategy decay analysis: Sharpe ratio in early vs late half of each ",
        "strategy's history. ",
        if (nrow(decayed) > 0) paste0(
          paste(nms$long_name[match(decayed$strategy, nms$code_name)], collapse = " and "),
          " show >50% decay. "
        ) else "No strategy shows >50% decay. ",
        if (nrow(stable) > 0) paste0(
          paste(nms$long_name[match(stable$strategy, nms$code_name)], collapse = " and "),
          " are stable across time periods."
        ) else ""
      )
    })

  )
}
