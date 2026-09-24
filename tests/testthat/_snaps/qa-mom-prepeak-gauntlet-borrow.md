# check_mom_prepeak_gauntlet_borrow_consistency flags a named-arg call missing borrow_rate_annual

    Code
      check_mom_prepeak_gauntlet_borrow_consistency(tmp)
    Condition
      Error in `check_mom_prepeak_gauntlet_borrow_consistency()`:
      x 1 .mom_prepeak_compute_returns() call(s) in gauntlet_fixture_named_missing.R omit borrow_rate_annual (#800):
      i  gauntlet_fixture_named_missing.R:1 -- ret <- .mom_prepeak_compute_returns(
      i Pass borrow_rate_annual = mom_prepeak_params$borrow_rate_annual to match the published mom_prepeak/mom_postpeak/mom_combined targets' cost basis (#665), or add a trailing '# zero-borrow-intentional' comment explaining why this specific recomputation is exempt.

# check_mom_prepeak_gauntlet_borrow_consistency flags a positional-arg call missing borrow_rate_annual (CPCV style)

    Code
      check_mom_prepeak_gauntlet_borrow_consistency(tmp)
    Condition
      Error in `check_mom_prepeak_gauntlet_borrow_consistency()`:
      x 1 .mom_prepeak_compute_returns() call(s) in gauntlet_fixture_positional_missing.R omit borrow_rate_annual (#800):
      i  gauntlet_fixture_positional_missing.R:1 -- ret_is <- .mom_prepeak_compute_returns(port_is, ltr_universe, 0.001)
      i Pass borrow_rate_annual = mom_prepeak_params$borrow_rate_annual to match the published mom_prepeak/mom_postpeak/mom_combined targets' cost basis (#665), or add a trailing '# zero-borrow-intentional' comment explaining why this specific recomputation is exempt.

# qa_mom_prepeak_gauntlet_borrow_consistency scanner function signature is stable (catches API drift)

    Code
      args(check_mom_prepeak_gauntlet_borrow_consistency)
    Output
      function (file) 
      NULL

