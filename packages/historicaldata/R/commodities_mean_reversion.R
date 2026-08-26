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


#' Minimum number of names required on ONE side (long or short) for a
#' cross-sectional split to be treated as meaningful
#'
#' No formal minimum-breadth threshold for a commodity cross-sectional sort
#' was found in the literature consulted for #751 items C/D -- Fama-French,
#' Asness-Moskowitz-Pedersen, and Miffre-Rallis all state their quantile
#' FRACTION but none states a floor on N before applying it. This constant
#' is therefore a HOUSE RULE, not an adopted standard, documented as such
#' rather than presented as literature-derived. It is framed the same way
#' \code{.HD_MR_MIN_OBS_FLOOR} above is framed for the signal window: a leg
#' of 1 name is not a diversified basket, it is that single name's own
#' return relabelled as a "leg return" -- 2 is the smallest count for which
#' a leg is actually more than one bet.
#'
#' Originally combined with a \code{frac} parameter (item C's tercile
#' construction) to derive a minimum TOTAL ranked-name requirement of
#' \code{ceiling(.HD_CMR_MIN_LEG_NAMES / frac)}. Item D's rank-weighting
#' scheme (\code{\link{hd_commodity_mr_portfolio}}) has no \code{frac}
#' parameter to combine it with, so \code{\link{.HD_CMR_MIN_BREADTH_RANK}}
#' below derives the analogous floor directly from this constant instead.
#'
#' @noRd
.HD_CMR_MIN_LEG_NAMES <- 2L

#' Minimum number of ranked names required for rank-weighting to be
#' meaningful (#751 item D)
#'
#' Under \code{\link{hd_commodity_mr_portfolio}}'s rank-weighting scheme,
#' names are ranked 1..\code{n_avail} by \code{mr_signal} (ties averaged)
#' and weighted by their distance from the mean rank
#' \code{(n_avail + 1) / 2}. For \code{n_avail} names with no ties, exactly
#' \code{floor(n_avail / 2)} receive a strictly positive (long) weight and
#' \code{floor(n_avail / 2)} receive a strictly negative (short) weight --
#' the remaining name, only possible when \code{n_avail} is odd, sits
#' exactly at the mean rank and receives zero weight. \code{floor(n_avail /
#' 2) >= .HD_CMR_MIN_LEG_NAMES} holds for every \code{n_avail >= 2 *
#' .HD_CMR_MIN_LEG_NAMES} and fails below it, so \code{2 *
#' .HD_CMR_MIN_LEG_NAMES} is the exact rank-weighting analogue of the
#' tercile construction's old \code{ceiling(.HD_CMR_MIN_LEG_NAMES / frac)}
#' floor: "at least \code{.HD_CMR_MIN_LEG_NAMES} names get a meaningful bet
#' on each side" is the same guarantee both floors give, derived the way
#' that best fits each scheme's own parameterisation. Like
#' \code{.HD_CMR_MIN_LEG_NAMES} itself, this is a HOUSE RULE with no
#' literature precedent -- see that constant's roxygen.
#'
#' Below this floor, \code{hd_commodity_mr_portfolio()} holds no position at
#' all for the date (both \code{n_long} and \code{n_short} are 0,
#' contributing \code{gross_ret = 0}) rather than forcing a thin,
#' near-degenerate rank spread.
#'
#' @noRd
.HD_CMR_MIN_BREADTH_RANK <- 2L * .HD_CMR_MIN_LEG_NAMES

