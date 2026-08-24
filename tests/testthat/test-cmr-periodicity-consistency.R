# Tests for the #738 periodicity CONSISTENCY check in
# .assert_cmr_ann_factor() (R/plan_commodities_mean_reversion.R).
#
# #720 added a median-gap reconciliation of a declared `ann_factor` against
# the observed date frequency. #738 measured that `cmr_portfolio_1m` runs at
# 12 obs/year before 2000 and ~255/year after, declared daily throughout:
# 94 of 6851 gaps are monthly, and the overall median gap is 1 day, so the
# median-gap check passes -- correctly by its own logic -- on a series where
# 1.4% of observations sit at a twenty-one-fold different frequency.
#
# The check added here answers the DISPERSION question ("is the spacing
# consistent with ONE declared periodicity") that no measure of central
# tendency can answer. These tests pin both directions: it must fire on a
# mixed-frequency series, and it must NOT fire on a genuine business-daily
# series whose gaps widen over weekends, holidays, and market closures.
testthat::local_edition(3)

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_commodities_mean_reversion.R"))

# ── Fixtures ────────────────────────────────────────────────────────────────

# A genuine business-daily series: weekdays only, so most gaps are 1 day and
# every weekend produces a 3-day gap. This is the shape that a naive
# "all gaps identical" consistency test would false-positive on.
biz_days <- function(from, n) {
  all_days <- seq.Date(as.Date(from), by = "day", length.out = ceiling(n * 7 / 5) + 14L)
  wd <- all_days[!format(all_days, "%u") %in% c("6", "7")]
  wd[seq_len(n)]
}

# Monthly-spaced dates.
month_days <- function(from, n) seq.Date(as.Date(from), by = "month", length.out = n)

# ── The check must NOT fire on genuine daily data ───────────────────────────

test_that("a clean business-daily series passes the consistency check at 252", {
  expect_silent(.assert_cmr_ann_factor(biz_days("2010-01-04", 2000L), 252L, "biz-daily"))
})

test_that("weekend + holiday-cluster gaps do not trip the daily band", {
  # Deliberately includes gaps at the extremes a real daily series produces:
  # a 4-day Thanksgiving-style break, a 5-day Christmas/New-Year cluster, and
  # a 7-day gap the size of the 9/11 market closure (2001-09-10 -> 2001-09-17,
  # the longest US closure since 1990). All are <= the daily band's 10-day
  # upper bound, so none is counted out-of-band.
  d <- biz_days("2001-01-02", 500L)
  d <- sort(unique(c(
    d[d < as.Date("2001-09-10") | d > as.Date("2001-09-17")],
    as.Date(c("2001-09-10", "2001-09-17"))
  )))
  gaps <- as.numeric(diff(d))
  expect_equal(max(gaps), 7)           # the 9/11-sized closure is present
  expect_true(sum(gaps == 3) > 50)     # and plenty of ordinary weekends
  expect_silent(.assert_cmr_ann_factor(d, 252L, "holiday-daily"))
})

test_that("a clean monthly series passes the consistency check at 12", {
  expect_silent(.assert_cmr_ann_factor(month_days("1990-01-01", 300L), 12L, "monthly"))
})

test_that("isolated outages within the allowance floor do not fire", {
  # Two isolated month-long outages in a 400-point daily series. n_gaps = 399,
  # so ceiling(0.001 * 399) = 1, and the absolute floor of 2 governs. The
  # guard fires on a PATTERN, never on one or two bad prints.
  d <- biz_days("2010-01-04", 400L)
  d <- d[-seq(100L, 121L)]
  d <- d[-seq(250L, 271L)]
  gaps <- as.numeric(diff(d))
  expect_equal(sum(gaps > 10), 2L)
  expect_silent(.assert_cmr_ann_factor(d, 252L, "two-outages"))
})

# ── The check MUST fire on mixed-frequency data ─────────────────────────────

test_that("three isolated outages exceed the allowance floor and fire", {
  d <- biz_days("2010-01-04", 400L)
  d <- d[-seq(100L, 121L)]
  d <- d[-seq(200L, 221L)]
  d <- d[-seq(280L, 301L)]
  expect_equal(sum(as.numeric(diff(d)) > 10), 3L)
  expect_error(
    .assert_cmr_ann_factor(d, 252L, "three-outages"),
    "NOT consistent with a single declared periodicity"
  )
})

