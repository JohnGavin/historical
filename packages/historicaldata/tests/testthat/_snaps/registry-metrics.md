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

# hd_registry_leg_count_status aborts clearly on a pre-#839 registry with no leg_count column

    Code
      hd_registry_leg_count_status(con)
    Condition
      Error in `hd_registry_leg_count_status()`:
      x bt.strategy has no leg_count column.
      i Columns present: "strategy_id" and "short_name".
      i The registry file predates schema 1.1.0 (#839) and was never migrated.
      i Run `hd_registry_init()` (idempotent) to add it.

