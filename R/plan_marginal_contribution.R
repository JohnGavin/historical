# Plan: Marginal Contribution Analysis (#54)
#
# Does adding strategy N improve the portfolio?
# Tests all combinations of the 2 confirmed alpha strategies (DRIF, Factor MAX)
# plus borderline (LTR) to measure diversification benefit.

plan_marginal_contribution <- function() {
  list(

    targets::tar_target(mc_analysis, {
      library(dplyr)

      # Align strategies by year-month (dates differ: mid-month vs end-of-month)
      drif <- fals_drif_input |> mutate(ym = format(date, "%Y-%m")) |>
        select(ym, drif = strategy_ret)
      fmax <- fals_fac_max_input |> mutate(ym = format(date, "%Y-%m")) |>
        select(ym, fac_max = strategy_ret)
      ltr  <- fals_ltr_input |> mutate(ym = format(date, "%Y-%m")) |>
        select(ym, ltr = strategy_ret)

      # Merge all three
      all3 <- drif |>
        inner_join(fmax, by = "ym") |>
        inner_join(ltr, by = "ym")

      ann <- 12  # monthly

      # Helper: compute portfolio stats
      port_stats <- function(rets, name) {
        r <- rowMeans(rets, na.rm = TRUE)
        tibble(
          portfolio = name,
          n_strategies = ncol(rets),
          n_months = length(r),
          ann_return_pct = round(mean(r) * ann * 100, 1),
          ann_vol_pct = round(sd(r) * sqrt(ann) * 100, 1),
          sharpe = round(mean(r) / sd(r) * sqrt(ann), 2),
          max_dd_pct = round(min((cumprod(1 + r) - cummax(cumprod(1 + r))) /
                                   cummax(cumprod(1 + r))) * 100, 1),
          calmar = round((prod(1 + r)^(ann / length(r)) - 1) /
                           abs(min((cumprod(1 + r) - cummax(cumprod(1 + r))) /
                                     cummax(cumprod(1 + r)))), 2)
        )
      }

      # All portfolio combinations
      combos <- bind_rows(
        port_stats(all3[, "drif", drop = FALSE], "DRIF alone"),
        port_stats(all3[, "fac_max", drop = FALSE], "Factor MAX alone"),
        port_stats(all3[, "ltr", drop = FALSE], "LTR alone"),
        port_stats(all3[, c("drif", "fac_max")], "DRIF + Factor MAX"),
        port_stats(all3[, c("drif", "ltr")], "DRIF + LTR"),
        port_stats(all3[, c("fac_max", "ltr")], "Factor MAX + LTR"),
        port_stats(all3[, c("drif", "fac_max", "ltr")], "All three")
      )

      # Correlation matrix
      cor_mat <- cor(all3[, c("drif", "fac_max", "ltr")], use = "complete.obs")

      list(
        combinations = combos,
        correlation = round(cor_mat, 3),
        n_overlap_months = nrow(all3),
        date_range = paste(min(all3$ym), "to", max(all3$ym))
      )
    }),

    targets::tar_target(mc_caption, {
      mc <- mc_analysis
      combos <- mc$combinations
      best <- combos |> dplyr::slice_max(sharpe, n = 1)
      drif_alone <- combos |> dplyr::filter(portfolio == "DRIF alone")
      combined <- combos |> dplyr::filter(portfolio == "DRIF + Factor MAX")

      paste0(
        "Marginal contribution analysis: equal-weight portfolios of confirmed ",
        "alpha strategies. ", mc$n_overlap_months, " overlapping months (",
        mc$date_range, "). ",
        "Best portfolio: ", best$portfolio, " (Sharpe = ", best$sharpe, "). ",
        "DRIF alone: Sharpe = ", drif_alone$sharpe,
        "; DRIF + Factor MAX: Sharpe = ", combined$sharpe, ". ",
        "Correlation between DRIF and Factor MAX: ",
        mc$correlation["drif", "fac_max"], ". ",
        "At r = ", mc$correlation["drif", "fac_max"],
        ", diversification benefit is limited — both strategies exploit ",
        "similar factor momentum signals."
      )
    })

  )
}
