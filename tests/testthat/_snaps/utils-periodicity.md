# classification mismatch aborts and names the supplied label

    Code
      .assert_periodicity_reconciles(month_days("1990-01-01", 100L), 252L,
      "Risk State")
    Condition
      Error in `.assert_periodicity_reconciles()`:
      x Risk State: declared ann_factor (252) disagrees with the observed data frequency.
      i Median gap between observation dates is 31 days, consistent with ann_factor = 12, not 252.
      i Periodicity reconciliation guard -- see .claude/rules/fail-loud-not-null.md Required Pattern 5 and issue #719.

