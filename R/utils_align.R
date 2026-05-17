#' Align multiple time series to a common period
#'
#' Resamples a named list of series to a common period and returns a wide
#' tibble. Handles mixed input frequencies (e.g., 2 daily + 3 monthly with
#' inconsistent month-day conventions). Aggregation is causal — uses only
#' observations within the period (no look-ahead).
#'
#' @param series Named list of tibbles. Each tibble must have a `date` column
#'   (Date) and a value column whose name is given by `value_col`. List names
#'   become column names in the output.
#' @param to_period One of "day", "week", "month", "quarter", "year".
#' @param anchor One of "end_bizday" (default — last weekday of period),
#'   "end" (last calendar day), "start" (first calendar day).
#' @param method One of "compound" (default — `prod(1+r) - 1`, for returns),
#'   "last" (last observation in period — for levels), "mean", "sum".
#' @param value_col Name of the value column inside each input tibble.
#'   Default "strategy_ret".
#' @param min_obs Minimum non-NA observations required per period to emit a
#'   non-NA value. Default 1L.
#' @return Wide tibble with one row per period: column `date` (the anchor
#'   date for the period), one column per name in `series`.
#' @export
align_period <- function(series,
                         to_period = "month",
                         anchor = "end_bizday",
                         method = c("compound", "last", "mean", "sum"),
                         value_col = "strategy_ret",
                         min_obs = 1L) {

  # ── Input validation ────────────────────────────────────────────────────────

  if (!is.list(series) || length(series) == 0L) {
    cli::cli_abort(c(
      "x" = "{.arg series} must be a non-empty named list.",
      "i" = "Received: {.cls {class(series)}} of length {length(series)}."
    ))
  }
  if (is.null(names(series)) || any(nchar(names(series)) == 0L)) {
    cli::cli_abort(c(
      "x" = "All elements of {.arg series} must be named.",
      "i" = "Names are used as column names in the output."
    ))
  }

  allowed_periods <- c("day", "week", "month", "quarter", "year")
  if (!to_period %in% allowed_periods) {
    cli::cli_abort(c(
      "x" = "{.arg to_period} must be one of {.val {allowed_periods}}.",
      "i" = "Got {.val {to_period}}."
    ))
  }

  allowed_anchors <- c("end_bizday", "end", "start")
  if (!anchor %in% allowed_anchors) {
    cli::cli_abort(c(
      "x" = "{.arg anchor} must be one of {.val {allowed_anchors}}.",
      "i" = "Got {.val {anchor}}."
    ))
  }

  method <- match.arg(method)

  if (!is.numeric(min_obs) || length(min_obs) != 1L || is.na(min_obs) ||
      min_obs < 1 || min_obs != floor(min_obs)) {
    cli::cli_abort(c(
      "x" = "{.arg min_obs} must be a positive integer-valued scalar.",
      "i" = "Got {.val {min_obs}}."
    ))
  }
  min_obs <- as.integer(min_obs)

  # Validate each element has required columns
  purrr::walk2(series, names(series), function(tbl, nm) {
    if (!is.data.frame(tbl)) {
      cli::cli_abort(c(
        "x" = "series[[{.val {nm}}]] must be a data frame.",
        "i" = "Got {.cls {class(tbl)}}."
      ))
    }
    missing_cols <- setdiff(c("date", value_col), names(tbl))
    if (length(missing_cols) > 0L) {
      cli::cli_abort(c(
        "x" = "series[[{.val {nm}}]] is missing column(s): {.val {missing_cols}}.",
        "i" = "Each tibble must have columns {.val date} and {.val {value_col}}."
      ))
    }
  })

  # ── Anchor computation helper ───────────────────────────────────────────────

  compute_anchor <- function(dates, to_period, anchor) {
    if (anchor == "start") {
      return(as.Date(lubridate::floor_date(dates, unit = to_period)))
    }

    # Last calendar day of period
    last_cal <- as.Date(lubridate::ceiling_date(dates, unit = to_period) - 1L)

    if (anchor == "end") {
      return(last_cal)
    }

    # end_bizday: snap last calendar day back to Friday if Sat/Sun.
    # Note: week_start = 1 means Monday = 1, ..., Saturday = 6, Sunday = 7.
    # This handles weekends but NOT public holidays; holiday-aware
    # calendars are a follow-up (see the bizdays package).
    wd <- lubridate::wday(last_cal, week_start = 1L)
    result <- last_cal - dplyr::case_when(
      wd == 6L ~ 1L,  # Saturday → Friday
      wd == 7L ~ 2L,  # Sunday   → Friday
      TRUE     ~ 0L
    )
    # Always return Date (ceiling_date on POSIXct inputs returns POSIXct,
    # which would prevent join across mixed-type series).
    as.Date(result)
  }

  # ── Summarise each series ───────────────────────────────────────────────────

  summarise_one <- function(tbl, nm) {
    if (nrow(tbl) == 0L) {
      # Empty series: return a zero-row tibble with the right schema.
      return(tibble::tibble(
        .anchor = lubridate::Date(0),
        .value  = numeric(0)
      ))
    }

    # Coerce date to Date class — input may be POSIXct (e.g. end-of-day stamps
    # from ltr: "2005-01-31 23:59:59 UTC"). Without this, ceiling_date() returns
    # POSIXct anchors that fail to join with Date anchors from other series.
    tbl <- dplyr::mutate(tbl, date = as.Date(.data$date))
    tbl <- dplyr::arrange(tbl, date)
    anchored <- dplyr::mutate(
      tbl,
      .anchor = compute_anchor(.data$date, to_period, anchor),
      .value  = .data[[value_col]]
    )

    # Group and summarise with causal semantics:
    # every row's .value comes from a date <= the anchor (ceiling_date - 1 >= date).
    summarised <- dplyr::summarise(
      dplyr::group_by(anchored, .data$.anchor),
      .n_obs = sum(!is.na(.data$.value)),
      .summary = {
        vals <- .data$.value[!is.na(.data$.value)]
        if (length(vals) == 0L) {
          NA_real_
        } else if (method == "compound") {
          prod(1 + vals) - 1
        } else if (method == "last") {
          # last non-NA (rows are already arranged by date within the group
          # because we arranged tbl above; group_by preserves row order)
          utils::tail(.data$.value[!is.na(.data$.value)], 1L)
        } else if (method == "mean") {
          mean(vals)
        } else {
          # sum
          sum(vals)
        }
      },
      .groups = "drop"
    )

    dplyr::mutate(
      summarised,
      .value = dplyr::if_else(.data$.n_obs >= min_obs, .data$.summary, NA_real_)
    )
  }

  summaries <- purrr::map(series, summarise_one)

  # ── Outer-join all series on the anchor date ────────────────────────────────

  result <- purrr::reduce(
    purrr::imap(summaries, function(s, nm) {
      # Use string-based rename to avoid .data$ in tidyselect context (deprecated tidyselect 1.2.0)
      out <- dplyr::rename(s, date = ".anchor")
      out <- dplyr::rename(out, !!nm := ".value")
      dplyr::select(out, "date", dplyr::all_of(nm))
    }),
    function(a, b) dplyr::full_join(a, b, by = "date")
  )

  dplyr::arrange(result, date)
}

