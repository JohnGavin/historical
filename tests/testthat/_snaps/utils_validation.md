# mixed-types abort message names the offending targets and classes

    Code
      check_date_key_types(reg, read_fn = reader)
    Condition
      Error in `check_date_key_types()`:
      x Inconsistent date-key types across 2 present series.
      i d_date: Date; d_posix: POSIXct/POSIXt
      i Coerce to a common type (`as.Date()`) at the producing target.

# check_monthly_convention snapshot — ok tibble structure

    Code
      names(result)
    Output
      [1] "target"    "status"    "n"         "pct_match"

---

    Code
      result$status
    Output
      [1] "ok"

# check_temporal_coverage: below-abort-floor coverage aborts, names target + pct

    Code
      check_temporal_coverage(reg, read_fn = reader)
    Condition
      Error in `check_temporal_coverage()`:
      x 1 target below the 30% temporal-coverage floor.
      i sparse_tgt: 25.8%
      i Coverage = distinct trading days present / expected weekdays in the target's date range.

# check_freshness: stale message names target, days stale, and threshold

    Code
      . <- check_freshness(reg, read_fn = reader, as_of = as_of)
    Condition
      Warning:
      ! 1 target exceeds their freshness threshold.
      i stale_named: 15d stale (threshold 7d)
      i A weekly data poll can fail silently (#613) -- check the upstream fetch.

