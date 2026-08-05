# hd_metric_record aborts on an unrecognised unit (wide form)

    Code
      hd_metric_record(s$con, s$uuid, tibble::tibble(cagr = 0.05), units = c(cagr = "pct"))
    Condition
      Error in `.hd_validate_metric_units()`:
      x Unknown metric_unit "pct" for metric "cagr".
      i Allowed units: "fraction", "percent", "ratio", "count", "days", and "years".

# hd_metric_record aborts on a missing unit (wide form, no units arg)

    Code
      hd_metric_record(s$con, s$uuid, tibble::tibble(cagr = 0.05))
    Condition
      Error in `.hd_validate_metric_units()`:
      x Missing metric_unit for metric "cagr".
      i Every metric written to `bt.metric` must declare a unit.
      i Allowed units: "fraction", "percent", "ratio", "count", "days", and "years".
      i Long form: add a metric_unit column. Wide form: pass `units`.

# hd_metric_record aborts on a missing unit (long form, no metric_unit / units)

    Code
      hd_metric_record(s$con, s$uuid, long)
    Condition
      Error in `.hd_validate_metric_units()`:
      x Missing metric_unit for metric "cagr".
      i Every metric written to `bt.metric` must declare a unit.
      i Allowed units: "fraction", "percent", "ratio", "count", "days", and "years".
      i Long form: add a metric_unit column. Wide form: pass `units`.

# hd_metric_record aborts on an unrecognised unit (long form)

    Code
      hd_metric_record(s$con, s$uuid, long)
    Condition
      Error in `.hd_validate_metric_units()`:
      x Unknown metric_unit "pct" for metric "cagr".
      i Allowed units: "fraction", "percent", "ratio", "count", "days", and "years".

# hd_leaderboard_from_registry aborts on legacy NA-unit rows

    Code
      hd_leaderboard_from_registry(s$con, metric_name = "legacy_cagr")
    Condition
      Error in `.hd_validate_metric_units()`:
      x Missing metric_unit for metric "legacy_cagr".
      i Every metric written to `bt.metric` must declare a unit.
      i Allowed units: "fraction", "percent", "ratio", "count", "days", and "years".
      i Long form: add a metric_unit column. Wide form: pass `units`.

