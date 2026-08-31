# a non-exempt strategy with a mismatched declared ann_factor aborts and names it

    Code
      check_strategy_periodicity_reconciliation(bad, good_obs_ann_factor)
    Condition
      Error in `check_strategy_periodicity_reconciliation()`:
      x 1 strategy/strategies failed periodicity reconciliation (S28, #719 Layer 3):
      i TOM (code_name tom): x TOM: declared ann_factor (252) disagrees with the observed data frequency. i Median gap between observation dates is 31 days, consistent with ann_factor = 12, not 252. i Periodicity reconciliation guard -- see .claude/rules/fail-loud-not-null.md Required Pattern 5 and issue #719.
      i A declared ann_factor must match the OBSERVED frequency of the series it annualises -- see .claude/rules/fail-loud-not-null.md Required Pattern 5 and issue #719. Known, documented exceptions go in PERIODICITY_RECONCILIATION_EXEMPT (R/plan_qa_gates.R), not a code change here.

