# Point-in-time S&P 500 membership (#816)
#
# Reads the free fja05680/sp500 historical-components file downloaded by
# scripts/fetch_sp500_membership.R: one row per index-change date, a `tickers`
# cell holding the FULL comma-separated membership after that change. This is
# membership-with-dates only. It has no prices, no returns and no delisting
# data: `delisting_date` in the PIT universe is the date a ticker LEFT THE
# INDEX (an acquisition, a bankruptcy, or a demotion all look alike), and the
# delisting reason and price are unavailable from this source.
#
# Ticker-only key caveat (#865): the file keys on ticker symbols, and a symbol
# can be reused by a different company (WM is Waste Management throughout;
# Washington Mutual is WAMUQ). Nothing here resolves identity.

#' Directory holding the local S&P 500 membership cache
#'
#' Reads `SP500_MEMBERSHIP_DIR`, defaulting to
#' `~/.cache/historical/sp500_membership`. Only resolves the path; it is never
#' created or written here. Populate it with `scripts/fetch_sp500_membership.R`.
#'
#' @return Character path (not guaranteed to exist).
#' @family sp500
#' @export
hd_sp500_data_dir <- function() {
  path.expand(Sys.getenv("SP500_MEMBERSHIP_DIR", "~/.cache/historical/sp500_membership"))
}

#' File name of the cached membership CSV inside [hd_sp500_data_dir()]
#' @return Character scalar.
#' @keywords internal
.hd_sp500_file_name <- function() "sp500_historical_components.csv"

#' Path of the cached S&P 500 membership CSV
#'
#' @param data_dir Directory holding the cache. Defaults to [hd_sp500_data_dir()].
#' @return Character path to the CSV. Aborts if the file is absent, naming the
#'   fetch script, so a machine without the cache fails loudly.
#' @family sp500
#' @export
hd_sp500_membership_path <- function(data_dir = hd_sp500_data_dir()) {
  path <- file.path(data_dir, .hd_sp500_file_name())
  if (!file.exists(path)) {
    cli::cli_abort(c(
      "x" = "S&P 500 membership file not found: {.path {path}}.",
      "i" = "Fetch it first: {.code Rscript scripts/fetch_sp500_membership.R}",
      "i" = "Or set {.envvar SP500_MEMBERSHIP_DIR} to a directory that holds {.file {(.hd_sp500_file_name())}}."
    ))
  }
  path
}

#' Read the raw membership snapshots (one row per change date)
#'
#' Validates the file boundary and returns the snapshot table unchanged in
#' shape: `date` (Date, ascending) and `tickers` (the comma-separated cell).
#' Aborts on a missing file, wrong columns, an empty file, an unparseable or
#' missing date, or a duplicated date. Nothing is coerced to `NA`.
#'
#' @param path Path to the CSV (columns `date,tickers`).
#' @return A data.frame with columns `date` (Date) and `tickers` (character),
#'   sorted by date.
#' @family sp500
#' @export
hd_sp500_read_snapshots <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path)) {
    cli::cli_abort("membership file not found: {.path {path}}")
  }
  d <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
                       colClasses = "character")
  if (!identical(names(d), c("date", "tickers"))) {
    cli::cli_abort(c(
      "x" = "membership file must have exactly the columns date,tickers.",
      "i" = "Found: {.val {names(d)}}"
    ))
  }
  if (nrow(d) == 0L) {
    cli::cli_abort("membership file has no rows.")
  }
  parsed <- as.Date(d$date, format = "%Y-%m-%d")
  if (anyNA(parsed)) {
    bad <- d$date[is.na(parsed)]
    cli::cli_abort(c(
      "x" = "membership file has {length(bad)} missing or unparseable date{?s}.",
      "i" = "Expected YYYY-MM-DD; first offending value: {.val {bad[1L]}}"
    ))
  }
  d$date <- parsed
  if (anyDuplicated(d$date) > 0L) {
    dup <- d$date[duplicated(d$date)]
    cli::cli_abort(c(
      "x" = "membership file has {length(dup)} duplicated snapshot date{?s}.",
      "i" = "First duplicate: {.val {format(dup[1L])}}. Two snapshots for one date are ambiguous."
    ))
  }
  d[order(d$date), , drop = FALSE]
}

