# Plan: Multi-Strategy Portfolio (#52)
#
# Combines confirmed alpha strategies (DRIF, LTR) with decay-aware weighting.
# Factor MAX downweighted due to >50% decay (#73).
# Uses marginal contribution results from #54.

plan_multi_strategy <- function() {
  list(

    targets::tar_target(ms_params, {
      list(
        # Strategies and weights
        # DRIF: stable, genuine alpha → 50%
        # LTR: stable, borderline alpha, negative correlation → 35%
        # Factor MAX: decayed >50% → 15%
        strategies = c("drif", "fac_max", "ltr"),
        weights = c(drif = 0.50, fac_max = 0.15, ltr = 0.35),
        rebalance = "monthly",
        cost_per_rebalance = 0.002  # 20bps round-trip
      )
    }),

    targets::tar_target(ms_portfolio, {
      library(dplyr)

      w <- ms_params$weights

      # Align by year-month
      drif <- fals_drif_input |> mutate(ym = format(as.Date(date), "%Y-%m")) |>
        select(ym, drif = strategy_ret)
      fmax <- fals_fac_max_input |> mutate(ym = format(as.Date(date), "%Y-%m")) |>
        select(ym, fac_max = strategy_ret)
      ltr <- fals_ltr_input |> mutate(ym = format(as.Date(date), "%Y-%m")) |>
        select(ym, ltr = strategy_ret)

      port <- drif |>
        inner_join(fmax, by = "ym") |>
        inner_join(ltr, by = "ym") |>
        arrange(ym) |>
        mutate(
          # Weighted portfolio return
          port_ret_gross = w["drif"] * drif + w["fac_max"] * fac_max + w["ltr"] * ltr,
          # Rebalance cost each month
          port_ret_net = port_ret_gross - ms_params$cost_per_rebalance,
          # Equal-weight benchmark
          ew_ret = (drif + fac_max + ltr) / 3,
          # Cumulative
          cum_weighted = cumprod(1 + port_ret_net),
          cum_ew = cumprod(1 + ew_ret - ms_params$cost_per_rebalance),
          cum_drif = cumprod(1 + drif),
          cum_ltr = cumprod(1 + ltr)
        )

      port
    }),

    targets::tar_target(ms_metrics, {
      library(dplyr)

      calc <- function(ret, name) {
        ret <- ret[!is.na(ret)]
        n <- length(ret)
        if (n < 12) return(NULL)
        years <- n / 12
        tibble(
          portfolio = name,
          months = n,
          ann_ret_pct = round(mean(ret) * 12 * 100, 1),
          ann_vol_pct = round(sd(ret) * sqrt(12) * 100, 1),
          sharpe = round(mean(ret) / sd(ret) * sqrt(12), 2),
          max_dd_pct = round(min((cumprod(1 + ret) - cummax(cumprod(1 + ret))) /
                                   cummax(cumprod(1 + ret))) * 100, 1),
          calmar = round((prod(1 + ret)^(12 / n) - 1) /
                           abs(min((cumprod(1 + ret) - cummax(cumprod(1 + ret))) /
                                     cummax(cumprod(1 + ret)))), 2)
        )
      }

      p <- ms_portfolio
      bind_rows(
        calc(p$port_ret_net, paste0("Weighted (", paste(ms_params$weights * 100, collapse="/"), ")")),
        calc(p$ew_ret - ms_params$cost_per_rebalance, "Equal Weight"),
        calc(p$drif, "DRIF alone"),
        calc(p$ltr, "LTR alone"),
        calc(p$fac_max, "Factor MAX alone")
      )
    }),

    targets::tar_target(ms_plot, {
      library(ggplot2)
      library(dplyr)

      plot_data <- ms_portfolio |>
        select(ym, Weighted = cum_weighted, `Equal Weight` = cum_ew,
               DRIF = cum_drif, LTR = cum_ltr) |>
        tidyr::pivot_longer(-ym, names_to = "portfolio", values_to = "growth") |>
        mutate(date = as.Date(paste0(ym, "-15")))

      ggplot(plot_data, aes(date, growth, colour = portfolio)) +
        geom_line(linewidth = 0.7) +
        scale_y_log10(labels = scales::dollar) +
        scale_colour_manual(values = c(
          "Weighted" = "#2ecc71", "Equal Weight" = "#e6a817",
          "DRIF" = "#4a90d9", "LTR" = "#e74c3c"
        )) +
        labs(x = NULL, y = "Growth of $1 (log)", colour = NULL,
             title = "Multi-Strategy Portfolio: Decay-Aware Weighting",
             subtitle = "DRIF 50% / LTR 35% / Factor MAX 15% (downweighted for decay)") +
        theme_minimal(base_size = 14) +
        theme(
          plot.background = element_rect(fill = "black", color = NA),
          panel.background = element_rect(fill = "black", color = NA),
          text = element_text(color = "#e0e0e0"),
          axis.text = element_text(color = "#e0e0e0"),
          legend.position = "top",
          legend.background = element_rect(fill = "black"),
          panel.grid.major = element_line(color = "#333"),
          panel.grid.minor = element_blank()
        )
    }),

    targets::tar_target(ms_caption, {
      m <- ms_metrics
      weighted <- m |> dplyr::filter(grepl("Weighted", portfolio))
      ew <- m |> dplyr::filter(portfolio == "Equal Weight")

      paste0(
        "Multi-strategy portfolio with decay-aware weighting: ",
        "DRIF 50% (stable alpha), LTR 35% (negative correlation diversifier), ",
        "Factor MAX 15% (downweighted for >50% decay). ",
        "Weighted: Sharpe ", weighted$sharpe, ", Vol ", weighted$ann_vol_pct,
        "%, Max DD ", weighted$max_dd_pct, "%. ",
        "Equal weight: Sharpe ", ew$sharpe, ", Vol ", ew$ann_vol_pct,
        "%, Max DD ", ew$max_dd_pct, "%. ",
        "Cost: ", ms_params$cost_per_rebalance * 100 * 12, "bps/year rebalancing. ",
        m$months[1], " months overlap."
      )
    })

  )
}
