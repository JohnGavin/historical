# hd_check_accessor_date_types: aborts on a genuine mismatch, naming accessor + class

    Code
      hd_check_accessor_date_types(fake_accessors)
    Condition
      Error in `hd_check_accessor_date_types()`:
      x Inconsistent `date` column types across 2 exported accessors.
      i a: Date; b: POSIXct/POSIXt
      i Coerce to a common type (`as.Date()`) inside the accessor -- see #615.

# hd_check_accessor_date_types: aborts when an accessor has no date column

    Code
      hd_check_accessor_date_types(fake_accessors)
    Condition
      Error in `hd_check_accessor_date_types()`:
      x 1 accessor returned a value with no `date` column.
      i Accessor: b
      i Remove from the probe set if the accessor is not date-keyed, or fix the accessor.

# hd_check_accessor_date_types: rejects an unnamed accessor list

    Code
      hd_check_accessor_date_types(list(function() NULL))
    Condition
      Error in `hd_check_accessor_date_types()`:
      ! `accessors` must be a fully named list.

