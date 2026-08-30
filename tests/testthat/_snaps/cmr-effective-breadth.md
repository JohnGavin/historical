# check_cmr_effective_breadth throws and names the worst offender when n_eff falls below the floor on a held date

    Code
      check_cmr_effective_breadth(list(`1m` = good_1m, `3m` = bad_3m))
    Condition
      Error in `check_cmr_effective_breadth()`:
      x CMR effective breadth (n_eff) fell below the minimum floor (4) on 1 date(s) holding a position.
      i Worst offender: 3m 2020-01-31 -- n_eff=3, n_long=2, n_short=1.
      i check_cmr_effective_breadth() (S26, #751 item F) guards the fundamental-law breadth floor -- see CMR_MIN_EFFECTIVE_BREADTH's roxygen (R/plan_qa_gates.R) for the derivation.

# check_cmr_effective_breadth throws when a CMR portfolio is missing required columns

    Code
      check_cmr_effective_breadth(list(`1m` = bad))
    Condition
      Error in `purrr::map2()`:
      i In index: 1.
      i With name: 1m.
      Caused by error in `.f()`:
      x CMR portfolio "1m" is missing 1 required column(s): n_eff.
      i check_cmr_effective_breadth() (S26) requires date, n_long, n_short, n_eff.