#' Load point-in-time S&P 500 membership as a tidy long table
#'
#' One row per (snapshot date, ticker): the ticker was an index member after
#' the change recorded on that date and until the next snapshot date.
#' Every boundary is validated and aborts loudly: see [hd_sp500_read_snapshots()]
#' plus, per snapshot, an empty token, a repeated ticker, a legacy
#' `SYM-YYYYMM` removal-marker token, or fewer than `min_members` members.
#'
#' @param path Path to the CSV. Defaults to [hd_sp500_membership_path()].
#' @param min_members Schema-drift guard: abort if any snapshot lists fewer
#'   members than this (the real file has 487 to 507 per snapshot).
#' @return A tibble with `date` (Date) and `ticker` (character), ordered by
#'   date then ticker.
#' @family sp500
#' @export
hd_sp500_membership <- function(path = hd_sp500_membership_path(),
                                min_members = 400L) {
  snaps <- hd_sp500_read_snapshots(path)
  cells <- strsplit(snaps$tickers, ",", fixed = TRUE)
  cells <- lapply(cells, trimws)
  n <- lengths(cells)

  empty <- vapply(cells, function(z) any(!nzchar(z)), logical(1))
  # strsplit() drops a trailing empty field ("A,B," -> "A","B"), so a trailing
  # comma must be caught on the raw cell.
  empty <- empty | n == 0L | grepl(",\\s*$", snaps$tickers)
  if (any(empty)) {
    cli::cli_abort(c(
      "x" = "{sum(empty)} snapshot{?s} with an empty ticker token or no tickers.",
      "i" = "First offending snapshot: {.val {format(snaps$date[which(empty)[1L]])}}"
    ))
  }
  dup <- vapply(cells, anyDuplicated, integer(1)) > 0L
  if (any(dup)) {
    cli::cli_abort(c(
      "x" = "{sum(dup)} snapshot{?s} with a ticker listed more than once.",
      "i" = "First offending snapshot: {.val {format(snaps$date[which(dup)[1L]])}}"
    ))
  }
  marked <- vapply(cells, function(z) any(grepl("-[0-9]{6}$", z)), logical(1))
  if (any(marked)) {
    cli::cli_abort(c(
      "x" = "{sum(marked)} snapshot{?s} with legacy {.code SYM-YYYYMM} removal-marker tokens.",
      "i" = "That is the old file layout. Use the maintained '(Updated)' file via {.code scripts/fetch_sp500_membership.R}."
    ))
  }
  thin <- n < min_members
  if (any(thin)) {
    cli::cli_abort(c(
      "x" = "{sum(thin)} snapshot{?s} with fewer than {min_members} members.",
      "i" = "First: {.val {format(snaps$date[which(thin)[1L]])}} with {n[which(thin)[1L]]} members.",
      "i" = "An S&P 500 snapshot holds about 500; a thin one means a truncated or corrupt download."
    ))
  }

  out <- tibble::tibble(
    date   = rep(snaps$date, times = n),
    ticker = unlist(cells, use.names = FALSE)
  )
  out[order(out$date, out$ticker), , drop = FALSE]
}

