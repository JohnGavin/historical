# Backtest registry — metric + diagnostic recorders + leaderboard reader
# (#347 PR 3/4; unit vocabulary + canonicalisation #640)
#
# Long-form writes:
#   hd_metric_record(con, run_uuid, metrics, units = NULL)
#   hd_diagnostic_record(con, run_uuid, diagnostics)
#
# Read:
#   hd_leaderboard_from_registry(con, metric_name = "sharpe", ...)

#' Allowed units for backtest registry metrics
#'
#' The canonical vocabulary for the `metric_unit` column written to
#' `bt.metric`, and the required values for the `units` argument of
#' [hd_metric_record()]. [hd_leaderboard_from_registry()] converts
#' `"percent"` values to `"fraction"` on read (matching the canonical
#' dashboard convention established in #639); the other four units pass
#' through read unchanged because they have no fraction-equivalent
#' conversion.
#'
#' \describe{
#'   \item{`fraction`}{Decimal fraction (e.g. `-0.15` = -15% drawdown).
#'     Canonical unit for returns-scale metrics on read.}
#'   \item{`percent`}{Native percent scale (e.g. `-15` = -15% drawdown).
#'     Converted to `fraction` on read.}
#'   \item{`ratio`}{Scale-free dimensionless statistic (Sharpe, t-stat,
#'     correlation coefficient, SSR, ...). Never scaled.}
#'   \item{`count`}{Integer/whole-number count of observations, periods,
#'     or events (months, trade counts, window counts, ...).}
#'   \item{`days`}{Duration measured in days (e.g. average drawdown
#'     length in a daily-frequency series).}
#'   \item{`years`}{Duration measured in years.}
#' }
#'
#' @return Character vector.
#' @export
hd_metric_units <- function() {
  c("fraction", "percent", "ratio", "count", "days", "years")
}

.hd_validate_metric_units <- function(metric_name, metric_unit) {
  allowed <- hd_metric_units()
  missing <- is.na(metric_unit)
  if (any(missing)) {
    cli::cli_abort(c(
      "x" = "Missing {.field metric_unit} for metric{?s} {.val {unique(metric_name[missing])}}.",
      "i" = "Every metric written to {.code bt.metric} must declare a unit.",
      "i" = "Allowed units: {.val {allowed}}.",
      "i" = "Long form: add a {.field metric_unit} column. Wide form: pass {.arg units}."
    ))
  }
  unknown <- !metric_unit %in% allowed
  if (any(unknown)) {
    cli::cli_abort(c(
      "x" = paste0(
        "Unknown {.field metric_unit} {.val {unique(metric_unit[unknown])}} ",
        "for metric{?s} {.val {unique(metric_name[unknown])}}."
      ),
      "i" = "Allowed units: {.val {allowed}}."
    ))
  }
  invisible(TRUE)
}

#' Record long-form metrics for a backtest run
#'
#' Writes one row per metric into `bt.metric`. The metric tibble may be
#' either:
#'
#' - Long form: columns `metric_name`, `metric_value`, optional
#'   `metric_unit`.
#' - Wide form (a single-row tibble): each numeric column is written as
#'   one metric row using its column name. Non-numeric and `NA` columns
#'   are skipped.
#'
#' Every metric written MUST resolve to a known unit (see
#' [hd_metric_units()]) — a missing or unrecognised unit aborts via
#' `cli::cli_abort()`. Long-form tibbles supply units via a `metric_unit`
#' column; wide-form tibbles have no per-column slot for a unit, so they
#' must supply the `units` argument instead (a named character vector,
#' `metric name -> unit`). Long-form rows with `NA` in `metric_unit` may
#' also be filled in from `units`, keyed by `metric_name`.
#'
#' Idempotent per (run_uuid, metric_name): re-recording overwrites.
#'
#' @param con DBI connection (writable).
#' @param run_uuid Character. Must refer to an existing `bt.run` row.
#' @param metrics A tibble (long or wide as above).
#' @param units Optional named character vector mapping metric name to
#'   one of [hd_metric_units()]. Required for wide-form `metrics` (no
#'   `metric_name`/`metric_value` columns); optional fallback for
#'   long-form `metrics` whose `metric_unit` column is absent or has
#'   `NA` entries.
#' @return Invisibly, the number of rows written.
#' @export
hd_metric_record <- function(con, run_uuid, metrics, units = NULL) {
  rlang::check_installed("DBI")
  if (is.null(run_uuid) || is.na(run_uuid) || !nzchar(run_uuid)) {
    cli::cli_abort("{.field run_uuid} is required.")
  }
  if (is.list(metrics) && !is.data.frame(metrics)) {
    metrics <- tibble::as_tibble(metrics)
  }
  long <- .normalise_metric_long(metrics, units = units)
  if (nrow(long) == 0L) return(invisible(0L))

  # Idempotent: delete existing rows for these (run_uuid, metric_name) pairs.
  DBI::dbExecute(
    con,
    sprintf(
      "DELETE FROM bt.metric WHERE run_uuid = ? AND metric_name IN (%s)",
      paste(rep("?", nrow(long)), collapse = ", ")
    ),
    params = c(list(run_uuid), as.list(long$metric_name))
  )

  for (i in seq_len(nrow(long))) {
    DBI::dbExecute(
      con,
      "INSERT INTO bt.metric (run_uuid, metric_name, metric_value, metric_unit)
       VALUES (?, ?, ?, ?)",
      params = list(
        run_uuid,
        long$metric_name[i],
        long$metric_value[i],
        long$metric_unit[i]
      )
    )
  }
  invisible(nrow(long))
}

