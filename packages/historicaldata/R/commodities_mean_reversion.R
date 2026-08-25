# Commodities Mean Reversion Functions (Issue #138)
#
# Counterpart to commodities_momentum.R (Issue #134).
# #134 found momentum in commodities is broken (Sharpe -0.85 baseline,
# -0.89 to -0.91 decomposed). Hypothesis: if momentum doesn't work, mean
# reversion might — commodities have backwardation/contango cycles,
# supply/demand seasonality, and supply shocks that reverse.
#
# Strategy: long-losers / short-winners (opposite of momentum).
# Signal at month t uses returns through t-1 only (look-ahead-safe).
# Execution: signal at t -> trade at t+1 close (t+1 execution discipline).
#
# Data: 37-series commodity universe (1992-2026); #717: the merged universe
#   is daily-dominated (ann_factor=252), not monthly (ann_factor=12) despite
#   this file's "monthly"/lookback_months naming throughout -- see
#   R/plan_commodities_mean_reversion.R's file header for the source
#   evidence. The `monthly_ret`/`lookback_months` naming is left un-renamed
#   per #720's note (shared with commodities_momentum.R); `monthly_ret` holds
#   a per-observation return whose actual period is daily for 96% of the
#   merged universe's rows (Yahoo futures/ETF series) and monthly for the
#   rest (FRED/IMF indexes) -- the name is a historical label, not a
#   guarantee about the row's cadence.
# #751: `lookback_months` was PREVIOUSLY a row-count window (the `lb`-th
#   previous ROW, regardless of its date) -- correctly "cosmetic-only" per
#   #720 only for a single-frequency series, but WRONG for this mixed-cadence
#   universe: `lookback_months = 3` gave a FRED monthly series a genuine
#   3-month window and a Yahoo daily series a 3-*trading-day* window, and
#   both were then ranked in the same cross-sectional sort. A 3-month return
#   has ~sqrt(21) times the dispersion of a 3-day return, so the monthly
#   names occupied the extreme ranks near-mechanically whenever they printed.
#   Verified still live through 2026-03-01 (13 IMF series still print
#   monthly), not just a pre-2000 artifact. hd_commodity_mr_signal() now
#   uses a CALENDAR window (elapsed days), so `lookback_months = 3` means the
#   same economic horizon for every series regardless of how often it prints
#   -- see that function's roxygen for the window/floor design.
# Universe re-uses commodities_returns from plan_commodities_momentum.R.


#' Average Gregorian calendar month length, in days (365.2425 / 12)
#'
#' Used to convert \code{lookback_months} into a fixed number of CALENDAR
#' DAYS for \code{\link{hd_commodity_mr_signal}}'s sliding window, rather
#' than using \code{lubridate::months()} period arithmetic directly.
#' \code{months()} subtraction produces \code{NA} whenever the anchor date
#' has no equivalent day N months prior (e.g. day 31 minus 3 months, when
#' the target month has fewer than 31 days) -- see
#' \code{strategy_mom_prepeak.R}'s \code{lubridate::`%m-%`} workaround for
#' the same underlying gotcha. A fixed-day window sidesteps this entirely:
#' \code{date - lubridate::days(n)} is always defined. 30.436875 (=
#' 365.2425 / 12) is the standard Gregorian mean month length; using it
#' rather than a round number (30) keeps a 12-month window close to 365
#' days rather than drifting short by ~4 days a year.
#'
#' @noRd
.HD_MR_MEAN_DAYS_PER_MONTH <- 365.2425 / 12

