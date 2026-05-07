# Plan: ECB/Eurostat EU Financial Data (#88)
#
# Fetches European financial time series from the ECB Statistical Data
# Warehouse via SDMX REST API. No additional R packages required (httr2 only).
#
# Upstream: none (independent data source)
# Downstream: plan_european_overlay (ECB yield curve as regime signal)
#
# Naming convention: ecb_*
# Total targets: 5

plan_ecb <- function() {
  list(

    # ── Parameters ──────────────────────────────────────────────────────
    targets::tar_target(ecb_params, {
      # Series to fetch — subset of hd_ecb_registry()
      list(
        series = c(
          "euribor_3m", "ecb_refi_rate", "yield_curve_10y",
          "hicp_inflation", "eurusd"
        ),
        start_date = "2000-01-01"
      )
    }),

    # ── Fetch all ECB series ────────────────────────────────────────────
    targets::tar_target(ecb_raw, {
      reg <- pkgload::load_all(
        here::here("packages/historicaldata"), quiet = TRUE
      )$env
      registry <- reg$hd_ecb_registry()

      results <- lapply(ecb_params$series, function(nm) {
        info <- registry[[nm]]
        if (is.null(info)) {
          cli::cli_warn("ECB series {nm} not in registry")
          return(NULL)
        }
        df <- reg$hd_ecb(info$key, start = ecb_params$start_date)
        if (!is.null(df)) {
          df$series_name <- nm
          df$description <- info$description
          df$unit <- info$unit
        }
        df
      })

      dplyr::bind_rows(results)
    }),

    # ── Summary statistics ──────────────────────────────────────────────
    targets::tar_target(ecb_summary, {
      if (nrow(ecb_raw) == 0L) return(NULL)

      ecb_raw |>
        dplyr::group_by(series_name, description, unit, frequency) |>
        dplyr::summarise(
          n_obs     = dplyr::n(),
          from_date = min(date, na.rm = TRUE),
          to_date   = max(date, na.rm = TRUE),
          min_val   = round(min(value, na.rm = TRUE), 4),
          max_val   = round(max(value, na.rm = TRUE), 4),
          mean_val  = round(mean(value, na.rm = TRUE), 4),
          .groups   = "drop"
        )
    }),

    # ── Yield spread: 10Y - ECB refi rate ──────────────────────────────
    targets::tar_target(ecb_yield_spread, {
      yc <- ecb_raw |>
        dplyr::filter(series_name == "yield_curve_10y") |>
        dplyr::select(date, yield_10y = value)

      refi <- ecb_raw |>
        dplyr::filter(series_name == "ecb_refi_rate") |>
        dplyr::select(date, refi_rate = value)

      # Join on date — both are daily(ish)
      spread <- dplyr::inner_join(yc, refi, by = "date") |>
        dplyr::mutate(spread_bps = round((yield_10y - refi_rate) * 100, 1)) |>
        dplyr::arrange(date)

      spread
    }),

    # ── Caption for vignette use ────────────────────────────────────────
    targets::tar_target(ecb_caption, {
      if (is.null(ecb_summary)) return(NULL)

      n_series <- nrow(ecb_summary)
      total_obs <- sum(ecb_summary$n_obs)
      date_range <- paste(
        min(ecb_summary$from_date),
        "to",
        max(ecb_summary$to_date)
      )

      paste0(
        n_series, " ECB series, ", format(total_obs, big.mark = ","),
        " total observations (", date_range, "). ",
        "Source: ECB Statistical Data Warehouse (SDMX REST API). ",
        "Series: EURIBOR 3M, ECB refi rate, 10Y yield curve, ",
        "HICP inflation, EUR/USD."
      )
    })
  )
}
