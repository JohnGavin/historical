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
#' exactly one row per \code{underlying_exposure} that is eligible to be
#' RANKED AS A POSITION. Three categories of \code{keep = FALSE} row exist:
#' (1) the ETF/index twin of a futures contract already held (e.g.
#' \code{GLD} when \code{GC=F} is held); (2) an ETF basket whose
#' constituents are already held individually (\code{DBA}, \code{DBB},
#' \code{DBC}, \code{PDBC} -- each given its own \code{underlying_exposure}
#' since they are not interchangeable with each other, but none is ever
#' kept); (3) the 8 \code{conditioning = TRUE} rows below.
#'
#' \strong{\code{conditioning} (#751 item 1, decided 2026-08-29 -- SUPERSEDES
#' the item B decision for these 8 rows):} every \code{underlying_exposure}
#' with no tradeable twin (EU natural gas, Australian coal, aluminium,
#' nickel, iron ore, rice, beef, pork) was PREVIOUSLY \code{keep = TRUE},
#' kept as a POSITION -- item B's decision on 2026-08-25. #751's own body
#' (option A) and its 2026-08-24/2026-08-29 decision comments both argue
#' this is wrong on the SAME investability grounds as item 1's pre-2000
#' truncation: an IMF Primary Commodity Price System index is a statistical
#' time-average, not a security, and cannot be bought or shorted -- ranking
#' it as a POSITION cross-sectionally against futures/ETF names (even after
#' deduplication) repeats the mixed-cadence defect item 1's truncation only
#' partially addressed (finding 3: these 8 series keep printing monthly
#' through the present and remained part of the post-cutoff cross-section).
#' These 8 rows are now \code{keep = FALSE} (removed from the POSITION
#' pool: \code{hd_commodity_mr_dedupe_universe()}'s output shrinks from 20
#' to 12 series) and \code{conditioning = TRUE} instead -- selected by
#' \code{\link{hd_commodity_mr_conditioning_universe}} for use as MIDAS-style
#' conditioning DATA (a slower macro covariate informing the daily-traded
#' strategy's exposure), never ranked against anything, per #751's decision
#' comment: \dQuote{The research that produced option A said explicitly to
#' keep them as conditioning data -- ... using a monthly macro series to
#' condition a daily-traded strategy is exactly what MIDAS is legitimately
#' for.} No \code{series_id} is ever both \code{keep} and
#' \code{conditioning}.
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
  ~series_id,      ~underlying_exposure,   ~instrument_type,   ~keep,  ~conditioning,
  # -- Energy --
  "POILBREUSDM",   "brent_crude",          "fred_imf_index",   FALSE,  FALSE,
  "BZ=F",          "brent_crude",          "futures",          TRUE,   FALSE,
  "POILWTIUSDM",   "wti_crude",            "fred_imf_index",   FALSE,  FALSE,
  "CL=F",          "wti_crude",            "futures",          TRUE,   FALSE,
  "USO",           "wti_crude",            "etf",              FALSE,  FALSE,
  "PNGASEUUSDM",   "natgas_eu",            "fred_imf_index",   FALSE,  TRUE,  # #751 item 1: no tradeable twin -> conditioning, not position
  "PNGASUSUSDM",   "natgas_us",            "fred_imf_index",   FALSE,  FALSE,
  "NG=F",          "natgas_us",            "futures",          TRUE,   FALSE,
  "PCOALAUUSDM",   "coal_au",              "fred_imf_index",   FALSE,  TRUE,  # #751 item 1: no tradeable twin -> conditioning, not position
  # -- Metals --
  "PGOLDUSDM",     "gold",                 "fred_imf_index",   FALSE,  FALSE,
  "GC=F",          "gold",                 "futures",          TRUE,   FALSE,
  "GLD",           "gold",                 "etf",              FALSE,  FALSE,
  "PSILVERUSDM",   "silver",               "fred_imf_index",   FALSE,  FALSE,
  "SI=F",          "silver",               "futures",          TRUE,   FALSE,
  "SLV",           "silver",               "etf",              FALSE,  FALSE,
  "PCOPPUSDM",     "copper",               "fred_imf_index",   FALSE,  FALSE,
  "HG=F",          "copper",               "futures",          TRUE,   FALSE,
  "PAABORUSDM",    "aluminium",            "fred_imf_index",   FALSE,  TRUE,  # #751 item 1: no tradeable twin -> conditioning, not position
  "PNICKUSDM",     "nickel",               "fred_imf_index",   FALSE,  TRUE,  # #751 item 1: no tradeable twin -> conditioning, not position
  "PIRONUSDM",     "iron_ore",             "fred_imf_index",   FALSE,  TRUE,  # #751 item 1: no tradeable twin -> conditioning, not position
  "PL=F",          "platinum",             "futures",          TRUE,   FALSE,  # no FRED twin fetched
  "PA=F",          "palladium",            "futures",          TRUE,   FALSE,  # no FRED twin fetched
  # -- Grains --
  "PWHEAMTUSDM",   "wheat",                "fred_imf_index",   FALSE,  FALSE,
  "ZW=F",          "wheat",                "futures",          TRUE,   FALSE,
  "PCORNGLUSDM",   "corn",                 "fred_imf_index",   FALSE,  FALSE,
  "ZC=F",          "corn",                 "futures",          TRUE,   FALSE,
  "PSOYBUSDM",     "soybeans",             "fred_imf_index",   FALSE,  FALSE,
  "ZS=F",          "soybeans",             "futures",          TRUE,   FALSE,
  "PRICEUSDM",     "rice",                 "fred_imf_index",   FALSE,  TRUE,  # #751 item 1: no tradeable twin -> conditioning, not position
  # -- Softs --
  "PCOFFOTMUSDM",  "coffee",               "fred_imf_index",   FALSE,  FALSE,
  "KC=F",          "coffee",               "futures",          TRUE,   FALSE,
  "PSUGAISAUSDM",  "sugar",                "fred_imf_index",   FALSE,  FALSE,
  "SB=F",          "sugar",                "futures",          TRUE,   FALSE,
  "PCOCOUSDM",     "cocoa",                "fred_imf_index",   FALSE,  FALSE,
  "CC=F",          "cocoa",                "futures",          TRUE,   FALSE,
  "PCOTTINDUSDM",  "cotton",               "fred_imf_index",   FALSE,  FALSE,
  "CT=F",          "cotton",               "futures",          TRUE,   FALSE,
  # -- Livestock --
  "PBEEFINDUSDM",  "beef",                 "fred_imf_index",   FALSE,  TRUE,  # #751 item 1: no tradeable twin -> conditioning, not position
  "PPABORUSDM",    "pork",                 "fred_imf_index",   FALSE,  TRUE,  # #751 item 1: no tradeable twin -> conditioning, not position
  "LE=F",          "live_cattle",          "futures",          TRUE,   FALSE,  # no FRED twin fetched
  "HE=F",          "lean_hogs",            "futures",          TRUE,   FALSE,  # no FRED twin fetched
  # -- Baskets: constituents already held individually above; never kept --
  "DBA",           "basket_agriculture",   "etf_basket",       FALSE,  FALSE,
  "DBB",           "basket_base_metals",   "etf_basket",       FALSE,  FALSE,
  "DBC",           "basket_broad_dbc",     "etf_basket",       FALSE,  FALSE,
  "PDBC",          "basket_broad_pdbc",    "etf_basket",       FALSE,  FALSE
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