#' Minimum window-fill fraction required for a calendar window to be treated
#' as complete
#'
#' A calendar window can span the right number of days while containing
#' almost no observations, if it happens to cross a data gap (a stale/thin
#' patch of a series, or -- for this mixed-cadence universe -- a series that
#' is far sparser than a typical window expects). \code{slider}'s own
#' \code{.complete = TRUE} only checks that the window's start boundary
#' falls inside the series' observed date RANGE; it does not check how many
#' observations actually fall inside the window.
#'
#' This fraction is applied against \code{window_days / median_gap_days} --
#' the observation count a window of this length would contain if the
#' series kept up its own typical (median) spacing. 0.5 tolerates normal
#' weekend/holiday sparsity in a daily series and the +/-1 rounding a
#' ~30.44-day-average month produces against real (non-uniform) monthly
#' print dates, while still rejecting a window degraded by an outage/gap
#' materially larger than the series' own norm. It is deliberately not
#' closer to 1: a strict 90-100% fill would reject completely ordinary daily
#' windows that happen to contain an extra holiday cluster.
#'
#' @noRd
.HD_MR_MIN_OBS_FRACTION <- 0.5

#' Absolute floor on observations inside a calendar window, regardless of
#' cadence
#'
#' A "cumulative return over a lookback window" is a product over multiple
#' observations; a window containing only the observation at \code{t} itself
#' is not a lookback return at all, it is that single observation's own
#' return relabelled as a longer-horizon one. 2 is the smallest count for
#' which the product spans more than one observation. This floor matters
#' when a series' own cadence cannot be estimated (fewer than 2 dated
#' observations) or is so sparse that \code{.HD_MR_MIN_OBS_FRACTION} of the
#' cadence-implied count would round below it.
#'
#' @noRd
.HD_MR_MIN_OBS_FLOOR <- 2L

