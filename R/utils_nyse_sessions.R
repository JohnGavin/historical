#' NYSE trading session of a UTC timestamp
#'
#' Classifies each instant by the New York clock and the NYSE holiday
#' calendar (#1080). UTC is converted to `America/New_York` with the tz
#' database, so daylight-saving transitions are handled by the database, not by
#' a hand-typed offset. Holidays come from `timeDate::holidayNYSE()`; nothing
#' is typed by hand.
#'
#' Sessions, by New York local time on a trading day:
#' \itemize{
#'   \item `regular`: 09:30 (inclusive) to 16:00 (exclusive)
#'   \item `extended`: 04:00 to 09:30 and 16:00 to 20:00
#'   \item `overnight`: 20:00 to 24:00 and 00:00 to 04:00
#'   \item `closed`: the WHOLE local calendar day of a weekend or NYSE holiday
#' }
#' The day is decided by the local calendar date of the instant. So Friday
#' 21:00 is `overnight` but Saturday 01:00 is `closed`, and Monday 01:00 is
#' `overnight` (Monday is a trading day), Thursday 2026-11-26 (Thanksgiving)
#' is `closed` from 00:00 to 24:00.
#'
#' Known gap: early-close days (13:00 close, e.g. the day after Thanksgiving)
#' are NOT modelled; `timeDate` exposes full-day holidays only. They are
#' treated as ordinary full days, so 13:00 to 16:00 on those days is labelled
#' `regular` although the cash market is shut.
#'
#' @param time_utc POSIXct vector (any tz attribute; the instant is what counts).
#'   Character and Date inputs are rejected: the caller must say which instant
#'   is meant. NA in, NA out.
#' @return A factor with levels `regular`, `extended`, `overnight`, `closed`.
#' @export
#' @examples
#' nyse_session(as.POSIXct("2026-11-24 14:30:00", tz = "UTC"))  # Tue 09:30 NY: regular
nyse_session <- function(time_utc) {
  levs <- c("regular", "extended", "overnight", "closed")
  .nyse_check_time(time_utc, "time_utc")
  lt <- as.POSIXlt(as.POSIXct(time_utc), tz = "America/New_York")
  local_date <- as.Date(format(lt, "%Y-%m-%d"))
  hour <- lt$hour + lt$min / 60 + lt$sec / 3600
  trading <- .nyse_is_trading_day(local_date)
  out <- ifelse(!trading, "closed",
         ifelse(hour >= 9.5 & hour < 16, "regular",
         ifelse((hour >= 4 & hour < 9.5) | (hour >= 16 & hour < 20),
                "extended", "overnight")))
  out[is.na(time_utc)] <- NA_character_
  factor(out, levels = levs)
}

#' Does a bar span the 09:30 New York open?
#'
#' TRUE when the 09:30 New York instant lies strictly inside the bar, i.e.
#' `open < 09:30 < open + length`. A bar that starts at 09:30 or ends at 09:30
#' does not straddle it. The check is a clock check only: it does not ask
#' whether that day is a trading day (a bar that spans 09:30 on a holiday
#' returns TRUE). The hour that straddles the open moves with daylight saving
#' (13:00-14:00 UTC in summer is 09:00-10:00 New York; in winter it is
#' 14:00-15:00 UTC), which is why this is computed, not hard-coded.
#'
#' @param bar_open_utc POSIXct vector of bar open times.
#' @param bar_len_minutes Positive number (or vector, recycled): bar length in
#'   minutes, at most 1440.
#' @return Logical vector, NA where the open time is NA.
#' @export
#' @examples
#' nyse_straddles_open(as.POSIXct("2026-11-24 14:00:00", tz = "UTC"), 60)  # TRUE (09:00 NY)
nyse_straddles_open <- function(bar_open_utc, bar_len_minutes) {
  .nyse_check_time(bar_open_utc, "bar_open_utc")
  if (!is.numeric(bar_len_minutes) || length(bar_len_minutes) == 0L ||
      anyNA(bar_len_minutes) || any(bar_len_minutes <= 0) ||
      any(bar_len_minutes > 1440)) {
    cli::cli_abort(c(
      "x" = "{.arg bar_len_minutes} must be a number in (0, 1440].",
      "i" = "Got {.val {bar_len_minutes}}."
    ))
  }
  open <- as.numeric(as.POSIXct(bar_open_utc))  # seconds; tz attributes cannot interfere
  end <- open + bar_len_minutes * 60
  lt <- as.POSIXlt(as.POSIXct(bar_open_utc), tz = "America/New_York")
  d0 <- as.Date(format(lt, "%Y-%m-%d"))
  at_open <- function(d) {
    out <- rep(NA_real_, length(d))
    ok <- !is.na(d)
    out[ok] <- as.numeric(as.POSIXct(paste(format(d[ok], "%Y-%m-%d"), "09:30:00"),
                                      tz = "America/New_York"))
    out
  }
  o0 <- at_open(d0)       # that day's open
  o1 <- at_open(d0 + 1L)  # next day's open (a bar that starts after 09:30)
  (open < o0 & o0 < end) | (open < o1 & o1 < end)
}

.nyse_check_time <- function(x, arg) {
  if (!inherits(x, "POSIXct")) {
    cli::cli_abort(c(
      "x" = "{.arg {arg}} must be a {.cls POSIXct} vector, not {.cls {class(x)[[1]]}}.",
      "i" = "Coerce explicitly with {.code as.POSIXct(x, tz = \"UTC\")}."
    ))
  }
  invisible(x)
}

# TRUE on a weekday that is not an NYSE holiday. NA date -> NA.
.nyse_is_trading_day <- function(d) {
  if (!requireNamespace("timeDate", quietly = TRUE)) {
    cli::cli_abort(c(
      "x" = "Package {.pkg timeDate} is required for the NYSE holiday calendar.",
      "i" = "It is listed in flake.nix; enter the project shell with {.code nix develop}."
    ))
  }
  yrs <- unique(as.integer(format(d[!is.na(d)], "%Y")))
  hol <- if (length(yrs) == 0L) as.Date(character()) else
    as.Date(format(timeDate::holidayNYSE(yrs), "%Y-%m-%d"))
  wd <- as.POSIXlt(d)$wday  # 0 = Sunday, 6 = Saturday
  !(wd %in% c(0L, 6L)) & !(d %in% hol)
}