#' Select the CMR conditioning-only universe (#751 item 1, decided 2026-08-29)
#'
#' Filters \code{returns_tbl} down to the \code{series_id} values marked
#' \code{conditioning = TRUE} in \code{\link{.HD_CMR_EXPOSURE_MAP}} -- the 8
#' untradeable-twin IMF/FRED series that remain in the post-cutoff universe
#' (#751 finding 3: they keep printing monthly through the present) but are
#' NOT ranked as positions. Each is the SOLE representative of its
#' underlying exposure (no futures/ETF twin exists), which is exactly why
#' \code{\link{hd_commodity_mr_dedupe_universe}}'s futures-preferred
#' selection previously kept every one of them as a POSITION by default --
#' the defect #751's item 1 decision (2026-08-29) corrects. This function is
#' the complement of \code{hd_commodity_mr_dedupe_universe()}: that function
#' now selects \code{keep == TRUE} (12 tradeable POSITION series, down from
#' 20); this one selects \code{conditioning == TRUE} (the 8-series
#' macro-conditioning pool). No \code{series_id} is ever in both sets --
#' see \code{.HD_CMR_EXPOSURE_MAP}'s roxygen for the full rationale and
#' \code{\link{hd_commodity_mr_conditioning_signal}} for how this universe is
#' turned into a usable covariate.
#'
#' Fails loudly (fail-loud-not-null.md) rather than silently on any
#' \code{series_id} present in \code{returns_tbl} but absent from the map --
#' an unmapped ticker must be classified before it can be used, never fall
#' through as though it were excluded by default.
#'
#' @param returns_tbl Tibble with a \code{series_id} column (any of
#'   \code{commodities_returns}, \code{cmr_tradeable_returns}, or a
#'   compatible universe).
#'
#' @return \code{returns_tbl} filtered to the \code{conditioning == TRUE}
#'   \code{series_id} values. All other columns pass through unchanged.
#'
#' @family commodities_mr
#' @export
hd_commodity_mr_conditioning_universe <- function(returns_tbl) {
  if (!is.data.frame(returns_tbl)) {
    cli::cli_abort(c("x" = "{.arg returns_tbl} must be a data frame, not {.cls {class(returns_tbl)}}."))
  }
  if (!"series_id" %in% names(returns_tbl)) {
    cli::cli_abort(c(
      "x" = "{.arg returns_tbl} has no {.field series_id} column.",
      "i" = "Cannot select the CMR conditioning universe without it -- see #751 item 1."
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
        "underlying_exposure, keep, and conditioning decision before it can ",
        "be classified -- see #751 item 1."
      )
    ))
  }

  cond_ids <- .HD_CMR_EXPOSURE_MAP$series_id[.HD_CMR_EXPOSURE_MAP$conditioning]

  cli::cli_inform(c(
    "v" = paste0(
      "CMR (#751 item 1): selected the conditioning-only universe -- ",
      "{length(intersect(present_ids, cond_ids))} of {length(present_ids)} ",
      "series are untradeable-twin IMF/FRED conditioning inputs."
    )
  ))

  returns_tbl |> dplyr::filter(.data$series_id %in% cond_ids)
}