#' Commodity Mean Reversion Signal
#'
#' Compute a mean-reversion signal for a commodity universe over a fixed
#' CALENDAR window (elapsed days), not a fixed number of rows.
#' The signal is the *negative* of the lookback-period return: commodities
#' that have fallen the most receive the highest (most positive) signal,
#' while those that have risen the most receive the lowest (most negative)
#' signal.
#'
#' Look-ahead safety: the signal at date \code{t} is constructed from
#' cumulative returns over the \code{lookback_months} calendar months
#' immediately preceding \code{t}, ending at \code{t - 1}'s observation. The
#' one-period lag is enforced via \code{dplyr::lag(cumret)} before the
#' negation, so no return at or after date \code{t} ever enters signal
#' formation.
#'
#' @param returns_tbl Tibble with columns \code{date} (Date), \code{series_id}
#'   (character), and \code{monthly_ret} (numeric per-observation return;
#'   despite the name, this is a DAILY return for series that print daily --
#'   see the file header note). Produced by \code{calculate_commodity_returns()}.
#' @param lookback_months Integer. Number of CALENDAR months the
#'   mean-reversion window spans (default 3), applied uniformly regardless
#'   of how often the underlying series is actually observed. Typical
#'   values: 1, 3, 6.
#'
#' @return Tibble with columns:
#'   \describe{
#'     \item{date}{Observation date.}
#'     \item{series_id}{Commodity identifier.}
#'     \item{mr_signal}{Mean-reversion signal = negative of cumulative
#'       return over the prior \code{lookback_months} calendar months.
#'       Higher values (bigger recent losers) rank first for the long leg.}
#'   }
#'   Rows with \code{NA} signals (insufficient history, or too few actual
#'   observations inside an otherwise-complete window) are dropped.
#'
#' @details
#' \strong{Window (#751):} the cumulative return is computed over a window
#' spanning \code{round(lookback_months * 365.2425 / 12)} CALENDAR DAYS
#' ending at \code{t} (inclusive), via \code{slider::slide_index_dbl()} keyed
#' on \code{date} rather than row position. This means
#' \code{lookback_months = 3} spans the same ~91-day economic horizon for
#' every series in the universe, whether it is observed daily (~63
#' observations in that window) or monthly (~3 observations). Previously the
#' window was \code{lookback_months} PREVIOUS ROWS regardless of their
#' dates, which silently gave a daily series a 3-*trading-day* window under
#' the same argument that gave a monthly series a genuine 3-month window
#' (#751) -- see the file header for the full defect history.
#'
#' \strong{Completeness (fail-loud-not-null.md):} a window counts as complete
#' only if BOTH (a) its start boundary falls within the series' own observed
#' date range (\code{slider}'s \code{.complete = TRUE}), AND (b) it actually
#' contains at least \code{max(.HD_MR_MIN_OBS_FLOOR,
#' ceiling(.HD_MR_MIN_OBS_FRACTION * expected_obs))} observations, where
#' \code{expected_obs} is \code{window_days / median_gap_days} for that
#' series' own median inter-observation gap. Condition (a) alone would
#' accept a window that nominally spans the right number of days but
#' crosses a data outage and contains almost no real observations -- see
#' \code{.HD_MR_MIN_OBS_FRACTION}'s roxygen for why a per-series relative
#' floor is used rather than one fixed count (a fixed count could not serve
#' both a ~63-observation daily window and a ~3-observation monthly one).
#' Windows failing either condition produce \code{NA}, which propagates
#' through the one-period lag and causes that row to be dropped from the
#' returned tibble, exactly as an insufficient-history \code{NA} always has.
#'
#' @family commodities_mr
#' @export
hd_commodity_mr_signal <- function(returns_tbl, lookback_months = 3L) {
  if (!is.data.frame(returns_tbl)) {
    cli::cli_abort(c(
      "x" = "{.arg returns_tbl} must be a data frame, not {.cls {class(returns_tbl)}}."
    ))
  }
  required_cols <- c("date", "series_id", "monthly_ret")
  missing_cols <- setdiff(required_cols, names(returns_tbl))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "{.arg returns_tbl} is missing required columns: {.field {missing_cols}}."
    ))
  }
  if (!is.numeric(lookback_months) || length(lookback_months) != 1L ||
      is.na(lookback_months) || lookback_months < 1L) {
    cli::cli_abort(c(
      "x" = "{.arg lookback_months} must be a positive integer, got {lookback_months}."
    ))
  }
  lookback_months <- as.integer(lookback_months)

  # #751: fixed CALENDAR days, not a row count and not lubridate::months()
  # period arithmetic -- see .HD_MR_MEAN_DAYS_PER_MONTH's roxygen for why.
  window_days <- .HD_MR_MEAN_DAYS_PER_MONTH * lookback_months

  returns_tbl |>
    dplyr::arrange(series_id, date) |>
    dplyr::group_by(series_id) |>
    dplyr::mutate(
      # This series' own typical observation cadence (median calendar-day
      # gap between its consecutive dates). Mirrors the "median gap defines
      # periodicity" logic in .assert_cmr_ann_factor()
      # (R/plan_commodities_mean_reversion.R), applied per-series here
      # rather than to the whole merged universe. NA when fewer than 2
      # dated observations exist for this series.
      .median_gap_days = {
        d <- sort(unique(date))
        if (length(d) < 2L) NA_real_ else stats::median(as.numeric(diff(d)))
      },
      # Observation count a `window_days`-wide window would hold if this
      # series kept up its own median cadence. 0 (not NA) when the cadence
      # is unknown/degenerate, so the fraction-of-expected floor collapses
      # to .HD_MR_MIN_OBS_FLOOR below rather than propagating NA into the
      # comparison.
      .expected_obs = dplyr::if_else(
        is.na(.median_gap_days) | .median_gap_days <= 0,
        0,
        window_days / .median_gap_days
      ),
      # Minimum observations required inside the window for it to count as
      # complete -- see .HD_MR_MIN_OBS_FRACTION / .HD_MR_MIN_OBS_FLOOR.
      .min_obs = pmax(
        .HD_MR_MIN_OBS_FLOOR,
        ceiling(.HD_MR_MIN_OBS_FRACTION * .expected_obs)
      ),
      # Cumulative return over the CALENDAR window ending at t (inclusive).
      # Keyed on `date` (slide_index_dbl), not row position (slide_dbl) --
      # this is the #751 fix. .complete = TRUE requires the window's start
      # boundary to fall within this series' own observed date range.
      cumret_raw = slider::slide_index_dbl(
        monthly_ret, date,
        .f = function(r) prod(1 + r) - 1,
        .before = lubridate::days(round(window_days)),
        .after  = 0L,
        .complete = TRUE
      ),
      # How many observations actually fell inside that same window --
      # .complete = TRUE alone cannot see a window that spans the right
      # number of days but crosses a data gap and contains almost none.
      .n_obs_window = slider::slide_index_dbl(
        monthly_ret, date,
        .f = function(r) as.double(length(r)),
        .before = lubridate::days(round(window_days)),
        .after  = 0L,
        .complete = TRUE
      ),
      # Enforce the fill-fraction floor: too few actual observations ->
      # treat the window as incomplete (NA), same as slider's own guard.
      cumret_raw = dplyr::if_else(.n_obs_window < .min_obs, NA_real_, cumret_raw),
      # Lag by 1: cumret at position t becomes the lookback return through t-1.
      # Signal = negation so recent losers have high (positive) signal.
      mr_signal = -dplyr::lag(cumret_raw, n = 1L)
    ) |>
    dplyr::ungroup() |>
    dplyr::select(date, series_id, mr_signal) |>
    dplyr::filter(!is.na(mr_signal))
}


