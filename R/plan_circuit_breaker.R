# Plan: Circuit-Breaker Time Series (#67)
#
# Dormant-until-active signals from the Fed balance sheet: data that
# sits near zero or at a historical baseline for years, then spikes
# sharply when activated (QE, emergency facilities, reserve injections).
#
# These series behave like circuit breakers — benign for long stretches,
# then suddenly "trip" during crises or policy shifts. Useful as regime
# indicators and macro stress sensors.
#
# FRED series used (all weekly, released weekly):
#   WALCL     — Fed total assets ($B)          — QE proxy
#   WSHOMCB   — Fed MBS holdings ($B)          — QE housing channel
#   DPCREDIT  — Discount window borrowing ($B)  — emergency lending
#   TOTRESNS  — Total bank reserves ($B)        — system-wide liquidity
#
# Activation test: value exceeds (median + mad_threshold * MAD) of a
# 5-year rolling baseline.  Robust stats only (median / MAD).
#
# Naming convention: cb_*
# Total targets: 8

plan_circuit_breaker <- function() {
  list(

    # ── Parameters ────────────────────────────────────────────────
    targets::tar_target(cb_params, {
      list(
        # FRED series to track
        fed_series = c(
          "WALCL",     # Fed total assets
          "WSHOMCB",   # Fed MBS holdings
          "DPCREDIT",  # Discount window lending
          "TOTRESNS"   # Total bank reserves
        ),
        # Human-readable labels (used in plots / captions)
        series_labels = c(
          WALCL    = "Fed Total Assets",
          WSHOMCB  = "Fed MBS Holdings",
          DPCREDIT = "Discount Window Lending",
          TOTRESNS = "Total Bank Reserves"
        ),
        # Activation threshold: value > median + mad_threshold * MAD
        mad_threshold = 3.0,
        # Rolling baseline window — 5 years of weekly data
        baseline_window = 260L,
        # Minimum baseline obs before we'll classify activation
        min_baseline_obs = 52L,
        # SPY forward windows for post-activation performance (trading days)
        fwd_windows = c(5L, 10L, 21L, 63L),
        # Minimum gap (weeks) between activation events for the same series
        min_event_gap = 52L
      )
    }),

    # ── Raw data: fetch all FRED series ──────────────────────────
    targets::tar_target(cb_data, {
      library(dplyr)

      results <- purrr::map(cb_params$fed_series, function(sid) {
        # Try HuggingFace parquet first (cheap, cached)
        df <- tryCatch({
          out <- hd_macro(sid) |>
            # hd_macro() returns POSIXt — always coerce
            mutate(date = as.Date(date)) |>
            filter(!is.na(value), is.finite(value)) |>
            select(date, series_id, value) |>
            arrange(date)
          if (nrow(out) == 0L) NULL else out
        }, error = function(e) {
          cli::cli_inform(
            "cb_data: hd_macro({sid}) failed ({conditionMessage(e)}); will try FRED API"
          )
          NULL
        })

        if (!is.null(df)) return(df)

        # Fallback: fetch directly from FRED API (the 4 Fed-asset series are not
        # currently in the macro_daily HF parquet — see #145 layer 2)
        if (!nzchar(Sys.getenv("FRED_API_KEY"))) {
          cli::cli_warn(c(
            "cb_data: {sid} not in HF parquet and FRED_API_KEY is unset.",
            "i" = "Set FRED_API_KEY in .Renviron, or remove {sid} from cb_params$fed_series."
          ))
          return(NULL)
        }

        tryCatch({
          fredr::fredr_set_key(Sys.getenv("FRED_API_KEY"))
          fredr::fredr(series_id = sid) |>
            mutate(
              date      = as.Date(date),
              series_id = sid,
              value     = as.numeric(value)
            ) |>
            filter(!is.na(value), is.finite(value)) |>
            select(date, series_id, value) |>
            arrange(date)
        }, error = function(e) {
          cli::cli_warn(
            "cb_data: FRED fallback for {sid} failed: {conditionMessage(e)}"
          )
          NULL
        })
      }) |>
        purrr::compact()

      if (length(results) == 0L) {
        cli::cli_abort(c(
          "x" = "cb_data: 0 FRED Fed series successfully fetched.",
          "i" = "Tried: {.val {cb_params$fed_series}}",
          "i" = "Check macro parquet contents: {.code DBI::dbGetQuery(con, \"SELECT DISTINCT series_id FROM ...\")}",
          "i" = "Or update {.code cb_params$fed_series} to use available IDs.",
          "i" = "Tracked in issue #145 layer 2 (data fix)."
        ))
      }

      dplyr::bind_rows(results)
    }),

    # ── Regime: classify dormant vs active ────────────────────────
    #
    # For each observation we compute:
    #   baseline_median — rolling median of the PRECEDING baseline_window obs
    #   baseline_mad    — rolling MAD of the PRECEDING baseline_window obs
    #   robust_z        — (value - baseline_median) / baseline_mad
    #   is_active       — TRUE when robust_z > mad_threshold (or series has
    #                     never been "dormant" and has crossed 2x its pre-
    #                     crisis peak for the truly zero-baseline series)
    #
    # Uses only past data — no look-ahead.
    targets::tar_target(cb_regime, {
      library(dplyr)

      # Defensive: cb_data should already have aborted if empty (issue #145 layer 1),
      # but guard here too in case cb_data is restored from an old cache.
      if (nrow(cb_data) == 0L || !all(c("series_id", "date", "value") %in% names(cb_data))) {
        cli::cli_abort(c(
          "x" = "cb_regime: cb_data is empty or missing required columns.",
          "i" = "nrow: {nrow(cb_data)}, names: {.val {names(cb_data)}}",
          "i" = "Expected columns: series_id, date, value."
        ))
      }

      thresh <- cb_params$mad_threshold
      win    <- cb_params$baseline_window
      min_w  <- cb_params$min_baseline_obs

      cb_data |>
        arrange(series_id, date) |>
        group_by(series_id) |>
        mutate(
          # Number of preceding observations available
          n_prec = seq_len(n()) - 1L,
          # Rolling baseline: use only the window of observations BEFORE
          # the current row (excludes current obs — no self-contamination)
          baseline_median = purrr::map_dbl(
            seq_len(n()),
            function(i) {
              start_i <- max(1L, i - win)
              end_i   <- i - 1L
              if (end_i < start_i || (end_i - start_i + 1L) < min_w) return(NA_real_)
              median(value[start_i:end_i], na.rm = TRUE)
            }
          ),
          baseline_mad = purrr::map_dbl(
            seq_len(n()),
            function(i) {
              start_i <- max(1L, i - win)
              end_i   <- i - 1L
              if (end_i < start_i || (end_i - start_i + 1L) < min_w) return(NA_real_)
              mad(value[start_i:end_i], na.rm = TRUE)
            }
          ),
          # Robust z-score: (value - median) / MAD
          # NA where MAD ~ 0 (flat series) or insufficient baseline
          robust_z = dplyr::case_when(
            is.na(baseline_mad) | is.na(baseline_median)    ~ NA_real_,
            baseline_mad < .Machine$double.eps * 1e6        ~ NA_real_,
            TRUE ~ (value - baseline_median) / baseline_mad
          ),
          # Activation: exceeds the robust-z threshold
          is_active = dplyr::case_when(
            is.na(robust_z) ~ NA,
            robust_z > thresh ~ TRUE,
            TRUE ~ FALSE
          )
        ) |>
        ungroup() |>
        select(date, series_id, value, baseline_median, baseline_mad,
               robust_z, is_active)
    }),

    # ── Events: activation transition dates ──────────────────────
    #
    # Returns one row per "trip" event: the first week the series
    # crosses from dormant → active, plus metadata about the event.
    targets::tar_target(cb_events, {
      library(dplyr)

      min_gap <- cb_params$min_event_gap

      cb_regime |>
        filter(!is.na(is_active)) |>
        arrange(series_id, date) |>
        group_by(series_id) |>
        mutate(
          # Detect dormant→active transitions
          prev_active = lag(is_active, default = FALSE),
          is_trip = is_active & !prev_active
        ) |>
        filter(is_trip) |>
        # Suppress events too close to each other (same "episode")
        mutate(
          weeks_since_prev = as.numeric(difftime(
            date, lag(date, default = date[1] - 365), units = "weeks"
          )),
          keep = weeks_since_prev >= min_gap | dplyr::row_number() == 1L
        ) |>
        filter(keep) |>
        # Look ahead (within the same group) to measure event magnitude /
        # duration — no look-ahead bias here: we're measuring the crisis
        # itself, not predicting returns. Used for descriptive exhibit only.
        mutate(
          magnitude_mad = robust_z,
          series_label  = cb_params$series_labels[series_id]
        ) |>
        ungroup() |>
        select(series_id, series_label, activation_date = date,
               activation_value = value, magnitude_mad)
    }),

    # ── SPY returns around activation events ─────────────────────
    #
    # For each activation event: SPY return in the N trading days
    # AFTER the event (t+1 execution — we use the NEXT trading day
    # as entry to avoid look-ahead bias).
    #
    # Compare to unconditional SPY returns over the same holding windows
    # to see whether activations are a buy or sell signal.
    targets::tar_target(cb_vs_spy, {
      library(dplyr)

      # SPY daily returns (close-to-close adjusted)
      spy <- tryCatch(
        hd_ohlcv("SPY") |>
          mutate(date = as.Date(date)) |>
          arrange(date) |>
          mutate(spy_ret = adjusted / lag(adjusted) - 1) |>
          filter(!is.na(spy_ret)) |>
          select(date, spy_ret),
        error = function(e) {
          cli::cli_warn("cb_vs_spy: could not fetch SPY: {conditionMessage(e)}")
          NULL
        }
      )

      if (is.null(spy) || nrow(spy) == 0 || nrow(cb_events) == 0) {
        return(tibble::tibble())
      }

      windows <- cb_params$fwd_windows

      # Unconditional mean returns over each window (full sample)
      spy_dates <- spy$date
      spy_rets  <- spy$spy_ret

      uncond <- purrr::map_dfr(windows, function(w) {
        # Rolling forward return: compound w-day returns
        fwd_ret <- purrr::map_dbl(seq_len(nrow(spy) - w), function(i) {
          prod(1 + spy_rets[(i + 1):(i + w)]) - 1
        })
        tibble::tibble(
          fwd_days = w,
          mean_unconditional = mean(fwd_ret, na.rm = TRUE),
          n_unconditional    = length(fwd_ret)
        )
      })

      # Conditional returns: enter 1 day AFTER each activation (t+1)
      event_rows <- purrr::map_dfr(seq_len(nrow(cb_events)), function(j) {
        ev_date <- cb_events$activation_date[j]
        sid     <- cb_events$series_id[j]
        s_label <- cb_events$series_label[j]

        # Entry: first SPY trading day strictly after activation date
        entry_idx <- which(spy_dates > ev_date)[1]
        if (is.na(entry_idx)) return(NULL)

        purrr::map_dfr(windows, function(w) {
          exit_idx <- entry_idx + w - 1L
          if (exit_idx > nrow(spy)) return(NULL)

          fwd_ret <- prod(1 + spy_rets[entry_idx:exit_idx]) - 1
          tibble::tibble(
            series_id      = sid,
            series_label   = s_label,
            activation_date = ev_date,
            fwd_days       = w,
            spy_fwd_ret    = fwd_ret
          )
        })
      })

      if (nrow(event_rows) == 0) return(tibble::tibble())

      # Merge unconditional for comparison
      event_rows |>
        left_join(uncond, by = "fwd_days") |>
        mutate(
          excess_ret = spy_fwd_ret - mean_unconditional,
          signal_type = "cb_activation"
        )
    }),

    # ── Summary plot: circuit-breaker time series ─────────────────
    targets::tar_target(cb_plot, {
      library(ggplot2)
      library(dplyr)

      # Normalise each series to index = 1 at the start so they fit on
      # one panel despite different units ($B vs $T etc.)
      plot_df <- cb_regime |>
        filter(!is.na(is_active)) |>
        group_by(series_id) |>
        arrange(date) |>
        mutate(
          label     = cb_params$series_labels[series_id],
          value_idx = value / value[1]    # index to first obs
        ) |>
        ungroup()

      # Activation periods shading
      active_spans <- plot_df |>
        filter(is_active) |>
        group_by(series_id) |>
        arrange(date) |>
        mutate(grp = cumsum(c(1L, diff(as.numeric(date)) > 14L))) |>
        group_by(series_id, grp) |>
        summarise(
          xmin = min(date), xmax = max(date),
          label = first(cb_params$series_labels[series_id]),
          .groups = "drop"
        )

      p <- ggplot(plot_df, aes(date, value_idx, colour = label)) +
        geom_line(linewidth = 0.5, alpha = 0.85)

      if (nrow(active_spans) > 0) {
        p <- p +
          geom_rect(
            data        = active_spans,
            inherit.aes = FALSE,
            aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf,
                fill = label),
            alpha = 0.12, colour = NA
          )
      }

      p +
        scale_y_log10(labels = scales::label_comma()) +
        scale_colour_manual(values = hd_palette(4)) +
        scale_fill_manual(values   = hd_palette(4), guide = "none") +
        labs(
          x        = NULL,
          y        = "Indexed level (log scale, first obs = 1)",
          colour   = NULL,
          title    = "Fed Circuit-Breaker Series (shaded = active regime)",
          subtitle = paste0(
            "Activated when value > median + ",
            cb_params$mad_threshold, " \u00d7 MAD of 5-year rolling baseline"
          )
        ) +
        hd_theme()
    }),

    # ── Caption ───────────────────────────────────────────────────
    targets::tar_target(cb_caption, {
      library(dplyr)

      n_series <- length(cb_params$fed_series)
      n_events <- nrow(cb_events)

      # Earliest and most recent activation
      date_range_str <- if (n_events > 0) {
        paste0(
          format(min(cb_events$activation_date), "%b %Y"),
          " to ",
          format(max(cb_events$activation_date), "%b %Y")
        )
      } else {
        "none detected"
      }

      # Post-activation SPY summary (21-day window)
      spy_21 <- cb_vs_spy |>
        filter(fwd_days == 21L) |>
        summarise(
          mean_ret    = round(mean(spy_fwd_ret, na.rm = TRUE) * 100, 1),
          mean_excess = round(mean(excess_ret,  na.rm = TRUE) * 100, 1),
          n           = dplyr::n()
        )

      spy_note <- if (nrow(spy_21) > 0 && spy_21$n > 0) {
        paste0(
          "Median 21-day SPY return after activation: ",
          spy_21$mean_ret, "% (vs unconditional baseline). ",
          "Excess: ", spy_21$mean_excess, " pp."
        )
      } else {
        "SPY post-activation data not available."
      }

      paste0(
        "Fed circuit-breaker signals: ", n_series, " FRED series ",
        "(", paste(cb_params$series_labels, collapse = ", "), "). ",
        "Dormant-until-active classification: a series is flagged as active ",
        "when its value exceeds the 5-year rolling median by more than ",
        cb_params$mad_threshold, " median absolute deviations. ",
        "Robust statistics (median/MAD) are used throughout to prevent ",
        "crisis spikes from inflating the baseline. ",
        n_events, " activation events detected across all series, ",
        date_range_str, ". ",
        spy_note, " ",
        "t+1 execution assumed: SPY entry on the first trading day after ",
        "the activation date, avoiding any look-ahead bias. ",
        "Source: FRED via hd_macro(); SPY via hd_ohlcv()."
      )
    })
  )
}
