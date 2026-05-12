# character input aborts with informative cli error

    Code
      to_month_end_bizday("2026-02-15")
    Condition
      Error in `to_month_end_bizday()`:
      x `date` must not be a <character> vector.
      i Coerce explicitly: `as.Date(date)` or `lubridate::ymd(date)`.

# numeric input aborts with informative cli error

    Code
      to_month_end_bizday(20250215)
    Condition
      Error in `to_month_end_bizday()`:
      x `date` must be a <Date> or <POSIXct> vector, not <numeric>.
      i Coerce explicitly: `as.Date(date)`.

