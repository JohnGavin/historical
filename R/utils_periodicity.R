# Shared periodicity reconciliation helper (#719 Layer 3)
#
# #717 found CMR annualising daily returns as if they were monthly
# (ann_factor = 12 against ~200 obs/year data): vol understated ~4.6x, CAGR
# annualised over 566 years, and the error fed directly into #635's leverage
# sizing recommendation. #720 fixed CMR by adding a reconciliation guard at
# the point CMR's `.compute_cmr_metrics()` receives its `ann_factor`
# argument (`.assert_cmr_ann_factor()`, R/plan_commodities_mean_reversion.R).
# #738 then found a SECOND failure mode the median-gap check alone could not
# see -- a series that changes frequency partway through (CMR: ~12 obs/year
# before 2000, ~255/year after, declared daily throughout) -- and added a
# dispersion check on top of the median-gap classification.
#
# #719 asked for this to generalise beyond CMR: "one assertion per helper --
# repetitive, though a shared helper fixes that." This file is that shared
# helper -- the SAME two-check algorithm (classification + dispersion),
# generalised with a `label` argument instead of a hardcoded "CMR" prefix,
# so a NEW call site does not have to hand-roll its own copy.
#
# Deliberately NOT a refactor of .assert_cmr_ann_factor() itself: that
# function, CMR_PERIODICITY_TOLERANCE, and the 20 pinned tests/snapshots in
# tests/testthat/test-cmr-periodicity-consistency.R are left untouched, to
# avoid regressing #738's hard-won CMR-specific coverage for a rename with
# no functional benefit. This file is a parallel, generic implementation;
# CMR keeps using its own. Every OTHER call site should use this one.
#
# Wired into the pipeline-wide coverage gate
# (qa_strategy_periodicity_reconciliation, R/plan_qa_gates.R S28) via
# strat_returns_daily_native (R/plan_strategy_correlation.R), which is
# already the one place the five daily-native strategies' own return series
# (with real dates) are collected together -- the "one place, cheap, covers
# everything at once" backstop #719 Layer 3 option (a) describes, for the
# cohort where a CMR-shaped defect is possible today. Monthly-native
# strategies are NOT covered by this backstop: their per-observation dates
# are not collected in any single place today (each is built inside its own
# plan file and immediately collapsed onto a monthly `ym` spine, which
# structurally forecloses the "daily data mislabelled monthly" defect shape
# CMR hit -- see the S28 gate's own roxygen in R/plan_qa_gates.R for the
# argument in full and the follow-up this leaves open).

#' Periodicity tolerance bands: declared `ann_factor` -> calendar-day gap
#' range consistent with it
#'
#' Generic counterpart of `CMR_PERIODICITY_TOLERANCE`
#' (R/plan_commodities_mean_reversion.R) -- identical values, kept as a
#' separate object so this file has no dependency on CMR's, and vice versa.
#' See that object's roxygen for how each bound is argued (weekend/holiday
#' headroom on the daily band; one-missing-period headroom on the others).
#'
#' @noRd
PERIODICITY_TOLERANCE_TBL <- tibble::tibble(
  ann_factor = c(252L, 52L, 12L, 4L),
  label      = c("daily", "weekly", "monthly", "quarterly"),
  min_gap    = c(1, 4, 20, 60),
  max_gap    = c(10, 24, 75, 200)
)

#' Fraction of gaps allowed to fall outside the declared periodicity's band
#'
#' Generic counterpart of `CMR_PERIODICITY_MAX_OUT_OF_BAND_FRAC` -- same
#' value and rationale (a single year of a different periodicity embedded in
#' a longer series is the smallest regime change worth catching; an isolated
#' vendor outage is not).
#'
#' @noRd
PERIODICITY_MAX_OUT_OF_BAND_FRAC <- 0.001

#' Minimum absolute number of out-of-band gaps tolerated, regardless of n
#'
#' Generic counterpart of `CMR_PERIODICITY_MIN_OUT_OF_BAND_ALLOWANCE` -- same
#' value and rationale (keeps the tolerance at "at least two isolated gaps"
#' on a short series, so the guard fires on a pattern, never a single print).
#'
#' @noRd
PERIODICITY_MIN_OUT_OF_BAND_ALLOWANCE <- 2L

