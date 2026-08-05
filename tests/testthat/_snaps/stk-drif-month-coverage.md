# check_month_coverage throws when a calendar month is entirely absent (#641)

    Code
      check_month_coverage(make_march_missing(), "stk_drif_portfolio")
    Condition
      Error in `check_month_coverage()`:
      x stk_drif_portfolio: calendar month(s) 3 entirely absent across the whole sample (66 month(s), 2010-01 to 2015-12).
      i A whole calendar month missing every year is a systematic construction bug, not sampling noise (#641).
      i Check for a lookback/rebalance window confined to a single calendar month, or a silent NA/join drop upstream.

# check_month_coverage throws when the ym column is missing

    Code
      check_month_coverage(bad, "test_portfolio")
    Condition
      Error in `check_month_coverage()`:
      x test_portfolio is missing the required ym column.
      i check_month_coverage() (S12) requires a ym ("YYYY-MM") column.

# check_month_coverage signature is stable (catches API drift)

    Code
      args(check_month_coverage)
    Output
      function (portfolio, target_name, min_span_coverage = 0.6) 
      NULL