#' Manual series_id -> underlying-exposure map for CMR universe deduplication
#' (#751 item B)
#'
#' \strong{# MANUAL: no source.} A ticker-to-underlying-exposure mapping
#' cannot be derived from price data -- the fact that \code{USO} and
#' \code{CL=F} both track WTI crude is a fact about the world, not a
#' computable property of either series. No machine-readable route exists in
#' this project: \code{scripts/fetch_commodities.R} stamps every row with
#' only \code{series_id} and \code{source} (\code{"fred_imf"} or
#' \code{"yahoo"}); neither carries a category/underlying field. Per
#' \code{.claude/rules/fail-loud-not-null.md}'s reproducible-ingestion
#' exception, this table is therefore hand-entered, carries this marker, and
#' is the SINGLE place the mapping is declared -- every consumer reads it
#' rather than re-deriving or duplicating it.
#'
#' \strong{The defect this corrects (#751 item B):} the CMR universe holds
#' multiple representations of the same underlying commodity (WTI crude
#' three times: \code{POILWTIUSDM} IMF index, \code{CL=F} futures,
#' \code{USO} ETF; gold and silver each twice; four ETF baskets --
#' \code{DBA}, \code{DBB}, \code{DBC}, \code{PDBC} -- that are linear
#' combinations of names already held individually). A cross-sectional
#' mean-reversion sort ranks the ranked universe against itself on any date
#' both twins print, manufacturing a spurious long/short pair out of one
#' exposure rather than measuring one commodity against another.
#'
#' \strong{Instrument-selection principle:} where a futures contract exists
#' for an exposure, it is preferred over an ETF/ETP twin and over an
#' IMF/FRED price index -- the literature standard for commodity
#' cross-sections (Miffre & Rallis 2007; Asness, Moskowitz & Pedersen 2013
#' both rank futures, not ETFs or price indexes). \code{keep = TRUE} marks
#' exactly one row per \code{underlying_exposure}. Three categories of
#' \code{keep = FALSE} row exist: (1) the ETF/index twin of a futures
#' contract already held (e.g. \code{GLD} when \code{GC=F} is held); (2) an
#' ETF basket whose constituents are already held individually (\code{DBA},
#' \code{DBB}, \code{DBC}, \code{PDBC} -- each given its own
#' \code{underlying_exposure} since they are not interchangeable with each
#' other, but none is ever kept); (3) none currently -- every
#' \code{underlying_exposure} with no tradeable twin (EU natural gas,
#' Australian coal, nickel) is KEPT as its sole IMF/FRED representative,
#' per #751's explicit decision that those series are not removed from the
#' universe, only deduplicated against a twin when one exists.
#'
#' This table lists every \code{series_id} that has EVER appeared in
#' \code{scripts/fetch_commodities.R}'s FRED/Yahoo fetch lists, not only
#' those in the current live store, so a data refresh that momentarily loses
#' and regains a series does not silently drop out of the map. Validated
#' against the live store on 2026-08-25 (37 distinct \code{series_id}
#' values; see #751 item B PR for the exact counts).
#'
#' @noRd
.HD_CMR_EXPOSURE_MAP <- tibble::tribble(
  ~series_id,      ~underlying_exposure,   ~instrument_type,   ~keep,
  # -- Energy --
  "POILBREUSDM",   "brent_crude",          "fred_imf_index",   FALSE,
  "BZ=F",          "brent_crude",          "futures",          TRUE,
  "POILWTIUSDM",   "wti_crude",            "fred_imf_index",   FALSE,
  "CL=F",          "wti_crude",            "futures",          TRUE,
  "USO",           "wti_crude",            "etf",              FALSE,
  "PNGASEUUSDM",   "natgas_eu",            "fred_imf_index",   TRUE,  # no tradeable twin
  "PNGASUSUSDM",   "natgas_us",            "fred_imf_index",   FALSE,
  "NG=F",          "natgas_us",            "futures",          TRUE,
  "PCOALAUUSDM",   "coal_au",              "fred_imf_index",   TRUE,  # no tradeable twin
  # -- Metals --
  "PGOLDUSDM",     "gold",                 "fred_imf_index",   FALSE,
  "GC=F",          "gold",                 "futures",          TRUE,
  "GLD",           "gold",                 "etf",              FALSE,
  "PSILVERUSDM",   "silver",               "fred_imf_index",   FALSE,
  "SI=F",          "silver",               "futures",          TRUE,
  "SLV",           "silver",               "etf",              FALSE,
  "PCOPPUSDM",     "copper",               "fred_imf_index",   FALSE,
  "HG=F",          "copper",               "futures",          TRUE,
  "PAABORUSDM",    "aluminium",            "fred_imf_index",   TRUE,  # no tradeable twin
  "PNICKUSDM",     "nickel",               "fred_imf_index",   TRUE,  # no tradeable twin
  "PIRONUSDM",     "iron_ore",             "fred_imf_index",   TRUE,  # no tradeable twin
  "PL=F",          "platinum",             "futures",          TRUE,  # no FRED twin fetched
  "PA=F",          "palladium",            "futures",          TRUE,  # no FRED twin fetched
  # -- Grains --
  "PWHEAMTUSDM",   "wheat",                "fred_imf_index",   FALSE,
  "ZW=F",          "wheat",                "futures",          TRUE,
  "PCORNGLUSDM",   "corn",                 "fred_imf_index",   FALSE,
  "ZC=F",          "corn",                 "futures",          TRUE,
  "PSOYBUSDM",     "soybeans",             "fred_imf_index",   FALSE,
  "ZS=F",          "soybeans",             "futures",          TRUE,
  "PRICEUSDM",     "rice",                 "fred_imf_index",   TRUE,  # no tradeable twin
  # -- Softs --
  "PCOFFOTMUSDM",  "coffee",               "fred_imf_index",   FALSE,
  "KC=F",          "coffee",               "futures",          TRUE,
  "PSUGAISAUSDM",  "sugar",                "fred_imf_index",   FALSE,
  "SB=F",          "sugar",                "futures",          TRUE,
  "PCOCOUSDM",     "cocoa",                "fred_imf_index",   FALSE,
  "CC=F",          "cocoa",                "futures",          TRUE,
  "PCOTTINDUSDM",  "cotton",               "fred_imf_index",   FALSE,
  "CT=F",          "cotton",               "futures",          TRUE,
  # -- Livestock --
  "PBEEFINDUSDM",  "beef",                 "fred_imf_index",   TRUE,  # no tradeable twin
  "PPABORUSDM",    "pork",                 "fred_imf_index",   TRUE,  # no tradeable twin
  "LE=F",          "live_cattle",          "futures",          TRUE,  # no FRED twin fetched
  "HE=F",          "lean_hogs",            "futures",          TRUE,  # no FRED twin fetched
  # -- Baskets: constituents already held individually above; never kept --
  "DBA",           "basket_agriculture",   "etf_basket",       FALSE,
  "DBB",           "basket_base_metals",   "etf_basket",       FALSE,
  "DBC",           "basket_broad_dbc",     "etf_basket",       FALSE,
  "PDBC",          "basket_broad_pdbc",    "etf_basket",       FALSE
)