#' Record long-form diagnostics for a backtest run
#'
#' Writes one row per diagnostic into `bt.diagnostic`. Accepts both
#' long form (with `diagnostic_name` + `value_num` / `value_text`) and
#' wide form (single-row tibble).
#'
#' @param con DBI connection (writable).
#' @param run_uuid Character.
#' @param diagnostics A tibble.
#' @return Invisibly, the number of rows written.
#' @export
hd_diagnostic_record <- function(con, run_uuid, diagnostics) {
  rlang::check_installed("DBI")
  if (is.null(run_uuid) || is.na(run_uuid) || !nzchar(run_uuid)) {
    cli::cli_abort("{.field run_uuid} is required.")
  }
  if (is.list(diagnostics) && !is.data.frame(diagnostics)) {
    diagnostics <- tibble::as_tibble(diagnostics)
  }
  long <- .normalise_diagnostic_long(diagnostics)
  if (nrow(long) == 0L) return(invisible(0L))

  DBI::dbExecute(
    con,
    sprintf(
      "DELETE FROM bt.diagnostic
       WHERE run_uuid = ? AND diagnostic_name IN (%s)",
      paste(rep("?", nrow(long)), collapse = ", ")
    ),
    params = c(list(run_uuid), as.list(long$diagnostic_name))
  )

  for (i in seq_len(nrow(long))) {
    DBI::dbExecute(
      con,
      "INSERT INTO bt.diagnostic
         (run_uuid, diagnostic_name, value_num, value_text)
       VALUES (?, ?, ?, ?)",
      params = list(
        run_uuid,
        long$diagnostic_name[i],
        long$value_num[i],
        long$value_text[i]
      )
    )
  }
  invisible(nrow(long))
}

#' Canonicalise stored metric values to a single unit per row
#'
#' `"percent"` values are divided by 100 and relabelled `"fraction"` —
#' the only defined conversion (matching the canonical dashboard
#' convention from #639). All other units (`"fraction"`, `"ratio"`,
#' `"count"`, `"days"`, `"years"`) pass through unscaled: a `"ratio"`
#' metric such as Sharpe must never be divided by 100.
#'
#' @param value Numeric vector of stored metric values.
#' @param unit Character vector of stored units (must already be
#'   validated — no `NA`/unknown values).
#' @return A list with `value` and `unit`, both canonicalised.
#' @noRd
.hd_canonicalise_unit <- function(value, unit) {
  is_percent <- unit == "percent"
  value[is_percent] <- value[is_percent] / 100
  unit[is_percent] <- "fraction"
  list(value = value, unit = unit)
}