#' Reconcile a declared `ann_factor` against the observed date frequency of
#' the series it is about to annualise (#719 Layer 3)
#'
#' Generic form of `.assert_cmr_ann_factor()`
#' (R/plan_commodities_mean_reversion.R, #717/#720/#738). Two checks, in
#' order, identical algorithm:
#'
#' \enumerate{
#'   \item \strong{Classification}. The MEDIAN gap between distinct sorted
#'     dates is mapped to an expected `ann_factor` (via the same
#'     daily/weekly/monthly/quarterly bands `PERIODICITY_TOLERANCE_TBL`
#'     documents) and compared against the declared one. Robust to the
#'     weekend/holiday gaps every real business-daily series carries.
#'   \item \strong{Consistency}. Counts the gaps falling OUTSIDE
#'     `tolerance_tbl`'s band for the declared periodicity, and aborts (or
#'     warns) when that count exceeds
#'     `max(PERIODICITY_MIN_OUT_OF_BAND_ALLOWANCE,
#'     ceiling(PERIODICITY_MAX_OUT_OF_BAND_FRAC * n_gaps))`. Exists because
#'     check 1 alone cannot see a series that CHANGES frequency partway
#'     through -- a median is precisely the statistic chosen to be
#'     insensitive to a minority at a different frequency, which is exactly
#'     the property a "does this series hold to ONE declared periodicity"
#'     question needs to detect. See #738 for the CMR case this was built to
#'     catch (94 of 6851 gaps monthly, the rest daily, overall median gap
#'     still 1 day).
#' }
#'
#' Placed at the point where `ann_factor` is SUPPLIED, per
#' fail-loud-not-null.md Required Pattern 5 ("guard where the value ENTERS,
#' not only where it is used") -- so a future caller that passes the wrong
#' constant fails immediately, on the value it got wrong, rather than
#' producing a plausible-looking but silently mis-annualised number.
#'
#' @param dates A date vector (one entry per observation; duplicates and
#'   unsorted input are handled).
#' @param ann_factor Integer. The annualisation factor about to be used.
#' @param label Character. Identifies the series in abort/warn messages
#'   (e.g. `"CMR 1m"`, `"OLMAR-1"`, `"Risk State"`) -- the reader must be
#'   able to tell which series failed without re-deriving it.
#' @param on_violation One of `"abort"` (default) or `"warn"`. Governs the
#'   CONSISTENCY check only -- the classification check always aborts (an
#'   unrecognised value is an error, not a value to warn about and use
#'   anyway -- fail-loud-not-null.md). `"warn"` is a staging lever for a
#'   series with a KNOWN, documented, tracked periodicity issue (mirrors
#'   `.assert_cmr_ann_factor()`'s own `on_violation` / `.compute_cmr_metrics()`'s
#'   `periodicity_check` argument) -- it is not a way to keep a
#'   mixed-frequency series in production indefinitely.
#' @param tolerance_tbl Tolerance table, same schema as
#'   `PERIODICITY_TOLERANCE_TBL` (`ann_factor`, `label`, `min_gap`,
#'   `max_gap`). Defaults to `PERIODICITY_TOLERANCE_TBL`; overridable for
#'   tests.
#' @return `NULL`, invisibly. Called for its abort/warn side effect.
#' @noRd
.assert_periodicity_reconciles <- function(dates, ann_factor, label,
                                            on_violation = c("abort", "warn"),
                                            tolerance_tbl = PERIODICITY_TOLERANCE_TBL) {
  on_violation <- match.arg(on_violation)

  d <- sort(unique(as.Date(dates)))
  if (length(d) < 3L) {
    # Too few points for a frequency to be meaningfully observed.
    return(invisible(NULL))
  }
  gaps <- as.numeric(diff(d))
  median_gap <- stats::median(gaps)

  # ── Check 1: classification (median gap -> expected ann_factor) ──────────
  expected_ann_factor <- dplyr::case_when(
    median_gap <= 3   ~ 252L,  # daily (business days; weekends widen some gaps)
    median_gap <= 10  ~ 52L,   # weekly
    median_gap <= 45  ~ 12L,   # monthly
    median_gap <= 135 ~ 4L,    # quarterly
    TRUE ~ NA_integer_
  )

  if (is.na(expected_ann_factor)) {
    cli::cli_abort(c(
      "x" = paste0(
        "{label}: cannot classify the observed data frequency ",
        "against declared ann_factor {ann_factor}."
      ),
      "i" = paste0(
        "Median gap between observation dates is {median_gap} day{?s}, ",
        "which does not match a recognised daily/weekly/monthly/quarterly band."
      ),
      "i" = "See .claude/rules/fail-loud-not-null.md Required Pattern 5."
    ))
  }

  if (expected_ann_factor != ann_factor) {
    cli::cli_abort(c(
      "x" = paste0(
        "{label}: declared ann_factor ({ann_factor}) disagrees with ",
        "the observed data frequency."
      ),
      "i" = paste0(
        "Median gap between observation dates is {median_gap} day{?s}, ",
        "consistent with ann_factor = {expected_ann_factor}, not {ann_factor}."
      ),
      "i" = "Periodicity reconciliation guard -- see .claude/rules/fail-loud-not-null.md Required Pattern 5 and issue #719."
    ))
  }

  # ── Check 2: consistency (dispersion of gaps, not their centre) ──────────
  tol <- tolerance_tbl[tolerance_tbl$ann_factor == ann_factor, , drop = FALSE]
  if (nrow(tol) != 1L) {
    cli::cli_abort(c(
      "x" = "{label}: no periodicity tolerance defined for declared ann_factor {ann_factor}.",
      "i" = "Known factors: {.val {tolerance_tbl$ann_factor}}.",
      "i" = "Add a row to the tolerance table rather than skipping the consistency check."
    ))
  }

  n_gaps    <- length(gaps)
  too_short <- gaps < tol$min_gap
  too_long  <- gaps > tol$max_gap
  n_out     <- sum(too_short) + sum(too_long)
  allowance <- max(
    PERIODICITY_MIN_OUT_OF_BAND_ALLOWANCE,
    ceiling(PERIODICITY_MAX_OUT_OF_BAND_FRAC * n_gaps)
  )

  if (n_out > allowance) {
    obs_band <- vapply(
      gaps,
      function(g) {
        hit <- which(g >= tolerance_tbl$min_gap & g <= tolerance_tbl$max_gap)
        if (length(hit) == 0L) "unclassified" else tolerance_tbl$label[hit[1]]
      },
      character(1)
    )
    band_counts <- sort(table(obs_band), decreasing = TRUE)
    band_txt <- paste0(names(band_counts), ": ", as.integer(band_counts), collapse = "; ")

    out_gaps  <- gaps[too_short | too_long]
    where_out <- d[-1L][too_short | too_long]

    msg <- c(
      "x" = paste0(
        "{label}: the observation spacing is NOT consistent with a ",
        "single declared periodicity (ann_factor {ann_factor}, {tol$label})."
      ),
      "i" = paste0(
        "{n_out} of {n_gaps} gaps ({round(100 * n_out / n_gaps, 3)}%) fall outside the ",
        "{tol$label} band [{tol$min_gap}, {tol$max_gap}] calendar days; ",
        "allowance is {allowance}."
      ),
      "i" = "Observed gap bands: {band_txt}.",
      "i" = paste0(
        "Out-of-band gaps range {min(out_gaps)}-{max(out_gaps)} calendar days, ",
        "spanning {format(min(where_out))}..{format(max(where_out))}."
      ),
      "i" = paste0(
        "The median gap ({median_gap} calendar days) agrees with the declared ",
        "factor, which is why the classification check passes -- a median cannot ",
        "see a minority at a different frequency."
      ),
      "i" = "See .claude/rules/fail-loud-not-null.md Required Pattern 5 and issue #719."
    )

    if (identical(on_violation, "warn")) {
      cli::cli_warn(msg)
    } else {
      cli::cli_abort(msg)
    }
  }

  invisible(NULL)
}
