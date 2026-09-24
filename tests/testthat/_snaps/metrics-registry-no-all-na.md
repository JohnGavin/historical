# discover_subperiod_targets() aborts loud when no *_subperiod target is found (RED case)

    Code
      discover_subperiod_targets(plan_dir = no_match_dir)
    Condition
      Error in `discover_subperiod_targets()`:
      x discover_subperiod_targets() found zero `*_subperiod` targets across 1 plan_*.R file(s).
      i This is fail-loud-not-null.md's Pattern 5 shape applied to a discovery mechanism: silently returning nothing looks identical to a real empty result. Known subperiod targets as of #668 (aw_subperiod, ltr_subperiod, rsc_subperiod) should have matched.
      i If the naming convention genuinely changed, update the regex in discover_subperiod_targets() (R/plan_qa_gates.R) -- do not silence this abort or make it a warning.

# check_metrics_registry_no_all_na() catches an all-NA numeric column on a NON-leaderboard target (the #668/#691 shape)

    Code
      check_metrics_registry_no_all_na(c("mf_metrics", "ltr_subperiod"), read_fn = reader)
    Condition
      Error in `check_no_all_na_numeric_columns()`:
      x ltr_subperiod has 1 numeric column(s) that are entirely NA:
      i  sharpe
      i A column with zero non-NA values across the whole ltr_subperiod usually means its source computation never ran, or its output was never actually wired into this target (#668 -- the ltr_subperiod$sharpe all-NA-since-inception class, #677 defect B).
      i If a column is legitimately expected to be all-NA under some pipeline states, add it to this gate's exemption constant in R/plan_qa_gates.R, with a documented reason -- do not silence the gate by removing the check.

# check_metrics_registry_no_all_na() aborts loud when registry_names is empty

    Code
      check_metrics_registry_no_all_na(character(0))
    Condition
      Error in `check_metrics_registry_no_all_na()`:
      x check_metrics_registry_no_all_na() was called with zero registry_names.
      i Both S11_METRICS_REGISTRY and discover_subperiod_targets() abort loud when empty, so this should be unreachable -- something upstream swallowed that abort (fail-loud-not-null.md Pattern 5).