#' Leaderboard read from the registry
#'
#' Joins `bt.strategy` + `bt.run` + `bt.metric` and pivots the named
#' metric (default `"sharpe"`) into a column. Returns one row per
#' (strategy_id, partition, run_uuid).
#'
#' `value`/`unit` are always in the **canonical** unit for their kind —
#' `"percent"` is converted to `"fraction"` (dividing by 100); `"ratio"`,
#' `"count"`, `"days"`, `"years"`, and already-`"fraction"` values pass
#' through unscaled. Callers never need to know the storage convention.
#' The original as-stored value/unit are preserved in `value_stored` /
#' `unit_stored` for auditability. A `NA` or unrecognised stored unit
#' aborts (see [hd_metric_units()]) rather than being silently treated
#' as any particular unit — this is deliberate: an un-unitised row is
#' exactly the #637/#640 hazard this function exists to prevent, and a
#' registry populated before this fix landed must be regenerated (all
#' pre-fix rows have `metric_unit IS NULL`).
#'
#' @param con DBI connection (read-only is fine).
#' @param metric_name Character. Default `"sharpe"`.
#' @param latest_per_partition Logical. If `TRUE` (default), keep only
#'   the most recent run per (strategy_id, partition). If `FALSE`, every
#'   recorded run is returned.
#' @return A tibble with canonical `value`/`unit` columns plus
#'   `value_stored`/`unit_stored` carrying the as-recorded values.
#' @export
hd_leaderboard_from_registry <- function(con,
                                         metric_name = "sharpe",
                                         latest_per_partition = TRUE) {
  rlang::check_installed("DBI")

  sql <- "
    SELECT
      s.strategy_id,
      s.short_name,
      s.long_name,
      s.asset_class,
      s.frequency,
      s.directionality,
      r.run_uuid,
      r.partition,
      r.git_sha,
      r.pipeline_version,
      r.started_at,
      m.metric_value AS value,
      m.metric_unit  AS unit
    FROM bt.strategy s
      JOIN bt.run    r ON r.strategy_id = s.strategy_id
      JOIN bt.metric m ON m.run_uuid     = r.run_uuid
    WHERE m.metric_name = ?
    ORDER BY s.strategy_id, r.partition, r.started_at DESC
  "

  out <- DBI::dbGetQuery(con, sql, params = list(metric_name))
  out <- tibble::as_tibble(out)

  if (isTRUE(latest_per_partition) && nrow(out) > 0L) {
    out <- out |>
      dplyr::group_by(.data$strategy_id, .data$partition) |>
      dplyr::slice_head(n = 1L) |>
      dplyr::ungroup()
  }
  out$metric_name <- metric_name

  if (nrow(out) > 0L) {
    .hd_validate_metric_units(out$metric_name, out$unit)
    canon <- .hd_canonicalise_unit(out$value, out$unit)
    out$value_stored <- out$value
    out$unit_stored  <- out$unit
    out$value <- canon$value
    out$unit  <- canon$unit
  } else {
    out$value_stored <- numeric(0)
    out$unit_stored  <- character(0)
  }
  out
}

# ── registry stability helper ─────────────────────────────────────────────