#' Default calendar lookback for the CMR conditioning composite signal
#' (#751 item 1 follow-up)
#'
#' Shared across all three CMR position-lookback partitions (1m/3m/6m) --
#' the #751 decision thread's "keep it small" instruction: one conditioning
#' signal, not three. 3 months matches the MIDDLE position lookback and the
#' MIDAS-style framing in #751's body (a slower, monthly macro series
#' conditioning a daily-traded strategy) -- long enough to smooth the
#' IMF/FRED series' own ~monthly print noise, short enough to still react
#' within a quarter.
#'
#' @noRd
.HD_CMR_COND_LOOKBACK_MONTHS <- 3L

#' Compute the CMR conditioning composite signal (#751 item 1 follow-up)
#'
#' Reuses \code{\link{hd_commodity_mr_signal}} -- the SAME calendar-window
#' momentum computation already used for the tradeable position universe --
#' applied to the 8-series conditioning-only universe
#' (\code{\link{hd_commodity_mr_conditioning_universe}}) instead of
#' inventing a new windowing mechanism.
#'
#' \strong{Unlike the position universe, these 8 series are never ranked
#' cross-sectionally against each other or against anything else} -- doing
#' so was exactly defects 2 and 3 in #751's body (ranking the same
#' commodity against itself; ranking a ~3-month return against a ~3-day
#' one). Instead, their per-series signals are aggregated to ONE scalar per
#' date via the CROSS-SERIES MEDIAN, giving a single macro-conditioning
#' covariate -- how much the untradeable commodity-index basket has
#' recently moved -- independent of any cross-sectional comparison.
#'
#' Because the 8 series are FRED/IMF monthly prints, this composite is
#' itself sparse (one row per date ANY conditioning series prints, not one
#' row per calendar day). See \code{.cmr_conditioning_regime()}
#' (R/plan_commodities_mean_reversion.R) for how it is turned into an
#' exposure-scaling regime and carried forward onto CMR's own daily dates.
#'
#' @param cond_returns_tbl Tibble as returned by
#'   \code{\link{hd_commodity_mr_conditioning_universe}}: columns
#'   \code{date}, \code{series_id}, \code{monthly_ret}.
#' @param lookback_months Integer. Passed through to
#'   \code{\link{hd_commodity_mr_signal}}. Default
#'   \code{\link{.HD_CMR_COND_LOOKBACK_MONTHS}} (3).
#'
#' @return Tibble with one row per date any conditioning series prints,
#'   columns:
#'   \describe{
#'     \item{date}{Observation date.}
#'     \item{cond_signal}{Median \code{mr_signal} (see
#'       \code{\link{hd_commodity_mr_signal}}) across the conditioning
#'       series available that date.}
#'     \item{n_series}{Number of conditioning series contributing to that
#'       date's median (breadth diagnostic).}
#'   }
#'
#' @family commodities_mr
#' @export
hd_commodity_mr_conditioning_signal <- function(cond_returns_tbl,
                                                 lookback_months = .HD_CMR_COND_LOOKBACK_MONTHS) {
  per_series <- hd_commodity_mr_signal(cond_returns_tbl, lookback_months = lookback_months)

  per_series |>
    dplyr::group_by(date) |>
    dplyr::summarise(
      cond_signal = stats::median(mr_signal, na.rm = TRUE),
      n_series    = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::arrange(date)
}


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
#'     \item{n_eff}{Effective breadth (#751 item F): the inverse Herfindahl
#'       index of the NORMALISED absolute weights held that date,
#'       \code{1 / sum(p_i^2)} where \code{p_i = abs(weight_i) /
#'       sum(abs(weight_i))} over the held names. Salvaged from the
#'       rank-weighted construction proposed (and closed unmerged) on #765,
#'       and computed here against the LIVE tercile construction instead --
#'       under \strong{equal-weight} tercile legs every held name carries
#'       identical \code{|weight|}, so \code{n_eff} collapses to exactly
#'       \code{n_long + n_short} whenever a position is held (the inverse
#'       Herfindahl index of N equal shares is N). This still answers the
#'       fundamental-law question \code{held_frac} does not -- "how many
#'       independent bets is this portfolio effectively making" (Grinold &
#'       Kahn; Ding & Martin 2017, cited in #751) -- and is the quantity a
#'       future change to the weighting scheme (a return to rank-weighting,
#'       item D) would make diverge from a plain headcount, at which point
#'       this column (and the S24 QA gate built on it,
#'       \code{check_cmr_effective_breadth()}, R/plan_qa_gates.R) would be
#'       doing non-redundant work without any call-site change. 0 on dates
#'       holding no position.}
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

  # Monthly gross returns, position counts, and effective breadth (n_eff,
  # #751 item F), for dates that hold a position at all.
  monthly_traded <- ranked |>
    dplyr::group_by(date) |>
    dplyr::summarise(
      gross_ret   = sum(weight * next_ret, na.rm = TRUE),
      n_long_pos  = sum(leg == "long",  na.rm = TRUE),
      n_short_pos = sum(leg == "short", na.rm = TRUE),
      # Inverse Herfindahl of the normalised absolute weights -- see
      # @return n_eff above. sum(abs(weight)) > 0 is guaranteed here
      # (n_leg > 0L was enforced by the filter above), so this division is
      # safe.
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