test_that("the CMR defect shape -- monthly era then daily era, declared daily -- aborts", {
  # Reproduces #738's measured proportions in miniature: a monthly-spaced
  # first era followed by a business-daily second era, declared 252
  # throughout. The median gap is 1 day, so the #720 median-gap check passes;
  # only the consistency check can see it.
  d <- sort(unique(c(month_days("1992-03-01", 94L), biz_days("2000-01-03", 2000L))))
  gaps <- as.numeric(diff(d))
  expect_equal(stats::median(gaps), 1)          # median-gap check would pass
  expect_true(sum(gaps > 10) >= 90L)            # ... on ~90 monthly gaps
  expect_snapshot(error = TRUE, .assert_cmr_ann_factor(d, 252L, "1m"))
})

test_that("daily prints interleaved into a monthly series abort (too-short direction)", {
  # The mirror image: a monthly-declared series contaminated with daily
  # observations. Consistency is two-sided -- a gap that is too SHORT for the
  # declared periodicity is the same defect as one that is too long.
  d <- sort(unique(c(
    month_days("1990-01-01", 240L),
    seq.Date(as.Date("1995-06-01"), by = "day", length.out = 40L)
  )))
  expect_snapshot(error = TRUE, .assert_cmr_ann_factor(d, 12L, "monthly-contaminated"))
})

# ── Structure of the guard ──────────────────────────────────────────────────

test_that("a declared ann_factor with no tolerance row aborts rather than skipping the check", {
  # fail-loud-not-null.md: an unrecognised value is an error, not a silent
  # pass. This branch guards the two tables -- the median-gap classifier's
  # bands and CMR_PERIODICITY_TOLERANCE -- drifting apart, so exercising it
  # means removing a row. Restored on exit.
  old <- CMR_PERIODICITY_TOLERANCE
  withr::defer(assign("CMR_PERIODICITY_TOLERANCE", old, envir = globalenv()))
  assign("CMR_PERIODICITY_TOLERANCE",
         old[old$ann_factor != 252L, , drop = FALSE], envir = globalenv())

  expect_snapshot(
    error = TRUE,
    .assert_cmr_ann_factor(biz_days("2010-01-04", 500L), 252L, "no-tolerance-row")
  )
})

test_that("every ann_factor the median-gap classifier can emit has a tolerance row", {
  # The invariant the defensive branch above exists to protect: adding a band
  # to the classifier without a matching tolerance row would silently disable
  # the consistency check for that periodicity.
  expect_true(all(c(252L, 52L, 12L, 4L) %in% CMR_PERIODICITY_TOLERANCE$ann_factor))
})

test_that("the #720 median-gap classification check still fires (regression)", {
  expect_snapshot(
    error = TRUE,
    .assert_cmr_ann_factor(month_days("1990-01-01", 100L), 252L, "monthly-declared-daily")
  )
})

test_that("on_violation = 'warn' downgrades the consistency abort to a warning", {
  # The documented staging lever: it must warn, not abort, and must NOT be
  # silent -- a silent pass is exactly the failure mode #738 is about.
  d <- sort(unique(c(month_days("1992-03-01", 94L), biz_days("2000-01-03", 2000L))))
  expect_warning(
    .assert_cmr_ann_factor(d, 252L, "1m", on_violation = "warn"),
    "NOT consistent with a single declared periodicity"
  )
  expect_error(.assert_cmr_ann_factor(d, 252L, "1m", on_violation = "abort"))
})

# ── .compute_cmr_metrics()'s periodicity_check staging lever (#738) ────────
# The two tests above exercise .assert_cmr_ann_factor() directly. The three
# production call sites (cmr_metrics_1m/3m/6m, R/plan_commodities_mean_reversion.R)
# don't call that helper themselves -- they pass periodicity_check through to
# .compute_cmr_metrics(), which forwards it as on_violation. These tests
# close that gap: they drive the guard through the ACTUAL parameter the
# staged call sites use, so a future refactor that breaks the forwarding
# (e.g. .compute_cmr_metrics() stops passing periodicity_check through, or
# starts swallowing it) fails here rather than only in production output.

test_that(".compute_cmr_metrics defaults periodicity_check to 'abort' -- never inherited by omission", {
  # A caller that forgets the argument must get the STRICT behaviour. The
  # lenient 'warn' path is opt-in only at the three staged call sites; every
  # other/future call site is silently protected by this default.
  d <- sort(unique(c(month_days("1992-03-01", 94L), biz_days("2000-01-03", 2000L))))
  set.seed(738)
  portfolio <- tibble::tibble(date = d, net_ret = stats::rnorm(length(d), 0, 0.01))
  # daily_rf aligned 1:1 on date with the portfolio: no rf-join gap of its
  # own, so only the periodicity guard is under test.
  daily_rf <- tibble::tibble(date = d, rf_ret = rep(0.00005, length(d)))

  expect_error(
    .compute_cmr_metrics(portfolio, lookback = "1m", daily_rf = daily_rf, ann_factor = 252L),
    "NOT consistent with a single declared periodicity"
  )
})