#' Default fraction of the ranked cross-section held on each leg (#751 items C/D)
#'
#' Long-standing cross-sectional-sort convention is a FIXED FRACTION
#' (quantile breakpoint) of the ranked universe, not a fixed headcount --
#' Fama & French (1993) rank the whole equity universe into
#' deciles/quintiles precisely because the universe's size varies by orders
#' of magnitude over the sample. \code{hd_commodity_mr_portfolio()}
#' previously held a fixed \code{n_long = n_short = 10}, which (#751) was
#' infeasible against our own tradeable universe for its first six years
#' (6-17 tradeable names 2000-2005, so 20 slots could not be filled from
#' tradeable names alone) and held ~10/24 = ~42\% of the universe PER LEG
#' (roughly 83\% total) by 2015-2026 (24 tradeable names) -- the same
#' parameter meaning two structurally different strategies at the two ends
#' of the sample.
#'
#' Two commodity-specific precedents exist at comparable breadth to ours (24
#' tradeable names as of 2015-2026, per #751):
#' \itemize{
#'   \item Asness, Moskowitz & Pedersen (2013, "Value and Momentum
#'     Everywhere", J. Finance) sort 27 commodity futures into TERCILES
#'     (1/3 per leg).
#'   \item Miffre & Rallis (2007, "Momentum Strategies in Commodity Futures
#'     Markets", J. Banking & Finance) sort 31 commodity futures into
#'     QUINTILES (1/5 per leg).
#' }
#' TERCILES is chosen as the default here: AMP's 27-future universe is
#' within 3 names of our own 24-name tradeable universe -- the closer
#' structural match of the two -- and a tercile (8 of 24 names per leg,
#' currently) keeps meaningfully more cross-sectional discrimination than
#' the old fixed count of 10 (~42\% per leg) without over-thinning the legs
#' the way a quintile would in years where our tradeable universe is
#' smaller (e.g. 2006-2007's 20 tradeable names -> a quintile gives 4 per
#' leg, close to the \code{.HD_CMR_MIN_LEG_NAMES} floor below; a tercile
#' gives 6). Quintiles remain a reasonable, better-precedented-by-breadth
#' alternative (Miffre-Rallis' 31 futures is the larger universe) and can be
#' requested via \code{frac = 1/5}.
#'
#' @noRd
.HD_CMR_DEFAULT_FRAC <- 1 / 3

