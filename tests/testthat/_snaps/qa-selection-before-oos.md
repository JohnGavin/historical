# build_selection_before_oos_table aborts on an empty/malformed walk-forward registry

    Code
      build_selection_before_oos_table(ss, walk_forward = tibble::tibble())
    Condition
      Error in `build_selection_before_oos_table()`:
      x SELECTION_WALK_FORWARD_REGISTRY (or the `walk_forward` override) is empty or malformed.
      i build_selection_before_oos_table() (S41) needs at least one registered walk-forward strategy.

# build_selection_before_oos_table aborts when single_shot is missing a required column

    Code
      build_selection_before_oos_table(tibble::tibble(strategy = "x"), walk_forward = wf)
    Condition
      Error in `build_selection_before_oos_table()`:
      x `single_shot` is missing required column(s): strategy, cutoff_date, first_oos_date, evidence.
      i build_selection_before_oos_table() (S41, #910 item 1).

# check_selection_before_oos: enforce=TRUE aborts on FAIL/INDETERMINATE

    Code
      check_selection_before_oos(tbl, enforce = TRUE)
    Message
      i qa_selection_before_oos: 2 strategy/mechanism row(s) checked (S41, #910 item 1):
      i  ok [walk_forward] -- PASS: fine
      i  bad [single_shot] -- INDETERMINATE: trouble
    Condition
      Error in `check_selection_before_oos()`:
      x 1 strategy/mechanism row(s) FAILED or are INDETERMINATE on the selection-before-OOS gate (S41, #910 item 1, HD_ENFORCE_SELECTION_BEFORE_OOS=1):
      i  bad -- INDETERMINATE: trouble
      i A selection procedure must use only data strictly before the first OOS bar (look-ahead-bias-prevention.md, #910). FAIL means it did not; INDETERMINATE means the cutoff/first-OOS date could not be established -- never treated as a pass (checks-must-distinguish-unknown.md). Fix the underlying selection, or add the strategy to SELECTION_BEFORE_OOS_ACKNOWLEDGED (R/plan_qa_gates.R) with a written reason after an explicit human review.

# check_selection_before_oos aborts on a zero-row verdict table

    Code
      check_selection_before_oos(empty)
    Condition
      Error in `check_selection_before_oos()`:
      x check_selection_before_oos() (S41) received a zero-row verdict table.
      i build_selection_before_oos_table() already aborts on an empty registry -- this should be unreachable.

