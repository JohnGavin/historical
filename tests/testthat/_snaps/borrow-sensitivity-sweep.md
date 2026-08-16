# compute_borrow_sensitivity requires >= 12 months

    Code
      compute_borrow_sensitivity(rep(0.01, 6L))
    Condition
      Error in `compute_borrow_sensitivity()`:
      x compute_borrow_sensitivity() requires >= 12 monthly returns.
      i Got 6.

# compute_borrow_sensitivity aborts on NA input rather than dropping it silently

    Code
      compute_borrow_sensitivity(bad)
    Condition
      Error in `compute_borrow_sensitivity()`:
      x compute_borrow_sensitivity(): monthly_ret_pre_borrow contains NA.
      i Filter NA out before calling -- never coerced or dropped silently here.

# compute_borrow_sensitivity's cagr/vol match an independent formula recomputation

    Code
      print(out, n = Inf)
    Output
      # A tibble: 4 x 5
        borrow_rate_annual    cagr    vol sharpe sharpe_delta
                     <dbl>   <dbl>  <dbl>  <dbl>        <dbl>
      1               0     0.141  0.0445  3.18         0    
      2               0.03  0.108  0.0445  2.43        -0.751
      3               0.1   0.0335 0.0445  0.754       -2.43 
      4               0.25 -0.111  0.0445 -2.49        -5.67 

# build_borrow_sensitivity_table requires a non-empty named list

    Code
      build_borrow_sensitivity_table(list())
    Condition
      Error in `build_borrow_sensitivity_table()`:
      x build_borrow_sensitivity_table(): returns_by_strategy must be a non-empty NAMED list.