#' Minimum number of names required on ONE side (long or short) for a
#' cross-sectional quantile split to be treated as meaningful
#'
#' No formal minimum-breadth threshold for a commodity cross-sectional sort
#' was found in the literature consulted for #751 item C -- Fama-French,
#' Asness-Moskowitz-Pedersen, and Miffre-Rallis all state their quantile
#' FRACTION but none states a floor on N before applying it. This constant
#' is therefore a HOUSE RULE, not an adopted standard, documented as such
#' rather than presented as literature-derived. It is framed the same way
#' \code{.HD_MR_MIN_OBS_FLOOR} above is framed for the signal window: a leg
#' of 1 name is not a diversified basket, it is that single name's own
#' return relabelled as a "leg return" -- 2 is the smallest count for which
#' a leg is actually more than one bet. Combined with \code{frac} this
#' implies a minimum TOTAL ranked-name requirement of
#' \code{ceiling(.HD_CMR_MIN_LEG_NAMES / frac)} (6 names, at the default
#' tercile \code{frac}) before either leg is populated on a given date;
#' below that, the date holds NO position (both legs empty, contributing
#' \code{gross_ret = 0} for that date) rather than forcing a 1-name leg or
#' risking an overlapping split -- see
#' \code{\link{hd_commodity_mr_portfolio}}'s implementation. This is
#' equivalent to capping the MAXIMUM held fraction implicitly (never more
#' than \code{2 * frac} of the ranked universe is held, and never less than
#' zero when breadth is too thin), which the fraction-vs-headcount
#' literature above does support, even though it does not state a breadth
#' floor as such.
#'
#' @noRd
.HD_CMR_MIN_LEG_NAMES <- 2L

