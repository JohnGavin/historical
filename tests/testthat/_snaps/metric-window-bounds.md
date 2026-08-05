# check_metric_window_bounds throws when an OOS window extends past test_end

    Code
      check_metric_window_bounds(unbounded_oos_metrics, test_end, "mf_metrics")
    Condition
      Error in `check_metric_window_bounds()`:
      x mf_metrics has 1 row(s) whose computed window extends past the sealed Validation partition boundary (test_end = 2022-12-31), #645:
      i  TS-Mom L/S / OOS -- window_end 2026-01-31 exceeds test_end 2022-12-31
      i Bound the window at test_end in the source metrics target, or relabel the period "Validation" if the window is intentionally sealed.

# check_metric_window_bounds throws when required columns are missing

    Code
      check_metric_window_bounds(bad, test_end, "mf_metrics")
    Condition
      Error in `check_metric_window_bounds()`:
      x mf_metrics is missing 1 required column(s): window_end.
      i check_metric_window_bounds() (S11) requires strategy, period, window_end.

