# hd_compute_add: errors on non-data-frame input

    Code
      hd_compute_add("not a tibble")
    Condition
      Error in `hd_compute_add()`:
      x `quintile_assignments` must be a data frame or tibble.
      i Got <character>.

# hd_compute_add: errors on missing required columns

    Code
      hd_compute_add(bad)
    Condition
      Error in `hd_compute_add()`:
      x `quintile_assignments` is missing required columns: anomaly_id and quintile.
      i Found columns: stock and date.

# hd_compute_add: errors on empty input

    Code
      hd_compute_add(empty)
    Condition
      Error in `hd_compute_add()`:
      x `quintile_assignments` must not be empty.
      i Pass a tibble with at least one row.

# hd_compute_add: errors on non-Date date column

    Code
      hd_compute_add(bad)
    Condition
      Error in `hd_compute_add()`:
      x Column date must be a <Date> or <POSIXct>.
      i Got <character>.

# hd_compute_add: errors on out-of-range quintile values

    Code
      hd_compute_add(bad)
    Condition
      Error in `hd_compute_add()`:
      x Column quintile must contain integers in 1-5 or NA.
      i Got values outside [1, 5].

# hd_aggregate_add: errors on missing columns

    Code
      hd_aggregate_add(bad)
    Condition
      Error in `hd_aggregate_add()`:
      x `add_tbl` is missing required columns: anomaly_id and add.
      i These are produced by `hd_compute_add()`.

# hd_aggregate_add: errors on unsupported 'by' argument

    Code
      hd_aggregate_add(add_tbl, by = "anomaly_date")
    Condition
      Error in `hd_aggregate_add()`:
      x Only "stock_date" is supported for `by`.
      i Got "anomaly_date".

# hd_aggregate_add: errors on empty input

    Code
      hd_aggregate_add(empty)
    Condition
      Error in `hd_aggregate_add()`:
      x `add_tbl` must not be empty.

