# check_bdbb_no_lookahead aborts naming a row that scores a return at window_end (contemporaneous)

    Code
      check_bdbb_no_lookahead(scored)
    Condition
      Error in `check_bdbb_no_lookahead()`:
      x 1 row in bdbb_tail_predict() scored windows score a return at or before window_end (#868 look-ahead bias):
      i First offender: window_end = 2023-01-01 05:00:00, next_time = 2023-01-01 05:00:00.
      i The scored return must be strictly AFTER window_end -- see bdbb_tail_predict() row-order lead() join (packages/historicaldata/R/bdbb.R).

# check_bdbb_no_lookahead aborts on a scored tibble missing required columns

    Code
      check_bdbb_no_lookahead(tibble::tibble(window_end = Sys.time()))
    Condition
      Error in `check_bdbb_no_lookahead()`:
      x `scored` is missing 1 required column(s): next_time.
      i check_bdbb_no_lookahead() (S34) requires window_end, next_time -- the bdbb_scored_windows attribute attached by bdbb_tail_predict().

# check_bdbb_no_lookahead signature is stable (catches API drift)

    Code
      args(check_bdbb_no_lookahead)
    Output
      function (scored) 
      NULL