test_that(".compute_cmr_metrics(periodicity_check = 'warn') warns with the full diagnostic and still computes finite metrics", {
  # The staging lever actually wired at cmr_metrics_1m/3m/6m. A staging flag
  # that silently did nothing -- proceeded without warning, or aborted
  # anyway, or returned the NA-row short-circuit instead of real metrics --
  # would be exactly the class of defect fail-loud-not-null.md exists to
  # catch, just inverted (silent success instead of silent failure).
  d <- sort(unique(c(month_days("1992-03-01", 94L), biz_days("2000-01-03", 2000L))))
  set.seed(738)
  portfolio <- tibble::tibble(date = d, net_ret = stats::rnorm(length(d), 0, 0.01))
  daily_rf <- tibble::tibble(date = d, rf_ret = rep(0.00005, length(d)))

  w <- testthat::capture_warnings(
    metrics <- .compute_cmr_metrics(
      portfolio,
      lookback = "1m", daily_rf = daily_rf, ann_factor = 252L,
      periodicity_check = "warn"
    )
  )

  # Full diagnostic, not a truncated summary: the strategy/lookback label,
  # the declared factor, the out-of-band count/allowance, and the observed
  # band breakdown all round-trip into the warning text a reader sees.
  full_warning <- paste(w, collapse = " ")
  expect_match(full_warning, "CMR 1m")
  expect_match(full_warning, "ann_factor 252")
  expect_match(full_warning, "NOT consistent with a single declared periodicity")
  expect_match(full_warning, "\\d+ of \\d+ gaps")
  expect_match(full_warning, "fall outside the")
  expect_match(full_warning, "allowance is \\d+")
  expect_match(full_warning, "Observed gap bands:")

  # Not the n < 12 NA-row short-circuit, and not a silently-abandoned
  # computation -- real, finite metrics from real data.
  expect_equal(metrics$lookback, "1m")
  expect_gt(metrics$n_days, 12L)
  expect_true(is.finite(metrics$sharpe))
  expect_true(is.finite(metrics$cagr))
  expect_true(is.finite(metrics$vol))
})

test_that("each tolerance band contains its own nominal spacing and is monotone in ann_factor", {
  tol <- CMR_PERIODICITY_TOLERANCE
  expect_true(all(tol$min_gap < tol$max_gap))
  # Every band contains its own nominal calendar spacing (365.25 / ann_factor).
  nominal <- 365.25 / tol$ann_factor
  expect_true(all(nominal >= tol$min_gap & nominal <= tol$max_gap))
  # Bands widen monotonically as the declared frequency falls.
  o <- order(tol$ann_factor, decreasing = TRUE)
  expect_true(!is.unsorted(tol$min_gap[o]))
  expect_true(!is.unsorted(tol$max_gap[o]))
})

test_that("adjacent bands overlap by design, and the check is unaffected by that", {
  # daily [1, 10] and weekly [4, 24] deliberately overlap: a 7-day gap is
  # consistent BOTH with a daily series over a holiday week and with a weekly
  # series. That ambiguity affects only the diagnostic band label in the abort
  # message (first match wins); the check itself only ever asks whether a gap
  # lies in the DECLARED periodicity's band, so overlap cannot cause a missed
  # detection or a false positive.
  tol <- CMR_PERIODICITY_TOLERANCE
  daily  <- tol[tol$ann_factor == 252L, ]
  weekly <- tol[tol$ann_factor == 52L, ]
  expect_true(weekly$min_gap < daily$max_gap)   # the overlap is real

  seven_day <- seq.Date(as.Date("2015-01-05"), by = "7 days", length.out = 200L)
  expect_silent(.assert_cmr_ann_factor(seven_day, 52L, "weekly"))   # declared weekly: passes
  expect_error(                                                      # declared monthly: fires
    .assert_cmr_ann_factor(seven_day, 12L, "weekly-declared-monthly")
  )
})

test_that("fewer than three observations is a no-op, not a false abort", {
  expect_silent(.assert_cmr_ann_factor(as.Date(c("2020-01-01", "2020-06-01")), 252L, "tiny"))
})
