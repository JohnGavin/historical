# Funding-clamp check for Hyperliquid perp funding (JohnGavin/historical#1072).
#
# Claim under test (outside comment on #1072): the settled funding rate is
# "interval-censored": pinned to a base value while the premium sits inside a
# clamp band, tracking the premium only outside it, with a band that changed
# during 2023, so that "83.5% of BTC premium variance never reaches it".
#
# Pure functions: each takes a data frame shaped like the output of
# scripts/fetch_hyperliquid.R (`perp_funding.parquet`) with columns
# dex, coin, time (POSIXct), premium, interval_hours, rate_per_hour.
# No file access here, so tests need no file. scripts/check_funding_clamp.R
# reads the parquet, calls these, and writes audits/funding_clamp_<date>.md.
#
# Every threshold is defined ONCE below and passed by name; nothing in the
# functions repeats a literal.

# ── Constants (one home each) ───────────────────────────────────────
FC_BASE_RATE <- 1.25e-05          # base hourly rate: 0.01%/h interest / 8
FC_BAND_LO <- -0.0004             # lower premium edge of the clamp band
FC_BAND_HI <- 0.0006              # upper premium edge of the clamp band
FC_BAND_FROM <- as.Date("2024-01-01")  # first date the band is held fixed
FC_RATE_DIGITS <- 10L             # rate_per_hour is rounded to this many dp
FC_MIN_ROWS <- 500L               # minimum rows for a market to be summarised
FC_BTC_DEX <- ""                  # main perp exchange
FC_BTC_COIN <- "BTC"
FC_XYZ_DEX <- "xyz"               # builder dex (stock perps)
FC_INTERVAL_HOURS <- 1            # the hourly funding era

# ── Helpers ─────────────────────────────────────────────────────────
# TRUE where rate equals `base` after rounding to `digits` dp. The comparison
# uses a tolerance of half a unit in the last place, not `==` on doubles.
fc_is_pinned <- function(rate, base = FC_BASE_RATE, digits = FC_RATE_DIGITS) {
  abs(round(rate, digits) - round(base, digits)) < 0.5 * 10^(-digits)
}

# TRUE where premium lies in the closed interval [lo, hi].
fc_in_band <- function(premium, lo = FC_BAND_LO, hi = FC_BAND_HI) {
  premium >= lo & premium <= hi
}

# Calendar quarter label ("2023Q2") of a POSIXct, in UTC.
fc_quarter <- function(time) {
  utc <- as.POSIXlt(time, tz = "UTC")
  paste0(utc$year + 1900L, "Q", utc$mon %/% 3L + 1L)
}

fc_year <- function(time) as.POSIXlt(time, tz = "UTC")$year + 1900L

.fc_check_cols <- function(df, cols) {
  miss <- setdiff(cols, names(df))
  if (length(miss) > 0L) {
    cli::cli_abort(c(
      "x" = "Input is missing column{?s} {.field {miss}}.",
      "i" = "Expected the output of scripts/fetch_hyperliquid.R (perp_funding.parquet)."
    ))
  }
  invisible(df)
}

# Rows of one market class with a usable premium and rate.
fc_select <- function(df, dex, coin = NULL, interval_hours = FC_INTERVAL_HOURS) {
  .fc_check_cols(df, c("dex", "coin", "time", "premium", "interval_hours", "rate_per_hour"))
  out <- dplyr::filter(
    df,
    .data$dex == .env$dex,
    .data$interval_hours == .env$interval_hours,
    !is.na(.data$premium),
    !is.na(.data$rate_per_hour)
  )
  if (!is.null(coin)) out <- dplyr::filter(out, .data$coin == .env$coin)
  out
}

# Share of a rate that tracks premium: 1 - r^2, as a percent. NA if undefined.
.fc_pct_unexplained <- function(premium, rate) {
  if (length(premium) < 3L || stats::sd(premium) == 0 || stats::sd(rate) == 0) {
    return(NA_real_)
  }
  100 * (1 - stats::cor(premium, rate)^2)
}

# Percent of the premium sum of squares (about the set's own mean) that sits in
# the pinned rows.
.fc_pct_ss_pinned <- function(premium, pinned) {
  ss <- (premium - mean(premium))^2
  if (sum(ss) == 0) return(NA_real_)
  100 * sum(ss[pinned]) / sum(ss)
}

# ── BTC summary ─────────────────────────────────────────────────────
# One row per period: "all" rows and, if `year` is given, that calendar year.
# Columns: period, n, pct_pinned, pct_unexplained (100 * (1 - r^2) of
# rate vs premium), pct_ss_pinned (pinned rows' share of premium SS).
fc_btc_summary <- function(df,
                           base_rate = FC_BASE_RATE,
                           digits = FC_RATE_DIGITS,
                           year = 2023L,
                           dex = FC_BTC_DEX,
                           coin = FC_BTC_COIN,
                           interval_hours = FC_INTERVAL_HOURS) {
  h <- fc_select(df, dex = dex, coin = coin, interval_hours = interval_hours)
  one <- function(d, label) {
    pinned <- fc_is_pinned(d$rate_per_hour, base_rate, digits)
    dplyr::tibble(
      period = label,
      n = nrow(d),
      pct_pinned = if (nrow(d) > 0L) 100 * mean(pinned) else NA_real_,
      pct_unexplained = .fc_pct_unexplained(d$premium, d$rate_per_hour),
      pct_ss_pinned = if (nrow(d) > 0L) .fc_pct_ss_pinned(d$premium, pinned) else NA_real_
    )
  }
  out <- one(h, "all")
  if (!is.null(year)) {
    out <- dplyr::bind_rows(out, one(h[fc_year(h$time) == year, , drop = FALSE], as.character(year)))
  }
  out
}

