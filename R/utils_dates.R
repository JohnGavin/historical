#' Last business day of the month containing a date
#'
#' Returns the last business day (Mon-Fri, no holiday calendar) of the
#' calendar month containing each input date. Used to standardise monthly
#' time-series stamps across strategies — see issue #147.
#'
#' Holidays are NOT honoured in this version. A holiday-aware variant
#' would require integrating `bizdays` with a registered exchange
#' calendar; that is a follow-up task.
#'
#' @param date Date or vector of Dates. POSIXct is coerced via `as.Date()`.
#'   Character inputs are rejected with a `cli::cli_abort()` — the caller
#'   must coerce explicitly.
#' @return Date vector of the same length as the input. NA in, NA out.
#' @export
#'
#' @examples
#' # Mid-month -> last business day of same month
#' to_month_end_bizday(as.Date("2026-02-15"))  # 2026-02-27 (Fri, Feb 28 is Sat)
#'
#' # Calendar month-end already a weekday — idempotent
#' to_month_end_bizday(as.Date("2026-03-31"))  # 2026-03-31 (Tue)
to_month_end_bizday <- function(date) {
  # ── Input validation ────────────────────────────────────────────────────────
  if (is.character(date)) {
    cli::cli_abort(c(
      "x" = "{.arg date} must not be a {.cls character} vector.",
      "i" = "Coerce explicitly: {.code as.Date(date)} or {.code lubridate::ymd(date)}."
    ))
  }
  if (!inherits(date, c("Date", "POSIXct", "POSIXlt"))) {
    cli::cli_abort(c(
      "x" = "{.arg date} must be a {.cls Date} or {.cls POSIXct} vector, not {.cls {class(date)[[1]]}}.",
      "i" = "Coerce explicitly: {.code as.Date(date)}."
    ))
  }

  # ── Coerce POSIXct / POSIXlt to Date (safe, ignores sub-day precision) ─────
  date <- as.Date(date)

  # ── Last calendar day of each month ─────────────────────────────────────────
  month_end <- lubridate::ceiling_date(date, "month") - lubridate::days(1L)

  # ── Snap Saturday -> Friday (-1), Sunday -> Friday (-2) ─────────────────────
  # lubridate::wday with week_start = 1: Mon=1 ... Sat=6, Sun=7
  wday <- lubridate::wday(month_end, week_start = 1L)

  dplyr::case_when(
    wday == 6L ~ month_end - lubridate::days(1L),  # Sat -> Fri
    wday == 7L ~ month_end - lubridate::days(2L),  # Sun -> Fri
    TRUE       ~ month_end                          # already Mon-Fri
  )
}


#' Last business day of the month FOLLOWING the month containing a date
#'
#' Use when the input date represents an execution time and snapping to the
#' current month-end would create look-ahead bias (i.e., the signal is
#' computed mid-month but the trade can only execute at the following
#' month-end).
#'
#' @param date Date or vector of Dates. Same coercion rules as
#'   [to_month_end_bizday()].
#' @return Date vector the same length as the input.
#' @export
#'
#' @examples
#' # A signal computed on 2026-02-15 that trades at March month-end
#' to_next_month_end_bizday(as.Date("2026-02-15"))  # 2026-03-31
to_next_month_end_bizday <- function(date) {
  if (is.character(date)) {
    cli::cli_abort(c(
      "x" = "{.arg date} must not be a {.cls character} vector.",
      "i" = "Coerce explicitly: {.code as.Date(date)}."
    ))
  }
  # Advance by enough days to guarantee landing in the next calendar month,
  # then call the same-month helper.
  to_month_end_bizday(as.Date(date) + lubridate::days(32L))
}