#' Record SSR and top-pct-share stability metrics for a backtest run
#'
#' Convenience wrapper that calls [hd_sharpe_stability_ratio()] and
#' [hd_top5pct_share()] on a returns vector, then writes the combined
#' 8 metric values into `bt.metric` via [hd_metric_record()].
#'
#' The 8 metrics written are (unit in parens; see [hd_metric_units()]):
#' \describe{
#'   \item{`ssr`}{Sharpe Stability Ratio. (`ratio`)}
#'   \item{`ssr_mean_sharpe`}{Mean of rolling Sharpe series. (`ratio`)}
#'   \item{`ssr_se`}{Newey-West HAC standard error. (`ratio`)}
#'   \item{`ssr_n_windows`}{Number of complete rolling windows. (`count`)}
#'   \item{`ssr_lag_nw`}{Newey-West bandwidth used. (`count`)}
#'   \item{`top_share`}{Fraction of total return from the top-`pct` periods. (`fraction`)}
#'   \item{`top_n_top`}{Count of top-`pct` periods. (`count`)}
#'   \item{`top_n_total`}{Total non-NA period count. (`count`)}
#' }
#' These units are fixed by this helper's own contract — always the same
#' regardless of caller — so they are hardcoded here rather than accepted
#' as an argument.
#'
#' `NA` values in `returns` are silently removed before both computations
#' (matching the behaviour of [hd_sharpe_stability_ratio()] and
#' [hd_top5pct_share()]).  If all values are `NA` the function returns
#' a list of eight `NA` values without writing anything to the database.
#'
#' Idempotency: [hd_metric_record()] performs a DELETE-then-INSERT for each
#' `(run_uuid, metric_name)` pair, so calling this helper twice with the same
#' arguments overwrites the earlier values and leaves exactly 8 rows.
#'
#' @param con DBI connection (writable).
#' @param run_uuid Character. Must refer to an existing `bt.run` row.
#' @param returns Numeric vector of period returns.
#' @param w Integer window length for the rolling Sharpe computation.
#'   Typical choices: 252 (daily) or 36 (monthly).
#' @param ann_factor Annualisation factor matching the frequency of `returns`
#'   (252 for daily, 12 for monthly, 4 for quarterly). Default 252.
#' @param pct Numeric in (0, 1). The top fraction for [hd_top5pct_share()].
#'   Default 0.05 (top 5%).
#'
#' @return Invisibly, a named list of the 8 metric values.
#'
#' @seealso [hd_sharpe_stability_ratio()], [hd_top5pct_share()],
#'   [hd_metric_record()]
#' @export
hd_record_stability_metrics <- function(con, run_uuid, returns,
                                        w, ann_factor = 252, pct = 0.05) {
  if (!is.numeric(returns)) {
    cli::cli_abort(c("x" = "{.arg returns} must be a numeric vector."))
  }
  returns_clean <- returns[!is.na(returns)]
  if (length(returns_clean) == 0L) {
    empty <- list(
      ssr            = NA_real_,
      ssr_mean_sharpe = NA_real_,
      ssr_se         = NA_real_,
      ssr_n_windows  = 0L,
      ssr_lag_nw     = NA_integer_,
      top_share      = NA_real_,
      top_n_top      = 0L,
      top_n_total    = 0L
    )
    return(invisible(empty))
  }

  ssr_out <- hd_sharpe_stability_ratio(returns, w = w, ann_factor = ann_factor)
  top_out <- hd_top5pct_share(returns, pct = pct)

  metrics <- list(
    ssr            = ssr_out$ssr,
    ssr_mean_sharpe = ssr_out$mean_sharpe,
    ssr_se         = ssr_out$se,
    ssr_n_windows  = ssr_out$n_windows,
    ssr_lag_nw     = ssr_out$lag_nw,
    top_share      = top_out$top_share,
    top_n_top      = top_out$n_top,
    top_n_total    = top_out$n_total
  )

  stability_units <- c(
    ssr             = "ratio",
    ssr_mean_sharpe = "ratio",
    ssr_se          = "ratio",
    ssr_n_windows   = "count",
    ssr_lag_nw      = "count",
    top_share       = "fraction",
    top_n_top       = "count",
    top_n_total     = "count"
  )

  hd_metric_record(con, run_uuid, metrics, units = stability_units)
  invisible(metrics)
}


#' Leg-count / manufactured-Sharpe calibration coverage from the registry
#'
#' For every strategy in `bt.strategy` whose `leg_count > 1` (a declared
#' composite/blended book -- see [hd_strategy_upsert()]'s `leg_count`
#' section, #839), reports whether ANY of its runs has an accompanying
#' manufactured-Sharpe calibration annotation, recorded via
#' [hd_diagnostic_record()] under `diagnostic_name =
#' "leg_blend_manufactured_sharpe"` -- the diagnostic name
#' [hd_zero_alpha_calibration()]'s output is intended to feed.
#'
#' This is a pure read -- it does not itself decide pass/fail; see
#' `check_registry_leg_count_calibration()` (`R/plan_qa_gates.R`, QA gate
#' S33) for the gate built on top of this reader.
#'
#' @param con DBI connection (read-only is fine).
#' @return A tibble with columns `strategy_id`, `leg_count`,
#'   `has_leg_calibration` (logical) -- one row per composite strategy
#'   (`leg_count > 1`) currently in `bt.strategy`. Zero rows if no
#'   composite strategy is registered yet.
#' @export
hd_registry_leg_count_status <- function(con) {
  rlang::check_installed("DBI")
  sql <- "
    SELECT
      s.strategy_id,
      s.leg_count,
      EXISTS (
        SELECT 1
        FROM bt.run r
        JOIN bt.diagnostic d ON d.run_uuid = r.run_uuid
        WHERE r.strategy_id = s.strategy_id
          AND d.diagnostic_name = 'leg_blend_manufactured_sharpe'
      ) AS has_leg_calibration
    FROM bt.strategy s
    WHERE s.leg_count > 1
    ORDER BY s.strategy_id
  "
  out <- DBI::dbGetQuery(con, sql)
  out <- tibble::as_tibble(out)
  if (nrow(out) == 0L) {
    out <- tibble::tibble(
      strategy_id = character(0),
      leg_count = integer(0),
      has_leg_calibration = logical(0)
    )
  } else {
    out$has_leg_calibration <- as.logical(out$has_leg_calibration)
  }
  out
}

