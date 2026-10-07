# .aw_excess_series: a hole INSIDE the rf span aborts (#937)

    Code
      .aw_excess_series(d, rep(0.001, 10L), rf, strategy = "Avoid Worst")
    Condition
      Error in `.aw_excess_series()`:
      x 1 day inside the daily risk-free series' own span have no rate.
      i Missing dates: "2020-01-04".
      i Fama-French daily RF spans 2020-01-01..2020-02-01, so this is a HOLE, not a publication lag.
      i Investigate hd_factors() (factor_name == "RF", frequency == "daily") before trusting this Sharpe.

