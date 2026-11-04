# Plan: JST Macrohistory Database Analysis (#98 Phase 2)
#
# Analyzes 155-year global asset returns from the Jordà-Schularick-Taylor
# database: equity premium by country/decade, comparison with FF factors,
# cross-geography pervasiveness tests.
#
# Upstream: none (hd_jst() fetches from macrohistory.net)
# Downstream: vignettes, cross-geography-pervasiveness rule validation
#
# Naming convention: jst_*
# Total targets: 6

plan_jst <- function() {
  list(

    # ── Load JST data ─────────────────────────────────────────────────────
    targets::tar_target(jst_raw, {
      hd_jst(cache = TRUE)
    }),

    # ── Equity premium by country and decade ──────────────────────────────
    # Key metric: eq_tr - bill_rate (equity total return minus short rate)
    targets::tar_target(jst_equity_premium, {
      jst_raw |>
        dplyr::filter(!is.na(eq_tr), !is.na(bill_rate)) |>
        dplyr::mutate(
          equity_premium = eq_tr - bill_rate,
          decade = floor(year / 10) * 10
        ) |>
        dplyr::group_by(iso, decade) |>
        dplyr::summarise(
          n_years = dplyr::n(),
          mean_premium = round(mean(equity_premium, na.rm = TRUE), 2),
          sd_premium = round(sd(equity_premium, na.rm = TRUE), 2),
          min_premium = round(min(equity_premium, na.rm = TRUE), 2),
          max_premium = round(max(equity_premium, na.rm = TRUE), 2),
          sharpe = round(mean_premium / sd_premium, 2),
          .groups = "drop"
        ) |>
        dplyr::arrange(iso, decade)
    }),

    # ── Cross-geography pervasiveness: is equity premium positive everywhere? ──
    targets::tar_target(jst_pervasiveness, {
      # Full-sample equity premium by country
      country_premium <- jst_raw |>
        dplyr::filter(!is.na(eq_tr), !is.na(bill_rate)) |>
        dplyr::mutate(equity_premium = eq_tr - bill_rate) |>
        dplyr::group_by(iso) |>
        dplyr::summarise(
          from_year = min(year),
          to_year = max(year),
          n_years = dplyr::n(),
          mean_premium = round(mean(equity_premium, na.rm = TRUE), 2),
          sd_premium = round(sd(equity_premium, na.rm = TRUE), 2),
          t_stat = round(mean(equity_premium) / (sd(equity_premium) / sqrt(dplyr::n())), 2),
          pct_positive = round(100 * mean(equity_premium > 0, na.rm = TRUE), 1),
          .groups = "drop"
        ) |>
        dplyr::mutate(
          # Pervasive = positive mean premium, t > 2, majority positive years
          pervasive = mean_premium > 0 & t_stat > 2 & pct_positive > 50
        ) |>
        dplyr::arrange(dplyr::desc(mean_premium))

      country_premium
    }),

    # ── Financial crisis detection (crisisJST indicator) ──────────────────
    targets::tar_target(jst_crises, {
      jst_raw |>
        dplyr::filter(crisisJST == 1) |>
        dplyr::select(iso, year) |>
        dplyr::arrange(iso, year) |>
        dplyr::group_by(iso) |>
        dplyr::summarise(
          n_crises = dplyr::n(),
          crisis_years = paste(year, collapse = ", "),
          .groups = "drop"
        ) |>
        dplyr::arrange(dplyr::desc(n_crises))
    }),

    # ── Summary for dashboard caption ─────────────────────────────────────
    targets::tar_target(jst_summary, {
      n_countries <- length(unique(jst_raw$iso))
      year_range <- range(jst_raw$year, na.rm = TRUE)
      n_obs <- nrow(jst_raw)

      pervasive_countries <- sum(jst_pervasiveness$pervasive, na.rm = TRUE)
      total_countries <- nrow(jst_pervasiveness)

      list(
        n_countries = n_countries,
        year_range = year_range,
        n_obs = n_obs,
        pervasive_count = pervasive_countries,
        pervasive_total = total_countries
      )
    })
  )
}
