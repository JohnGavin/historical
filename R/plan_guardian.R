# Plan: Guardian Open Platform news sentiment (#89)
#
# Fetches UK/international financial news from the Guardian Content API.
# Free tier: 12 calls/sec (with key), 1 call/sec (test key).
# Full article text available (unlike NYT which gives snippets only).
#
# Upstream: none (independent data source)
# Downstream: compare with plan_nyt_sentiment, correlate with SPY/STOXX
#
# Naming convention: gdn_*
# Total targets: 5

plan_guardian <- function() {
  list(

    # ── Parameters ──────────────────────────────────────────────────────
    targets::tar_target(gdn_params, {
      list(
        keywords = c("recession", "inflation", "interest rate",
                     "stock market", "central bank", "trade war"),
        section  = "business",
        from     = "2020-01-01",
        to       = NULL  # up to today
      )
    }),

    # ── Monthly keyword counts ──────────────────────────────────────────
    targets::tar_target(gdn_monthly_counts, {

      results <- lapply(gdn_params$keywords, function(kw) {
        cli::cli_inform("Fetching Guardian: {kw}")
        hd_guardian_monthly(
          query   = kw,
          section = gdn_params$section,
          from    = gdn_params$from,
          to      = gdn_params$to
        )
      })

      dplyr::bind_rows(results)
    }),

    # ── Summary by keyword ──────────────────────────────────────────────
    targets::tar_target(gdn_summary, {
      if (nrow(gdn_monthly_counts) == 0L) return(NULL)

      gdn_monthly_counts |>
        dplyr::group_by(keyword) |>
        dplyr::summarise(
          n_months       = dplyr::n(),
          total_articles = sum(n_articles),
          mean_per_month = round(mean(n_articles), 1),
          max_month      = year_month[which.max(n_articles)],
          max_count      = max(n_articles),
          .groups = "drop"
        ) |>
        dplyr::arrange(dplyr::desc(total_articles))
    }),

    # ── Correlation with SPY returns ────────────────────────────────────
    targets::tar_target(gdn_vs_spy, {
      if (nrow(gdn_monthly_counts) == 0L) return(NULL)


      # Get SPY monthly returns
      spy <- tryCatch({
        hd_ohlcv("SPY", from = gdn_params$from, collect = TRUE) |>
          dplyr::mutate(
            year_month = format(as.Date(date), "%Y-%m")
          ) |>
          dplyr::group_by(year_month) |>
          dplyr::summarise(
            spy_return = (dplyr::last(adjusted) / dplyr::first(adjusted) - 1) * 100,
            .groups = "drop"
          )
      }, error = function(e) {
        cli::cli_warn("Failed to fetch SPY: {conditionMessage(e)}")
        NULL
      })

      if (is.null(spy)) return(NULL)

      # Pivot keyword counts wide, join with SPY
      wide <- gdn_monthly_counts |>
        tidyr::pivot_wider(
          names_from = keyword,
          values_from = n_articles,
          values_fill = 0L
        )

      merged <- dplyr::inner_join(wide, spy, by = "year_month")

      # Compute correlations for each keyword
      kw_cols <- setdiff(names(merged), c("year_month", "spy_return"))
      cors <- vapply(kw_cols, function(kw) {
        stats::cor(merged[[kw]], merged$spy_return,
                   use = "complete.obs", method = "spearman")
      }, numeric(1))

      tibble::tibble(
        keyword     = names(cors),
        spearman_r  = round(cors, 3),
        n_months    = nrow(merged),
        signal      = dplyr::case_when(
          abs(cors) >= 0.3 ~ "moderate",
          abs(cors) >= 0.15 ~ "weak",
          TRUE ~ "none"
        )
      ) |>
        dplyr::arrange(dplyr::desc(abs(spearman_r)))
    }),

    # ── Caption ─────────────────────────────────────────────────────────
    targets::tar_target(gdn_caption, {
      if (is.null(gdn_summary)) return(NULL)

      n_kw <- nrow(gdn_summary)
      total <- sum(gdn_summary$total_articles)

      paste0(
        n_kw, " keywords tracked, ", format(total, big.mark = ","),
        " total Guardian business articles. ",
        "Source: Guardian Open Platform API (content.guardianapis.com). ",
        "UK/international focus complements NYT (US-centric). ",
        "Free tier: 12 calls/sec with developer key."
      )
    })
  )
}