# ── BTC band by quarter ─────────────────────────────────────────────
# Per quarter: rows, in-band-not-pinned, pinned-out-of-band, and the premium
# range of the pinned rows. From FC_BAND_FROM the claim predicts both mismatch
# counts are 0; earlier quarters show where the band was different.
fc_band_by_quarter <- function(df,
                               base_rate = FC_BASE_RATE,
                               band_lo = FC_BAND_LO,
                               band_hi = FC_BAND_HI,
                               digits = FC_RATE_DIGITS,
                               dex = FC_BTC_DEX,
                               coin = FC_BTC_COIN,
                               interval_hours = FC_INTERVAL_HOURS) {
  if (band_lo >= band_hi) {
    cli::cli_abort(c(
      "x" = "Band edges are inverted: {.arg band_lo} = {band_lo} >= {.arg band_hi} = {band_hi}.",
      "i" = "Pass band_lo < band_hi."
    ))
  }
  h <- fc_select(df, dex = dex, coin = coin, interval_hours = interval_hours)
  h$pinned <- fc_is_pinned(h$rate_per_hour, base_rate, digits)
  h$in_band <- fc_in_band(h$premium, band_lo, band_hi)
  h$quarter <- fc_quarter(h$time)
  pin_range <- function(x, f) if (length(x) > 0L) f(x) else NA_real_
  h |>
    dplyr::group_by(.data$quarter) |>
    dplyr::summarise(
      n = dplyr::n(),
      inband_not_pinned = sum(.data$in_band & !.data$pinned),
      pinned_out_band = sum(.data$pinned & !.data$in_band),
      pmin_pinned = pin_range(.data$premium[.data$pinned], min),
      pmax_pinned = pin_range(.data$premium[.data$pinned], max),
      .groups = "drop"
    ) |>
    dplyr::arrange(.data$quarter)
}

# ── Mode (deterministic: smallest value wins a tie) ─────────────────
.fc_mode <- function(x) {
  tab <- table(x)
  as.numeric(names(tab)[which.max(tab)])  # names sorted ascending: first max = smallest
}

# ── xyz (stock perp) summary ────────────────────────────────────────
# Per market the "base" is its modal rounded rate. Returns one row: number of
# markets with >= min_rows rows, median pinned share (%), median R^2, number of
# distinct modal bases and their min / max.
fc_xyz_summary <- function(df,
                           min_rows = FC_MIN_ROWS,
                           digits = FC_RATE_DIGITS,
                           dex = FC_XYZ_DEX,
                           interval_hours = FC_INTERVAL_HOURS) {
  x <- fc_select(df, dex = dex, interval_hours = interval_hours)
  x$rate_r <- round(x$rate_per_hour, digits)
  per <- x |>
    dplyr::group_by(.data$coin) |>
    dplyr::filter(dplyr::n() >= min_rows) |>
    dplyr::summarise(
      n = dplyr::n(),
      base = .fc_mode(.data$rate_r),
      pct_pinned = 100 * mean(abs(.data$rate_r - .fc_mode(.data$rate_r)) < 0.5 * 10^(-digits)),
      r2 = if (stats::sd(.data$premium) == 0 || stats::sd(.data$rate_per_hour) == 0) {
        NA_real_
      } else {
        stats::cor(.data$premium, .data$rate_per_hour)^2
      },
      .groups = "drop"
    )
  dplyr::tibble(
    markets = nrow(per),
    med_pct_pinned = if (nrow(per) > 0L) stats::median(per$pct_pinned) else NA_real_,
    med_r2 = if (nrow(per) > 0L) stats::median(per$r2, na.rm = TRUE) else NA_real_,
    n_distinct_base = length(unique(per$base)),
    min_base = if (nrow(per) > 0L) min(per$base) else NA_real_,
    max_base = if (nrow(per) > 0L) max(per$base) else NA_real_
  )
}

# ── Markdown rendering ──────────────────────────────────────────────
# Minimal pipe table from a data frame. Whole numbers (counts) print exactly;
# other numbers keep 4 significant digits.
fc_md_table <- function(df) {
  fmt <- function(x) {
    if (!is.numeric(x)) return(as.character(x))
    whole <- all(is.na(x) | x == round(x))
    shown <- if (whole) x else signif(x, 4)
    ifelse(is.na(x), "NA", format(shown, scientific = FALSE, trim = TRUE, drop0trailing = TRUE))
  }
  cells <- lapply(df, fmt)
  header <- paste0("| ", paste(names(df), collapse = " | "), " |")
  rule <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  rows <- vapply(seq_len(nrow(df)), function(i) {
    paste0("| ", paste(vapply(cells, function(col) col[i], character(1)), collapse = " | "), " |")
  }, character(1))
  c(header, rule, rows)
}