#' Deduplicate the CMR ranked universe to one instrument per underlying
#' exposure (#751 item B)
#'
#' Filters \code{returns_tbl} down to the \code{series_id} values marked
#' \code{keep = TRUE} in \code{\link{.HD_CMR_EXPOSURE_MAP}}. This removes
#' ETF/index twins of a held futures contract and ETF baskets whose
#' constituents are already held individually, so a cross-sectional
#' mean-reversion rank never compares one underlying commodity's exposure
#' against itself under two different tickers.
#'
#' Fails loudly (fail-loud-not-null.md) rather than silently on any
#' \code{series_id} present in \code{returns_tbl} but absent from the map --
#' an unmapped ticker must be classified before it can be ranked, never fall
#' through as though it were its own independent exposure.
#'
#' @param returns_tbl Tibble with a \code{series_id} column (any of
#'   \code{commodities_returns}, \code{cmr_tradeable_returns}, or a
#'   compatible universe).
#'
#' @return \code{returns_tbl} filtered to the kept \code{series_id} values.
#'   All other columns pass through unchanged.
#'
#' @family commodities_mr
#' @export
hd_commodity_mr_dedupe_universe <- function(returns_tbl) {
  if (!is.data.frame(returns_tbl)) {
    cli::cli_abort(c("x" = "{.arg returns_tbl} must be a data frame, not {.cls {class(returns_tbl)}}."))
  }
  if (!"series_id" %in% names(returns_tbl)) {
    cli::cli_abort(c(
      "x" = "{.arg returns_tbl} has no {.field series_id} column.",
      "i" = "Cannot deduplicate the CMR universe without it -- see #751 item B."
    ))
  }

  # Invariant on the map itself: exactly zero or one kept instrument per
  # underlying exposure. Checked every call (36 rows, negligible cost) so a
  # future hand-edit that accidentally keeps two instruments for one
  # exposure aborts immediately rather than silently re-introducing the
  # defect this function exists to fix.
  over_kept <- .HD_CMR_EXPOSURE_MAP |>
    dplyr::filter(.data$keep) |>
    dplyr::count(.data$underlying_exposure, name = "n_kept") |>
    dplyr::filter(.data$n_kept > 1L)
  if (nrow(over_kept) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        ".HD_CMR_EXPOSURE_MAP keeps more than one instrument for ",
        "{nrow(over_kept)} underlying exposure{?s}."
      ),
      "i" = "Exposure{?s}: {.val {over_kept$underlying_exposure}}.",
      "i" = "Exactly one row per underlying_exposure may have keep = TRUE."
    ))
  }

  present_ids <- unique(returns_tbl$series_id)
  mapped_ids  <- .HD_CMR_EXPOSURE_MAP$series_id
  unmapped    <- setdiff(present_ids, mapped_ids)
  if (length(unmapped) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        "{length(unmapped)} series_id{?s} in {.arg returns_tbl} {?is/are} ",
        "not in the CMR exposure map."
      ),
      "i" = "Unmapped: {.val {unmapped}}.",
      "i" = paste0(
        "Add {.val {unmapped}} to .HD_CMR_EXPOSURE_MAP ",
        "(packages/historicaldata/R/commodities_mean_reversion.R) with its ",
        "underlying_exposure and keep decision before it can be ranked -- ",
        "see #751 item B."
      )
    ))
  }

  keep_ids <- .HD_CMR_EXPOSURE_MAP$series_id[.HD_CMR_EXPOSURE_MAP$keep]
  dropped  <- intersect(present_ids, setdiff(mapped_ids, keep_ids))

  cli::cli_inform(c(
    "v" = paste0(
      "CMR (#751 item B): deduplicated the universe to one instrument per ",
      "underlying exposure -- {length(intersect(present_ids, keep_ids))} of ",
      "{length(present_ids)} series kept."
    ),
    "i" = "Dropped ({length(dropped)}): {.val {sort(dropped)}}."
  ))

  returns_tbl |> dplyr::filter(.data$series_id %in% keep_ids)
}


