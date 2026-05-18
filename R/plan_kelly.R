# Position sizing: Kelly criterion and fixed % risk (#38)
#
# Compares three sizing modes per strategy:
#   1. Flat 1% risk per trade
#   2. Flat 2% risk per trade
#   3. Fractional Kelly (quarter-Kelly default)
#
# Edge estimated on TRAINING data only (look-ahead-bias safe).
# Kelly fraction: f* = edge / variance, then × fraction (0.25).

plan_kelly <- function() {
  list(
    targets::tar_target(kelly_params, {
      list(
        fraction = 0.25,           # quarter-Kelly
        max_stake_pct = 0.05,      # never exceed 5% of capital
        risk_per_trade = c(0.01, 0.02)  # flat sizing modes
      )
    }),

    # Estimate edge (mean monthly return) and variance on training data only
    targets::tar_target(kelly_edge_estimates, {
      library(dplyr)

      estimate_edge <- function(port_df, ret_col, params, strategy_name) {
        train <- port_df |>
          filter(date <= params$is_end)
        ret <- train[[ret_col]]
        ret <- ret[!is.na(ret)]
        if (length(ret) < 12) return(NULL)
        tibble(
          strategy = strategy_name,
          edge = mean(ret),
          variance = var(ret),
          n_months_train = length(ret),
          kelly_full = ifelse(variance > 0, edge / variance, 0),
          kelly_frac = pmin(kelly_full * kelly_params$fraction,
                           kelly_params$max_stake_pct)
        )
      }

      bind_rows(
        estimate_edge(stk_max_portfolio, "port_ret", stk_params, "Stock MAX"),
        estimate_edge(stk_drif_portfolio, "port_ret", stk_params, "Stock DRIF"),
        estimate_edge(fm_portfolio, "portfolio_ret", fm_params, "Factor MAX"),
        estimate_edge(drif_portfolio, "portfolio_ret", drif_params, "Factor DRIF")
      )
    }),

    # Apply sizing modes to raw portfolio returns
    targets::tar_target(kelly_sized_returns, {
      library(dplyr)

      apply_sizing <- function(port_df, ret_col, strategy_name) {
        ret <- port_df[[ret_col]]
        dates <- port_df$date
        if (is.null(ret) || length(ret) == 0) return(NULL)

        edge_row <- kelly_edge_estimates |> filter(strategy == strategy_name)
        if (nrow(edge_row) == 0) return(NULL)

        kelly_f <- edge_row$kelly_frac

        bind_rows(
          tibble(strategy = strategy_name, sizing = "flat_1pct",
                 date = dates, ym = port_df$ym,
                 sized_ret = ret * 0.01),
          tibble(strategy = strategy_name, sizing = "flat_2pct",
                 date = dates, ym = port_df$ym,
                 sized_ret = ret * 0.02),
          tibble(strategy = strategy_name, sizing = "kelly_quarter",
                 date = dates, ym = port_df$ym,
                 sized_ret = ret * kelly_f)
        )
      }

      bind_rows(
        apply_sizing(stk_max_portfolio, "port_ret", "Stock MAX"),
        apply_sizing(stk_drif_portfolio, "port_ret", "Stock DRIF"),
        apply_sizing(fm_portfolio |> mutate(date = as.Date(paste0(ym, "-15"))),
                     "portfolio_ret", "Factor MAX"),
        apply_sizing(drif_portfolio |> mutate(date = as.Date(paste0(ym, "-15"))),
                     "portfolio_ret", "Factor DRIF")
      )
    }),

    # Metrics per strategy x sizing mode
    targets::tar_target(kelly_metrics, {
      library(dplyr)

      kelly_sized_returns |>
        group_by(strategy, sizing) |>
        summarise(
          months = n(),
          cagr = prod(1 + sized_ret)^(12 / n()) - 1,
          vol = sd(sized_ret) * sqrt(12),
          sharpe = ifelse(vol > 0, cagr / vol, NA_real_),
          max_dd = {
            cum <- cumprod(1 + sized_ret)
            min(cum / cummax(cum) - 1)
          },
          .groups = "drop"
        )
    }),

    # Summary table for leaderboard integration
    targets::tar_target(kelly_sizing_table, {
      library(dplyr)

      kelly_edge_estimates |>
        select(strategy, edge, variance, kelly_full, kelly_frac) |>
        mutate(
          across(c(edge, variance, kelly_full, kelly_frac),
                 ~ round(., 4))
        )
    }),

    # Comparison plot: Sharpe by strategy, grouped by sizing mode
    targets::tar_target(kelly_comparison_plot, {
      library(ggplot2)
      library(dplyr)

      kelly_metrics |>
        ggplot(aes(x = strategy, y = sharpe, fill = sizing)) +
        geom_col(position = "dodge", width = 0.7) +
        scale_fill_manual(
          values = hd_palette(3),
          labels = c("flat_1pct" = "Flat 1%", "flat_2pct" = "Flat 2%",
                     "kelly_quarter" = "Quarter Kelly")
        ) +
        labs(x = NULL, y = "Annualised Sharpe",
             fill = "Sizing Mode",
             title = "Position Sizing: Sharpe by Strategy and Mode") +
        hd_theme() +
        theme(axis.text.x = element_text(angle = 30, hjust = 1))
    })
  )
}
