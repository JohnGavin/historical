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

# check_s11_registry_consistency throws when a registry name is never fetched

    Code
      check_s11_registry_consistency(registry_names = c("mf_metrics", "ev_metrics",
        "rsc_metrics"), metrics_by_name_names = c("mf_metrics", "ev_metrics"))
    Condition
      Error in `check_s11_registry_consistency()`:
      x S11_METRICS_REGISTRY names 1 target(s) qa_metric_window_bounds never fetched:
      i rsc_metrics
      i Add the target to the metrics_by_name list literal in R/plan_qa_gates.R (S11).

# check_s11_registry_consistency throws when a fetched target is absent from the registry

    Code
      check_s11_registry_consistency(registry_names = c("mf_metrics", "ev_metrics"),
      metrics_by_name_names = c("mf_metrics", "ev_metrics", "aw_metrics"))
    Condition
      Error in `check_s11_registry_consistency()`:
      x qa_metric_window_bounds fetched 1 target(s) absent from S11_METRICS_REGISTRY, so S11 never checked them:
      i aw_metrics
      i Add each to S11_METRICS_REGISTRY in R/plan_qa_gates.R, mapped to its bt_partitions class (equity/macro/factor).

