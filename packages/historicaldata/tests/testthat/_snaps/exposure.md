# NA in w aborts with informative error

    Code
      hd_exposure_metrics(c(0.5, NA_real_))
    Condition
      Error in `hd_exposure_metrics()`:
      ! `w` must not contain "NA" or "NaN".
      i Found 1 missing value at position 2.
      i Resolve missingness upstream; `hd_exposure_metrics()` does not `na.rm`.

# character input aborts with informative error

    Code
      hd_exposure_metrics(c("0.5", "0.5"))
    Condition
      Error in `hd_exposure_metrics()`:
      ! `w` must be a numeric vector.
      x Got <character>.

# zero-length input aborts with informative error

    Code
      hd_exposure_metrics(numeric(0))
    Condition
      Error in `hd_exposure_metrics()`:
      ! `w` must have length >= 1.
      x Got a zero-length vector.

# function signature is stable (catches API drift)

    Code
      args(hd_exposure_metrics)
    Output
      function (w) 
      NULL

