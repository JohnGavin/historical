# Plan: NYT Keyword Frequency & Market Sentiment (#nyt-sentiment)
#
# Reads pre-processed NYT keyword counts from tedalcorn/nyt (parsed by
# scripts/parse_nyt_tedalcorn.R) and correlates keyword frequency with
# SPY monthly returns.
#
# Targets produced:
#   nyt_params      — configuration list
#   nyt_keywords    — tidy tibble with rolling avg and YoY change per keyword
#   nyt_vs_spy      — correlation table (lag 0–3 months) vs SPY returns
#   nyt_caption     — dynamic prose caption

plan_nyt_sentiment <- function() {
  list(

    # ── Parameters ─────────────────────────────────────────────────────────────
    targets::tar_target(nyt_params, {
      list(
        subjects_path = here::here("data/raw/nyt_keywords.parquet"),
        target_keywords = c(
          "Federal Reserve System",   # matches "Federal Reserve" keyword filter
          "Recession",
          "Inflation",
          "Unemployment",
          "Tariff",
          "Oil",
          "Housing",
          "Trump",
          "Biden",
          "Obama",
          "Bush"
        ),
        source_data_path = "/tmp/tedalcorn-nyt",
        rolling_window   = 12L,   # months for rolling average
        min_months       = 24L    # minimum months of data required for correlation
      )
    }),

    # ── Load and process keyword counts ────────────────────────────────────────
    targets::tar_target(nyt_keywords, {
      library(dplyr)
      library(tidyr)

      if (!file.exists(nyt_params$subjects_path)) {
        cli::cli_warn(
          "nyt_keywords.parquet not found at {nyt_params$subjects_path}. ",
          "Run scripts/parse_nyt_tedalcorn.R to generate it."
        )
        return(tibble(
          date         = as.Date(character()),
          keyword      = character(),
          source       = character(),
          count        = integer(),
          count_12m_avg = numeric(),
          yoy_change    = numeric()
        ))
      }

      raw <- arrow::read_parquet(nyt_params$subjects_path) |>
        mutate(date = as.Date(date))

      # Restrict to target keywords (partial match on presidents OR exact on subjects)
      # Also always include TOTAL_ARTICLES for normalisation reference
      kw_data <- raw |>
        filter(
          keyword %in% nyt_params$target_keywords |
          keyword == "TOTAL_ARTICLES"
        ) |>
        arrange(keyword, date)

      if (nrow(kw_data) == 0) {
        cli::cli_warn(
          "No rows matched target_keywords in {nyt_params$subjects_path}. ",
          "Available keywords: {paste(head(unique(raw$keyword), 10), collapse = ', ')} ..."
        )
        return(tibble(
          date          = as.Date(character()),
          keyword       = character(),
          source        = character(),
          count         = integer(),
          count_12m_avg = numeric(),
          yoy_change    = numeric()
        ))
      }

      # 12-month rolling average and YoY change per keyword
      # Using slider for rolling window (available via base R if slider not present)
      compute_rolling <- function(dates, counts, window = 12L) {
        n <- length(counts)
        avg <- numeric(n)
        for (i in seq_len(n)) {
          start_i <- max(1L, i - window + 1L)
          avg[i]  <- mean(counts[start_i:i], na.rm = TRUE)
        }
        avg
      }

      result <- kw_data |>
        group_by(keyword, source) |>
        arrange(date, .by_group = TRUE) |>
        mutate(
          count_12m_avg = compute_rolling(date, count, nyt_params$rolling_window),
          # YoY change: count vs same month prior year
          date_lag12 = date - 365L,
          count_lag12 = {
            # Match to same calendar month prior year
            kw_counts <- count
            kw_dates  <- date
            vapply(seq_along(date), function(i) {
              target_yr_mo <- format(date[i] - 365, "%Y-%m")
              match_idx <- which(format(kw_dates, "%Y-%m") == target_yr_mo)
              if (length(match_idx) == 0L) NA_integer_ else kw_counts[match_idx[1L]]
            }, integer(1))
          },
          yoy_change = dplyr::case_when(
            is.na(count_lag12) | count_lag12 == 0L ~ NA_real_,
            TRUE ~ (count - count_lag12) / count_lag12
          )
        ) |>
        select(-date_lag12, -count_lag12) |>
        ungroup()

      cli::cli_alert_success(
        "nyt_keywords: {nrow(result)} rows | ",
        "{n_distinct(result$keyword)} keywords | ",
        "{format(min(result$date), '%Y-%m')} to {format(max(result$date), '%Y-%m')}"
      )

      result
    }),

    # ── Correlate keyword frequency with SPY monthly returns ───────────────────
    targets::tar_target(nyt_vs_spy, {
      library(dplyr)
      library(tidyr)

      if (nrow(nyt_keywords) == 0) {
        cli::cli_warn("nyt_keywords is empty — cannot compute nyt_vs_spy correlations")
        return(tibble(
          keyword  = character(),
          corr_lag0 = numeric(), corr_lag1 = numeric(),
          corr_lag2 = numeric(), corr_lag3 = numeric(),
          n_months  = integer()
        ))
      }

      # Load SPY daily OHLCV
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

      spy_daily <- tryCatch(
        hd_ohlcv("SPY") |>
          mutate(date = as.Date(date)) |>
          arrange(date) |>
          mutate(daily_ret = adjusted / dplyr::lag(adjusted) - 1) |>
          filter(!is.na(daily_ret)),
        error = function(e) {
          cli::cli_warn("Could not load SPY data: {e$message}")
          NULL
        }
      )

      if (is.null(spy_daily) || nrow(spy_daily) == 0) {
        cli::cli_warn("SPY daily data unavailable — cannot compute correlations")
        return(tibble(
          keyword   = character(),
          corr_lag0 = numeric(), corr_lag1 = numeric(),
          corr_lag2 = numeric(), corr_lag3 = numeric(),
          n_months  = integer()
        ))
      }

      # Aggregate to monthly returns: compound daily returns within each month
      spy_monthly <- spy_daily |>
        mutate(ym = format(date, "%Y-%m")) |>
        group_by(ym) |>
        summarise(
          spy_ret = prod(1 + daily_ret) - 1,
          .groups = "drop"
        ) |>
        mutate(date = as.Date(paste0(ym, "-01"))) |>
        select(date, spy_ret)

      # Exclude volume keyword (not meaningful to correlate raw volume counts)
      kw_for_corr <- nyt_keywords |>
        filter(keyword != "TOTAL_ARTICLES") |>
        select(date, keyword, count)

      # Compute contemporaneous and lagged correlations
      # lag_k: does month-t keyword count predict month-(t+k) SPY return?
      compute_lag_corr <- function(kw_name, kw_df, spy_df, lag_k) {
        joined <- kw_df |>
          filter(keyword == kw_name) |>
          inner_join(
            spy_df |> mutate(date = date + months(lag_k)),
            by = "date"
          )
        if (nrow(joined) < nyt_params$min_months) return(NA_real_)
        cor(joined$count, joined$spy_ret, use = "complete.obs", method = "pearson")
      }

      kw_names <- unique(kw_for_corr$keyword)

      result <- dplyr::bind_rows(lapply(kw_names, function(kw) {
        tibble(
          keyword   = kw,
          corr_lag0 = compute_lag_corr(kw, kw_for_corr, spy_monthly, 0L),
          corr_lag1 = compute_lag_corr(kw, kw_for_corr, spy_monthly, 1L),
          corr_lag2 = compute_lag_corr(kw, kw_for_corr, spy_monthly, 2L),
          corr_lag3 = compute_lag_corr(kw, kw_for_corr, spy_monthly, 3L),
          n_months  = {
            joined <- kw_for_corr |>
              filter(keyword == kw) |>
              inner_join(spy_monthly, by = "date")
            nrow(joined)
          }
        )
      })) |>
        mutate(
          across(starts_with("corr_"), ~ round(.x, 3))
        ) |>
        arrange(dplyr::desc(abs(corr_lag1)))

      cli::cli_alert_success(
        "nyt_vs_spy: {nrow(result)} keyword-correlation rows"
      )

      result
    }),

    # ── Dynamic prose caption ─────────────────────────────────────────────────
    targets::tar_target(nyt_caption, {
      library(dplyr)

      if (nrow(nyt_keywords) == 0) {
        return(paste0(
          "NYT keyword frequency data unavailable. ",
          "Run scripts/parse_nyt_tedalcorn.R to generate data/raw/nyt_keywords.parquet."
        ))
      }

      date_min <- format(min(nyt_keywords$date), "%b %Y")
      date_max <- format(max(nyt_keywords$date), "%b %Y")
      n_kw     <- n_distinct(nyt_keywords$keyword[nyt_keywords$keyword != "TOTAL_ARTICLES"])
      n_months <- n_distinct(nyt_keywords$date)

      # Strongest SPY predictor (lag 1)
      if (nrow(nyt_vs_spy) > 0 && !all(is.na(nyt_vs_spy$corr_lag1))) {
        best_row <- nyt_vs_spy |>
          filter(!is.na(corr_lag1)) |>
          slice_max(abs(corr_lag1), n = 1, with_ties = FALSE)

        corr_str <- paste0(
          "Strongest 1-month leading correlation: ",
          best_row$keyword,
          " (r = ", round(best_row$corr_lag1, 2), ", N = ", best_row$n_months, " months)."
        )
      } else {
        corr_str <- "SPY correlation data unavailable."
      }

      paste0(
        "NYT keyword frequency from tedalcorn/nyt (", date_min, " to ", date_max, "). ",
        n_kw, " financial/political keywords across ", n_months, " months. ",
        "Subjects.json provides annual counts spread evenly across 12 months; ",
        "presidents.json provides true monthly counts. ",
        corr_str, " ",
        "Correlations are descriptive only; no causal claim is intended. ",
        "Source: tedalcorn.com/nyt (subjects.json, presidents.json, dashboard.json). ",
        "Processed: ", format(max(nyt_keywords$fetched_at, na.rm = TRUE), "%Y-%m-%d"), "."
      )
    })

  )
}