#' Build the point-in-time universe table from membership
#'
#' Turns [hd_sp500_membership()] output into the schema documented in
#' `R/plan_universe_pit.R`. Rows exist only for members, so
#' `in_universe_pit` is `TRUE` on every row (absence of a row means "not a
#' member"). Use [hd_sp500_members_asof()] for an as-of lookup.
#'
#' `delisting_date` is the **index-exit date**: the first snapshot date at
#' which the ticker is no longer a member after the membership spell that
#' contains this row. It is `NA` while the ticker is still a member at the
#' last snapshot. It is NOT a delisting: a ticker can leave the index
#' because it was acquired, went bankrupt, or was only demoted. The source
#' carries no delisting reason or price, so `delisting_reason` and
#' `delisting_price` are always `NA`.
#'
#' @param membership Output of [hd_sp500_membership()].
#' @param index_name Index label written to `index_name`.
#' @return A tibble: `ticker`, `date`, `in_universe_pit` (logical),
#'   `index_name`, `delisting_date` (Date, index-exit date), `delisting_reason`
#'   (character, always `NA`), `delisting_price` (double, always `NA`).
#' @family sp500
#' @export
hd_sp500_pit_universe <- function(membership, index_name = "SP500") {
  .hd_sp500_check_membership(membership)
  dates <- sort(unique(membership$date))
  sid <- match(membership$date, dates)
  ord <- order(membership$ticker, sid)
  m <- membership[ord, , drop = FALSE]
  sid <- sid[ord]

  new_tick <- c(TRUE, m$ticker[-1L] != m$ticker[-nrow(m)])
  gap <- c(TRUE, diff(sid) != 1L)
  new_spell <- new_tick | gap
  spell <- cumsum(new_spell)
  last_sid <- tapply(sid, spell, max)
  exit_sid <- as.integer(last_sid[as.character(spell)]) + 1L
  exit_date <- rep(as.Date(NA), nrow(m))
  has_exit <- exit_sid <= length(dates)
  exit_date[has_exit] <- dates[exit_sid[has_exit]]

  out <- tibble::tibble(
    ticker           = m$ticker,
    date             = m$date,
    in_universe_pit  = TRUE,
    index_name       = index_name,
    delisting_date   = exit_date,
    delisting_reason = NA_character_,
    delisting_price  = NA_real_
  )
  out[order(out$date, out$ticker), , drop = FALSE]
}

#' Members of the index as of a date
#'
#' @param membership Output of [hd_sp500_membership()].
#' @param asof Date (or coercible). The last snapshot on or before it is used.
#' @return A list: `snapshot_date` (Date) and `tickers` (character).
#' @family sp500
#' @export
hd_sp500_members_asof <- function(membership, asof) {
  .hd_sp500_check_membership(membership)
  asof <- as.Date(asof)
  if (length(asof) != 1L || is.na(asof)) {
    cli::cli_abort("{.arg asof} must be one non-missing date.")
  }
  snaps <- unique(membership$date)
  ok <- snaps[snaps <= asof]
  if (length(ok) == 0L) {
    cli::cli_abort(c(
      "x" = "No membership snapshot on or before {.val {format(asof)}}.",
      "i" = "Coverage starts {.val {format(min(snaps))}}."
    ))
  }
  d <- max(ok)
  list(snapshot_date = d, tickers = membership$ticker[membership$date == d])
}

#' @keywords internal
.hd_sp500_check_membership <- function(membership) {
  if (!is.data.frame(membership) ||
      !all(c("date", "ticker") %in% names(membership)) ||
      !inherits(membership$date, "Date") || !is.character(membership$ticker)) {
    cli::cli_abort(c(
      "x" = "{.arg membership} must be a data frame with a Date {.field date} and a character {.field ticker}.",
      "i" = "Build it with {.fn hd_sp500_membership}."
    ))
  }
  if (nrow(membership) == 0L || anyNA(membership$date) || anyNA(membership$ticker)) {
    cli::cli_abort("{.arg membership} is empty or has missing dates or tickers.")
  }
  invisible(membership)
}

# ---------------------------------------------------------------------------
# Known-delisted presence check (stub step 3 of R/plan_universe_pit.R)
# ---------------------------------------------------------------------------

#' Names known to have died while in the S&P 500
#'
#' Reads `inst/extdata/sp500/known_delisted.csv`: `ticker`, `name`,
#' `member_on` (a date at which the name was an index member). MANUAL: no
#' machine-readable source for "famous failures"; each row was found in the
#' downloaded membership file, never assumed (#816).
#'
#' @return A data.frame with `ticker`, `name`, `member_on` (Date).
#' @family sp500
#' @export
hd_sp500_known_delisted <- function() {
  path <- system.file("extdata", "sp500", "known_delisted.csv", package = "historicaldata")
  if (!nzchar(path)) {
    cli::cli_abort("known_delisted.csv is missing from the installed package.")
  }
  d <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  d$member_on <- as.Date(d$member_on)
  d
}