#' As-of join: attach the most recent y value at or before each x date
#'
#' For each row of `x`, finds the row in `y` whose date is the largest value
#' less than or equal to `x$date` (the "as-of" semantic). Returns `x` with the
#' matched `value_col` from `y` attached.
#'
#' Use this when the question is a *point-in-time level lookup*, NOT a period
#' aggregation. Example: "what was VIX (level) on each month-end?".
#' For aggregating returns or other flow quantities, use `align_period()`.
#'
#' @param x Tibble with a `date` column (Date). Driver of the lookup.
#' @param y Tibble with a `date` column (Date) and the value column.
#' @param value_col Name of the column in `y` to attach (character scalar).
#' @param tol_days Optional max staleness in days. If the most recent y
#'   observation is older than `x$date - tol_days`, the result is NA.
#'   Default `NULL` (no limit). Common choice: `7L` for daily data joined
#'   to monthly anchors; `1L` for strict same-day-or-prior.
#' @return `x` with one extra column named `value_col`. Row order matches `x`.
#' @export
asof_lookup <- function(x, y, value_col, tol_days = NULL) {

  # ── Input validation ──────────────────────────────────────────────────────────

  if (!is.data.frame(x)) {
    cli::cli_abort(c(
      "x" = "{.arg x} must be a data frame.",
      "i" = "Received: {.cls {class(x)}}."
    ))
  }
  if (!is.data.frame(y)) {
    cli::cli_abort(c(
      "x" = "{.arg y} must be a data frame.",
      "i" = "Received: {.cls {class(y)}}."
    ))
  }
  if (!"date" %in% names(x)) {
    cli::cli_abort(c(
      "x" = "{.arg x} must have a {.val date} column.",
      "i" = "Columns found: {.val {names(x)}}."
    ))
  }
  if (!"date" %in% names(y)) {
    cli::cli_abort(c(
      "x" = "{.arg y} must have a {.val date} column.",
      "i" = "Columns found: {.val {names(y)}}."
    ))
  }
  if (!is.character(value_col) || length(value_col) != 1L || is.na(value_col) ||
      nchar(value_col) == 0L) {
    cli::cli_abort(c(
      "x" = "{.arg value_col} must be a non-empty character scalar.",
      "i" = "Received: {.val {value_col}}."
    ))
  }
  if (!value_col %in% names(y)) {
    cli::cli_abort(c(
      "x" = "{.arg y} does not have a column named {.val {value_col}}.",
      "i" = "Columns in y: {.val {names(y)}}."
    ))
  }
  if (!is.null(tol_days)) {
    if (!is.numeric(tol_days) || length(tol_days) != 1L || is.na(tol_days) ||
        tol_days < 0 || tol_days != floor(tol_days)) {
      cli::cli_abort(c(
        "x" = "{.arg tol_days} must be NULL or a non-negative integer-valued scalar.",
        "i" = "Received: {.val {tol_days}}."
      ))
    }
    tol_days <- as.integer(tol_days)
  }

  # ── Defensive date coercion (data-validation-timeseries Section 9) ─────────
  # POSIXct join keys silently produce 0 matches in SQL; coerce both sides.
  # as.Date() truncates time-of-day — if y has multiple intraday rows for the
  # same date, the coercion collapses them and DuckDB selects an arbitrary one.
  # Error loudly here rather than silently returning wrong values.
  # (roborev cluster B, finding F2)

  x <- dplyr::mutate(x, date = as.Date(.data$date))
  y <- dplyr::mutate(y, date = as.Date(.data$date))

  dup_dates <- y |>
    dplyr::count(.data$date, name = "n_") |>
    dplyr::filter(.data$n_ > 1L)
  if (nrow(dup_dates) > 0L) {
    cli::cli_abort(c(
      "x" = "{.arg y} has {nrow(dup_dates)} date{?s} with more than one row after \\
coercing to Date (intraday observations collapse to an arbitrary row).",
      "i" = "Aggregate {.arg y} to daily before calling {.fn asof_lookup}: \\
e.g. last observation per date.",
      "i" = "First duplicate date: {.val {dup_dates$date[1L]}} \\
({dup_dates$n_[1L]} rows)."
    ))
  }

  # ── ASOF JOIN via DuckDB ──────────────────────────────────────────────────────
  # DuckDB ASOF LEFT JOIN is available from DuckDB >= 0.9.
  # Semantics: for each row of x_tbl, pick the y_tbl row whose date is the
  # largest value <= x_tbl.date (i.e., the most recent y observation that is
  # not in the future relative to x).

  con <- duckdb::dbConnect(duckdb::duckdb())
  on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  duckdb::duckdb_register(con, "x_tbl", x)
  duckdb::duckdb_register(con, "y_tbl", y[, c("date", value_col), drop = FALSE])

  sql <- paste0(
    "SELECT x_tbl.*, y_tbl.", value_col, ", ",
    "       y_tbl.date AS asof_y_date_ ",
    "FROM x_tbl ",
    "ASOF LEFT JOIN y_tbl ON x_tbl.date >= y_tbl.date"
  )

  out <- DBI::dbGetQuery(con, sql)

  # ── tol_days post-filter ──────────────────────────────────────────────────────
  # If y_date is more than tol_days before x date, set value_col to NA.
  # The asof_y_date_ sentinel column lets us compute staleness without re-joining.

  if (!is.null(tol_days)) {
    stale <- !is.na(out[["asof_y_date_"]]) &
      (as.Date(out[["date"]]) - as.Date(out[["asof_y_date_"]])) > tol_days
    out[[value_col]][stale] <- NA
    # Also mark rows where y_date is missing (no y obs at or before x date)
    out[[value_col]][is.na(out[["asof_y_date_"]])] <- NA
  }

  # Drop the internal sentinel column
  out[["asof_y_date_"]] <- NULL

  tibble::as_tibble(out)
}
