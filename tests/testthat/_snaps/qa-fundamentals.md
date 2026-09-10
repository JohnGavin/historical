# check_fundamentals_lag_shift: aborts above 40% -- the known-peek case

    Code
      check_fundamentals_lag_shift(metric_as_used = 1.2, metric_lag_shifted = 0.1,
        metric_name = "Sharpe")
    Condition
      Error in `check_fundamentals_lag_shift()`:
      x CHECK 6 (#554): Sharpe degrades by 91.7% when fundamentals are shifted to their worst-case public-availability date (period_end + 120d) -- above the 40% FAIL threshold.
      i Sharpe as-used: 1.2; lag-shifted: 0.1.
      i The difference was never alpha -- it was the filing-lag peek. See #553/#554.
      > Delay every fundamental input's availability date to period_end + FUNDAMENTAL_MAX_LAG_DAYS before joining, or drop the fundamental feature.

# check_fundamentals_join_dates: catches a deliberately-leaked row

    Code
      check_fundamentals_join_dates(leaked_frame)
    Condition
      Error in `check_fundamentals_join_dates()`:
      x Join-date audit (#555): 33.333% of rows (1/3) are visible before their filing date.
      i Sample offending row(s): MSFT / 2024Q1 / Revenues
      > Any row where visible_date < first_filed is look-ahead by construction -- fix the join, not the threshold.

# check_fundamentals_join_dates: errors loudly when required columns are missing

    Code
      check_fundamentals_join_dates(bad)
    Condition
      Error in `check_fundamentals_join_dates()`:
      x Fundamentals feature frame is missing 1 required column(s): first_filed.
      i check_fundamentals_join_dates() (#555) requires visible_date and first_filed.