#' Check that known failed names are PIT members but absent from a price universe
#'
#' For each row of `known`, two facts are tested:
#' 1. the ticker is a PIT index member on `member_on` (the membership source
#'    knows the name existed), and
#' 2. the ticker is absent from `universe_tickers` (the price universe has
#'    the survivorship gap this project is measuring).
#'
#' A row is `"PASS"` only when both hold. If a name is not a member on the
#' date, the check reports `"FAIL_NOT_MEMBER"`: the fixture or the source is
#' wrong, so the check cannot vouch for anything. If it is present in the
#' price universe the survivorship gap has closed (good news, but the
#' baseline moved): `"FAIL_IN_PRICE_UNIVERSE"`.
#'
#' @param membership Output of [hd_sp500_membership()].
#' @param universe_tickers Character vector of tickers present in the price
#'   universe (e.g. `equity_daily`).
#' @param known Table from [hd_sp500_known_delisted()].
#' @return A tibble with `ticker`, `name`, `member_on`, `is_pit_member`,
#'   `in_price_universe`, `status`.
#' @family sp500
#' @export
hd_sp500_presence_check <- function(membership, universe_tickers,
                                    known = hd_sp500_known_delisted()) {
  .hd_sp500_check_membership(membership)
  if (!is.character(universe_tickers) || length(universe_tickers) == 0L ||
      anyNA(universe_tickers)) {
    cli::cli_abort(c(
      "x" = "{.arg universe_tickers} must be a non-empty character vector without NA.",
      "i" = "A check that passes on an empty price universe proves nothing."
    ))
  }
  need <- c("ticker", "name", "member_on")
  if (!is.data.frame(known) || !all(need %in% names(known)) || nrow(known) == 0L ||
      !inherits(known$member_on, "Date") || anyNA(known$member_on)) {
    cli::cli_abort(c(
      "x" = "{.arg known} must be a non-empty data frame with {.field {need}} and a Date {.field member_on}."
    ))
  }
  is_member <- vapply(seq_len(nrow(known)), function(i) {
    known$ticker[i] %in% hd_sp500_members_asof(membership, known$member_on[i])$tickers
  }, logical(1))
  in_px <- known$ticker %in% universe_tickers
  tibble::tibble(
    ticker            = known$ticker,
    name              = known$name,
    member_on         = known$member_on,
    is_pit_member     = is_member,
    in_price_universe = in_px,
    status = ifelse(!is_member, "FAIL_NOT_MEMBER",
                    ifelse(in_px, "FAIL_IN_PRICE_UNIVERSE", "PASS"))
  )
}

# ---------------------------------------------------------------------------
# Coverage statistic: the survivorship gap, measured
# ---------------------------------------------------------------------------

#' Per-ticker first and last price date in `equity_daily`
#'
#' Reads the remote (or `local = TRUE` cached) `equity_daily` parquet through
#' [hd_lazy()] and returns one row per ticker, with Date columns. Input to
#' [hd_sp500_coverage()] and [hd_sp500_presence_check()].
#'
#' @param local Passed to [hd_lazy()].
#' @return A tibble: `ticker`, `first_date`, `last_date` (Date).
#' @family sp500
#' @export
hd_sp500_equity_spans <- function(local = FALSE) {
  raw <- hd_lazy("equity_daily", local = local) |>
    dplyr::summarise(first_date = min(.data$date), last_date = max(.data$date),
                     .by = "ticker") |>
    dplyr::collect()
  # The parquet stores timestamps at UTC midnight; as.Date() on that class
  # warns about nanosecond resolution, so convert from epoch seconds directly.
  to_date <- function(x) {
    if (inherits(x, "Date")) return(x)
    as.Date(floor(as.numeric(unclass(x)) / 86400), origin = "1970-01-01")
  }
  out <- tibble::tibble(
    ticker     = as.character(raw$ticker),
    first_date = to_date(raw$first_date),
    last_date  = to_date(raw$last_date)
  )
  if (nrow(out) == 0L || anyNA(out$first_date) || anyNA(out$last_date)) {
    cli::cli_abort("equity_daily returned no tickers or missing dates.")
  }
  out
}

