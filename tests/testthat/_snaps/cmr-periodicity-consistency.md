# the CMR defect shape -- monthly era then daily era, declared daily -- aborts

    Code
      .assert_cmr_ann_factor(d, 252L, "1m")
    Condition
      Error in `.assert_cmr_ann_factor()`:
      x CMR 1m: the observation spacing is NOT consistent with a single declared periodicity (ann_factor 252, daily).
      i 94 of 2093 gaps (4.491%) fall outside the daily band [1, 10] calendar days; allowance is 3.
      i Observed gap bands: daily: 1999; monthly: 94.
      i Out-of-band gaps range 28-33 calendar days, spanning 1992-04-01..2000-01-03.
      i The median gap (1 calendar days) agrees with the declared factor, which is why the #720 median-gap check passes -- a median cannot see a minority at a different frequency. See #738.
      i See .claude/rules/fail-loud-not-null.md Required Pattern 5.

# daily prints interleaved into a monthly series abort (too-short direction)

    Code
      .assert_cmr_ann_factor(d, 12L, "monthly-contaminated")
    Condition
      Error in `.assert_cmr_ann_factor()`:
      x CMR monthly-contaminated: the observation spacing is NOT consistent with a single declared periodicity (ann_factor 12, monthly).
      i 39 of 277 gaps (14.079%) fall outside the monthly band [20, 75] calendar days; allowance is 2.
      i Observed gap bands: monthly: 237; daily: 39; weekly: 1.
      i Out-of-band gaps range 1-1 calendar days, spanning 1995-06-02..1995-07-10.
      i The median gap (30 calendar days) agrees with the declared factor, which is why the #720 median-gap check passes -- a median cannot see a minority at a different frequency. See #738.
      i See .claude/rules/fail-loud-not-null.md Required Pattern 5.

# a declared ann_factor with no tolerance row aborts rather than skipping the check

    Code
      .assert_cmr_ann_factor(biz_days("2010-01-04", 500L), 252L, "no-tolerance-row")
    Condition
      Error in `.assert_cmr_ann_factor()`:
      x CMR no-tolerance-row: no periodicity tolerance defined for declared ann_factor 252.
      i Known factors: 52, 12, and 4.
      i Add a row to CMR_PERIODICITY_TOLERANCE rather than skipping the consistency check.

# the #720 median-gap classification check still fires (regression)

    Code
      .assert_cmr_ann_factor(month_days("1990-01-01", 100L), 252L,
      "monthly-declared-daily")
    Condition
      Error in `.assert_cmr_ann_factor()`:
      x CMR monthly-declared-daily: declared ann_factor (252) disagrees with the observed data frequency.
      i Median gap between observation dates is 31 days, consistent with ann_factor = 12, not 252.
      i This is the reconciliation guard added for #717 -- see .claude/rules/fail-loud-not-null.md Required Pattern 5.

