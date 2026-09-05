# check_leverage_gross_detection_gate throws when an underpowered strategy exceeds 1.0x

    Code
      check_leverage_gross_detection_gate(bad, lb)
    Condition
      Error in `check_leverage_gross_detection_gate()`:
      x 1 strategy/strategies would receive allocator gross above 1.0x while detection-underpowered or unverified (#626/#719 Layer 2, detection-power-required.md):
      i  Underpowered -- G_capped = 1.50x, detection_underpowered = TRUE
      i A strategy that cannot be distinguished from a zero Sharpe (or has no verdict at all) must not be levered above 1.0x gross. Either fix the underlying detection verdict, lower the strategy's allocator input (leverage_gross_backstop / HD_LEVERAGE_GROSS_BACKSTOP), or add a written row to LEVERAGE_GROSS_DETECTION_OVERRIDE (R/plan_qa_gates.R) with an explicit reason.

# check_leverage_gross_detection_gate treats a missing (NA) detection verdict as blocking

    Code
      check_leverage_gross_detection_gate(bad, lb)
    Condition
      Error in `check_leverage_gross_detection_gate()`:
      x 1 strategy/strategies would receive allocator gross above 1.0x while detection-underpowered or unverified (#626/#719 Layer 2, detection-power-required.md):
      i  Unverified -- G_capped = 1.20x, detection_underpowered = NA (not computed)
      i A strategy that cannot be distinguished from a zero Sharpe (or has no verdict at all) must not be levered above 1.0x gross. Either fix the underlying detection verdict, lower the strategy's allocator input (leverage_gross_backstop / HD_LEVERAGE_GROSS_BACKSTOP), or add a written row to LEVERAGE_GROSS_DETECTION_OVERRIDE (R/plan_qa_gates.R) with an explicit reason.

# check_leverage_gross_detection_gate throws when allocator_gross is missing required columns

    Code
      check_leverage_gross_detection_gate(bad, leaderboard_fixture)
    Condition
      Error in `check_leverage_gross_detection_gate()`:
      x `allocator_gross` is missing required column: G_capped.
      i check_leverage_gross_detection_gate() (S31) needs strategy and G_capped (see compute_allocator_gross()).

# check_leverage_gross_detection_gate throws when leaderboard is missing required columns

    Code
      check_leverage_gross_detection_gate(allocator_gross, bad_lb)
    Condition
      Error in `check_leverage_gross_detection_gate()`:
      x `leaderboard` is missing required column: detection_underpowered.
      i check_leverage_gross_detection_gate() (S31) needs strategy, period, and detection_underpowered.

# check_leverage_gross_detection_gate throws when override_tbl is missing required columns

    Code
      check_leverage_gross_detection_gate(allocator_gross, leaderboard_fixture,
        override_tbl = bad_override)
    Condition
      Error in `check_leverage_gross_detection_gate()`:
      x `override_tbl` is missing required column(s): strategy, reason.
      i check_leverage_gross_detection_gate() (S31) requires LEVERAGE_GROSS_DETECTION_OVERRIDE's strategy, reason columns.

