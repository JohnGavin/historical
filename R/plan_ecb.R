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
          # FX
          "eurusd", "eurgbp", "eurjpy", "eurchf",
          # Interest rates
          "euribor_3m", "euribor_6m", "ecb_refi_rate",
          # Yield curve
          "yield_curve_10y", "yield_curve_5y", "yield_curve_2y", "yield_curve_1y",
          "yc_level", "yc_slope", "yc_curvature",
          # CISS stress
          "ciss_composite", "ciss_bond", "ciss_equity", "ciss_fx",
          "ciss_money", "ciss_financial", "ciss_correlation", "ciss_sovereign",
          # CISS per country
          "ciss_de", "ciss_fr", "ciss_it", "ciss_gb", "ciss_us",
          # Macro
          "hicp_inflation", "m3_money_supply"
        ),
        start_date = "2000-01-01"
      )
    }),

    # ── Fetch all ECB series ────────────────────────────────────────────
    targets::tar_target(ecb_raw, {
      registry <- hd_ecb_registry()

      results <- lapply(ecb_params$series, function(nm) {
        info <- registry[[nm]]
        if (is.null(info)) {
          cli::cli_warn("ECB series {nm} not in registry")
          return(NULL)
        }
        # Wrap per-series fetch so one stalled/errored endpoint cannot hang the
        # entire target.  hd_ecb() already has req_timeout(30) + req_retry(3),
        # but transport errors (connection refused, TCP stall) can still escape
        # as R conditions.  tryCatch here ensures the lapply continues.
        tryCatch({
          df <- hd_ecb(info$key, start = ecb_params$start_date)
          if (!is.null(df)) {
            df$series_name <- nm
            df$description <- info$description
            df$unit <- info$unit
          }
          df
        }, error = function(e) {
          cli::cli_warn(c(
            "!" = "ECB series {nm} failed and will be skipped.",
            "i" = "{conditionMessage(e)}"
          ))
          NULL
        })
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
