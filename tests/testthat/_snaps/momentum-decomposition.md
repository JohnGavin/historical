# F1: error message includes date ranges for diagnosis

    Code
      decompose_momentum(stock_ret, ff_no_overlap, lookback_months = 24L)
    Condition
      Error in `decompose_momentum()`:
      x Factor join produced 0 rows — date convention mismatch.
      i stock_returns date range: 2020-01-31 to 2020-05-31
      i factor_returns date range: 2015-01-01 to 2015-05-01
      i Both sides are coerced to YYYY-MM keys before joining.
      i Check that factor_returns has a 'date' column with parseable dates.

# F2: asof_lookup error message shows first duplicate date

    Code
      asof_lookup(x, y, value_col = "signal")
    Condition
      Error in `asof_lookup()`:
      x `y` has 1 date with more than one row after coercing to Date (intraday observations collapse to an arbitrary row).
      i Aggregate `y` to daily before calling `asof_lookup()`: e.g. last observation per date.
      i First duplicate date: 2025-01-15 (2 rows).

# F6: error message includes parameter count

    Code
      decompose_momentum(stock_ret, ff, lookback_months = 10L)
    Condition
      Error in `decompose_momentum()`:
      x `lookback_months` must be >= 13 to avoid overfitting.
      i Regression has 6 parameters (5 FF factors + 0 industry dummies + 1 intercept).
      i Received: 10 months (10 obs vs 6 params).
      i Use lookback_months >= 13 for at least 7 degrees of freedom.