# ── internals ─────────────────────────────────────────────────────────────

#' @param tbl A metrics tibble (long or wide form; see [hd_metric_record()]).
#' @param units Optional named character vector, `metric_name -> unit`.
#' @return A tibble with columns `metric_name`, `metric_value`,
#'   `metric_unit` — every row's `metric_unit` validated non-`NA` and
#'   in [hd_metric_units()].
#' @noRd
.normalise_metric_long <- function(tbl, units = NULL) {
  if (all(c("metric_name", "metric_value") %in% names(tbl))) {
    metric_name <- as.character(tbl$metric_name)
    metric_unit <- if ("metric_unit" %in% names(tbl)) {
      as.character(tbl$metric_unit)
    } else {
      rep(NA_character_, length(metric_name))
    }
    if (!is.null(units)) {
      needs_fill <- is.na(metric_unit)
      if (any(needs_fill)) {
        metric_unit[needs_fill] <- unname(units[metric_name[needs_fill]])
      }
    }
    out <- tibble::tibble(
      metric_name  = metric_name,
      metric_value = as.numeric(tbl$metric_value),
      metric_unit  = metric_unit
    )
    out <- out[!is.na(out$metric_value), , drop = FALSE]
    .hd_validate_metric_units(out$metric_name, out$metric_unit)
    return(out)
  }
  # Wide form: take first row, numeric columns only. No metric_unit slot
  # exists in wide form, so `units` is the only source of truth.
  row1 <- as.list(tbl[1L, ])
  is_num <- vapply(row1, function(x) is.numeric(x) && !is.na(x), logical(1))
  if (!any(is_num)) {
    return(tibble::tibble(
      metric_name = character(),
      metric_value = numeric(),
      metric_unit = character()
    ))
  }
  metric_name <- names(row1)[is_num]
  metric_unit <- if (is.null(units)) {
    rep(NA_character_, length(metric_name))
  } else {
    unname(units[metric_name])
  }
  out <- tibble::tibble(
    metric_name  = metric_name,
    metric_value = as.numeric(unlist(row1[is_num])),
    metric_unit  = metric_unit
  )
  .hd_validate_metric_units(out$metric_name, out$metric_unit)
  out
}

.normalise_diagnostic_long <- function(tbl) {
  if (all(c("diagnostic_name") %in% names(tbl))) {
    out <- tibble::tibble(
      diagnostic_name = as.character(tbl$diagnostic_name),
      value_num  = if ("value_num"  %in% names(tbl))
                     as.numeric(tbl$value_num)  else NA_real_,
      value_text = if ("value_text" %in% names(tbl))
                     as.character(tbl$value_text) else NA_character_
    )
    return(out)
  }
  row1 <- as.list(tbl[1L, ])
  nms <- names(row1)
  if (length(nms) == 0L) {
    return(tibble::tibble(
      diagnostic_name = character(),
      value_num = numeric(),
      value_text = character()
    ))
  }
  is_num <- vapply(row1, function(x) is.numeric(x) && !is.na(x), logical(1))
  tibble::tibble(
    diagnostic_name = nms,
    value_num       = ifelse(is_num, vapply(row1, function(x)
                       suppressWarnings(as.numeric(x)[1]), numeric(1)),
                       NA_real_),
    value_text      = ifelse(is_num, NA_character_,
                       vapply(row1, function(x) as.character(x)[1],
                              character(1)))
  )
}
