# check_leaderboard_no_all_na_metric catches an all-NA ssr column (regression, #400/#668)

    Code
      check_leaderboard_no_all_na_metric(bad)
    Condition
      Error in `check_no_all_na_numeric_columns()`:
      x leaderboard has 1 numeric column(s) that are entirely NA:
      i  ssr
      i A column with zero non-NA values across the whole leaderboard usually means its source computation never ran, or its output was never actually wired into this target (#668 -- the ltr_subperiod$sharpe all-NA-since-inception class, #677 defect B).
      i If a column is legitimately expected to be all-NA under some pipeline states, add it to this gate's exemption constant in R/plan_qa_gates.R, with a documented reason -- do not silence the gate by removing the check.

# check_leaderboard_no_all_na_metric catches an all-NA column with NO prior hardcoded check (the #668 point)

    Code
      check_leaderboard_no_all_na_metric(bad)
    Condition
      Error in `check_no_all_na_numeric_columns()`:
      x leaderboard has 1 numeric column(s) that are entirely NA:
      i  sharpe
      i A column with zero non-NA values across the whole leaderboard usually means its source computation never ran, or its output was never actually wired into this target (#668 -- the ltr_subperiod$sharpe all-NA-since-inception class, #677 defect B).
      i If a column is legitimately expected to be all-NA under some pipeline states, add it to this gate's exemption constant in R/plan_qa_gates.R, with a documented reason -- do not silence the gate by removing the check.

