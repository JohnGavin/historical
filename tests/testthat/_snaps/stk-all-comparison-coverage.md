# check_stk_all_comparison_coverage aborts when a calendar month is missing entirely (#656)

    Code
      check_stk_all_comparison_coverage(gapped_stk_all_comparison)
    Condition
      Error in `check_stk_all_comparison_coverage()`:
      x stk_all_comparison has 1 calendar-month gap(s) in its ym sequence:
      i  2021-03
      i stk_all_comparison builds a calendar-complete spine specifically so this cannot happen (#656) -- check for a changed spine/join in R/plan_stock_backtest.R or a new gap in stk_max_portfolio / stk_drif_portfolio.

# check_stk_all_comparison_coverage names the missing constituents for a thin-coverage month

    Code
      check_stk_all_comparison_coverage(thin_march)
    Condition
      Warning:
      ! 1 month(s) in stk_all_comparison have at least one missing constituent strategy (#656):
      i  2021-03 -- missing: stk_drif, fac_max, fac_drif
      i Usually the benign live-edge lag between stock-level and factor-level data feeds.

# check_stk_all_comparison_coverage throws when required columns are missing

    Code
      check_stk_all_comparison_coverage(bad)
    Condition
      Error in `check_stk_all_comparison_coverage()`:
      x stk_all_comparison is missing 1 required column(s): stk_drif.
      i check_stk_all_comparison_coverage() (S24) requires ym, stk_max, stk_drif, fac_max, fac_drif.

