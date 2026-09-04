# check_registry_leg_count_calibration aborts naming an uncalibrated composite

    Code
      check_registry_leg_count_calibration(status)
    Condition
      Error in `check_registry_leg_count_calibration()`:
      x 1 composite (leg_count > 1) registry strategy has no manufactured-Sharpe calibration annotation (#839):
      i  ens1 -- leg_count = 2
      i Record a 'leg_blend_manufactured_sharpe' diagnostic via hd_diagnostic_record() -- see hd_zero_alpha_calibration() (#839).

# check_registry_leg_count_calibration aborts on a status tibble missing required columns

    Code
      check_registry_leg_count_calibration(tibble::tibble(strategy_id = "ens1"))
    Condition
      Error in `check_registry_leg_count_calibration()`:
      x `status` is missing 2 required column(s): leg_count and has_leg_calibration.
      i check_registry_leg_count_calibration() (S33) requires strategy_id, leg_count, has_leg_calibration -- the output of hd_registry_leg_count_status().

