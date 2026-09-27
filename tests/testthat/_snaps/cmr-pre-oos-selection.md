# .cmr_select_pre_oos_lookback's exclusion message is stable (snapshot-test-policy.md)

    Code
      invisible(.cmr_select_pre_oos_lookback(portfolios = portfolios_thin, oos_start = .oos_start,
        daily_rf = .cmr_fixture_daily_rf, ann_factor = 12L, label = "CMR"))
    Message
      ! CMR: lookback 1m could not be scored on pre-OOS data (8 obs each, need >= 12) -- excluded from selection.

# .cmr_select_pre_oos_lookback aborts when NO lookback can be scored pre-OOS, never falling back to full-sample selection

    Code
      .cmr_select_pre_oos_lookback(portfolios = starved, oos_start = .oos_start,
        daily_rf = .cmr_fixture_daily_rf, ann_factor = 12L, label = "CMR")
    Condition
      Error in `.cmr_select_pre_oos_lookback()`:
      x CMR: no lookback (1m/3m/6m) could be scored on data strictly before the OOS start (2021-01-01).
      i Every candidate had fewer than 12 non-NA observations before 2021-01-01 (.compute_cmr_metrics()'s minimum).
      i Refusing to fall back to full-sample selection -- see .claude/rules/fail-loud-not-null.md and .claude/rules/look-ahead-bias-prevention.md (S41, #910).