#' Commodity Mean Reversion Portfolio
#'
#' Convert a mean-reversion signal tibble into rank-weighted long/short
#' portfolio weights with t+1 execution.
#'
#' \strong{Rank-weighting, not quantile buckets (#751 item D -- replaces
#' item C's tercile construction):} every ranked name on a date receives a
#' weight proportional to its cross-sectional rank distance from the mean
#' rank -- the construction Asness, Moskowitz & Pedersen (2013, "Value and
#' Momentum Everywhere", J. Finance) use for cross-sectional value/momentum
#' portfolios. For \code{n_avail} ranked names on a date: rank each by
#' \code{mr_signal} (ties broken by AVERAGING the tied positions' ranks --
#' see "Ties" below), subtract the mean rank \code{(n_avail + 1) / 2}, and
#' scale the whole cross-section by a single constant so gross exposure
#' (\code{sum(abs(weight))}) equals \code{target_gross}. This:
#' \itemize{
#'   \item needs no fraction or headcount parameter at all, unlike the
#'     tercile construction it replaces -- it is scale-free in
#'     \code{n_avail}, which #751 measured moving 6 -> 37 across the sample;
#'   \item concentrates weight at the extremes (biggest losers / winners),
#'     where a mean-reversion signal is strongest, instead of giving every
#'     name inside a bucket the same weight regardless of how extreme its
#'     rank is;
#'   \item has no discontinuity at a bucket boundary -- under the tercile
#'     scheme, with \code{n_avail} down to a median of 17 (#751 item B), name
#'     5 of 17 was in at full weight and name 6 was out entirely; here
#'     weight varies continuously with rank;
#'   \item is dollar-neutral and unit-gross BY CONSTRUCTION: ranks minus the
#'     mean rank always sum to exactly zero, irrespective of ties (see
#'     "Ties"), so ONE scaling constant applied to the whole cross-section
#'     produces \code{sum(weight) = 0} and \code{sum(abs(weight)) =
#'     target_gross} simultaneously -- the long side and short side
#'     automatically sum to \code{target_gross / 2} and
#'     \code{-target_gross / 2} respectively, with no separate per-leg
#'     scaling needed. Verified explicitly at runtime below rather than
#'     trusted silently (fail-loud-not-null.md).
#' }
#'
#' \strong{Replaces, rather than sits alongside, the tercile construction
#' (#751 items C/D):} the previous \code{frac} parameter is removed, not
#' kept as an option. Two live sizing mechanisms invite silent divergence --
#' a caller who does not set \code{frac} deliberately gets whichever default
#' happens to be wired in, and nothing forces the choice to be revisited.
#' Rank-weighting is the better structural fit at every breadth this
#' universe has shown (#751; recommended in #758's own body), so it replaces
#' the tercile scheme outright. The tercile construction remains available
#' in git history at the commit immediately before this change if it is ever
#' needed again.
#'
#' \strong{Ties:} \code{rank(mr_signal, ties.method = "average")} is used,
#' not \code{"first"}/\code{"min"}/\code{"random"}. Averaging is the only
#' rule under which tied names receive IDENTICAL weight -- any rule that
#' assigns tied names different ranks would give economically identical
#' signals different weights, which is exactly the "silently produces
#' asymmetric weights" failure this construction must avoid
#' (fail-loud-not-null.md). Averaging also preserves the sum of ranks
#' exactly (\code{n_avail * (n_avail + 1) / 2}), which is what guarantees
#' the dollar-neutral property above holds even in the presence of ties.
#'
#' \strong{Minimum-breadth floor:} dates with fewer than
#' \code{\link{.HD_CMR_MIN_BREADTH_RANK}} ranked names hold no position at
#' all -- see that constant's roxygen for the derivation (a house rule, not
#' a literature threshold; #751 items C/D found none). A date where every
#' \code{mr_signal} happens to be exactly tied (no cross-sectional
#' distinction to weight) is treated the same way, since averaged ranks
#' collapse to the mean rank and every raw weight is zero.
#'
#' Execution discipline is unchanged from the tercile construction: the
#' signal from date \code{t} (formed from returns through \code{t-1}) drives
#' trades executed at date \code{t+1} closing prices, enforced by joining
#' the signal at date \code{t} to the return realised at date \code{t+1} via
#' \code{dplyr::lead()}.
#'
#' @param signal_tbl Tibble returned by \code{\link{hd_commodity_mr_signal}},
#'   with columns \code{date}, \code{series_id}, \code{mr_signal}.
#' @param returns_tbl Tibble with columns \code{date}, \code{series_id},
#'   \code{monthly_ret}.  Must overlap in date range with \code{signal_tbl}.
#' @param target_gross Numeric, single positive value. Target gross exposure
#'   (\code{sum(abs(weight))}) on every date that clears the minimum-breadth
#'   floor. Default 2.0, matching \code{strategy_gross_convention}'s
#'   existing CMR entry (R/plan_exposure.R) -- the long side sums to
#'   \code{target_gross / 2}, the short side to \code{-target_gross / 2}, so
#'   the default reproduces the same 1.0-long / 1.0-short exposure LEVEL the
#'   tercile construction implemented, on a different weighting SHAPE.
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
#'     \item{n_long}{Number of names receiving strictly positive weight.}
#'     \item{n_short}{Number of names receiving strictly negative weight.}
#'     \item{n_avail}{Number of ranked names available that date (breadth
#'       diagnostic, #751 item C).}
#'     \item{held_frac}{\code{(n_long + n_short) / n_avail}. Retained for
#'       continuity with the tercile construction, but no longer the
#'       headline breadth diagnostic -- see \code{n_eff}. Under
#'       rank-weighting this is ~1.0 by construction (every ranked name
#'       gets a nonzero weight, except an exact median tie possible only for
#'       odd \code{n_avail}), so it is now mostly a sanity check that the
#'       minimum-breadth floor is firing where expected, not a measure of
#'       participation.}
#'     \item{n_eff}{Effective breadth (#751 item D; a step toward item F):
#'       the inverse Herfindahl index of the NORMALISED absolute weights,
#'       \code{1 / sum(p_i^2)} where \code{p_i = abs(weight_i) /
#'       sum(abs(weight_i))}. This answers the question \code{held_frac}
#'       answered under the tercile scheme -- "how many independent bets is
#'       this portfolio effectively making" -- because rank-weighting no
#'       longer has a discrete leg size to report: every ranked name
#'       receives SOME weight, but a portfolio dominated by its two most
#'       extreme names has \code{n_eff} near 2 regardless of how large
#'       \code{n_avail} is. Bounded \verb{[1, n_long + n_short]}; only
#'       approaches \code{n_long + n_short} in the limit of near-equal
#'       weight magnitudes, which a LINEAR rank scheme never quite reaches
#'       (the most extreme ranks always carry more weight than near-median
#'       ones). 0 on dates holding no position.}
#'   }
#'   Dates below \code{.HD_CMR_MIN_BREADTH_RANK}'s minimum-breadth floor
#'   hold no position at all: \code{n_long = n_short = 0}, \code{n_eff = 0},
#'   \code{gross_ret = 0}. Such dates are still returned as rows (not
#'   dropped) so the return series stays date-complete for downstream
#'   periodicity checks (#738).
#'
#' @family commodities_mr
#' @export
hd_commodity_mr_portfolio <- function(signal_tbl,
                                       returns_tbl,
                                       target_gross = 2.0,
                                       cost_bps = 20) {
  if (!is.data.frame(signal_tbl)) {
    cli::cli_abort(c("x" = "{.arg signal_tbl} must be a data frame."))
  }
  if (!is.data.frame(returns_tbl)) {
    cli::cli_abort(c("x" = "{.arg returns_tbl} must be a data frame."))
  }
  if (!is.numeric(target_gross) || length(target_gross) != 1L ||
      is.na(target_gross) || target_gross <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg target_gross} must be a single positive number, got {target_gross}.",
      "i" = paste0(
        "{.arg target_gross} is the target sum(abs(weight)) on every date ",
        "that clears the minimum-breadth floor -- see #751 item D."
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

  # Rank-weight within each signal date (#751 item D). rank(..., "average")
  # breaks ties symmetrically -- see roxygen "Ties". raw_weight always sums
  # to exactly zero within a date (by construction of rank minus mean rank),
  # which is what makes a SINGLE per-date scaling constant (gross_raw)
  # sufficient to hit both the dollar-neutral and unit-gross targets at once.
  ranked <- combined |>
    dplyr::group_by(date) |>
    dplyr::mutate(
      n_avail    = dplyr::n(),
      rk         = rank(mr_signal, ties.method = "average"),
      rank_bar   = (n_avail + 1) / 2,
      raw_weight = rk - rank_bar
    ) |>
    # Minimum-breadth floor -- see .HD_CMR_MIN_BREADTH_RANK's roxygen.
    dplyr::filter(n_avail >= .HD_CMR_MIN_BREADTH_RANK) |>
    dplyr::mutate(gross_raw = sum(abs(raw_weight))) |>
    # A date where every mr_signal is exactly tied has gross_raw == 0 (every
    # name shares the same averaged rank_bar rank) -- there is no
    # cross-sectional distinction to weight. Treated the same as a
    # below-floor date: no position. This also guards the division below.
    dplyr::filter(gross_raw > 1e-12) |>
    dplyr::mutate(weight = raw_weight / gross_raw * target_gross) |>
    # The one name that can land exactly at the mean rank (only possible for
    # odd n_avail with no other ties) receives weight == 0 and holds no
    # position -- it is neither long nor short.
    dplyr::filter(weight != 0) |>
    dplyr::mutate(leg = dplyr::if_else(weight > 0, "long", "short")) |>
    dplyr::ungroup()

  # fail-loud-not-null.md: verify the dollar-neutral / unit-gross invariants
  # explicitly rather than trusting the rank arithmetic silently -- a future
  # refactor that breaks it must abort loudly, not produce a
  # plausible-looking but wrong portfolio.
  invariant_check <- ranked |>
    dplyr::group_by(date) |>
    dplyr::summarise(
      net_w   = sum(weight),
      gross_w = sum(abs(weight)),
      .groups = "drop"
    ) |>
    dplyr::filter(abs(net_w) > 1e-6 | abs(gross_w - target_gross) > 1e-6)
  if (nrow(invariant_check) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        "CMR rank-weighted portfolio violates the dollar-neutral / ",
        "unit-gross invariant on {nrow(invariant_check)} date{?s}."
      ),
      "i" = paste0(
        "Expected sum(weight) ~ 0 and sum(abs(weight)) ~ {target_gross} on ",
        "every date holding a position -- see #751 item D."
      ),
      "i" = paste0(
        "First offending date: {format(invariant_check$date[1])} ",
        "(sum(weight)={round(invariant_check$net_w[1], 6)}, ",
        "sum(abs(weight))={round(invariant_check$gross_w[1], 6)})."
      )
    ))
  }

  # Gross returns, position counts, and effective breadth (n_eff, #751 item
  # D), for dates that hold a position at all.
  monthly_traded <- ranked |>
    dplyr::group_by(date) |>
    dplyr::summarise(
      gross_ret   = sum(weight * next_ret, na.rm = TRUE),
      n_long_pos  = sum(leg == "long",  na.rm = TRUE),
      n_short_pos = sum(leg == "short", na.rm = TRUE),
      # Inverse Herfindahl of the normalised absolute weights -- see @return
      # n_eff above. sum(abs(weight)) > 0 is guaranteed here (gross_raw >
      # 1e-12 was enforced above), so this division is safe.
      n_eff       = 1 / sum((abs(weight) / sum(abs(weight)))^2),
      .groups = "drop"
    )

  # Every date the signal/return join produced (breadth_by_date) gets a row
  # in the output, INCLUDING dates below the minimum-breadth floor -- those
  # hold gross_ret = 0 / n_long = n_short = 0 / n_eff = 0 (flat, no
  # position), matching the pre-existing "zero valid signals -> gross_ret =
  # 0" convention rather than silently vanishing from the return series
  # (fail-loud-not-null.md: a dropped date is a dropped observation, not a
  # neutral one).
  monthly <- breadth_by_date |>
    dplyr::left_join(monthly_traded, by = "date") |>
    dplyr::mutate(
      gross_ret   = dplyr::if_else(is.na(gross_ret), 0, gross_ret),
      n_long_pos  = dplyr::if_else(is.na(n_long_pos), 0L, n_long_pos),
      n_short_pos = dplyr::if_else(is.na(n_short_pos), 0L, n_short_pos),
      n_eff       = dplyr::if_else(is.na(n_eff), 0, n_eff)
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
    dplyr::select(date, gross_ret, turnover, cost, net_ret, n_long, n_short, n_avail, held_frac, n_eff)
}
