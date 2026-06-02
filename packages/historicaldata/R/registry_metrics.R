# Backtest registry — metric + diagnostic recorders + leaderboard reader
# (#347 PR 3/4)
#
# Long-form writes:
#   hd_metric_record(con, run_uuid, metrics)
#   hd_diagnostic_record(con, run_uuid, diagnostics)
#
# Read:
#   hd_leaderboard_from_registry(con, metric_name = "sharpe", ...)

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
#' Idempotent per (run_uuid, metric_name): re-recording overwrites.
#'
#' @param con DBI connection (writable).
#' @param run_uuid Character. Must refer to an existing `bt.run` row.
#' @param metrics A tibble (long or wide as above).
#' @return Invisibly, the number of rows written.
#' @export
hd_metric_record <- function(con, run_uuid, metrics) {
  rlang::check_installed("DBI")
  if (is.null(run_uuid) || is.na(run_uuid) || !nzchar(run_uuid)) {
    cli::cli_abort("{.field run_uuid} is required.")
  }
  if (is.list(metrics) && !is.data.frame(metrics)) {
    metrics <- tibble::as_tibble(metrics)
  }
  long <- .normalise_metric_long(metrics)
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

#' Leaderboard read from the registry
#'
#' Joins `bt.strategy` + `bt.run` + `bt.metric` and pivots the named
#' metric (default `"sharpe"`) into a column. Returns one row per
#' (strategy_id, partition, run_uuid).
#'
#' @param con DBI connection (read-only is fine).
#' @param metric_name Character. Default `"sharpe"`.
#' @param latest_per_partition Logical. If `TRUE` (default), keep only
#'   the most recent run per (strategy_id, partition). If `FALSE`, every
#'   recorded run is returned.
#' @return A tibble.
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
  out
}

# ── registry stability helper ─────────────────────────────────────────────

#' Record SSR and top-pct-share stability metrics for a backtest run
#'
#' Convenience wrapper that calls [hd_sharpe_stability_ratio()] and
#' [hd_top5pct_share()] on a returns vector, then writes the combined
#' 8 metric values into `bt.metric` via [hd_metric_record()].
#'
#' The 8 metrics written are:
#' \describe{
#'   \item{`ssr`}{Sharpe Stability Ratio.}
#'   \item{`ssr_mean_sharpe`}{Mean of rolling Sharpe series.}
#'   \item{`ssr_se`}{Newey-West HAC standard error.}
#'   \item{`ssr_n_windows`}{Number of complete rolling windows.}
#'   \item{`ssr_lag_nw`}{Newey-West bandwidth used.}
#'   \item{`top_share`}{Fraction of total return from the top-`pct` periods.}
#'   \item{`top_n_top`}{Count of top-`pct` periods.}
#'   \item{`top_n_total`}{Total non-NA period count.}
#' }
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

  hd_metric_record(con, run_uuid, metrics)
  invisible(metrics)
}


# ── internals ─────────────────────────────────────────────────────────────

.normalise_metric_long <- function(tbl) {
  if (all(c("metric_name", "metric_value") %in% names(tbl))) {
    out <- tibble::tibble(
      metric_name  = as.character(tbl$metric_name),
      metric_value = as.numeric(tbl$metric_value),
      metric_unit  = if ("metric_unit" %in% names(tbl))
                       as.character(tbl$metric_unit) else NA_character_
    )
    return(out[!is.na(out$metric_value), , drop = FALSE])
  }
  # Wide form: take first row, numeric columns only.
  row1 <- as.list(tbl[1L, ])
  is_num <- vapply(row1, function(x) is.numeric(x) && !is.na(x), logical(1))
  if (!any(is_num)) {
    return(tibble::tibble(
      metric_name = character(),
      metric_value = numeric(),
      metric_unit = character()
    ))
  }
  tibble::tibble(
    metric_name  = names(row1)[is_num],
    metric_value = as.numeric(unlist(row1[is_num])),
    metric_unit  = NA_character_
  )
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
