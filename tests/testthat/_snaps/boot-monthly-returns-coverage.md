# check_boot_monthly_returns_coverage aborts when a calendar month is missing entirely (#603)

    Code
      check_boot_monthly_returns_coverage(gapped_boot_monthly_returns)
    Condition
      Error in `check_boot_monthly_returns_coverage()`:
      x boot_monthly_returns has 1 calendar-month gap(s) in its ym sequence:
      i  2021-03
      i boot_monthly_returns builds a calendar-complete spine specifically so this cannot happen (#603/#656) -- check for a changed spine/join in R/plan_bootstrap_ci.R or a new gap in stk_max_portfolio / stk_drif_portfolio. A gap here also means the block bootstrap in boot_draws would splice non-adjacent calendar months (the original #603 defect).

# check_boot_monthly_returns_coverage names the missing constituents for a thin-coverage month

    Code
      check_boot_monthly_returns_coverage(thin_march)
    Condition
      Warning:
      ! 1 month(s) in boot_monthly_returns have at least one missing constituent strategy (#603/#656):
      i  2021-03 -- missing: stk_drif, fac_max, fac_drif
      i calc_boot_metrics() drops NA pairwise per strategy, so this cannot poison another strategy's bootstrap draws.

# check_boot_monthly_returns_coverage throws when required columns are missing

    Code
      check_boot_monthly_returns_coverage(bad)
    Condition
      Error in `check_boot_monthly_returns_coverage()`:
      x boot_monthly_returns is missing 1 required column(s): stk_drif.
      i check_boot_monthly_returns_coverage() (S25) requires ym, stk_max, stk_drif, fac_max, fac_drif.