#' Share of point-in-time S&P 500 members that have price data
#'
#' For each snapshot date, the share of that snapshot's members whose ticker
#' has price history on or near the date. "Has price data" means the
#' ticker's `[first_date, last_date]` span in the price universe, widened by
#' `tol_days` each side, contains the snapshot date. This is a span test, not
#' a row-by-row test, so an interior gap in a ticker's history still counts as
#' covered. Membership tickers are matched after `ticker_map` is applied.
#' Only snapshots inside the price universe's overall window (earliest
#' `first_date` to latest `last_date`, each widened by `tol_days`) are scored;
#' later snapshots would measure stale price data, not survivorship.
#'
#' `share_covered` is an UPPER bound on true coverage: a recycled ticker (a
#' different company reusing the symbol, #865) and an interior gap inside a
#' span both count as covered. The survivorship gap `1 - share_covered` is
#' therefore a LOWER bound.
#'
#' @param membership Output of [hd_sp500_membership()].
#' @param spans A data.frame with `ticker`, `first_date`, `last_date`
#'   (one row per ticker; Date-coercible).
#' @param tol_days Tolerance in days on both ends of a span.
#' @param ticker_map Function applied to membership tickers before matching
#'   to `spans$ticker`. The default maps `.` to `-` (membership `BRK.B`,
#'   price `BRK-B`).
#' @return A tibble: `date`, `n_members`, `n_covered`, `share_covered`.
#' @family sp500
#' @export
hd_sp500_coverage <- function(membership, spans, tol_days = 7L,
                              ticker_map = function(x) gsub(".", "-", x, fixed = TRUE)) {
  .hd_sp500_check_membership(membership)
  need <- c("ticker", "first_date", "last_date")
  if (!is.data.frame(spans) || !all(need %in% names(spans)) || nrow(spans) == 0L) {
    cli::cli_abort("{.arg spans} must be a non-empty data frame with {.field {need}}.")
  }
  if (anyDuplicated(spans$ticker) > 0L) {
    cli::cli_abort("{.arg spans} must have one row per ticker.")
  }
  first <- as.Date(spans$first_date)
  last  <- as.Date(spans$last_date)
  if (anyNA(first) || anyNA(last) || any(first > last)) {
    cli::cli_abort("{.arg spans} has missing or inverted dates.")
  }
  if (length(tol_days) != 1L || is.na(tol_days) || tol_days < 0) {
    cli::cli_abort("{.arg tol_days} must be a single non-negative number.")
  }
  if (!is.function(ticker_map)) {
    cli::cli_abort("{.arg ticker_map} must be a function.")
  }
  # Only score snapshots inside the price universe's own date window. A
  # snapshot after the last price date would read as "0 covered" because the
  # price data has not been refreshed, which measures staleness, not the
  # survivorship gap.
  w_start <- min(first) - tol_days
  w_end   <- max(last) + tol_days
  keep <- membership$date >= w_start & membership$date <= w_end
  if (!any(keep)) {
    cli::cli_abort(c(
      "x" = "No membership snapshot falls inside the price window {.val {format(min(first))}} to {.val {format(max(last))}}."
    ))
  }
  membership <- membership[keep, , drop = FALSE]
  key <- ticker_map(membership$ticker)
  idx <- match(key, spans$ticker)
  covered <- !is.na(idx) &
    first[idx] <= membership$date + tol_days &
    last[idx]  >= membership$date - tol_days
  covered[is.na(covered)] <- FALSE
  n_members <- tapply(rep(1L, nrow(membership)), membership$date, sum)
  n_covered <- tapply(as.integer(covered), membership$date, sum)
  tibble::tibble(
    date          = as.Date(names(n_members)),
    n_members     = as.integer(n_members),
    n_covered     = as.integer(n_covered),
    share_covered = as.numeric(n_covered) / as.numeric(n_members)
  )
}