#' Commodity Mean Reversion Portfolio
#'
#' Convert a mean-reversion signal tibble into monthly long/short portfolio
#' weights with t+1 execution.
#'
#' Execution discipline: the signal from month \code{t} (formed from returns
#' through \code{t-1}) drives trades that are executed at month \code{t+1}
#' closing prices.  This is enforced by joining the signal at date \code{t}
#' to the return realised at date \code{t+1} via \code{dplyr::lead()}.
#'
#' \strong{Fixed fraction, not fixed headcount (#751 items C/D):} each leg
#' holds \code{floor(n_avail * frac)} names, where \code{n_avail} is the
#' number of ranked names available on that date -- NOT a fixed count. See
#' \code{.HD_CMR_DEFAULT_FRAC}'s roxygen for the tercile-vs-quintile
#' citation and reasoning, and \code{.HD_CMR_MIN_LEG_NAMES}'s roxygen
#' for the minimum-breadth floor below which a date holds no position.
#' \code{floor()} together with \code{frac < 0.5} (enforced by input
#' validation) guarantees \code{2 * n_leg <= 2 * frac * n_avail < n_avail},
#' so the long and short legs can never overlap by construction; this is
#' also verified explicitly at runtime (fail-loud-not-null.md) rather than
#' trusted silently.
#'
#' @param signal_tbl Tibble returned by \code{\link{hd_commodity_mr_signal}},
#'   with columns \code{date}, \code{series_id}, \code{mr_signal}.
#' @param returns_tbl Tibble with columns \code{date}, \code{series_id},
#'   \code{monthly_ret}.  Must overlap in date range with \code{signal_tbl}.
#' @param frac Numeric fraction in \verb{(0, 0.5)}. Share of the ranked
#'   cross-section held on EACH leg (long and short) -- \code{1/3} =
#'   terciles (default), \code{1/5} = quintiles. Replaces the previous fixed
#'   \code{n_long}/\code{n_short} headcount parameters (#751 items C/D): one
#'   sizing mechanism, not two.
#' @param cost_bps Numeric. One-way transaction cost in basis points
#'   (default 20 = 0.2\%).  The same 0.2\% used in commodity momentum (#134).
#'
#' @return Tibble with one row per date present in the signal/return join
#'   and columns:
#'   \describe{
#'     \item{date}{Execution date (t+1).}
#'     \item{gross_ret}{Gross portfolio return for the date.}
#'     \item{turnover}{One-way turnover fraction.}
#'     \item{cost}{Transaction cost deducted (= turnover * cost_bps/10000).}
#'     \item{net_ret}{Net return after transaction costs.}
#'     \item{n_long}{Number of long positions actually held.}
#'     \item{n_short}{Number of short positions actually held.}
#'     \item{n_avail}{Number of ranked names available that date (breadth
#'       diagnostic, #751 item C).}
#'     \item{held_frac}{\code{(n_long + n_short) / n_avail}: the fraction of
#'       that date's ranked universe actually held (breadth diagnostic,
#'       #751 item C). 0 when \code{n_avail} is below the minimum-breadth
#'       floor.}
#'   }
#'   Dates below \code{.HD_CMR_MIN_LEG_NAMES}'s minimum-breadth floor
#'   hold no position at all: \code{n_long = n_short = 0},
#'   \code{gross_ret = 0}. Such dates are still returned as rows (not
#'   dropped) so the return series stays date-complete for downstream
#'   periodicity checks (#738).
#'
#' @family commodities_mr
#' @export
hd_commodity_mr_portfolio <- function(signal_tbl,
                                       returns_tbl,
                                       frac = .HD_CMR_DEFAULT_FRAC,
                                       cost_bps = 20) {
  if (!is.data.frame(signal_tbl)) {
    cli::cli_abort(c("x" = "{.arg signal_tbl} must be a data frame."))
  }
  if (!is.data.frame(returns_tbl)) {
    cli::cli_abort(c("x" = "{.arg returns_tbl} must be a data frame."))
  }
  if (!is.numeric(frac) || length(frac) != 1L || is.na(frac) ||
      frac <= 0 || frac >= 0.5) {
    cli::cli_abort(c(
      "x" = "{.arg frac} must be a single fraction in (0, 0.5), got {frac}.",
      "i" = paste0(
        "{.arg frac} is the share of the ranked cross-section held on EACH ",
        "leg (long and short) -- 1/3 = terciles (default), 1/5 = quintiles."
      ),
      "i" = paste0(
        "A value >= 0.5 would let the two legs overlap, or consume the ",
        "entire ranked universe leaving nothing held out; see #751 items C/D."
      )
    ))
  }

  cost_per_unit <- cost_bps / 10000

  # t+1 execution: for each commodity build (signal_date -> next_ret) pairs.
  # signal at t -> realised return at t+1 (lead by 1 within each series).
  ret_with_lead <- returns_tbl |>
    dplyr::arrange(series_id, date) |>
    dplyr::group_by(series_id) |>
    dplyr::mutate(next_ret = dplyr::lead(monthly_ret, n = 1L)) |>
    dplyr::ungroup() |>
    dplyr::filter(!is.na(next_ret)) |>
    dplyr::select(series_id, signal_date = date, next_ret)

  # Join signal (at t) to execution return (at t+1).
  combined <- signal_tbl |>
    dplyr::inner_join(ret_with_lead, by = c("date" = "signal_date", "series_id"))

  # Per-date breadth diagnostic (#751 item C), computed BEFORE the
  # minimum-breadth floor is applied, so it is reported even for dates that
  # end up holding no position at all.
  breadth_by_date <- combined |>
    dplyr::count(date, name = "n_avail")

  min_total_names <- ceiling(.HD_CMR_MIN_LEG_NAMES / frac)

  # Rank within each signal date; assign long/short weights by FRACTION of
  # that date's own ranked breadth, not a fixed headcount (#751 items C/D).
  ranked <- combined |>
    dplyr::group_by(date) |>
    dplyr::mutate(
      rk      = dplyr::row_number(dplyr::desc(mr_signal)),  # rank 1 = highest signal = biggest loser
      n_avail = dplyr::n(),
      # Dates below the minimum-breadth floor hold no position (n_leg = 0)
      # rather than a house-rule-forced 1-name leg or an overlapping split
      # -- see .HD_CMR_MIN_LEG_NAMES's roxygen.
      n_leg   = dplyr::if_else(
        n_avail >= min_total_names,
        as.integer(floor(n_avail * frac)),
        0L
      )
    ) |>
    dplyr::filter(n_leg > 0L, rk <= n_leg | rk > (n_avail - n_leg)) |>
    dplyr::mutate(
      leg    = dplyr::if_else(rk <= n_leg, "long", "short"),
      weight = dplyr::if_else(leg == "long", 1 / n_leg, -1 / n_leg)
    ) |>
    dplyr::ungroup()

  # fail-loud-not-null.md: verify the no-overlap invariant explicitly rather
  # than trusting the floor()/frac<0.5 arithmetic silently -- a future
  # refactor that breaks it must abort loudly, not produce a
  # plausible-looking but wrong portfolio.
  overlap_dates <- ranked |>
    dplyr::distinct(date, n_avail, n_leg) |>
    dplyr::filter(2L * n_leg > n_avail)
  if (nrow(overlap_dates) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        "CMR portfolio construction would OVERLAP the long/short legs on ",
        "{nrow(overlap_dates)} date{?s}."
      ),
      "i" = paste0(
        "2 * n_leg > n_avail should be impossible once {.arg frac} < 0.5 is ",
        "enforced at input validation -- investigate the rank/n_leg ",
        "arithmetic before trusting this portfolio."
      ),
      "i" = "First offending date: {format(overlap_dates$date[1])} (n_avail={overlap_dates$n_avail[1]}, n_leg={overlap_dates$n_leg[1]})."
    ))
  }

  # Monthly gross returns and position counts, for dates that hold a
  # position at all.
  monthly_traded <- ranked |>
    dplyr::group_by(date) |>
    dplyr::summarise(
      gross_ret   = sum(weight * next_ret, na.rm = TRUE),
      n_long_pos  = sum(leg == "long",  na.rm = TRUE),
      n_short_pos = sum(leg == "short", na.rm = TRUE),
      .groups = "drop"
    )

  # Every date the signal/return join produced (breadth_by_date) gets a row
  # in the output, INCLUDING dates below the minimum-breadth floor -- those
  # hold gross_ret = 0 / n_long = n_short = 0 (flat, no position), matching
  # the pre-existing "zero valid signals -> gross_ret = 0" convention rather
  # than silently vanishing from the return series (fail-loud-not-null.md:
  # a dropped date is a dropped observation, not a neutral one).
  monthly <- breadth_by_date |>
    dplyr::left_join(monthly_traded, by = "date") |>
    dplyr::mutate(
      gross_ret   = dplyr::if_else(is.na(gross_ret), 0, gross_ret),
      n_long_pos  = dplyr::if_else(is.na(n_long_pos), 0L, n_long_pos),
      n_short_pos = dplyr::if_else(is.na(n_short_pos), 0L, n_short_pos)
    )

  # Turnover: sum of absolute weight changes relative to prior traded date.
  # Use series_id-level lag of weight within the ranked (traded-only) dataset.
  weight_tbl <- ranked |>
    dplyr::select(date, series_id, weight) |>
    dplyr::arrange(series_id, date) |>
    dplyr::group_by(series_id) |>
    dplyr::mutate(prev_weight = dplyr::lag(weight, default = 0)) |>
    dplyr::ungroup()

  turnover_tbl <- weight_tbl |>
    dplyr::group_by(date) |>
    dplyr::summarise(
      turnover = sum(abs(weight - prev_weight), na.rm = TRUE) / 2,
      .groups = "drop"
    )

  monthly |>
    dplyr::left_join(turnover_tbl, by = "date") |>
    dplyr::mutate(
      turnover  = dplyr::if_else(is.na(turnover), 0, turnover),
      cost      = turnover * cost_per_unit,
      net_ret   = gross_ret - cost,
      n_long    = n_long_pos,
      n_short   = n_short_pos,
      held_frac = dplyr::if_else(n_avail > 0L, (n_long + n_short) / n_avail, 0)
    ) |>
    dplyr::select(date, gross_ret, turnover, cost, net_ret, n_long, n_short, n_avail, held_frac)
}
