# mixed-types abort message names the offending targets and classes

    Code
      check_date_key_types(reg, read_fn = reader)
    Condition
      Error in `check_date_key_types()`:
      x Inconsistent date-key types across 2 present series.
      i d_date: Date; d_posix: POSIXct/POSIXt
      i Coerce to a common type (`as.Date()`) at the producing target.

