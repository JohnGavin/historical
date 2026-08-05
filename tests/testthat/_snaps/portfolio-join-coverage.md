# check_portfolio_join_coverage aborts when a calendar month is missing entirely (#641)

    Code
      check_portfolio_join_coverage(gapped_port_returns)
    Condition
      Error in `check_portfolio_join_coverage()`:
      x port_returns has 1 calendar-month gap(s) in its date sequence:
      i  2021-03
      i port_returns builds a calendar-complete spine specifically so this cannot happen (#641) -- check for a changed spine/join in R/plan_portfolio_opt.R or a new gap in stk_max_portfolio / stk_drif_portfolio (R/plan_stock_backtest.R).

# check_portfolio_join_coverage names the missing constituents for a thin-coverage month

    Code
      check_portfolio_join_coverage(thin_march)
    Condition
      Warning:
      ! 1 month(s) have fewer than 2 of 4 constituent strategies reporting a value (renormalised to NA in port_combined rather than a single-strategy bet, #641):
      i  2021-03 -- missing: stk_drif, fac_max, fac_drif
      i Usually the benign live-edge lag between stock-level and factor-level data feeds -- verify if this list grows or covers a month that isn't at the trailing edge.

# check_portfolio_join_coverage throws when required columns are missing

    Code
      check_portfolio_join_coverage(bad)
    Condition
      Error in `check_portfolio_join_coverage()`:
      x port_returns is missing 1 required column(s): stk_drif.
      i check_portfolio_join_coverage() (S13) requires date, stk_max, stk_drif, fac_max, fac_drif.

