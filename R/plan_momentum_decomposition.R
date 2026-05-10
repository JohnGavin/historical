# Targets Plan: Momentum Decomposition
# Based on De Boer, Gao, Montminy (2025): "Optimizing the Persistence of Price Momentum"

plan_momentum_decomposition <- function() {
  list(
    # 1. Download Ken French factor data
    tar_target(
      ff_5factors,
      hd_ff_factors("F-F_Research_Data_5_Factors_2x3", "monthly", cache = TRUE),
      cue = tar_cue("always")  # Always check for updates
    ),

    tar_target(
      ff_momentum,
      hd_ff_factors("F-F_Momentum_Factor", "monthly", cache = TRUE),
      cue = tar_cue("always")
    ),

    tar_target(
      ff_industries_12,
      hd_ff_factors("12_Industry_Portfolios", "monthly", cache = TRUE),
      cue = tar_cue("always")
    ),

    # 2. Prepare stock returns for decomposition
    # Use LTR universe (529 stocks with >= 252 days history)
    tar_target(
      stock_returns_monthly,
      {
        # Load from existing LTR universe
        ltr_univ <- tar_read(ltr_universe)

        ltr_univ |>
          mutate(ym = format(date, "%Y-%m")) |>
          group_by(ticker, ym) |>
          summarise(
            date = max(date),  # Month-end date
            monthly_ret = prod(1 + (adjusted / lag(adjusted) - 1), na.rm = TRUE) - 1,
            .groups = "drop"
          ) |>
          select(ticker, date, monthly_ret) |>
          filter(!is.na(monthly_ret))
      }
    ),

    # 3. Decompose momentum into components
    tar_target(
      momentum_components,
      {
        decompose_momentum(
          stock_returns = stock_returns_monthly,
          factor_returns = ff_5factors,
          industry_returns = ff_industries_12,
          lookback_months = 12,
          min_obs = 6
        )
      }
    ),

    # 4. Compute persistence metrics
    tar_target(
      persistence_metrics,
      {
        compute_persistence(
          decomposed_momentum = momentum_components,
          stock_returns = stock_returns_monthly,
          horizons = c("1m", "3m", "6m", "12m")
        )
      }
    ),

    # 5. Visualize persistence
    tar_target(
      persistence_plot,
      {
        plot_persistence_by_component(
          persistence_metrics,
          title = "Which Momentum Components Persist? (De Boer et al. 2025 Replication)"
        )
      }
    ),

    # 6. Comparison: Total momentum vs decomposed
    tar_target(
      momentum_comparison,
      {
        # Total 12m return
        total_momentum <- stock_returns_monthly |>
          group_by(ticker) |>
          arrange(date) |>
          mutate(
            ret_12m = RcppRoll::roll_prodr(1 + monthly_ret, n = 12) - 1
          ) |>
          ungroup() |>
          select(ticker, date, total_momentum = ret_12m)

        # Join with components
        comparison <- momentum_components |>
          inner_join(total_momentum, by = c("ticker", "date")) |>
          mutate(
            # Sum of components should approximate total return
            sum_components = beta_momentum + style_momentum + industry_momentum + stock_specific_momentum,
            residual = ret_12m - sum_components
          )

        # Summary stats
        list(
          correlation = cor(comparison$ret_12m, comparison$sum_components, use = "complete.obs"),
          mean_residual = mean(comparison$residual, na.rm = TRUE),
          median_residual = median(comparison$residual, na.rm = TRUE),
          rmse = sqrt(mean(comparison$residual^2, na.rm = TRUE)),
          data = comparison
        )
      }
    ),

    # 7. Summary table for display
    tar_target(
      momentum_summary_table,
      {
        persistence_metrics |>
          mutate(
            component_label = recode(
              component,
              beta_momentum = "Beta (Market)",
              style_momentum = "Style (Value/Size/Profitability/Investment)",
              industry_momentum = "Industry (12 Sectors)",
              stock_specific_momentum = "Stock-Specific (Residual)"
            ),
            significance = case_when(
              abs(t_stat) > 2.576 ~ "***",  # 1% level
              abs(t_stat) > 1.960 ~ "**",   # 5% level
              abs(t_stat) > 1.645 ~ "*",    # 10% level
              TRUE ~ ""
            )
          ) |>
          select(
            Component = component_label,
            Horizon = horizon,
            `Rank IC` = rank_ic,
            `t-stat` = t_stat,
            Sig = significance,
            `N Months` = n_months
          ) |>
          arrange(Horizon, desc(abs(`Rank IC`)))
      }
    ),

    # 8. Component statistics
    tar_target(
      component_stats,
      {
        momentum_components |>
          summarise(
            across(
              c(ret_12m, beta_momentum, style_momentum, industry_momentum, stock_specific_momentum),
              list(
                mean = ~mean(.x, na.rm = TRUE),
                sd = ~sd(.x, na.rm = TRUE),
                median = ~median(.x, na.rm = TRUE),
                q25 = ~quantile(.x, 0.25, na.rm = TRUE),
                q75 = ~quantile(.x, 0.75, na.rm = TRUE)
              ),
              .names = "{.col}_{.fn}"
            )
          ) |>
          tidyr::pivot_longer(
            everything(),
            names_to = c("component", "stat"),
            names_sep = "_(?=[^_]+$)"  # Split on last underscore
          ) |>
          tidyr::pivot_wider(
            names_from = stat,
            values_from = value
          ) |>
          mutate(
            component = recode(
              component,
              ret = "Total 12m Return",
              beta = "Beta Component",
              style = "Style Component",
              industry = "Industry Component",
              stock_specific = "Stock-Specific Component"
            )
          )
      }
    ),

    # 9. Cross-sectional dispersion (width of momentum spread)
    tar_target(
      momentum_dispersion,
      {
        momentum_components |>
          group_by(date) |>
          summarise(
            across(
              c(ret_12m, beta_momentum, style_momentum, industry_momentum, stock_specific_momentum),
              list(
                iqr = ~IQR(.x, na.rm = TRUE),
                sd = ~sd(.x, na.rm = TRUE),
                range = ~diff(range(.x, na.rm = TRUE))
              ),
              .names = "{.col}_{.fn}"
            ),
            n_stocks = n(),
            .groups = "drop"
          )
      }
    ),

    # 10. Time series plot: component dispersion over time
    tar_target(
      dispersion_plot,
      {
        dispersion_long <- momentum_dispersion |>
          select(date, ends_with("_iqr")) |>
          tidyr::pivot_longer(
            -date,
            names_to = "component",
            values_to = "iqr"
          ) |>
          mutate(
            component = sub("_momentum_iqr$", "", component),
            component = sub("_iqr$", "", component),
            component_label = recode(
              component,
              ret_12m = "Total 12m",
              beta = "Beta",
              style = "Style",
              industry = "Industry",
              stock_specific = "Stock-Specific"
            )
          )

        ggplot(dispersion_long, aes(x = date, y = iqr, color = component_label)) +
          geom_line(linewidth = 0.8) +
          labs(
            title = "Cross-Sectional Dispersion of Momentum Components",
            subtitle = "Interquartile range (IQR) over time",
            x = NULL,
            y = "IQR",
            color = "Component"
          ) +
          theme_minimal() +
          theme(legend.position = "bottom")
      }
    )
  )
}
