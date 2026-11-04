# low benchmark coverage raises the FAIL class

    Code
      align_to_benchmark(strat, short_spy)
    Condition
      Error in `align_to_benchmark()`:
      x Benchmark covers only 60 of 108 monthly strategy periods inside its span (55.6%).
      i Minimum coverage is 80%.

# unknown frequency raises the INDETERMINATE class

    Code
      align_to_benchmark(strat, spy)
    Condition
      Error in `align_to_benchmark()`:
      x Cannot detect the strategy frequency: median gap between dates is 100 days.
      i Expected about 1 (daily), 7 (weekly) or 27 to 32 (monthly) days.

# POSIXct key on either side raises INDETERMINATE (Date vs POSIXct)

    Code
      align_to_benchmark(strat_ct, spy)
    Condition
      Error in `align_to_benchmark()`:
      x `strategy_df`$date must be <Date>, not <POSIXct>.
      i A POSIXct key silently gives zero matches on a join; coerce with as.Date() upstream (data-validation-timeseries section 9).

# an empty side raises INDETERMINATE

    Code
      align_to_benchmark(strat[0L, ], spy)
    Condition
      Error in `align_to_benchmark()`:
      x The strategy series has 0 non-NA rows; at least 2 are needed to detect its frequency.

